// FR9b clipboard-token handshake — read side (POS-229 / POS-170 plan §4, D7).
//
// The click page (C) writes the short-link URL to the iOS pasteboard VERBATIM
// (`tryWriteClipboard(pageUrl)`), and the click recorder (D) stores that identical string as
// `pastedLink`. The matcher exact-matches `pastedLink` (weight 350), so write-format == read-format
// is load-bearing: any transformation on the read side silently drops the match. These tests prove
// the SDK surfaces the pasteboard token byte-for-byte, for both the pure read-format seam and the
// real `UIPasteboard.general` round trip.
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

    // MARK: - Real UIPasteboard round trip (write like C → read via SDK path)

    @MainActor
    func testPasteboardRoundTripIsByteIdentical() async {
        let original = UIPasteboard.general.string
        defer { UIPasteboard.general.string = original ?? "" }

        // Emulate C's write: the short-link URL, verbatim. A canonical https URL so the iOS 14+
        // `.probableWebURL` gate recognizes it (that gate decides *whether* to read, not the format).
        let written = "https://godetour.dev/x9Az"
        UIPasteboard.general.string = written

        let read = await DeviceUtils.readClipboardLinkIfAvailable(shouldUseClipboard: true)
        assertByteIdentical(read, written)
    }

    @MainActor
    func testReadSkippedWhenClipboardDisabled() async {
        UIPasteboard.general.string = "https://godetour.dev/should-not-be-read"
        let read = await DeviceUtils.readClipboardLinkIfAvailable(shouldUseClipboard: false)
        XCTAssertNil(read, "shouldUseClipboard=false must skip the pasteboard read entirely")
    }
}
