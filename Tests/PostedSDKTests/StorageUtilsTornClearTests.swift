// Torn-clear regression test for StorageUtils.clearAttributionResolved() (POS-476, audit
// follow-up to POS-433). clearAttributionResolved() issues two sequential
// UserDefaults.removeObject calls with no batch/multi-remove API available, so a process
// crash/kill between them can tear the clear. The flag-removed-first ordering is what makes
// that survivable: this test simulates the torn state directly (flag gone, blob still present)
// and asserts the SDK collapses it to "unresolved," never "resolved with no cache."
import XCTest
@testable import PostedSDK

@MainActor
final class StorageUtilsTornClearTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Full clear before each test, independent of the invariant under test.
        UserDefaults.standard.removeObject(forKey: StorageUtils.Constants.attributionResolvedKey)
        UserDefaults.standard.removeObject(forKey: StorageUtils.Constants.cachedAttributionResultKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: StorageUtils.Constants.attributionResolvedKey)
        UserDefaults.standard.removeObject(forKey: StorageUtils.Constants.cachedAttributionResultKey)
        super.tearDown()
    }

    // Simulates a crash landing between clearAttributionResolved()'s two removeObject calls:
    // the flag (removed first) is already gone, but the cached blob (removed second) never got
    // torn away. This is the ONLY reachable torn state under the flag-first ordering.
    private func simulateTornClearFlagGoneBlobPresent() {
        let envelopeJSON = #"{"schemaVersion":1,"result":{"processed":true,"link":null}}"#
        UserDefaults.standard.set(
            envelopeJSON.data(using: .utf8)!,
            forKey: StorageUtils.Constants.cachedAttributionResultKey
        )
        UserDefaults.standard.removeObject(forKey: StorageUtils.Constants.attributionResolvedKey)
    }

    func testTornClearFlagGoneBlobPresentReportsUnresolved() {
        // Arrange: fully resolved state, then tear it exactly as a crash mid-clear would.
        StorageUtils.markAttributionResolved(result: PostedResult(processed: true, link: nil))
        simulateTornClearFlagGoneBlobPresent()

        XCTAssertFalse(
            StorageUtils.isAttributionResolved(),
            "Torn clear (flag gone, blob present) must report unresolved — the flag is authoritative"
        )
    }

    func testTornClearFlagGoneBlobPresentCausesReResolution() async throws {
        StubURLProtocol.reset()
        let session = StubURLProtocol.makeSession()
        let config = PostedConfig(apiKey: "test-key", appID: "com.test.app")
        Posted.shared.resetSession(allowDeferredRetry: true)

        // Arrange the torn state directly — no live crash needed to reproduce it.
        simulateTornClearFlagGoneBlobPresent()

        StubURLProtocol.responseData = #"{"link":"https://example.com/re-resolved"}"#.data(using: .utf8)!
        let result = await Posted.shared._resolveAppLaunch(config: config, launchContext: nil, session: session)

        XCTAssertNotNil(
            StubURLProtocol.capturedRequests["https://godetour.dev/api/link/match-link"],
            "A torn clear (flag gone, blob present) must be treated as unresolved and re-resolve over the network, " +
            "never short-circuit to the stale leftover blob"
        )
        XCTAssertEqual(result.link?.url, "https://example.com/re-resolved")
    }

    // Sanity check that a full, untorn clearAttributionResolved() removes both keys — guards
    // against a future refactor accidentally leaving one behind.
    func testFullClearRemovesBothFlagAndBlob() {
        StorageUtils.markAttributionResolved(result: PostedResult(processed: true, link: nil))

        StorageUtils.clearAttributionResolved()

        XCTAssertFalse(StorageUtils.isAttributionResolved())
        XCTAssertNil(StorageUtils.getCachedAttributionResult())
    }
}
