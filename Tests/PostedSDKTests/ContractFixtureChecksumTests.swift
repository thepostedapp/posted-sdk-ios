// Whole-file contract drift guard — POS-580 / POS-283.
//
// Until now iOS vendored no copy of the SDK-backend contract; the canonical
// digest was recorded only in a header comment in ContractConformanceTests,
// which nothing enforced. This vendors the contract into
// Tests/PostedSDKTests/Fixtures/ and asserts it.
//
// The vendored copy must stay byte-identical to the canonical contract owned
// by posted-sdk-admin at contract/posted-backend-contract.yaml.
//
// TO RE-VENDOR after the canonical contract changes:
//   1. copy canonical over Tests/PostedSDKTests/Fixtures/posted-backend-contract.yaml
//   2. shasum -a 256 Tests/PostedSDKTests/Fixtures/posted-backend-contract.yaml
//   3. update canonicalSha256 below
//   4. move the sibling pins in the same change (Flutter
//      test/contract_drift_test.dart, Android ContractFixtureChecksumTest.kt,
//      React Native src/__tests__/contract-drift.test.ts) and the digest quoted
//      in the ContractConformanceTests header
//
// KNOWN LIMITATION: a pinned checksum detects this vendored copy being edited,
// but NOT the canonical contract drifting ahead of it. That needs cross-repo
// read access in CI and is deliberately out of scope.

import CryptoKit
import XCTest

final class ContractFixtureChecksumTests: XCTestCase {

    /// Canonical contract v1.1.0 digest.
    private static let canonicalSha256 =
        "9a6d4ce0013d4b9de4f2199ce603855890c39e93d605c7195dd8b8275a088bde"

    private func fixtureData() throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "posted-backend-contract",
                withExtension: "yaml"
            ),
            "Missing vendored contract fixture in the test bundle."
        )
        return try Data(contentsOf: url)
    }

    func testVendoredContractMatchesPinnedCanonicalChecksum() throws {
        let digest = SHA256.hash(data: try fixtureData())
        let actual = digest.map { String(format: "%02x", $0) }.joined()

        XCTAssertEqual(
            actual,
            Self.canonicalSha256,
            "Vendored contract drifted from canonical. Re-vendor and update "
                + "canonicalSha256 (see this file's header)."
        )
    }

    func testVendoredContractDeclaresVersion110() throws {
        let text = try XCTUnwrap(String(data: try fixtureData(), encoding: .utf8))
        XCTAssertTrue(
            text.contains("version: 1.1.0"),
            "Vendored contract is not v1.1.0; re-vendor from canonical."
        )
    }

    func testVendoredContractTargetsPostedappHost() throws {
        let text = try XCTUnwrap(String(data: try fixtureData(), encoding: .utf8))
        XCTAssertTrue(
            text.contains("https://attr.postedapp.com"),
            "Contract must declare attr.postedapp.com as the API server."
        )
        XCTAssertFalse(
            text.contains("godetour.dev"),
            "Contract must not reference the third-party godetour.dev host."
        )
    }
}
