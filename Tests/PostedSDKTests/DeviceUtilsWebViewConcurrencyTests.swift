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
    // completion passes. The bound only exists so a real hang fails the test instead of wedging
    // the CI job. Two cold WKWebView evaluations on a shared CI runner's simulator have been
    // measured at six minutes, so the bound is well above that.
    private static let hardCeiling: TimeInterval = 900

    @MainActor
    func testTwoConcurrentGetRealUserAgentCallsBothComplete() async {
        let result: (String, String)? = await withTaskGroup(of: (String, String)?.self) { group in
            group.addTask { @MainActor in
                async let first = DeviceUtils.getRealUserAgent()
                async let second = DeviceUtils.getRealUserAgent()
                return await (first, second)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(Self.hardCeiling * 1_000_000_000))
                return nil
            }
            let winner = await group.next() ?? nil
            group.cancelAll()
            return winner
        }

        guard let (userAgentOne, userAgentTwo) = result else {
            XCTFail("both concurrent getRealUserAgent() calls must complete within \(Self.hardCeiling)s; a shared-static WKWebView race would hang one of them")
            return
        }
        XCTAssertFalse(userAgentOne.isEmpty, "the first concurrent call must resolve to a real user agent string")
        XCTAssertFalse(userAgentTwo.isEmpty, "the second concurrent call must resolve to a real user agent string")
    }
}
