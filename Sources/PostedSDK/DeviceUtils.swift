import UIKit
import WebKit

class DeviceUtils {
    private static let tag = "FingerprintCollector"

    @MainActor
    private static var webView: WKWebView?

    @MainActor
    private static func getRealUserAgent() async -> String {
        return await withCheckedContinuation { continuation in
            webView = WKWebView()

            webView?.evaluateJavaScript("navigator.userAgent") { result, error in
                if let error = error {
                    PostedLogger.warn(tag, "[Posted:FINGERPRINT] WebKit userAgent retrieval failed: \(error.localizedDescription)")
                }

                if let ua = result as? String {
                    continuation.resume(returning: ua)
                } else {
                    PostedLogger.warn(tag, "[Posted:FINGERPRINT] WebKit userAgent result was nil")
                    continuation.resume(returning: "")
                }

                webView = nil
            }
        }
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

    @MainActor
    static func readClipboardLinkIfAvailable(shouldUseClipboard: Bool) async -> String? {
        guard shouldUseClipboard else { return nil }

        if #available(iOS 14.0, *) {
            let hasProbableWebURL = await withCheckedContinuation { continuation in
                UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { result in
                    switch result {
                    case .success(let patterns):
                        continuation.resume(returning: patterns.contains(.probableWebURL))
                    case .failure:
                        continuation.resume(returning: false)
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

        let userAgent = await getRealUserAgent()

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
