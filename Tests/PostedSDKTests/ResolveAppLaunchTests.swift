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

    // MARK: - resetSession mid-resolve must not clobber a fresher in-flight resolve (POS-267,
    // mirrors RN POS-154's inFlight-clear-under-lock guard)

    // A resolve started before resetSession() ("stale") settling after the reset must not persist
    // its result or leave stale in-flight bookkeeping behind for a later caller to join. Two real
    // concurrent network legs (stale + fresh, both genuinely in flight at once) reliably escape
    // StubURLProtocol in CI — two independent ephemeral sessions racing on a shared static analyzer
    // both hit the real network and time out, hanging the test's semaphores rather than the SDK
    // call under test. So this proves the epoch guard with exactly one network leg in flight at a
    // time: gate `stale`, reset, assert the bookkeeping was abandoned synchronously (no second live
    // request needed for that), release `stale` and assert it didn't clobber anything, THEN run
    // `fresh` only once `stale` has fully settled. True concurrent third-caller de-dup is POS-139's
    // single-flight territory, not this epoch-guard invariant, and is intentionally not re-driven
    // here.
    //
    // Driven through the link-present branch (sendUniversalLinkClick), NOT the deferred branch:
    // the deferred branch's DeviceUtils.getFingerprint() drives a shared-static WKWebView, which
    // has its own pre-existing race (tracked separately as POS-472) that surfaces as a CI hang the
    // moment two real resolutions run concurrently.
    func testResetSessionMidResolveDoesNotClobberSubsequentDedup() async throws {
        let staleURL = URL(string: "https://example.com/campaign/stale/click")!
        let freshURL = URL(string: "https://example.com/campaign/fresh/click")!

        let staleReceived = DispatchSemaphore(value: 0)
        let staleRelease = DispatchSemaphore(value: 0)
        StubURLProtocol.requestReceived = staleReceived
        StubURLProtocol.releaseResponse = staleRelease
        StubURLProtocol.responseData = #"{"allowed":true}"#.data(using: .utf8)!

        async let stale = Posted.shared._resolveAppLaunch(
            config: config,
            launchContext: .launchOptions([.url: staleURL]),
            session: session
        )
        // `startLoading()` itself signals this, proving `stale` is genuinely in-flight rather than
        // relying on a timing guess.
        await waitForSemaphore(staleReceived)

        let generationBeforeReset = Posted.shared.debugResolutionGeneration
        XCTAssertTrue(
            Posted.shared.debugHasInFlightResolutionTask,
            "stale must be registered as in-flight before reset"
        )

        // resetSession() lands while `stale` is still parked on the network.
        Posted.shared.resetSession()

        // The epoch-guard proof: resetSession() must bump the generation and abandon the in-flight
        // pointer synchronously, before stale ever settles — no second live network call needed to
        // show that a caller arriving right now would no longer see stale's task.
        XCTAssertEqual(
            Posted.shared.debugResolutionGeneration, generationBeforeReset + 1,
            "resetSession must bump the generation synchronously"
        )
        XCTAssertFalse(
            Posted.shared.debugHasInFlightResolutionTask,
            "resetSession must abandon the stale in-flight pointer synchronously, before stale settles"
        )

        // Let `stale` complete now that reset has already landed.
        staleRelease.signal()
        let staleResult = await stale

        // The actual clobber assertion POS-267 cares about: a resolution in flight across
        // resetSession() must not re-arm fire-once or repopulate the cache once it settles.
        XCTAssertFalse(
            StorageUtils.isAttributionResolved(),
            "A stale resolution settling after reset must not re-arm fire-once"
        )
        XCTAssertNil(
            StorageUtils.getCachedAttributionResult(),
            "A stale resolution settling after reset must not repopulate the cache"
        )
        XCTAssertEqual(staleResult.link?.url, staleURL.absoluteString, "stale's own caller still observes its own result")

        // Only now — stale fully settled, nothing concurrent — does a fresh post-reset resolution
        // run, proving the next launch re-resolves cleanly under the new generation.
        StubURLProtocol.requestReceived = nil
        StubURLProtocol.releaseResponse = nil
        StubURLProtocol.responseData = #"{"allowed":true}"#.data(using: .utf8)!

        let freshResult = await Posted.shared._resolveAppLaunch(
            config: config,
            launchContext: .launchOptions([.url: freshURL]),
            session: session
        )

        XCTAssertEqual(
            StubURLProtocol.requestCallCount[Self.universalClickURL], 2,
            "stale and fresh each fire exactly one network call"
        )
        XCTAssertEqual(freshResult.link?.url, freshURL.absoluteString)
        XCTAssertTrue(StorageUtils.isAttributionResolved(), "fresh's resolution must re-arm fire-once for the new generation")
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
