// Per-call WKWebView scoping for DeviceUtils.getRealUserAgent().
//
// A shared static WKWebView let two concurrent lookups race: one call's teardown could
// deallocate the other's still-in-flight WKWebView before its `evaluateJavaScript` completion
// fired, hanging that call's continuation forever. Each call now scopes its WKWebView to a local
// retained only by its own completion closure. This test drives two concurrent calls and asserts
// both complete.
import XCTest
@testable import PostedSDK

final class DeviceUtilsWebViewConcurrencyTests: XCTestCase {
    // A hang detector, not a performance budget: a regressed race hangs forever, so any finite
    // completion passes. Cold WKWebView JS evaluations on a loaded CI runner were measured
    // at up to 70s, so the ceiling is generous while still bounding a wedged run.
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
            "both concurrent getRealUserAgent() calls must complete; a shared-static WKWebView race would hang one of them"
        )
        XCTAssertFalse(userAgentOne.isEmpty, "the first concurrent call must resolve to a real user agent string")
        XCTAssertFalse(userAgentTwo.isEmpty, "the second concurrent call must resolve to a real user agent string")
    }
}
