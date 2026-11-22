import Foundation

/// Bounded fuzzy vocabulary matcher for OCR misread recovery.
///
/// Used as a fallback when exact vocabulary matching fails.
/// Guards are the point: see `bestFuzzyMatch` for full invariants.
enum OCRFuzzyMatcher {

    /// Returns the canonical vocabulary entry whose Levenshtein distance to `token` is
    /// within bounds and unambiguous, or nil otherwise.
    ///
    /// Guards (all must pass):
    /// - Distance ≤ 1 for token length < 7; ≤ 2 for length ≥ 7.
    /// - Exactly one vocabulary entry at the minimum distance (ambiguity → nil).
    /// - No longer vocabulary entry contains `token` as a substring; this preserves
    ///   the longest-first ordering the parser relies on (e.g. "PETG" inside "PETG-CF").
    ///
    /// Callers are responsible for any minimum-length guard appropriate to their domain.
    static func bestFuzzyMatch(_ token: String, in vocabulary: [String]) -> String? {
        guard !token.isEmpty else { return nil }
        let upper = token.uppercased()
        let len = upper.count
        let threshold = len >= 7 ? 2 : 1

        // Reject when a longer vocabulary entry subsumes this token as a substring.
        for entry in vocabulary where entry.uppercased().count > len {
            if entry.uppercased().contains(upper) { return nil }
        }

        var closest: String?
        var closestDist = Int.max
        var tied = false

        for entry in vocabulary {
            let d = levenshtein(upper, entry.uppercased())
            guard d <= threshold else { continue }
            if d < closestDist {
                closest = entry
                closestDist = d
                tied = false
            } else if d == closestDist {
                tied = true
            }
        }

        return tied ? nil : closest
    }

    // Standard single-row bottom-up Levenshtein distance.
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }
        var row = Array(0 ... n)
        for i in 1 ... m {
            var prev = row[0]
            row[0] = i
            for j in 1 ... n {
                let tmp = row[j]
                row[j] = a[i - 1] == b[j - 1] ? prev : 1 + min(prev, row[j], row[j - 1])
                prev = tmp
            }
        }
        return row[n]
    }
}
