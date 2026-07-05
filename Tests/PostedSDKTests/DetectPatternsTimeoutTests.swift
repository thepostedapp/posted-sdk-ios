// Bounded-timeout hardening for the iOS `detectPatterns` pasteboard gate (POS-241).
//
// Production `DeviceUtils.readClipboardLinkIfAvailable` (iOS 14+ branch) gates the clipboard read
// behind `UIPasteboard.general.detectPatterns(for: [.probableWebURL])`. On a real device that
// completion handler can fail to fire — the same failure mode that hung unattended CI simulators
// for 30+ min on POS-229. Wrapping it in an unbounded continuation would hang app-launch
// fingerprinting (`getFingerprint` → match) indefinitely, so the gate now races the detection
// against a bounded timeout and degrades to `false` (skip clipboard) when the callback never
// arrives.
//
// These tests drive the `probableWebURLGate(timeoutNanoseconds:detect:)` seam with injected
// callbacks — an immediate hit, an immediate miss, a callback that fires after the timeout, and a
// callback that NEVER fires. They deliberately never touch the live `UIPasteboard.general`
// singleton (which itself can block on unattended sims); the seam takes the detection primitive as
// a closure, so the timeout / first-wins contract is proven host-independently.
import XCTest
@testable import PostedSDK

final class DetectPatternsTimeoutTests: XCTestCase {
    // Generous relative to the injected sub-second timeouts, but a hard ceiling: if the gate ever
    // regressed to hanging on a never-firing callback, this bounds the failure instead of wedging
    // the whole test run (the exact CI hang POS-241 exists to prevent).
    private static let hardCeiling: TimeInterval = 10

    // MARK: - First-wins: real callback beats the timeout

    func testImmediateHitReturnsTrue() async {
        let result = await DeviceUtils.probableWebURLGate(
            timeoutNanoseconds: DeviceUtils.detectPatternsTimeoutNanoseconds
        ) { resume in
            resume(true)
        }
        XCTAssertTrue(result, "a callback reporting a probable web URL must win the race and return true")
    }

    func testImmediateMissReturnsFalse() async {
        let result = await DeviceUtils.probableWebURLGate(
            timeoutNanoseconds: DeviceUtils.detectPatternsTimeoutNanoseconds
        ) { resume in
            resume(false)
        }
        XCTAssertFalse(result, "a callback reporting no probable web URL must win the race and return false")
    }

    // MARK: - Timeout degrades to skip (false)

    func testNeverFiringCallbackDegradesToFalseWithinBound() async {
        let start = Date()
        let result = await DeviceUtils.probableWebURLGate(
            timeoutNanoseconds: 50_000_000  // 50ms
        ) { _ in
            // Simulates the real-device hang: the completion handler is never invoked.
        }
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertFalse(result, "a never-firing detectPatterns callback must degrade to false (skip clipboard), not hang")
        XCTAssertLessThan(elapsed, Self.hardCeiling, "the gate must return via the timeout, not block indefinitely")
    }

    func testCallbackAfterTimeoutIsIgnored() async {
        // The detection fires — but only well after the timeout has already resolved the gate.
        // The once-guard must keep the timeout's `false` and drop the late callback safely.
        let result = await DeviceUtils.probableWebURLGate(
            timeoutNanoseconds: 50_000_000  // 50ms; callback below fires later
        ) { resume in
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms > timeout
                resume(true)
            }
        }
        XCTAssertFalse(result, "a callback that arrives after the timeout must be ignored; the gate already skipped")
    }

    // MARK: - First-wins: callback within the timeout window still wins

    func testCallbackWithinTimeoutWindowWins() async {
        let result = await DeviceUtils.probableWebURLGate(
            timeoutNanoseconds: 2_000_000_000  // 2s
        ) { resume in
            Task {
                try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms << timeout
                resume(true)
            }
        }
        XCTAssertTrue(result, "a callback that arrives before the timeout must win and return its value")
    }

    // MARK: - Once-guard invariant

    func testResumeOnceGuardRunsBodyExactlyOnce() {
        let guardUnderTest = ResumeOnceGuard()
        var runCount = 0
        for _ in 0..<5 {
            guardUnderTest.run { runCount += 1 }
        }
        XCTAssertEqual(runCount, 1, "ResumeOnceGuard must run its body exactly once across repeated calls")
    }
}
