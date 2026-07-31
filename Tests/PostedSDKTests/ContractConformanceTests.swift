// Conformance suite for the 5 PostedSDK→backend endpoints.
// Validates against Tests/PostedSDKTests/Fixtures/detour-backend-contract.yaml (pinned v1.1.0).
// Uses a URLProtocol stub injected via the `session` parameter added to each network method.
import XCTest
@testable import PostedSDK

final class ContractConformanceTests: XCTestCase {
    private let testConfig = PostedConfig(apiKey: "test-api-key", appID: "com.test.app")
    private var session: URLSession!

    private static let matchLinkURL = "https://godetour.dev/api/link/match-link"
    private static let resolveShortURL = "https://godetour.dev/api/link/resolve-short"
    private static let universalClickURL = "https://godetour.dev/api/link/universal-link-click"
    private static let analyticsEventURL = "https://godetour.dev/api/analytics/event"
    private static let analyticsRetentionURL = "https://godetour.dev/api/analytics/retention"

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        session = StubURLProtocol.makeSession()
    }

    // MARK: - Helpers

    private func assertCommonHeaders(_ req: URLRequest, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(
            req.value(forHTTPHeaderField: "Authorization"), "Bearer test-api-key",
            "Authorization header missing or wrong", file: file, line: line
        )
        XCTAssertEqual(
            req.value(forHTTPHeaderField: "X-App-ID"), "com.test.app",
            "X-App-ID header missing or wrong", file: file, line: line
        )
        // X-SDK must be ios/<version> — no Flutter marker present in test bundle.
        let sdk = req.value(forHTTPHeaderField: "X-SDK") ?? ""
        XCTAssertTrue(
            sdk.hasPrefix("ios/"),
            "X-SDK must start with 'ios/' — got '\(sdk)'", file: file, line: line
        )
    }

    private func assertISO8601MsTimestamp(_ raw: Any?, file: StaticString = #file, line: UInt = #line) {
        guard let str = raw as? String else {
            XCTFail("timestamp must be an ISO-8601 string, got: \(String(describing: raw))", file: file, line: line)
            return
        }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertNotNil(
            fmt.date(from: str),
            "timestamp '\(str)' is not a valid ISO-8601 UTC ms timestamp", file: file, line: line
        )
    }

    private func assertEpochMsTimestamp(_ raw: Any?, file: StaticString = #file, line: UInt = #line) {
        guard let ms = raw as? Int else {
            XCTFail("timestamp must be an integer (epoch-ms), got: \(String(describing: raw))", file: file, line: line)
            return
        }
        // Sanity: must be after 2020-01-01 (1577836800000 ms).
        XCTAssertGreaterThan(ms, 1_577_836_800_000, "timestamp looks too small to be epoch-ms", file: file, line: line)
    }

    private func makeFingerprint(pastedLink: String? = nil) -> ProbabilisticFingerprint {
        ProbabilisticFingerprint(
            platform: "ios",
            model: "iPhone15,3",
            manufacturer: "Apple",
            systemVersion: "17.5.1",
            screenWidth: 430,
            screenHeight: 932,
            scale: 3,
            locale: [LocaleTag(languageTag: "en-US")],
            timezone: "America/New_York",
            userAgent: "PostedSDK/2.0.0",
            timestamp: 1_719_158_400_000,
            pastedLink: pastedLink
        )
    }

    // MARK: - match-link

    func testMatchLinkProbabilisticShape() throws {
        StubURLProtocol.responseData = #"{"link":null}"#.data(using: .utf8)!
        let exp = expectation(description: "matchLink completes")

        PostedNetwork.matchLink(
            config: testConfig,
            fingerprint: makeFingerprint(),
            session: session
        ) { _ in exp.fulfill() }

        wait(for: [exp], timeout: 3.0)

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.matchLinkURL])
        assertCommonHeaders(req)

        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        // Required ProbabilisticFingerprint keys
        for key in ["platform", "model", "manufacturer", "systemVersion",
                    "screenWidth", "screenHeight", "scale", "locale", "timestamp"] {
            XCTAssertNotNil(json[key], "Required key '\(key)' missing from match-link body")
        }

        XCTAssertEqual(json["platform"] as? String, "ios", "platform must be 'ios'")

        // timestamp must be epoch-ms (integer, not string)
        assertEpochMsTimestamp(json["timestamp"])

        // locale must be array of {languageTag} objects
        let locale = try XCTUnwrap(json["locale"] as? [[String: Any]], "locale must be array of objects")
        XCTAssertFalse(locale.isEmpty, "locale array must not be empty")
        XCTAssertNotNil(locale[0]["languageTag"], "locale items must have 'languageTag'")

        // iOS sends probabilistic fingerprint — must not contain deterministic 'clickId'
        XCTAssertNil(json["clickId"], "iOS match-link must not include 'clickId' (deterministic branch)")
    }

    func testMatchLinkPastedLinkNullWhenNotSet() throws {
        StubURLProtocol.responseData = #"{"link":null}"#.data(using: .utf8)!
        let exp = expectation(description: "matchLink completes")

        PostedNetwork.matchLink(
            config: testConfig,
            fingerprint: makeFingerprint(pastedLink: nil),
            session: session
        ) { _ in exp.fulfill() }

        wait(for: [exp], timeout: 3.0)

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.matchLinkURL])
        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        // When pastedLink is nil it should be encoded as JSON null or omitted — never a non-null string.
        if let pastedLink = json["pastedLink"] {
            XCTAssertTrue(pastedLink is NSNull, "pastedLink must be JSON null when not set, got: \(pastedLink)")
        }
    }

    func testMatchLinkPastedLinkPresentWhenSet() throws {
        StubURLProtocol.responseData = #"{"link":null}"#.data(using: .utf8)!
        let exp = expectation(description: "matchLink completes")

        PostedNetwork.matchLink(
            config: testConfig,
            fingerprint: makeFingerprint(pastedLink: "https://example.com/promo"),
            session: session
        ) { _ in exp.fulfill() }

        wait(for: [exp], timeout: 3.0)

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.matchLinkURL])
        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["pastedLink"] as? String, "https://example.com/promo")
    }

    func testMatchLinkNoAdditionalProperties() throws {
        StubURLProtocol.responseData = #"{"link":null}"#.data(using: .utf8)!
        let exp = expectation(description: "matchLink completes")

        PostedNetwork.matchLink(
            config: testConfig,
            fingerprint: makeFingerprint(),
            session: session
        ) { _ in exp.fulfill() }

        wait(for: [exp], timeout: 3.0)

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.matchLinkURL])
        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        let allowed: Set<String> = [
            "platform", "model", "manufacturer", "systemVersion",
            "screenWidth", "screenHeight", "scale", "locale",
            "timezone", "userAgent", "timestamp", "pastedLink"
        ]
        let extra = Set(json.keys).subtracting(allowed)
        XCTAssertTrue(extra.isEmpty, "match-link body has unexpected keys: \(extra)")
    }

    // MARK: - resolve-short

    func testResolveShortShape() async throws {
        StubURLProtocol.responseData = #"{"link":"https://example.com/product/42"}"#.data(using: .utf8)!

        _ = await PostedNetwork.resolveShortLink(
            config: testConfig,
            url: "https://godetour.dev/x9Az",
            session: session
        )

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.resolveShortURL])
        assertCommonHeaders(req)

        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertNotNil(json["url"] as? String, "resolve-short must include 'url' key")

        // additionalProperties: false — only 'url' is allowed
        XCTAssertEqual(
            json.keys.sorted(), ["url"],
            "resolve-short body must contain only 'url' (additionalProperties:false)"
        )
    }

    // MARK: - universal-link-click

    func testUniversalLinkClickShape() async throws {
        StubURLProtocol.responseData = #"{"allowed":true}"#.data(using: .utf8)!

        _ = await PostedNetwork.sendUniversalLinkClick(
            config: testConfig,
            url: "https://godetour.dev/u/launch?campaign=spring&variant=b",
            linkId: "lnk_5567",
            session: session
        )

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.universalClickURL])
        assertCommonHeaders(req)

        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        // Required: url, timestamp, platform
        XCTAssertNotNil(json["url"] as? String, "universal-link-click must include 'url'")
        XCTAssertEqual(json["platform"] as? String, "ios", "platform must be 'ios'")
        assertEpochMsTimestamp(json["timestamp"])

        // link_id must be present when linkId is provided
        XCTAssertEqual(json["link_id"] as? String, "lnk_5567", "link_id must be present when provided")

        // params present when URL has query items
        XCTAssertNotNil(json["params"] as? [String: String], "params must be present when URL has query params")

        // metadata always present on iOS (non-null fields)
        let metadata = try XCTUnwrap(json["metadata"] as? [String: Any], "metadata must be present")
        XCTAssertNotNil(metadata["os_version"], "metadata.os_version must be present")
        XCTAssertNotNil(metadata["app_version"], "metadata.app_version must be present")
        XCTAssertNotNil(metadata["device_model"], "metadata.device_model must be present")
    }

    func testUniversalLinkClickLinkIdAbsentWhenNil() async throws {
        StubURLProtocol.responseData = #"{"allowed":true}"#.data(using: .utf8)!

        _ = await PostedNetwork.sendUniversalLinkClick(
            config: testConfig,
            url: "https://godetour.dev/u/launch",
            linkId: nil,
            session: session
        )

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.universalClickURL])
        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertNil(json["link_id"], "link_id must be absent from JSON when not provided (iOS contract)")
    }

    func testUniversalLinkClickParamsAbsentWhenNoQueryItems() async throws {
        StubURLProtocol.responseData = #"{"allowed":true}"#.data(using: .utf8)!

        _ = await PostedNetwork.sendUniversalLinkClick(
            config: testConfig,
            url: "https://godetour.dev/u/launch",
            session: session
        )

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.universalClickURL])
        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertNil(json["params"], "params must be absent when URL has no query parameters")
    }

    func testUniversalLinkClickNoAdditionalProperties() async throws {
        StubURLProtocol.responseData = #"{"allowed":true}"#.data(using: .utf8)!

        _ = await PostedNetwork.sendUniversalLinkClick(
            config: testConfig,
            url: "https://godetour.dev/u/launch?x=1",
            session: session
        )

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.universalClickURL])
        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        let allowed: Set<String> = ["url", "timestamp", "platform", "link_id", "params", "metadata"]
        let extra = Set(json.keys).subtracting(allowed)
        XCTAssertTrue(extra.isEmpty, "universal-link-click body has unexpected keys: \(extra)")
    }

    // MARK: - analytics/event

    func testAnalyticsEventShape() async throws {
        StubURLProtocol.responseData = #"{"ok":true,"eventId":"evt_abc"}"#.data(using: .utf8)!

        await AnalyticsNetwork.sendEvent(
            config: testConfig,
            eventName: "purchase",
            data: ["order_id": "ord_1001"],
            deviceID: "test-device-uuid",
            session: session
        )

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.analyticsEventURL])
        assertCommonHeaders(req)

        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        for key in ["event_name", "timestamp", "platform", "device_id"] {
            XCTAssertNotNil(json[key], "analytics/event must include '\(key)'")
        }
        XCTAssertEqual(json["platform"] as? String, "ios", "platform must be 'ios'")

        // timestamp: ISO-8601 UTC with ms precision
        assertISO8601MsTimestamp(json["timestamp"])
    }

    func testAnalyticsEventDataPresentWhenProvided() async throws {
        StubURLProtocol.responseData = #"{"ok":true,"eventId":"evt_abc"}"#.data(using: .utf8)!

        await AnalyticsNetwork.sendEvent(
            config: testConfig,
            eventName: "purchase",
            data: ["order_id": "ord_1001", "value": 29.99],
            deviceID: "test-device-uuid",
            session: session
        )

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.analyticsEventURL])
        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertNotNil(json["data"], "analytics/event must include 'data' when provided")
    }

    func testAnalyticsEventDataAbsentWhenNil() async throws {
        StubURLProtocol.responseData = #"{"ok":true,"eventId":"evt_abc"}"#.data(using: .utf8)!

        await AnalyticsNetwork.sendEvent(
            config: testConfig,
            eventName: "level_completed",
            data: nil,
            deviceID: "test-device-uuid",
            session: session
        )

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.analyticsEventURL])
        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertNil(json["data"], "analytics/event must omit 'data' when nil")
    }

    func testAnalyticsEventNoAdditionalProperties() async throws {
        StubURLProtocol.responseData = #"{"ok":true,"eventId":"evt_abc"}"#.data(using: .utf8)!

        await AnalyticsNetwork.sendEvent(
            config: testConfig,
            eventName: "purchase",
            data: nil,
            deviceID: "test-device-uuid",
            session: session
        )

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.analyticsEventURL])
        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        let allowed: Set<String> = ["event_name", "timestamp", "platform", "device_id", "data"]
        let extra = Set(json.keys).subtracting(allowed)
        XCTAssertTrue(extra.isEmpty, "analytics/event body has unexpected keys: \(extra)")
    }

    // MARK: - analytics/retention

    func testAnalyticsRetentionShape() async throws {
        StubURLProtocol.responseData = #"{"ok":true,"eventId":"evt_abc"}"#.data(using: .utf8)!

        await AnalyticsNetwork.sendRetentionEvent(
            config: testConfig,
            eventName: "app_open",
            deviceID: "test-device-uuid",
            session: session
        )

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.analyticsRetentionURL])
        assertCommonHeaders(req)

        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        for key in ["event_name", "timestamp", "platform", "device_id"] {
            XCTAssertNotNil(json[key], "analytics/retention must include '\(key)'")
        }
        XCTAssertEqual(json["platform"] as? String, "ios", "platform must be 'ios'")

        // timestamp: ISO-8601 UTC with ms precision
        assertISO8601MsTimestamp(json["timestamp"])

        // Retention NEVER carries 'data'
        XCTAssertNil(json["data"], "analytics/retention must never include 'data' key")
    }

    func testAnalyticsRetentionNoAdditionalProperties() async throws {
        StubURLProtocol.responseData = #"{"ok":true,"eventId":"evt_abc"}"#.data(using: .utf8)!

        await AnalyticsNetwork.sendRetentionEvent(
            config: testConfig,
            eventName: "app_open",
            deviceID: "test-device-uuid",
            session: session
        )

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.analyticsRetentionURL])
        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        let allowed: Set<String> = ["event_name", "timestamp", "platform", "device_id"]
        let extra = Set(json.keys).subtracting(allowed)
        XCTAssertTrue(extra.isEmpty, "analytics/retention body has unexpected keys: \(extra)")
    }
}

