// Tests for the install report (POST /api/install) — parity with the RN SDK's reportInstall
// (posted-sdk-react-native src/__tests__/reportInstall.test.ts):
//   1. POST /api/install with SDK auth, the install fields and device_id, then the flag is armed
//   2. No clickId and no clipboard read
//   3. Sent once: nothing is sent once the flag is armed
//   4. The flag is armed only on a 2xx, so failures retry on the next launch
//   5. Concurrent calls share one request
//   6. The device id is stable across reports
import UIKit
import XCTest
@testable import PostedSDK

@MainActor
final class InstallReportTests: XCTestCase {
    private let config = PostedConfig(apiKey: "test-api-key", appID: "com.test.app")
    private var session: URLSession!

    private static let installURL = "https://attr.postedapp.com/api/install"

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        session = StubURLProtocol.makeSession()
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

    func testPostsInstallContextAndDeviceIDWithSDKAuthThenArmsFlag() async throws {
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
            XCTAssertNotNil(json[key], "install field '\(key)' missing from install body")
        }
        XCTAssertEqual(json["platform"] as? String, "ios")
        XCTAssertEqual(json["manufacturer"] as? String, "Apple")
        XCTAssertEqual(json["installSource"] as? String, "development", "simulator builds are development builds")
        XCTAssertEqual(
            json["device_id"] as? String,
            UserDefaults.standard.string(forKey: StorageUtils.Constants.deviceIDKey),
            "install body must carry the persisted device id"
        )
        XCTAssertTrue(StorageUtils.isInstallReported())
    }

    func testSendsNoClickIdAndNoPastedLink() async throws {
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

    func testDeviceIDIsStableAcrossReports() async throws {
        StubURLProtocol.responseStatusCode = 500
        await Posted.shared._reportInstall(config: config, session: session)
        let first = try XCTUnwrap(sentBody()["device_id"] as? String)

        StubURLProtocol.responseStatusCode = 200
        await Posted.shared._reportInstall(config: config, session: session)
        let second = try XCTUnwrap(sentBody()["device_id"] as? String)

        XCTAssertEqual(first, second, "a retry must carry the same device id as the failed attempt")
        XCTAssertFalse(first.isEmpty)
    }
}

/// Fails every request with a transport error.
private final class FailingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
