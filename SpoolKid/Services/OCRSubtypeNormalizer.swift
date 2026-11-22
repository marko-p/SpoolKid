import Foundation

/// Normalizes raw OCR text into a canonical subtype string.
/// The output values (Basic, Matte, SnapSpeed, Silk, Support, HF, 95A, 95A HF)
/// are a USER-SPECIFIED subset of `AppConfig.subtypes` — chosen for the labels
/// actually scanned. Do not change these values without consulting the decision log.
enum OCRSubtypeNormalizer {
    private static let hfSignals = ["high flow", "highspeed", "high speed", "hyper speed", "hyperspeed", "hf"]

    static func normalize(rawText: String?) -> String? {
        guard let rawText else { return nil }
        let normalized = normalize(stripSupportNoise(rawText))
        let tokenSet = Set(normalized.split(separator: " ").map(String.init))

        let has95A = tokenSet.contains("95a")
        let hasSnapSpeed = normalized.contains("snapspeed") || normalized.contains("snap speed")
        let hasHF = hasAnySignal(in: normalized, tokens: tokenSet, signals: hfSignals)

        if has95A && hasHF {
            return "95A HF"
        }
        if has95A {
            return "95A"
        }
        if hasSnapSpeed {
            return "SnapSpeed"
        }
        if tokenSet.contains("matte") {
            return "Matte"
        }
        if tokenSet.contains("silk") {
            return "Silk"
        }
        if tokenSet.contains("support") || tokenSet.contains("pva") {
            return "Support"
        }
        if hasHF {
            return "HF"
        }
        if tokenSet.contains("basic") {
            return "Basic"
        }

        return nil
    }

    /// Removes "support" occurrences that are help-desk noise rather than the filament type:
    /// contact emails ("support@3djayo.com") and phrases like "technical support". A genuine
    /// "PVA support" / "PLA+ Support" is left intact.
    private static func stripSupportNoise(_ text: String) -> String {
        var cleaned = text
        for pattern in ["[\\w.+%-]+@[\\w.-]+\\.[A-Za-z]{2,}",
                        "(?i)\\b(?:technical|customer|product|tech|contact)\\s+support\\b"] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = cleaned as NSString
            cleaned = regex.stringByReplacingMatches(
                in: cleaned, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        }
        return cleaned
    }

    private static func normalize(_ text: String) -> String {
        let lower = text.lowercased()
        let replaced = lower.replacingOccurrences(
            of: "[^a-z0-9]+",
            with: " ",
            options: .regularExpression
        )
        return replaced.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hasAnySignal(in normalized: String, tokens: Set<String>, signals: [String]) -> Bool {
        for signal in signals {
            if signal.contains(" ") {
                if normalized.contains(signal) {
                    return true
                }
            } else if tokens.contains(signal) {
                return true
            }
        }
        return false
    }
}