// MARK: - resolveAppLaunch → match-link conformance (POS-439, extends the POS-118 harness)
//
// Drives the PUBLIC one-shot `Posted.resolveAppLaunch` — via the same session-injectable
// `_resolveAppLaunch` entry point ResolveAppLaunchTests.swift uses to make the call
// interceptable by StubURLProtocol — instead of calling PostedNetwork.matchLink directly,
// so this guards that the 3.0.0 facade refactor didn't drift the match-link wire body.
//
// iOS finding: resolveAppLaunch's match-link call always encodes a ProbabilisticFingerprint.
// There is no deterministic-match code path on this platform — PostedNetwork.matchLink has a
// single ProbabilisticFingerprint-only signature, and the only `clickId` concept on iOS is
// returned in the *response* of the unrelated universal-link-click endpoint, which never
// routes through match-link. So the two cases below are: (1) the deferred branch, the only
// branch that reaches match-link, asserted against the contract's ProbabilisticFingerprint
// member with an explicit absence check for `clickId`, and (2) the link-present branch,
// which is asserted to never emit a match-link request at all.
@MainActor
final class ResolveAppLaunchMatchLinkConformanceTests: XCTestCase {
    private let config = PostedConfig(apiKey: "test-api-key", appID: "com.test.app")
    private var session: URLSession!

