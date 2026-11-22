import Foundation

/// Lifts every 1–3 digit integer out of canonical OCR label text into an `OCRNumberToken`,
/// tagging each with the unit printed after it and the nearest field label printed before it.
/// Pure & synchronous; ranges are in the input string's coordinates.
nonisolated enum OCRNumberTokenizer {

    /// Field-label keywords that "own" the numbers following them — temperature keywords plus the
    /// other spool fields. Whole-word prefixes (`\b(?:kw)\w*\b`), matched case-insensitively.
    static let labelPatterns = [
        "nozzle", "noz", "extruder", "hotend", "print", "pt",        // nozzle temperature
        "bed", "hot\\s*bed", "build\\s*plate", "buildplate", "bt",   // bed temperature
        "length", "weight", "net", "colo", "diameter", "density", "made", "size", "spool"
    ]

    static func tokenize(_ text: String) -> [OCRNumberToken] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        // Same digit guard the old `domainIntegers` used: reject digits inside a longer run or a
        // real decimal fraction (the "75" in "1.75"), but allow a digit after a non-numeric
        // separator dot (the "80" in "BT.80°C"). 1–3 digits.
        guard let numberRegex = try? NSRegularExpression(
            pattern: "(?<![0-9])(?<!\\d\\.)(\\d{1,3})(?![0-9.])"
        ) else { return [] }

        let labelAlts = labelPatterns.joined(separator: "|")
        let labelRegex = try? NSRegularExpression(pattern: "(?i)\\b(\(labelAlts))\\w*\\b")

        var tokens: [OCRNumberToken] = []
        for m in numberRegex.matches(in: text, range: full) {
            let digits = m.range(at: 1)
            guard let value = Int(ns.substring(with: digits)) else { continue }
            let unit = unitFollowing(digits.location + digits.length, in: ns)
            let label = nearestLabel(before: digits.location, in: ns, regex: labelRegex)
            tokens.append(OCRNumberToken(value: value, unit: unit, range: digits, label: label))
        }
        return tokens
    }

    /// The unit printed immediately after the digits (spaces skipped), else `.none`.
    private static func unitFollowing(_ index: Int, in ns: NSString) -> OCRNumberUnit {
        let remaining = ns.length - index
        guard remaining > 0 else { return .none }
        let tail = ns.substring(with: NSRange(location: index, length: Swift.min(6, remaining)))
        let tailNS = tail as NSString
        let tailRange = NSRange(location: 0, length: tailNS.length)

        // Degree first: "°C" / "°F" / "°" / a bare word-bounded C or F.
        if let deg = try? NSRegularExpression(pattern: "^\\s*(?:°\\s*[cf]?|[cf])\\b", options: .caseInsensitive),
           deg.firstMatch(in: tail, range: tailRange) != nil {
            return .degree
        }
        if let phys = try? NSRegularExpression(pattern: "^\\s*(mm|m|kg|g|%)\\b", options: .caseInsensitive),
           let match = phys.firstMatch(in: tail, range: tailRange) {
            switch tailNS.substring(with: match.range(at: 1)).lowercased() {
            case "mm": return .millimeter
            case "m":  return .meter
            case "kg": return .kilogram
            case "g":  return .gram
            case "%":  return .percent
            default:   return .none
            }
        }
        return .none
    }

    /// The label keyword whose match ends closest before `index`, whitespace-stripped and
    /// lowercased (so "Build Plate" → "buildplate"), or nil.
    private static func nearestLabel(before index: Int, in ns: NSString, regex: NSRegularExpression?) -> String? {
        guard let regex, index > 0 else { return nil }
        var found: String?
        for m in regex.matches(in: ns as String, range: NSRange(location: 0, length: index))
        where m.range.location + m.range.length <= index {
            found = ns.substring(with: m.range(at: 1))
                .replacingOccurrences(of: " ", with: "")
                .lowercased()
        }
        return found
    }
}
