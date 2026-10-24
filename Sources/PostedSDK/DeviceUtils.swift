import Foundation
import UIKit
import WebKit

class DeviceUtils {
    private static let tag = "FingerprintCollector"

    /// Scoped per-call (POS-472): a shared static WKWebView let two genuinely concurrent
    /// resolutions race on the same instance — one call's teardown could deallocate the
    /// other's still-in-flight WKWebView, hanging its continuation forever. Each call now
    /// owns its own WKWebView, retained only by this closure's capture, so concurrent calls
    /// cannot interfere with one another.
    /// Internal (not private) so the concurrency test (POS-472) can drive two overlapping
    /// calls directly without going through the full `getFingerprint` path. Not part of the
    /// SDK's public API surface.
    @MainActor
    static func getRealUserAgent() async -> String {
        return await withCheckedContinuation { continuation in
            let webView = WKWebView()

            webView.evaluateJavaScript("navigator.userAgent") { result, error in
                if let error = error {
                    PostedLogger.warn(tag, "[Posted:FINGERPRINT] WebKit userAgent retrieval failed: \(error.localizedDescription)")
                }

                if let ua = result as? String {
                    continuation.resume(returning: ua)
                } else {
                    PostedLogger.warn(tag, "[Posted:FINGERPRINT] WebKit userAgent result was nil")
                    continuation.resume(returning: "")
                }

                _ = webView
            }
        }
    }

    // One user-agent lookup per process, shared by every fingerprint (match-link and the install
    // report run concurrently on first launch): a single WKWebView instead of one per caller. An
    // empty (failed) lookup is not kept, so a later fingerprint tries again.
    @MainActor private static var userAgentTask: Task<String, Never>?

    @MainActor
    static func sharedUserAgent() async -> String {
        if let userAgentTask { return await userAgentTask.value }
        let task = Task { await getRealUserAgent() }
        userAgentTask = task
        let userAgent = await task.value
        if userAgent.isEmpty, userAgentTask == task { userAgentTask = nil }
        return userAgent
    }

    /// FR9b read-format contract (POS-229 / POS-170 D7).
    ///
    /// The click page (C) writes the short-link URL to the iOS pasteboard *verbatim*, and the
    /// click recorder (D) stores that identical string as `pastedLink`. The matcher exact-matches
    /// `pastedLink` (weight 350), so write-format (C) MUST equal read-format (here). This read
    /// format is therefore the IDENTITY function by contract: do not trim, lowercase, normalize,
    /// re-encode, or otherwise mutate the pasteboard string — any transformation drops a
    /// load-bearing signal. Exposed `internal` purely so the byte-identical round-trip test can
    /// assert the no-transformation guarantee directly.
    static func pastedLink(fromPasteboardString raw: String?) -> String? {
        raw
    }

    /// Default bound for the `detectPatterns` gate (POS-241).
    ///
    /// Long enough that a healthy `detectPatterns` callback wins the race on a real device,
    /// short enough that a wedged callback can't stall app-launch fingerprinting for more than this.
    static let detectPatternsTimeoutNanoseconds: UInt64 = 2_000_000_000  // 2s

    /// Runs a bounded-timeout race for the pasteboard pattern-detection gate (POS-241).
    ///
    /// `UIPasteboard.general.detectPatterns(for:)` takes a completion handler that, on a real
    /// device, may never fire — the same failure mode that hung unattended CI simulators (see
    /// [POS-229]). Wrapping it in a plain, unbounded `withCheckedContinuation` therefore risks
    /// hanging `getFingerprint` → match indefinitely at app launch. This races the detection
    /// against a timeout: whichever arm resolves first wins, and if the callback never arrives the
    /// gate degrades to `false` (skip clipboard) instead of hanging. A late/never callback after
    /// the timeout is harmless — the once-guard drops it.
    ///
    /// `detect` is injected (rather than hard-wired to `UIPasteboard.general`) so the timeout /
    /// first-wins behaviour is testable without the live singleton, which itself can block on
    /// unattended sims.
    @MainActor
    static func probableWebURLGate(
        timeoutNanoseconds: UInt64 = detectPatternsTimeoutNanoseconds,
        detect: @escaping (@escaping (Bool) -> Void) -> Void
    ) async -> Bool {
        let onceGuard = ResumeOnceGuard()
        return await withCheckedContinuation { continuation in
            let timeout = Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                onceGuard.run {
                    PostedLogger.warn(
                        tag,
                        "[Posted:FINGERPRINT] pasteboard detectPatterns gate timed out; skipping clipboard read"
                    )
                    // Structured signal (POS-246), distinct from the hit/miss outcome above, so
                    // real-device gate-timeout frequency is queryable. No clipboard contents/PII —
                    // just the timeout occurrence itself.
                    PostedLogger.signal(tag, "pasteboard_detect_patterns_gate_timeout")
                    continuation.resume(returning: false)
                }
            }
            detect { hasPattern in
                onceGuard.run {
                    timeout.cancel()
                    continuation.resume(returning: hasPattern)
                }
            }
        }
    }

    @MainActor
    static func readClipboardLinkIfAvailable(shouldUseClipboard: Bool) async -> String? {
        guard shouldUseClipboard else { return nil }

        if #available(iOS 14.0, *) {
            let hasProbableWebURL = await probableWebURLGate { resume in
                UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { result in
                    switch result {
                    case .success(let patterns):
                        resume(patterns.contains(.probableWebURL))
                    case .failure:
                        resume(false)
                    }
                }
            }

            guard hasProbableWebURL else { return nil }
        }

        return pastedLink(fromPasteboardString: UIPasteboard.general.string)
    }

    @MainActor
    static func getFingerprint(shouldUseClipboard: Bool) async -> ProbabilisticFingerprint {
        let device = UIDevice.current
        let screen = UIScreen.main

        let pastedLink = await readClipboardLinkIfAvailable(shouldUseClipboard: shouldUseClipboard)

        let locales = Locale.preferredLanguages.map { LocaleTag(languageTag: $0) }

        let userAgent = await sharedUserAgent()

        return ProbabilisticFingerprint(
            platform: "ios",
            model: device.model,
            manufacturer: "Apple",
            systemVersion: device.systemVersion,
            screenWidth: Double(screen.bounds.width),
            screenHeight: Double(screen.bounds.height),
            scale: Double(screen.scale),
            locale: locales,
            timezone: TimeZone.current.identifier,
            userAgent: userAgent,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            pastedLink: pastedLink
        )
    }
}

/// Thread-safe run-exactly-once guard for the `detectPatterns` timeout race (POS-241).
///
/// Both race arms — the `detectPatterns` completion handler and the timeout `Task` — may fire,
/// and they can fire on different threads. This ensures the underlying `withCheckedContinuation`
/// is resumed exactly once (resuming twice is undefined behaviour), letting the second arm's
/// callback be safely dropped whenever it lands.
final class ResumeOnceGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var hasRun = false

    /// Runs `body` iff no prior call has run; subsequent calls are no-ops.
    func run(_ body: () -> Void) {
        lock.lock()
        if hasRun {
            lock.unlock()
            return
        }
        hasRun = true
        lock.unlock()
        body()
    }
}
