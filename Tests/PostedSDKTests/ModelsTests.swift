// Tests for the public `PostedResult.resolutionFailed` signal (POS-471) and the persisted
// fire-once cache envelope's Codable shape, which must stay byte-unchanged (POS-460).
import XCTest
@testable import PostedSDK

final class ModelsTests: XCTestCase {

    // MARK: - resolutionFailed producers

    func testFailedResultExposesResolutionFailedTrue() {
        let result = PostedResult.failed()

        XCTAssertTrue(result.resolutionFailed)
        XCTAssertTrue(result.processed)
        XCTAssertNil(result.link)
    }

    func testEmptyResultExposesResolutionFailedFalse() {
        let result = PostedResult.empty()

        XCTAssertFalse(result.resolutionFailed)
        XCTAssertTrue(result.processed)
        XCTAssertNil(result.link)
    }

    func testMatchedLinkResultExposesResolutionFailedFalse() {
        let link = PostedLink(
            url: "https://example.com/promo",
            route: "/promo",
            pathname: "/promo",
            params: [:],
            type: .deferred
        )
        let result = PostedResult(processed: true, link: link)

        XCTAssertFalse(result.resolutionFailed)
        XCTAssertEqual(result.link?.url, "https://example.com/promo")
    }

    // MARK: - Cache round-trip: persisted JSON shape must stay unchanged

    func testCacheRoundTripYieldsResolutionFailedFalseRegardlessOfSource() throws {
        let failed = PostedResult.failed()

        let data = try JSONEncoder().encode(failed)
        let decoded = try JSONDecoder().decode(PostedResult.self, from: data)

        XCTAssertFalse(
            decoded.resolutionFailed,
            "a reloaded/persisted result must never report resolutionFailed == true, even if the " +
            "original in-memory result was a failure — fire-once must not fire on failure"
        )
        XCTAssertTrue(decoded.processed)
        XCTAssertNil(decoded.link)
    }

    func testCacheRoundTripDoesNotAddResolutionFailedKeyToWireJSON() throws {
        let failed = PostedResult.failed()

        let data = try JSONEncoder().encode(failed)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(json["resolutionFailed"], "resolutionFailed must never appear on the wire/cache JSON")
        XCTAssertEqual(
            Set(json.keys), Set(["processed", "link"]),
            "persisted cache envelope shape must stay exactly {processed, link} — no new keys"
        )
    }

    func testCacheRoundTripPreservesMatchedLinkAndFalseResolutionFailed() throws {
        let link = PostedLink(
            url: "https://example.com/deal",
            route: "/deal",
            pathname: "/deal",
            params: ["ref": "banner"],
            type: .verified
        )
        let original = PostedResult(processed: true, link: link)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PostedResult.self, from: data)

        XCTAssertFalse(decoded.resolutionFailed)
        XCTAssertEqual(decoded.link?.url, "https://example.com/deal")
        XCTAssertEqual(decoded.link?.params, ["ref": "banner"])
    }
}
