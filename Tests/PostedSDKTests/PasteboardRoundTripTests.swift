// FR9b clipboard-token handshake — read side (POS-229 / POS-170 plan §4, D7).
//
// The click page (C) writes the short-link URL to the iOS pasteboard VERBATIM
// (`tryWriteClipboard(pageUrl)`), and the click recorder (D) stores that identical string as
// `pastedLink`. The matcher exact-matches `pastedLink` (weight 350), so write-format == read-format
// is load-bearing: any transformation on the read side silently drops the match. These tests prove
// the SDK surfaces the pasteboard token byte-for-byte through the read-format seam
// (`DeviceUtils.pastedLink(fromPasteboardString:)`), which is the exact string `readClipboardLinkIfAvailable`
// hands the fingerprint — so byte-identity here == byte-identity end to end.
//
// These tests deliberately never touch the live `UIPasteboard.general` singleton. On the unattended CI
// simulator any access to the pasteboard service can block indefinitely (both the iOS-14
// `detectPatterns` gate and even a plain `.string` get/set), which hung the `test` job for 30+ min on
// prior attempts. The seam takes the pasteboard string as a parameter, so it proves the FR9b *format*
// contract host-independently without depending on that flaky service. The `.probableWebURL` gate is a
// *whether-to-read* privacy decision, not part of the format handshake, so it is out of scope here.
import XCTest
@testable import PostedSDK

final class PasteboardRoundTripTests: XCTestCase {
    /// Strings that mirror what C can write: canonical short link, query params, trailing slash,
    /// preserved casing, percent-encoding, unicode, empty. Read format must be byte-identical to each.
    private static let writeFormatSamples: [String] = [
        "https://godetour.dev/x9Az",
        "https://godetour.dev/x9Az?utm_source=ig&variant=b",
        "https://godetour.dev/x9Az/",
        "https://GoDetour.dev/X9aZ",                       // casing must survive (no lowercasing)
        "https://godetour.dev/promo?q=a%20b&e=%C3%A9",     // percent-encoding must survive verbatim
        "https://godetour.dev/naïve-café-🚀",              // non-ASCII must survive verbatim
        "  https://godetour.dev/x9Az  ",                   // surrounding whitespace must NOT be trimmed
        "",                                                // empty string is not nil
    ]

    private func assertByteIdentical(
        _ actual: String?, _ expected: String,
        file: StaticString = #file, line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("expected a non-nil pastedLink, got nil", file: file, line: line)
            return
        }
        XCTAssertEqual(actual, expected, "pastedLink must equal C's write format", file: file, line: line)
        // Explicit byte-for-byte comparison — the FR9b handshake is UTF-8 exact-match, not just String==.
        XCTAssertEqual(
            Array(actual.utf8), Array(expected.utf8),
            "pastedLink bytes must be identical to C's write format", file: file, line: line
        )
    }

    // MARK: - Pure read-format seam (host-independent, deterministic)

    func testReadFormatIsVerbatimIdentity() {
        for sample in Self.writeFormatSamples {
            assertByteIdentical(DeviceUtils.pastedLink(fromPasteboardString: sample), sample)
        }
    }

    func testReadFormatPreservesNil() {
        XCTAssertNil(
            DeviceUtils.pastedLink(fromPasteboardString: nil),
            "a nil pasteboard must surface as nil pastedLink (JSON null), never coerced to a string"
        )
    }

    // MARK: - Read-path guard (no live pasteboard access)

    @MainActor
    func testReadSkippedWhenClipboardDisabled() async {
        // `shouldUseClipboard: false` must short-circuit before any pasteboard access at all. We assert
        // this without seeding `UIPasteboard.general` — the guard returns `nil` ahead of every
        // pasteboard call, and seeding the live singleton is exactly the flaky CI hang this suite avoids.
        let read = await DeviceUtils.readClipboardLinkIfAvailable(shouldUseClipboard: false)
        XCTAssertNil(read, "shouldUseClipboard=false must skip the pasteboard read entirely")
    }
}
