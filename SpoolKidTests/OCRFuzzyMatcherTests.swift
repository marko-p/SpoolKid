import Testing
@testable import SpoolKid

struct OCRFuzzyMatcherTests {

    // MARK: - Basic distance matching

    @Test func matcherResolvesPETC_to_PETG() {
        // C→G substitution, distance 1, unique match
        let result = OCRFuzzyMatcher.bestFuzzyMatch("PETC", in: ["PETG", "PLA", "ABS"])
        #expect(result == "PETG")
    }

    @Test func matcherResolves_P1A_to_PLA() {
        // 1→L substitution (OCR confuses 1/l/I), distance 1
        // Note: the parser applies a ≥4-char length guard before calling the matcher,
        // so "P1A" is not recovered at the parser level — this test verifies the
        // underlying distance logic.
        let result = OCRFuzzyMatcher.bestFuzzyMatch("P1A", in: ["PLA", "PETG", "ABS", "ASA"])
        #expect(result == "PLA")
    }

    @Test func matcherResolvesSevenCharMisreadAtDistance2() {
        // "PETG-CQ" → "PETG-CF": two substitutions; threshold for len ≥ 7 is 2
        let result = OCRFuzzyMatcher.bestFuzzyMatch("PETG-CQ", in: ["PETG-CF", "PLA-CF", "PETG"])
        #expect(result == "PETG-CF")
    }

    @Test func matcherReturnsSelfOnExactMatch() {
        let result = OCRFuzzyMatcher.bestFuzzyMatch("PETG", in: ["PETG", "PLA", "ABS"])
        #expect(result == "PETG")
    }

    // MARK: - Ambiguity guard

    @Test func matcherRejectsAmbiguousToken() {
        // "XPLA" is distance 1 from both "CPLA" and "MPLA" → ambiguous → nil
        let result = OCRFuzzyMatcher.bestFuzzyMatch("XPLA", in: ["CPLA", "MPLA", "ABS"])
        #expect(result == nil)
    }

    @Test func matcherResolvesWhenOneEntryIsCloser() {
        // "PETG" (exact) and "PETQ" misread: PETQ is distance 1 from PETG, distance ≥ 3 from others
        let result = OCRFuzzyMatcher.bestFuzzyMatch("PETQ", in: ["PETG", "PLA", "ABS"])
        #expect(result == "PETG")
    }

    // MARK: - Longer-entry-contains guard (preserves longest-first intent)

    @Test func matcherRejectsPET_becauseLongerEntryContainsIt() {
        // "PETG" is longer than "PET" and contains "PET" as a prefix → guard fires
        let result = OCRFuzzyMatcher.bestFuzzyMatch("PET", in: ["PETG", "PLA", "ABS"])
        #expect(result == nil)
    }

    @Test func matcherAllowsPETC_evenThoughPETGCFExists() {
        // "PETG-CF" does NOT contain "PETC" as a substring → guard does not fire
        let result = OCRFuzzyMatcher.bestFuzzyMatch("PETC", in: ["PETG-CF", "PETG", "PLA"])
        #expect(result == "PETG")
    }

    // MARK: - Distance threshold boundary

    @Test func matcherRejectsDistance2ForShortToken() {
        // "PXYZ" (4 chars) vs "PETG" (4 chars): distance 3 > threshold 1 → no match
        let result = OCRFuzzyMatcher.bestFuzzyMatch("PXYZ", in: ["PETG", "PLA"])
        #expect(result == nil)
    }

    @Test func matcherRejectsDistance3ForLongToken() {
        // "PETG-XXY" (8 chars) vs "PETG-CF" (7 chars): 3 edits — exceeds threshold of 2 for len ≥ 7
        let result = OCRFuzzyMatcher.bestFuzzyMatch("PETG-XXY", in: ["PETG-CF", "PETG"])
        #expect(result == nil)
    }

    // MARK: - Empty / trivial inputs

    @Test func matcherReturnsNilForEmptyToken() {
        #expect(OCRFuzzyMatcher.bestFuzzyMatch("", in: ["PLA"]) == nil)
    }

    @Test func matcherReturnsNilForEmptyVocabulary() {
        #expect(OCRFuzzyMatcher.bestFuzzyMatch("PETG", in: []) == nil)
    }

    // MARK: - Levenshtein sanity

    @Test func levenshteinSymmetry() {
        let ab = OCRFuzzyMatcher.levenshtein("PETG", "PETC")
        let ba = OCRFuzzyMatcher.levenshtein("PETC", "PETG")
        #expect(ab == ba)
        #expect(ab == 1)
    }

    @Test func levenshteinIdentity() {
        #expect(OCRFuzzyMatcher.levenshtein("PLA", "PLA") == 0)
    }
}
