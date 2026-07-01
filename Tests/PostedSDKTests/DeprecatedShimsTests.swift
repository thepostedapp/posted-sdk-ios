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

        let exp = XCTestExpectation(description: "launchOptions completion called")
        var received: PostedResult?
        Posted.shared.resolveInitialLink(config: config, launchOptions: nil) { result in
            received = result
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: 3.0)

        XCTAssertEqual(received?.link?.url, cached.link?.url,
            "resolveInitialLink must return the cached resolveAppLaunch result")
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty,
            "resolveInitialLink must not make a new network call when fire-once cache is warm")
    }

    func testResolveInitialLinkConnectionOptionsDelegatesToResolveAppLaunch() async {
        StubURLProtocol.responseData = #"{"link":"https://example.com/scene-referral"}"#.data(using: .utf8)!
        let cached = await Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)
        XCTAssertNotNil(cached.link, "Precondition: cache must hold a resolved result")

        StubURLProtocol.reset()

        let exp = XCTestExpectation(description: "connectionOptions completion called")
        var received: PostedResult?
        Posted.shared.resolveInitialLink(
            config: config,
            connectionOptions: UIScene.ConnectionOptions()
        ) { result in
            received = result
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: 3.0)

        XCTAssertEqual(received?.link?.url, cached.link?.url,
            "resolveInitialLink(connectionOptions:) must return the cached resolveAppLaunch result")
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty,
            "resolveInitialLink must not make a new network call when fire-once cache is warm")
    }
}
