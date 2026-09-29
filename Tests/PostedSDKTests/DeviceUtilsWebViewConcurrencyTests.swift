// Per-call WKWebView scoping for DeviceUtils.getRealUserAgent() (POS-472).
//
// Production `getRealUserAgent()` used to stash its WKWebView in a single shared
// `@MainActor static var webView: WKWebView?`. Two genuinely concurrent resolutions (different
// generations, not de-duped against each other — see POS-267) both hitting this deferred branch
// would race on that shared static: one call's teardown (`webView = nil`) could deallocate the
// other's still-in-flight WKWebView before its `evaluateJavaScript` completion fired, hanging that
// call's `withCheckedContinuation` forever. This was a real production bug, not test-only — it
// first surfaced because POS-267's overlap test was the first to legitimately drive two concurrent
// real resolutions.
//
// The fix scopes the WKWebView to a local variable per call, retained only by that call's own
// completion closure, so two overlapping calls cannot interfere with one another. This test drives
// two concurrent `getRealUserAgent()` calls and asserts both complete (no hung continuation).
import XCTest
@testable import PostedSDK

final class DeviceUtilsWebViewConcurrencyTests: XCTestCase {
    // Generous relative to a real WKWebView JS evaluation, but a hard ceiling: if the shared-static
    // race ever regressed, one of the two calls would hang forever instead of completing, and this
    // bounds the failure instead of wedging the whole test run.
    //
    // Raised 30 -> 120 (POS-146). This is a hang detector, not a performance budget: a regressed
    // race hangs forever, so any finite completion passes the thing we actually care about. On a
    // loaded CI runner two cold WKWebView JS evaluations were measured at 40.9s and 69.5s, which
    // tripped the old ceiling without any race being present. 120s still bounds a wedged run.
    private static let hardCeiling: TimeInterval = 120

    @MainActor
    func testTwoConcurrentGetRealUserAgentCallsBothComplete() async {
        let start = Date()

        async let first = DeviceUtils.getRealUserAgent()
        async let second = DeviceUtils.getRealUserAgent()

        let (userAgentOne, userAgentTwo) = await (first, second)

        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(
            elapsed,
            Self.hardCeiling,
            "both concurrent getRealUserAgent() calls must complete promptly; a shared-static WKWebView race would hang one of them"
        )
        XCTAssertFalse(userAgentOne.isEmpty, "the first concurrent call must resolve to a real user agent string")
        XCTAssertFalse(userAgentTwo.isEmpty, "the second concurrent call must resolve to a real user agent string")
    }
}
