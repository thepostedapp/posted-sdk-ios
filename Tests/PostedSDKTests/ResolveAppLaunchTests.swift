// Tests for resolveAppLaunch: two-branch dispatch + fire-once + re-arm + concurrency de-dup (POS-125/POS-139/POS-140).
import XCTest
@testable import PostedSDK

@MainActor
final class ResolveAppLaunchTests: XCTestCase {
    private let config = PostedConfig(apiKey: "test-key", appID: "com.test.app")
    private var session: URLSession!

    private static let matchLinkURL = "https://godetour.dev/api/link/match-link"
    private static let universalClickURL = "https://godetour.dev/api/link/universal-link-click"

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        session = StubURLProtocol.makeSession()
        // Re-arm fire-once and legacy session flag before each test.
        Posted.shared.resetSession(allowDeferredRetry: true)
    }

    // MARK: - Deferred branch

    func testDeferredBranchHitsMatchLink() async throws {
        StubURLProtocol.responseData = #"{"link":"https://example.com/promo"}"#.data(using: .utf8)!

        let result = await Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)

        let req = try XCTUnwrap(
            StubURLProtocol.capturedRequests[Self.matchLinkURL],
            "match-link must be called on deferred branch"
        )
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertTrue(result.processed)
        XCTAssertNotNil(result.link, "deferred branch with a matched link should return a non-nil link")
    }

    func testDeferredBranchNoLinkReturnsEmpty() async throws {
        StubURLProtocol.responseData = #"{"link":null}"#.data(using: .utf8)!

        let result = await Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)

        XCTAssertNotNil(StubURLProtocol.capturedRequests[Self.matchLinkURL], "match-link must be called")
        XCTAssertTrue(result.processed)
        XCTAssertNil(result.link, "no matched link should yield a nil link in result")
    }

    // MARK: - Link-present branch

    func testLinkPresentBranchHitsUniversalLinkClick() async throws {
        // Universal-link-click returns allowed; match-link URL is not expected.
        StubURLProtocol.responseData = #"{"allowed":true}"#.data(using: .utf8)!
        let launchURL = URL(string: "https://godetour.dev/u/summer?ref=banner")!
        let context = LaunchContext.launchOptions([.url: launchURL])

        _ = await Posted.shared._resolveAppLaunch(config: config, launchContext: context, session: session)

        XCTAssertNotNil(
            StubURLProtocol.capturedRequests[Self.universalClickURL],
            "universal-link-click must be called for a https launch URL"
        )
        XCTAssertNil(
            StubURLProtocol.capturedRequests[Self.matchLinkURL],
            "match-link must NOT be called on link-present branch"
        )
    }

    func testLinkPresentBranchBlockedByClick() async throws {
        // Click endpoint returns explicit deny.
        StubURLProtocol.responseData = #"{"allowed":false}"#.data(using: .utf8)!
        let launchURL = URL(string: "https://godetour.dev/u/launch")!
        let context = LaunchContext.launchOptions([.url: launchURL])

        let result = await Posted.shared._resolveAppLaunch(config: config, launchContext: context, session: session)

        XCTAssertNil(result.link, "blocked click should produce an empty result")
    }

    // MARK: - Fire-once cache

    func testFireOnceCachesResultAndSkipsNetwork() async throws {
        StubURLProtocol.responseData = #"{"link":"https://example.com/deal"}"#.data(using: .utf8)!

        // First call — performs network resolution.
        let first = await Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)
        let requestCount = StubURLProtocol.capturedRequests.count
        XCTAssertGreaterThan(requestCount, 0, "First call must hit the network")

        // Reset stub so a new network call would produce different data.
        StubURLProtocol.reset()
        StubURLProtocol.responseData = #"{"link":"https://example.com/other"}"#.data(using: .utf8)!

        // Second call — must use cached result without network.
        let second = await Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)

        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty, "Second call must not hit the network (fire-once)")
        XCTAssertEqual(first.link?.url, second.link?.url, "Second call must return the same cached result")
    }

    // MARK: - Concurrent first-launch de-dup (POS-139)

    func testConcurrentFirstLaunchProducesExactlyOneNetworkCall() async throws {
        StubURLProtocol.responseData = #"{"link":"https://example.com/promo"}"#.data(using: .utf8)!

        // Fire two concurrent resolutions before the fire-once flag is persisted.
        async let first = Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)
        async let second = Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)

        let (result1, result2) = await (first, second)

        XCTAssertEqual(
            StubURLProtocol.requestCallCount[Self.matchLinkURL], 1,
            "Concurrent first-launch calls must produce exactly one network call"
        )
        XCTAssertEqual(result1.link?.url, result2.link?.url, "Both concurrent calls must return identical results")
    }

    // MARK: - Re-arm via resetSession

    func testResetSessionRearmsFireOnce() async throws {
        StubURLProtocol.responseData = #"{"link":null}"#.data(using: .utf8)!

        // First call — caches result.
        _ = await Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)
        XCTAssertTrue(StorageUtils.isAttributionResolved(), "Attribution must be marked resolved after first call")

        // Re-arm.
        Posted.shared.resetSession()
        XCTAssertFalse(StorageUtils.isAttributionResolved(), "resetSession must clear the fire-once flag")

        StubURLProtocol.reset()
        StubURLProtocol.responseData = #"{"link":"https://example.com/rearm"}"#.data(using: .utf8)!

        // After re-arm, next call must hit the network again.
        _ = await Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)
        XCTAssertNotNil(
            StubURLProtocol.capturedRequests[Self.matchLinkURL],
            "After resetSession, resolveAppLaunch must perform a fresh network call"
        )
    }

    // MARK: - Re-arm across a real scheduler hop (POS-352, mirrors Android POS-182)

    // Unlike testResetSessionRearmsFireOnce above (sequential awaits within a single Task),
    // this drives both resolves through Task.detached and the reset through a real
    // DispatchQueue.main.async hop, proving the re-arm survives an actual scheduler boundary
    // rather than relying on structured-concurrency ordering within one Task.
    func testResetSessionRearmsFireOnceAcrossRealSchedulerHop() async throws {
        let cfg = config
        let sess = session!
        StubURLProtocol.responseData = #"{"link":"https://example.com/first"}"#.data(using: .utf8)!

        let first = await Task.detached {
            await Posted.shared._resolveAppLaunch(config: cfg, launchContext: nil, session: sess)
        }.value
        XCTAssertNotNil(first.link)
        XCTAssertTrue(StorageUtils.isAttributionResolved(), "Attribution must be marked resolved after first call")

        // Re-arm via a real DispatchQueue.main.async hop rather than an inline call.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                Posted.shared.resetSession()
                continuation.resume()
            }
        }
        XCTAssertFalse(StorageUtils.isAttributionResolved(), "resetSession must clear the fire-once flag")

        StubURLProtocol.reset()
        StubURLProtocol.responseData = #"{"link":"https://example.com/rearm"}"#.data(using: .utf8)!

        let second = await Task.detached {
            await Posted.shared._resolveAppLaunch(config: cfg, launchContext: nil, session: sess)
        }.value

        XCTAssertNotNil(
            StubURLProtocol.capturedRequests[Self.matchLinkURL],
            "After resetSession, resolveAppLaunch must perform a fresh network call across a real scheduler hop"
        )
        XCTAssertEqual(second.link?.url, "https://example.com/rearm")
    }

    // MARK: - resetSession mid-resolve (POS-352, mirrors Android POS-182)

    // Uses a gated mock-server handshake (StubURLProtocol.requestReceived / .releaseResponse) to
    // force deterministic overlap between an in-flight resolve and a concurrent resetSession()
    // call — no sleeps. Guards against the in-flight resolution's completion clobbering the reset
    // with a stale fire-once write (clear-under-lock + re-resolve).
    func testResetSessionMidResolveHonoredOnNextResolve() async throws {
        let requestReceived = DispatchSemaphore(value: 0)
        let releaseResponse = DispatchSemaphore(value: 0)
        StubURLProtocol.requestReceived = requestReceived
        StubURLProtocol.releaseResponse = releaseResponse
        StubURLProtocol.responseData = #"{"link":"https://example.com/in-flight"}"#.data(using: .utf8)!

        // Start a resolve but don't await it yet — its network call is gated open on the stub.
        async let inFlight = Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)

        // Block deterministically until the gated stub has actually received the request,
        // proving genuine overlap rather than relying on timing.
        await waitForSemaphore(requestReceived)

        // resetSession() lands while the first resolve is still suspended on the network call.
        Posted.shared.resetSession()
        XCTAssertFalse(
            StorageUtils.isAttributionResolved(),
            "resetSession must clear the flag while a resolve is in flight"
        )

        // Let the gated in-flight resolve complete.
        releaseResponse.signal()
        _ = await inFlight

        // The in-flight resolve's completion must not clobber the reset with a stale write.
        XCTAssertFalse(
            StorageUtils.isAttributionResolved(),
            "resetSession's clear must be honored — the in-flight resolve's completion must not re-mark fire-once"
        )

        StubURLProtocol.reset()
        StubURLProtocol.responseData = #"{"link":"https://example.com/after-reset"}"#.data(using: .utf8)!

        // The next resolve must make a fresh network call (re-resolve), not return stale cache.
        let next = await Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)

        XCTAssertNotNil(
            StubURLProtocol.capturedRequests[Self.matchLinkURL],
            "resetSession invoked mid-resolve must be honored: the next resolveAppLaunch must re-resolve over the network"
        )
        XCTAssertEqual(next.link?.url, "https://example.com/after-reset")
    }

    private func waitForSemaphore(_ semaphore: DispatchSemaphore) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                semaphore.wait()
                continuation.resume()
            }
        }
    }

    // MARK: - Defensive fire-once persistence (POS-140)

    func testFlagAndCacheConsistentAfterResolution() async throws {
        StubURLProtocol.responseData = #"{"link":"https://example.com/promo"}"#.data(using: .utf8)!

        _ = await Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)

        XCTAssertTrue(StorageUtils.isAttributionResolved(), "Flag must be set after resolution")
        let cached = StorageUtils.getCachedAttributionResult()
        XCTAssertNotNil(cached, "Cache must be decodable after resolution (flag never set without decodable blob)")
        XCTAssertTrue(cached?.processed == true)
        XCTAssertNotNil(cached?.link)
    }

    func testCacheVersionMismatchReturnsNilAndCausesReResolution() async throws {
        // Write an old-version envelope directly to UserDefaults.
        let oldVersionJSON = #"{"schemaVersion":0,"result":{"processed":true,"link":null}}"#
        UserDefaults.standard.set(
            oldVersionJSON.data(using: .utf8)!,
            forKey: StorageUtils.Constants.cachedAttributionResultKey
        )
        UserDefaults.standard.set(true, forKey: StorageUtils.Constants.attributionResolvedKey)

        // getCachedAttributionResult must return nil on version mismatch.
        XCTAssertNil(
            StorageUtils.getCachedAttributionResult(),
            "Version mismatch must return nil (safe drop, not crash)"
        )

        // Even though flag is true, resolveAppLaunch re-resolves when cache is nil.
        StubURLProtocol.responseData = #"{"link":"https://example.com/new"}"#.data(using: .utf8)!
        let result = await Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)

        XCTAssertNotNil(
            StubURLProtocol.capturedRequests[Self.matchLinkURL],
            "Version mismatch must trigger a fresh network call"
        )
        XCTAssertNotNil(result.link, "Re-resolution must return the new network result")

        // After re-resolution the cache must hold the current-version envelope.
        XCTAssertNotNil(
            StorageUtils.getCachedAttributionResult(),
            "Cache must be readable with current version after re-resolution"
        )
    }

    func testCorruptCacheDataReturnsNilAndCausesReResolution() async throws {
        // Write garbage bytes to simulate corrupt storage.
        UserDefaults.standard.set(
            Data([0xDE, 0xAD, 0xBE, 0xEF]),
            forKey: StorageUtils.Constants.cachedAttributionResultKey
        )
        UserDefaults.standard.set(true, forKey: StorageUtils.Constants.attributionResolvedKey)

        XCTAssertNil(
            StorageUtils.getCachedAttributionResult(),
            "Corrupt data must return nil (safe decode failure)"
        )

        StubURLProtocol.responseData = #"{"link":null}"#.data(using: .utf8)!
        _ = await Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)

        XCTAssertNotNil(
            StubURLProtocol.capturedRequests[Self.matchLinkURL],
            "Corrupt cache must trigger a fresh network call"
        )
    }
}