    private static let matchLinkURL = "https://godetour.dev/api/link/match-link"
    private static let universalClickURL = "https://godetour.dev/api/link/universal-link-click"

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        session = StubURLProtocol.makeSession()
        // Clean attribution store so fire-once actually fires the network call.
        Posted.shared.resetSession(allowDeferredRetry: true)
    }

    private func assertCommonHeaders(_ req: URLRequest, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(
            req.value(forHTTPHeaderField: "Authorization"), "Bearer test-api-key",
            "Authorization header missing or wrong", file: file, line: line
        )
        XCTAssertEqual(
            req.value(forHTTPHeaderField: "X-App-ID"), "com.test.app",
            "X-App-ID header missing or wrong", file: file, line: line
        )
        let sdk = req.value(forHTTPHeaderField: "X-SDK") ?? ""
        XCTAssertTrue(
            sdk.hasPrefix("ios/"),
            "X-SDK must start with 'ios/' — got '\(sdk)'", file: file, line: line
        )
    }

    // MARK: - Deferred branch (the only resolveAppLaunch branch that reaches match-link)

    func testResolveAppLaunchDeferredBranchEmitsContractValidProbabilisticMatchLink() async throws {
        StubURLProtocol.responseData = #"{"link":"https://example.com/promo"}"#.data(using: .utf8)!

        let result = await Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)

        let req = try XCTUnwrap(
            StubURLProtocol.capturedRequests[Self.matchLinkURL],
            "resolveAppLaunch deferred branch must POST to match-link"
        )
        XCTAssertEqual(req.httpMethod, "POST")
        assertCommonHeaders(req)
        XCTAssertTrue(result.processed)

        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        // Validate against the contract's ProbabilisticFingerprint oneOf member.
        for key in ["platform", "model", "manufacturer", "systemVersion",
                    "screenWidth", "screenHeight", "scale", "locale", "timestamp"] {
            XCTAssertNotNil(json[key], "Required ProbabilisticFingerprint key '\(key)' missing from resolveAppLaunch match-link body")
        }
        XCTAssertEqual(json["platform"] as? String, "ios", "platform must be 'ios'")

        // Documents the platform finding above: no DeterministicMatch oneOf member is ever sent.
        XCTAssertNil(
            json["clickId"],
            "resolveAppLaunch match-link body must not contain 'clickId' — iOS has no deterministic match-link branch"
        )
    }

    func testResolveAppLaunchDeferredBranchNoMatchStillEmitsContractValidBody() async throws {
        StubURLProtocol.responseData = #"{"link":null}"#.data(using: .utf8)!

        let result = await Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests[Self.matchLinkURL])
        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertNil(json["clickId"])
        XCTAssertNotNil(json["timestamp"])
        XCTAssertTrue(result.processed)
        XCTAssertNil(result.link, "no matching link should yield a nil link in result")
    }

    // MARK: - Link-present branch (proves the other resolveAppLaunch branch never touches match-link)

    func testResolveAppLaunchLinkPresentBranchNeverEmitsMatchLink() async throws {
        StubURLProtocol.responseData = #"{"allowed":true}"#.data(using: .utf8)!
        let launchURL = URL(string: "https://godetour.dev/u/summer?ref=banner")!
        let context = LaunchContext.launchOptions([.url: launchURL])

        _ = await Posted.shared._resolveAppLaunch(config: config, launchContext: context, session: session)

        XCTAssertNotNil(
            StubURLProtocol.capturedRequests[Self.universalClickURL],
            "link-present branch must call universal-link-click"
        )
        XCTAssertNil(
            StubURLProtocol.capturedRequests[Self.matchLinkURL],
            "link-present branch must never emit a match-link request"
        )
    }
}
