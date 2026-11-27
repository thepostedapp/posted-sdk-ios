// Tests for the purchases user link (POST /api/purchasesUser):
//   1. POST /api/purchasesUser with SDK auth, the install's device_id and purchases_user_id, then the flag is armed
//   2. The install is reported first; nothing is sent while it stays unreported
//   3. Sent once: nothing is sent once the flag is armed
//   4. The flag is armed only on a 2xx, so failures retry on the next call
//   5. An empty id sends nothing
import XCTest
@testable import PostedSDK

@MainActor
final class PurchasesUserTests: XCTestCase {
    private let config = PostedConfig(apiKey: "test-api-key", appID: "com.test.app")
    private var session: URLSession!

    private static let installURL = "https://attr.postedapp.com/api/install"
    private static let purchasesUserURL = "https://attr.postedapp.com/api/purchasesUser"

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        session = StubURLProtocol.makeSession()
        StorageUtils.clearInstallReported()
        StorageUtils.clearPurchasesUserReported()
    }

    override func tearDown() {
        StorageUtils.clearInstallReported()
        StorageUtils.clearPurchasesUserReported()
        super.tearDown()
    }

    private func body(of url: String) throws -> [String: Any] {
        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[url])
        return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(req.httpBody)) as? [String: Any])
    }

    func testReportsInstallThenPostsDeviceIDAndUserIDWithSDKAuthThenArmsFlag() async throws {
        await Posted.shared._setPurchasesUserId("rc-user-1", config: config, session: session)

        XCTAssertEqual(StubURLProtocol.requestCallCount[Self.installURL], 1)
        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.purchasesUserURL])
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-api-key")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-App-ID"), "com.test.app")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-SDK"), PostedConstants.sdkHeaderValue)

        let json = try body(of: Self.purchasesUserURL)
        XCTAssertEqual(json.count, 2)
        XCTAssertEqual(json["purchases_user_id"] as? String, "rc-user-1")
        XCTAssertEqual(
            json["device_id"] as? String,
            try body(of: Self.installURL)["device_id"] as? String,
            "the link must carry the device id the install was reported with"
        )
        XCTAssertTrue(StorageUtils.isPurchasesUserReported())
    }

    func testSkipsTheInstallReportWhenAlreadyReported() async {
        StorageUtils.markInstallReported()

        await Posted.shared._setPurchasesUserId("rc-user-1", config: config, session: session)

        XCTAssertNil(StubURLProtocol.requestCallCount[Self.installURL])
        XCTAssertEqual(StubURLProtocol.requestCallCount[Self.purchasesUserURL], 1)
        XCTAssertTrue(StorageUtils.isPurchasesUserReported())
    }

    func testSendsNothingWhileTheInstallIsUnreported() async {
        StubURLProtocol.responseStatusCode = 500

        await Posted.shared._setPurchasesUserId("rc-user-1", config: config, session: session)

        XCTAssertEqual(StubURLProtocol.requestCallCount[Self.installURL], 1)
        XCTAssertNil(StubURLProtocol.requestCallCount[Self.purchasesUserURL])
        XCTAssertFalse(StorageUtils.isPurchasesUserReported())
    }

    func testSendsNothingOnceReported() async {
        StorageUtils.markPurchasesUserReported()

        await Posted.shared._setPurchasesUserId("rc-user-1", config: config, session: session)

        XCTAssertTrue(StubURLProtocol.requestCallCount.isEmpty)
    }

    func testNon2xxLeavesFlagUnarmedSoTheNextCallRetries() async {
        StorageUtils.markInstallReported()
        StubURLProtocol.responseStatusCode = 404
        await Posted.shared._setPurchasesUserId("rc-user-1", config: config, session: session)
        XCTAssertFalse(StorageUtils.isPurchasesUserReported())

        StubURLProtocol.responseStatusCode = 200
        await Posted.shared._setPurchasesUserId("rc-user-1", config: config, session: session)

        XCTAssertEqual(StubURLProtocol.requestCallCount[Self.purchasesUserURL], 2)
        XCTAssertTrue(StorageUtils.isPurchasesUserReported())
    }

    func testConcurrentCallsShareOneRequest() async {
        async let first: Void = Posted.shared._setPurchasesUserId("rc-user-1", config: config, session: session)
        async let second: Void = Posted.shared._setPurchasesUserId("rc-user-1", config: config, session: session)
        _ = await (first, second)

        XCTAssertEqual(StubURLProtocol.requestCallCount[Self.purchasesUserURL], 1)
        XCTAssertTrue(StorageUtils.isPurchasesUserReported())
    }

    func testEmptyIDSendsNothing() async {
        await Posted.shared._setPurchasesUserId("", config: config, session: session)

        XCTAssertTrue(StubURLProtocol.requestCallCount.isEmpty)
        XCTAssertFalse(StorageUtils.isPurchasesUserReported())
    }
}
