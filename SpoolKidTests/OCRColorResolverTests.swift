import Testing
@testable import SpoolKid

struct OCRColorResolverTests {
    @Test func resolvesSingleTokenColorsToHex() {
        // Exact hexes track the bundled catalogue (large, real-world data the owner
        // refreshes), so assert that common single-token colours resolve to a valid hex
        // rather than pinning brittle values. Precise match ORDER is covered below.
        for input in ["Black PLA", "blue spool", "Beige filament"] {
            let hex = OCRColorResolver.resolveHex(from: input)
            #expect(hex?.count == 6)
        }
    }

    @Test func usesLongestPhraseFirstForColorFamilies() {
        #expect(OCRColorResolver.resolveHex(from: "Black Cherry matte") == "5D2E34")
        #expect(OCRColorResolver.resolveHex(from: "Army Green PLA") == "27352E")
    }

    @Test func resolvesBundledColorNames() {
        #expect(OCRColorResolver.resolveHex(from: "Avocado Green TPU") == "49ED5A")
        #expect(OCRColorResolver.resolveHex(from: "Azure Blue PLA") == "007DFA")
    }

    @Test func returnsNilWhenNoLexiconMatchExists() {
        // Nonsense consonant clusters no catalogue colour name contains.
        #expect(OCRColorResolver.resolveHex(from: "qwzx flarn") == nil)
    }

    @Test func doesNotMatchBaseColorsInsideLargerWords() {
        #expect(OCRColorResolver.resolveHex(from: "blackberry sparkle") == nil)
        #expect(OCRColorResolver.resolveHex(from: "blueberry finish") == nil)
    }

    @Test func resolvesHyphenatedColorPhrases() {
        #expect(OCRColorResolver.resolveHex(from: "Blue-Green PLA") != nil)
        #expect(OCRColorResolver.resolveHex(from: "Off-White filament") != nil)
    }

    @Test func labelWordsAreNotResolvedAsColors() {
        // "Color" appears literally on spool labels and must never resolve to a hex
        // (spec 049 — it was a junk catalogue entry that hijacked color resolution).
        #expect(OCRColorResolver.resolveHex(from: "Color") == nil)
        // When a real colour follows the label word, the real colour wins.
        #expect(OCRColorResolver.resolveHex(from: "Color: Blue") == "052BC2")
    }

    @Test func materialPrefixedColorsResolveToCleanHexNotPollutedCatalogueValue() {
        // The vocabulary script (preprocess_ocr_vocabulary.py) strips material-prefixed
        // catalogue colour phrases ("PLA - Black", "PETG - Grey") so they collapse into the
        // clean colour entry — the resolved *hex* must be the clean colour, not the polluted
        // catalogue value the prefixed phrase used to carry (e.g. "PLA - Black" was 0B0203).
        // Asserting equality with the bare colour keeps this robust to catalogue refreshes.
        let blackBare = OCRColorResolver.resolveHex(from: "Black")
        #expect(OCRColorResolver.resolveHex(from: "PLA Black") == blackBare)
        let greyBare = OCRColorResolver.resolveHex(from: "Grey")
        #expect(OCRColorResolver.resolveHex(from: "PETG Grey") == greyBare)
    }

    @Test func trailingIndexColorsCollapseToBareColor() {
        // "White 1" / "Black 2" (a stray label index digit) are stripped at the source, so
        // they resolve to the same hex as the bare colour rather than a separate entry.
        #expect(OCRColorResolver.resolveHex(from: "White 1") == OCRColorResolver.resolveHex(from: "White"))
    }
}
