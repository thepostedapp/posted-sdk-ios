// Tests for the RevenueCat user link (POST /api/revenueCatUser):
//   1. POST /api/revenueCatUser with SDK auth, the install's device_id and rc_user_id, then the flag is armed
//   2. The install is reported first; nothing is sent while it stays unreported
//   3. Sent once: nothing is sent once the flag is armed
//   4. The flag is armed only on a 2xx, so failures retry on the next call
//   5. An empty id sends nothing
import XCTest
@testable import PostedSDK

@MainActor
final class RevenueCatUserTests: XCTestCase {
    private let config = PostedConfig(apiKey: "test-api-key", appID: "com.test.app")
    private var session: URLSession!

    private static let installURL = "https://attr.postedapp.com/api/install"
    private static let revenueCatUserURL = "https://attr.postedapp.com/api/revenueCatUser"

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        session = StubURLProtocol.makeSession()
        StorageUtils.clearInstallReported()
        StorageUtils.clearRevenueCatUserReported()
    }

    override func tearDown() {
        StorageUtils.clearInstallReported()
        StorageUtils.clearRevenueCatUserReported()
        super.tearDown()
    }

    private func body(of url: String) throws -> [String: Any] {
        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[url])
        return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(req.httpBody)) as? [String: Any])
    }

    func testReportsInstallThenPostsDeviceIDAndUserIDWithSDKAuthThenArmsFlag() async throws {
        await Posted.shared._setRevenueCatUserId("rc-user-1", config: config, session: session)

        XCTAssertEqual(StubURLProtocol.requestCallCount[Self.installURL], 1)
        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.revenueCatUserURL])
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-api-key")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-App-ID"), "com.test.app")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-SDK"), PostedConstants.sdkHeaderValue)

        let json = try body(of: Self.revenueCatUserURL)
        XCTAssertEqual(json.count, 2)
        XCTAssertEqual(json["rc_user_id"] as? String, "rc-user-1")
        XCTAssertEqual(
            json["device_id"] as? String,
            try body(of: Self.installURL)["device_id"] as? String,
            "the link must carry the device id the install was reported with"
        )
        XCTAssertTrue(StorageUtils.isRevenueCatUserReported())
    }

    func testSkipsTheInstallReportWhenAlreadyReported() async {
        StorageUtils.markInstallReported()

        await Posted.shared._setRevenueCatUserId("rc-user-1", config: config, session: session)

        XCTAssertNil(StubURLProtocol.requestCallCount[Self.installURL])
        XCTAssertEqual(StubURLProtocol.requestCallCount[Self.revenueCatUserURL], 1)
        XCTAssertTrue(StorageUtils.isRevenueCatUserReported())
    }

    func testSendsNothingWhileTheInstallIsUnreported() async {
        StubURLProtocol.responseStatusCode = 500

        await Posted.shared._setRevenueCatUserId("rc-user-1", config: config, session: session)

        XCTAssertEqual(StubURLProtocol.requestCallCount[Self.installURL], 1)
        XCTAssertNil(StubURLProtocol.requestCallCount[Self.revenueCatUserURL])
        XCTAssertFalse(StorageUtils.isRevenueCatUserReported())
    }

    func testSendsNothingOnceReported() async {
        StorageUtils.markRevenueCatUserReported()

        await Posted.shared._setRevenueCatUserId("rc-user-1", config: config, session: session)

        XCTAssertTrue(StubURLProtocol.requestCallCount.isEmpty)
    }

    func testNon2xxLeavesFlagUnarmedSoTheNextCallRetries() async {
        StorageUtils.markInstallReported()
        StubURLProtocol.responseStatusCode = 404
        await Posted.shared._setRevenueCatUserId("rc-user-1", config: config, session: session)
        XCTAssertFalse(StorageUtils.isRevenueCatUserReported())

        StubURLProtocol.responseStatusCode = 200
        await Posted.shared._setRevenueCatUserId("rc-user-1", config: config, session: session)

        XCTAssertEqual(StubURLProtocol.requestCallCount[Self.revenueCatUserURL], 2)
        XCTAssertTrue(StorageUtils.isRevenueCatUserReported())
    }

    func testConcurrentCallsShareOneRequest() async {
        async let first: Void = Posted.shared._setRevenueCatUserId("rc-user-1", config: config, session: session)
        async let second: Void = Posted.shared._setRevenueCatUserId("rc-user-1", config: config, session: session)
        _ = await (first, second)

        XCTAssertEqual(StubURLProtocol.requestCallCount[Self.revenueCatUserURL], 1)
        XCTAssertTrue(StorageUtils.isRevenueCatUserReported())
    }

    func testEmptyIDSendsNothing() async {
        await Posted.shared._setRevenueCatUserId("", config: config, session: session)

        XCTAssertTrue(StubURLProtocol.requestCallCount.isEmpty)
        XCTAssertFalse(StorageUtils.isRevenueCatUserReported())
    }
}
