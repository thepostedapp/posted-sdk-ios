// Tests for the install report (POST /api/install) — iOS parity with the RN SDK's reportInstall
// (posted-sdk-react-native src/__tests__/reportInstall.test.ts):
//   1. POST /api/install with SDK auth, the fingerprint and device_id, then the flag is armed
//   2. No clickId and no clipboard read, even with shouldUseClipboard = true
//   3. Sent once: nothing is sent once the flag is armed
//   4. The flag is armed only on a 2xx, so failures retry on the next launch
//   5. Concurrent calls share one request
//   6. resolveAppLaunch triggers it, even when returning a cached fire-once result, and
//      returns without waiting for it
//   7. resetSession() leaves the flag armed
import UIKit
import XCTest
@testable import PostedSDK

@MainActor
final class InstallReportTests: XCTestCase {
    // shouldUseClipboard is on to prove the install report ignores it.
    private let config = PostedConfig(apiKey: "test-api-key", appID: "com.test.app", shouldUseClipboard: true)
    // For the resolveAppLaunch tests: match-link reads the clipboard by design, and a read in the
    // test host blocks on the system paste prompt.
    private let noClipboardConfig = PostedConfig(apiKey: "test-api-key", appID: "com.test.app", shouldUseClipboard: false)
    private var session: URLSession!

    private static let installURL = "https://attr.postedapp.com/api/install"

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        session = StubURLProtocol.makeSession()
        Posted.shared.resetSession(allowDeferredRetry: true)
        StorageUtils.clearInstallReported()
    }

    override func tearDown() {
        UIPasteboard.general.items = []
        StorageUtils.clearInstallReported()
        super.tearDown()
    }

    private func sentBody() throws -> [String: Any] {
        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.installURL], "install must be reported")
        let body = try XCTUnwrap(req.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    func testPostsFingerprintAndDeviceIDWithSDKAuthThenArmsFlag() async throws {
        await Posted.shared._reportInstall(config: config, session: session)

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.installURL])
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-api-key")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-App-ID"), "com.test.app")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-SDK"), PostedConstants.sdkHeaderValue)

        let json = try sentBody()
        for key in ["platform", "model", "manufacturer", "systemVersion", "screenWidth", "screenHeight",
                    "scale", "locale", "timezone", "userAgent", "timestamp"] {
            XCTAssertNotNil(json[key], "fingerprint key '\(key)' missing from install body")
        }
        XCTAssertEqual(json["platform"] as? String, "ios")
        XCTAssertEqual(
            json["device_id"] as? String,
            UserDefaults.standard.string(forKey: StorageUtils.Constants.deviceIDKey),
            "install body must carry the persisted analytics device id"
        )
        XCTAssertTrue(StorageUtils.isInstallReported())
    }

    func testSendsNoClickIdAndNoPastedLinkEvenWithClipboardEnabled() async throws {
        UIPasteboard.general.string = "https://l.postedapp.com/abc123"

        await Posted.shared._reportInstall(config: config, session: session)

        let json = try sentBody()
        XCTAssertNil(json["clickId"], "iOS has no install referrer — clickId must never be sent")
        XCTAssertNil(json["pastedLink"], "the install report must never read the clipboard")
    }

    func testSendsNothingOnceReported() async {
        StorageUtils.markInstallReported()

        await Posted.shared._reportInstall(config: config, session: session)

        XCTAssertNil(StubURLProtocol.requestCallCount[Self.installURL])
    }

    func testNon2xxLeavesFlagUnarmedSoTheNextLaunchRetries() async {
        StubURLProtocol.responseStatusCode = 500
        await Posted.shared._reportInstall(config: config, session: session)
        XCTAssertFalse(StorageUtils.isInstallReported())

        StubURLProtocol.responseStatusCode = 200
        await Posted.shared._reportInstall(config: config, session: session)

        XCTAssertEqual(StubURLProtocol.requestCallCount[Self.installURL], 2)
        XCTAssertTrue(StorageUtils.isInstallReported())
    }

    func testNetworkErrorLeavesFlagUnarmed() async {
        // Every request fails with a transport error.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FailingURLProtocol.self]
        let failing = URLSession(configuration: configuration)

        await Posted.shared._reportInstall(config: config, session: failing)

        XCTAssertFalse(StorageUtils.isInstallReported())
    }

    func testConcurrentCallsShareOneRequest() async {
        async let first: Void = Posted.shared._reportInstall(config: config, session: session)
        async let second: Void = Posted.shared._reportInstall(config: config, session: session)
        _ = await (first, second)

        XCTAssertEqual(StubURLProtocol.requestCallCount[Self.installURL], 1)
        XCTAssertTrue(StorageUtils.isInstallReported())
    }

    func testResolveAppLaunchTriggersReport() async throws {
        StubURLProtocol.responseData = #"{"link":null}"#.data(using: .utf8)!

        _ = await Posted.shared._resolveAppLaunch(config: noClipboardConfig, launchContext: nil, session: session)
        await Posted.shared.debugInFlightInstallReport?.value

        XCTAssertEqual(StubURLProtocol.requestCallCount[Self.installURL], 1)
        XCTAssertTrue(StorageUtils.isInstallReported())
    }

    func testResolveAppLaunchDoesNotWaitForTheInstallReport() async throws {
        StubURLProtocol.responseData = #"{"link":"https://example.com/promo"}"#.data(using: .utf8)!
        // Hold only the install response; match-link is answered at once.
        let release = DispatchSemaphore(value: 0)
        StubURLProtocol.gatedURL = Self.installURL
        StubURLProtocol.releaseResponse = release

        let result = await Posted.shared._resolveAppLaunch(config: noClipboardConfig, launchContext: nil, session: session)

        XCTAssertEqual(result.link?.url, "https://example.com/promo")
        let pending = try XCTUnwrap(
            Posted.shared.debugInFlightInstallReport,
            "resolveAppLaunch must return while the install report is still in flight"
        )
        XCTAssertFalse(StorageUtils.isInstallReported())

        release.signal()
        await pending.value
        XCTAssertTrue(StorageUtils.isInstallReported())
    }

    func testResolveAppLaunchRetriesReportEvenWhenAttributionIsCached() async throws {
        StorageUtils.markAttributionResolved(result: PostedResult(processed: true, link: nil))

        let result = await Posted.shared._resolveAppLaunch(config: noClipboardConfig, launchContext: nil, session: session)
        await Posted.shared.debugInFlightInstallReport?.value

        XCTAssertTrue(result.processed, "the cached fire-once result must be returned unchanged")
        XCTAssertNil(
            StubURLProtocol.capturedRequests["https://attr.postedapp.com/api/link/match-link"],
            "a cached launch must not re-resolve attribution"
        )
        XCTAssertEqual(
            StubURLProtocol.requestCallCount[Self.installURL], 1,
            "a cached launch must still retry an unreported install"
        )
    }

    func testResetSessionKeepsInstallReported() async {
        await Posted.shared._reportInstall(config: config, session: session)
        XCTAssertTrue(StorageUtils.isInstallReported())

        Posted.shared.resetSession(allowDeferredRetry: true)

        XCTAssertTrue(StorageUtils.isInstallReported(), "an install is reported once per device")
    }
}

/// Fails every request with a transport error.
private final class FailingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
