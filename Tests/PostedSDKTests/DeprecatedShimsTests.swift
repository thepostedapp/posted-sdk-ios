// Tests for deprecated shims (POS-126): processLink variants + resolveInitialLink.
// The whole class is marked deprecated to suppress call-site warnings on deprecated APIs.
import XCTest
@testable import PostedSDK
import UIKit

@available(*, deprecated)
@MainActor
final class DeprecatedShimsTests: XCTestCase {
    private let config = PostedConfig(apiKey: "test-key", appID: "com.test.app")
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        session = StubURLProtocol.makeSession()
        Posted.shared.resetSession(allowDeferredRetry: true)
        Posted._resetDeprecationWarnings()
    }

    // MARK: - processLink (sync, no network)

    func testProcessLinkSyncReturnsResult() {
        let url = URL(string: "https://example.com/product/42")!
        let result = Posted.shared.processLink(url)
        XCTAssertTrue(result.processed)
        XCTAssertNotNil(result.link)
        XCTAssertEqual(result.link?.url, url.absoluteString)
    }

    func testProcessLinkSyncInfraUrlReturnsEmpty() {
        // "about:blank" is the infrastructure URL string recognised by isInfrastructureUrl.
        // processLink must return .empty() — processed: true (always), link: nil.
        guard let url = URL(string: "about:blank") else { return }
        let result = Posted.shared.processLink(url)
        XCTAssertTrue(result.processed)
        XCTAssertNil(result.link)
    }

    // MARK: - processLink async (nil config → no network)

    func testProcessLinkAsyncNilConfigNoNetwork() async {
        let url = URL(string: "https://example.com/product/42")!
        let result = await Posted.shared.processLink(url, config: nil)
        XCTAssertTrue(result.processed)
        XCTAssertNotNil(result.link)
    }

    func testProcessLinkRawStringNilConfigNoNetwork() async {
        let result = await Posted.shared.processLink("https://example.com/product/42", config: nil)
        XCTAssertTrue(result.processed)
        XCTAssertNotNil(result.link)
    }

    // MARK: - resolveInitialLink delegation contract

    // Both overloads delegate to resolveAppLaunch. We prove this by:
    // 1. Pre-populating the fire-once cache via _resolveAppLaunch with a stub session.
    // 2. Calling resolveInitialLink — it must return the cached result with no new network call.
    // This verifies the delegation path, not just that the method compiles.

    func testResolveInitialLinkLaunchOptionsDelegatesToResolveAppLaunch() async {
        StubURLProtocol.responseData = #"{"link":"https://example.com/referral"}"#.data(using: .utf8)!
        let cached = await Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)
        XCTAssertNotNil(cached.link, "Precondition: cache must hold a resolved result")

        StubURLProtocol.reset()

        let received: PostedResult = await withCheckedContinuation { cont in
            Posted.shared.resolveInitialLink(config: config, launchOptions: nil) { cont.resume(returning: $0) }
        }

        XCTAssertEqual(received.link?.url, cached.link?.url,
            "resolveInitialLink must return the cached resolveAppLaunch result")
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty,
            "resolveInitialLink must not make a new network call when fire-once cache is warm")
    }

    // UIScene.ConnectionOptions has no public initializer, so the connectionOptions overload
    // cannot be exercised by fabricating that argument in unit tests. Instead we test
    // _resolveInitialLink — the shared delegation core that both public overloads call —
    // proving the same fire-once/no-new-request contract for both paths. The connectionOptions
    // -> LaunchContext.connectionOptions argument mapping itself is covered separately in
    // ConnectionOptionsMappingTests.swift via the `ConnectionOptionsMapping` seam (POS-173).
    func testResolveInitialLinkSharedHelperDelegatesToResolveAppLaunch() async {
        StubURLProtocol.responseData = #"{"link":"https://example.com/scene-referral"}"#.data(using: .utf8)!
        let cached = await Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)
        XCTAssertNotNil(cached.link, "Precondition: cache must hold a resolved result")

        StubURLProtocol.reset()

        let received: PostedResult = await withCheckedContinuation { cont in
            Posted.shared._resolveInitialLink(config: config, launchContext: nil) { cont.resume(returning: $0) }
        }

        XCTAssertEqual(received.link?.url, cached.link?.url,
            "_resolveInitialLink (shared path for both overloads) must return the cached result")
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty,
            "_resolveInitialLink must not make a new network call when fire-once cache is warm")
    }

    // MARK: - Deprecation warn (POS-174)

    // Verifies the launchOptions overload emits exactly one deprecation warning. The
    // connectionOptions overload itself still cannot be called from unit tests (UIScene.ConnectionOptions
    // has no public initialiser), so its warning emission is not separately assertable here.
    func testResolveInitialLinkLaunchOptionsEmitsDeprecationWarn() async {
        // Pre-warm fire-once cache via the stub session so resolveAppLaunch returns immediately.
        StubURLProtocol.responseData = #"{"link":"https://example.com/referral"}"#.data(using: .utf8)!
        _ = await Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)
        StubURLProtocol.reset()

        var capturedWarnings: [String] = []
        PostedLogger._warnSink = { _, message in capturedWarnings.append(message) }
        defer { PostedLogger._warnSink = nil }

        let _: PostedResult = await withCheckedContinuation { cont in
            Posted.shared.resolveInitialLink(config: config, launchOptions: nil) { cont.resume(returning: $0) }
        }

        let deprecationWarns = capturedWarnings.filter { $0.contains("[Posted] resolveInitialLink() is deprecated and will be removed in 4.0.0. Use resolveAppLaunch() instead.") }
        XCTAssertEqual(deprecationWarns.count, 1,
            "resolveInitialLink(launchOptions:) must emit exactly one deprecation warning per call")
    }

    // MARK: - Deprecation warn-once de-dup (POS-516)

    func testProcessLinkSyncWarnsOnce() {
        var captured: [String] = []
        PostedLogger._warnSink = { _, message in captured.append(message) }
        defer { PostedLogger._warnSink = nil }

        let url = URL(string: "https://example.com/product/42")!
        _ = Posted.shared.processLink(url)
        _ = Posted.shared.processLink(url)
        _ = Posted.shared.processLink(url)

        let deprecationWarns = captured.filter { $0.contains("[Posted] processLink() is deprecated and will be removed in 4.0.0. Use resolveAppLaunch() instead.") }
        XCTAssertEqual(deprecationWarns.count, 1, "processLink(_:) must warn at most once per session")
    }

    func testProcessLinkConfigOverloadsShareDeprecationKey() async {
        var captured: [String] = []
        PostedLogger._warnSink = { _, message in captured.append(message) }
        defer { PostedLogger._warnSink = nil }

        let url = URL(string: "https://example.com/product/42")!
        _ = await Posted.shared.processLink(url, config: nil)
        _ = await Posted.shared.processLink(url.absoluteString, config: nil)

        let deprecationWarns = captured.filter { $0.contains("[Posted] processLink() is deprecated and will be removed in 4.0.0. Use resolveAppLaunch() instead.") }
        XCTAssertEqual(deprecationWarns.count, 1,
            "processLink(_:config:) URL and String overloads share identical message text and must share one warn-once key")
    }

    func testDeprecationWarningsArePerMethodIndependent() async {
        var captured: [String] = []
        PostedLogger._warnSink = { _, message in captured.append(message) }
        defer { PostedLogger._warnSink = nil }

        let url = URL(string: "https://example.com/product/42")!
        _ = Posted.shared.processLink(url)
        _ = await Posted.shared.processLink(url, config: nil)

        // processLink(_:) and processLink(_:config:) share identical canonical wording (both
        // reduce to the bare "processLink()" name), but are keyed independently in warnOnce, so
        // both must still fire rather than one silencing the other.
        let deprecationWarns = captured.filter { $0.contains("[Posted] processLink() is deprecated and will be removed in 4.0.0. Use resolveAppLaunch() instead.") }
        XCTAssertEqual(deprecationWarns.count, 2,
            "processLink(_:) and processLink(_:config:) have independent warn-once keys and must each fire once")
    }

    func testDeprecationWarningRearmsAfterReset() {
        var captured: [String] = []
        PostedLogger._warnSink = { _, message in captured.append(message) }
        defer { PostedLogger._warnSink = nil }

        let url = URL(string: "https://example.com/product/42")!
        _ = Posted.shared.processLink(url)
        Posted._resetDeprecationWarnings()
        _ = Posted.shared.processLink(url)

        let deprecationWarns = captured.filter { $0.contains("[Posted] processLink() is deprecated and will be removed in 4.0.0. Use resolveAppLaunch() instead.") }
        XCTAssertEqual(deprecationWarns.count, 2, "_resetDeprecationWarnings() must re-arm the warn-once guard")
    }
}
