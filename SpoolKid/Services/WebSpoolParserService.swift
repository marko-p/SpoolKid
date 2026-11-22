import Foundation
import RegexBuilder

enum WebSpoolParserError: Error {
    case invalidURL
    case networkError(Error)
    case unsupportedVendor
    case requiresWebChallenge(URL)
    case parseFailed
}

class WebSpoolParserService {
    static let shared = WebSpoolParserService()

    func parse(url: URL) async throws -> FilamentTagData? {
        guard url.host?.lowercased() != nil else {
            throw WebSpoolParserError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 403 || httpResponse.statusCode == 503 {
            // Likely Cloudflare challenge
            throw WebSpoolParserError.requiresWebChallenge(url)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WebSpoolParserError.networkError(NSError(domain: "HTTPError", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: nil))
        }

        guard let htmlString = String(data: data, encoding: .utf8) else {
            throw WebSpoolParserError.parseFailed
        }

        if isLikelyCloudflareChallengePage(html: htmlString, response: httpResponse) {
            throw WebSpoolParserError.requiresWebChallenge(url)
        }

        return try parse(html: htmlString, url: url)
    }

    func parse(html: String, url: URL) throws -> FilamentTagData {
        guard let host = url.host?.lowercased() else {
            throw WebSpoolParserError.invalidURL
        }

        let path = url.path.lowercased()
        let is3DTagPrusamentAlias = host.contains("3dtag.org") && path.hasPrefix("/s/")
        let isPolymakerAlias = host.contains("polymaker.link") && path.hasPrefix("/qr/")

        if host.contains("prusament.com") || is3DTagPrusamentAlias {
            return try parsePrusament(html: html, url: url)
        } else if host.contains("polymaker.com") || isPolymakerAlias {
            return try parsePolymaker(html: html, url: url)
        }

        return parseGeneric(html: html, url: url, host: host)
    }

    private func parsePrusament(html: String, url: URL) throws -> FilamentTagData {
        // Look for: var spoolData = '{...}';
        let regex = try NSRegularExpression(pattern: "var spoolData = '(.*?)';", options: [])
        guard let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)) else {
            throw WebSpoolParserError.parseFailed
        }
        
        let jsonString = (html as NSString).substring(with: match.range(at: 1))
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw WebSpoolParserError.parseFailed
        }

        struct PrusamentData: Decodable {
            struct Filament: Decodable {
                let color_rgb: String?
                let material: String?
                let name: String?
                let he_min: Int?
                let he_max: Int?
                let hb_min: Int?
                let hb_max: Int?
            }
            let filament: Filament?
            let weight: Int?
            let spool_weight: Int?
        }

        let decoder = JSONDecoder()
        let prusamentData = try decoder.decode(PrusamentData.self, from: jsonData)
        
        guard let f = prusamentData.filament else {
            throw WebSpoolParserError.parseFailed
        }

        var tag = FilamentTagData(
            id: UUID(),
            name: f.name,
            material: f.material ?? "Unknown",
            brand: "Prusament",
            colorHex: (f.color_rgb ?? "#808080").replacingOccurrences(of: "#", with: ""),
            minNozzleTemp: f.he_min ?? 0,
            maxNozzleTemp: f.he_max ?? 0,
            minBedTemp: f.hb_min ?? 0,
            maxBedTemp: f.hb_max ?? 0
        )
        if let net = prusamentData.weight, let spoolWeight = prusamentData.spool_weight {
            tag.nominalNetWeight = Double(net)
            tag.emptyContainerWeight = Double(spoolWeight)
        }

        return tag
    }

    private func parsePolymaker(html: String, url: URL) throws -> FilamentTagData {
        let (family, code) = polymakerFamilyAndCode(from: url)

        let title = firstRegexGroup(in: html, pattern: "<title>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let ogTitle = firstRegexGroup(in: html, pattern: "<meta[^>]+property=['\"]og:title['\"][^>]+content=['\"](.*?)['\"]", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let h1 = firstRegexGroup(in: html, pattern: "<h1[^>]*>(.*?)</h1>", options: [.caseInsensitive, .dotMatchesLineSeparators])

        var name = cleanedNameCandidate([h1, ogTitle, title])
        if let family, let code {
            if let existingName = name {
                let upper = existingName.uppercased()
                var merged = existingName
                if !upper.contains(family.uppercased()) {
                    merged = "\(family) \(merged)"
                }
                if !upper.contains(code.uppercased()) {
                    merged += " \(code)"
                }
                name = merged
            } else {
                name = "\(family) \(code)"
            }
        }

        let extractedComposite = extractedMaterial(from: [name, code, ogTitle, title])
        let base = baseMaterial(from: extractedComposite ?? code)
        let material = base ?? extractedComposite ?? "Unknown"
        let subtype: String? = {
            let candidate = extractedComposite ?? code
            guard let candidate, candidate != material else { return nil }
            return candidate
        }()

        let text = normalizedText(html)
        let nozzleRange = extractedTemperatureRange(
            from: text,
            labels: ["Printing temperature", "Print temperature", "Nozzle temperature", "Extruder temperature"]
        )
        let bedRange = extractedTemperatureRange(
            from: text,
            labels: ["Bed temperature", "Build plate temperature", "Hotbed temperature"]
        )

        let colorHex = inferredColorHex(from: [name, ogTitle, h1]) ?? "808080"

        let tag = FilamentTagData(
            name: name,
            material: material,
            subtype: subtype,
            brand: "Polymaker",
            colorHex: colorHex,
            minNozzleTemp: nozzleRange?.0 ?? 0,
            maxNozzleTemp: nozzleRange?.1 ?? 0,
            minBedTemp: bedRange?.0 ?? 0,
            maxBedTemp: bedRange?.1 ?? 0,
            tagURL: url.absoluteString
        )

        return tag
    }

    private func parseGeneric(html: String, url: URL, host: String) -> FilamentTagData {
        let title = firstRegexGroup(in: html, pattern: "<title>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let ogTitle = firstRegexGroup(in: html, pattern: "<meta[^>]+property=['\"]og:title['\"][^>]+content=['\"](.*?)['\"]", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let h1 = firstRegexGroup(in: html, pattern: "<h1[^>]*>(.*?)</h1>", options: [.caseInsensitive, .dotMatchesLineSeparators])

        let nameCandidate = cleanedNameCandidate([ogTitle, h1, title])
        let materialCandidate = extractedMaterial(from: [ogTitle, h1, title, url.path]) ?? "Unknown"
        let brandCandidate = extractedBrand(from: [ogTitle, h1, title], host: host)

        let htmlText = html
            .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&deg;", with: " deg ")

        let nozzleRange = extractedTemperatureRange(
            from: htmlText,
            labels: ["Printing temperature", "Print temperature", "Extruder temperature", "Nozzle temperature"]
        )

        let bedRange = extractedTemperatureRange(
            from: htmlText,
            labels: ["Bed temperature", "Build plate temperature", "Platform temperature"]
        )

        let tag = FilamentTagData(
            id: UUID(),
            name: nameCandidate ?? (!materialCandidate.isEmpty ? materialCandidate : nil),
            material: materialCandidate,
            brand: brandCandidate,
            colorHex: "808080",
            minNozzleTemp: nozzleRange?.0 ?? 0,
            maxNozzleTemp: nozzleRange?.1 ?? 0,
            minBedTemp: bedRange?.0 ?? 0,
            maxBedTemp: bedRange?.1 ?? 0,
            tagURL: url.absoluteString
        )

        return tag
    }

    private func firstRegexGroup(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
              match.numberOfRanges > 1
        else {
            return nil
        }

        return (text as NSString).substring(with: match.range(at: 1))
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanedNameCandidate(_ candidates: [String?]) -> String? {
        for candidate in candidates {
            guard var value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                continue
            }

            // Remove common suffixes.
            value = value.replacingOccurrences(of: "|", with: " - ")
            if let split = value.split(separator: "-").first {
                let compact = split.trimmingCharacters(in: .whitespacesAndNewlines)
                if compact.count >= 3 {
                    return compact
                }
            }

            if value.count >= 3 {
                return value
            }
        }

        return nil
    }

    private func extractedMaterial(from candidates: [String?]) -> String? {
        let comboPattern = "\\b[A-Z]{2,6}(?:[0-9]{0,3})?(?:-[A-Z]{1,5}[0-9]{0,3})+\\b"
        let families = ["PLA", "PETG", "PET", "ABS", "ASA", "PA", "PA6", "PA12", "PA612", "TPU", "PC", "PPS", "PEEK", "PP", "HIPS", "NYLON"]

        for candidate in candidates {
            guard let candidate else { continue }
            let upper = candidate.uppercased()

            if let combo = firstRegexGroup(in: upper, pattern: "(\(comboPattern))", options: [.caseInsensitive]) {
                return combo
            }

            if let regex = try? NSRegularExpression(pattern: comboPattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: upper, options: [], range: NSRange(location: 0, length: upper.utf16.count)) {
                return (upper as NSString).substring(with: match.range)
            }

            for family in families {
                if upper.contains(family) {
                    return family
                }
            }
        }

        return nil
    }

    private func extractedBrand(from candidates: [String?], host: String) -> String {
        // Try "... by Brand" patterns in title/headings.
        for candidate in candidates {
            guard let candidate else { continue }
            if let brand = firstRegexGroup(in: candidate, pattern: "(?i)\\bby\\s+([A-Za-z0-9 ._-]{2,40})") {
                let cleaned = brand.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }

        // Fallback: normalize second-level domain.
        let hostParts = host.split(separator: ".")
        let base = hostParts.count >= 2 ? String(hostParts[hostParts.count - 2]) : host
        let normalized = base.replacingOccurrences(of: "-", with: " ")
        return normalized.capitalized
    }

    private func extractedTemperatureRange(from text: String, labels: [String]) -> (Int, Int)? {
        let labelPattern = labels.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let rangePattern = "(?:\(labelPattern))\\s*[:：]?\\s*(\\d{2,3})\\s*[^0-9]{0,8}(\\d{2,3})"
        if let regex = try? NSRegularExpression(pattern: rangePattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
           match.numberOfRanges > 2,
           let min = Int((text as NSString).substring(with: match.range(at: 1))),
           let max = Int((text as NSString).substring(with: match.range(at: 2))) {
            return (min, max)
        }

        let singlePattern = "(?:\(labelPattern))\\s*[:：]?\\s*(\\d{2,3})"
        if let regex = try? NSRegularExpression(pattern: singlePattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
           match.numberOfRanges > 1,
           let value = Int((text as NSString).substring(with: match.range(at: 1))) {
            return (value, value)
        }

        return nil
    }

    private func polymakerFamilyAndCode(from url: URL) -> (family: String?, code: String?) {
        let parts = url.pathComponents
            .filter { !$0.isEmpty && $0 != "/" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        if parts.count >= 2 {
            let code = parts.last?.uppercased()
            let family = parts.dropLast().last?.replacingOccurrences(of: "-", with: " ").capitalized
            return (family: family, code: code)
        }

        return (family: nil, code: parts.last?.uppercased())
    }

    private func baseMaterial(from value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let upper = value.uppercased()

        if let dashIndex = upper.firstIndex(of: "-") {
            let prefix = String(upper[..<dashIndex]).trimmingCharacters(in: .whitespaces)
            if !prefix.isEmpty {
                return prefix
            }
        }

        return upper
    }

    private func inferredColorHex(from candidates: [String?]) -> String? {
        let map: [(tokens: [String], hex: String)] = [
            (["dark grey", "dark gray", "charcoal"], "4A4A4A"),
            (["grey", "gray"], "808080"),
            (["black"], "000000"),
            (["white"], "FFFFFF"),
            (["red"], "C62828"),
            (["blue"], "1565C0"),
            (["green"], "2E7D32"),
            (["yellow"], "F9A825"),
            (["orange"], "EF6C00"),
            (["brown"], "6D4C41"),
            (["natural", "clear", "transparent"], "DCDCDC")
        ]

        for candidate in candidates {
            guard let candidate else { continue }
            let lower = candidate.lowercased()
            for entry in map {
                if entry.tokens.contains(where: { lower.contains($0) }) {
                    return entry.hex
                }
            }
        }

        return nil
    }

    private func normalizedText(_ html: String) -> String {
        html
            .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&deg;", with: " deg ")
    }

    private func isLikelyCloudflareChallengePage(html: String, response: HTTPURLResponse) -> Bool {
        let cfMitigated = response.value(forHTTPHeaderField: "cf-mitigated")?.lowercased()
        if cfMitigated == "challenge" {
            return true
        }

        let titlePatterns = ["<title>Just a moment...</title>", "<title>Attention Required! | Cloudflare</title>"]
        if titlePatterns.contains(where: { html.contains($0) }) {
            return true
        }

        let bodySignals = [
            "challenges.cloudflare.com",
            "__cf_chl_",
            "cf-mitigated"
        ]

        return bodySignals.contains(where: { html.contains($0) })
    }
}
