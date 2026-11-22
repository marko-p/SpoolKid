import Foundation

/// Tracks which ranges of the original text have been "consumed" by parsers
/// to avoid double-matching the same text for multiple fields.
///
/// Invariant: all ranges must be derived from the same string instance passed
/// to parse-stage helpers. Mixing strings (e.g. uppercased vs. original) risks
/// silent misalignment when character-case transforms change string length.
struct TextConsumptionTracker {
    private var consumedRanges: [NSRange] = []
    
    /// Checks if a range is already consumed (overlaps with any existing range)
    func isConsumed(_ range: NSRange) -> Bool {
        consumedRanges.contains { $0.intersection(range) != nil }
    }
    
    /// Marks a range as consumed
    mutating func consume(_ range: NSRange) {
        // Merge overlapping ranges
        var newRanges = consumedRanges
        newRanges.append(range)
        // Sort by location
        newRanges.sort { $0.location < $1.location }
        // Merge overlapping/adjacent ranges
        var merged: [NSRange] = []
        for range in newRanges {
            if let last = merged.last, last.location + last.length >= range.location {
                // Overlapping or adjacent - merge
                let newLocation = last.location
                let newLength = max(last.location + last.length, range.location + range.length) - newLocation
                merged[merged.count - 1] = NSRange(location: newLocation, length: newLength)
            } else {
                merged.append(range)
            }
        }
        consumedRanges = merged
    }
}


enum OCRFilamentParserService {
    /// Nozzle keywords used only by `parseDiameter` to skip a "Nozzle 0.4mm" size line. Temperature
    /// attribution lives in `OCRNumberTokenizer.labelPatterns` / `nozzleLabelKeywords`.
    private static let nozzleKeywordPatterns = ["nozzle", "noz", "extruder", "hotend", "print"]
    private static let nozzleDomain = 180 ... 450
    private static let bedDomain = 40 ... 160

    /// Nearest-label keywords (as `OCRNumberTokenizer` emits them — de-spaced, lowercased) that
    /// mark a number as a nozzle / bed temperature.
    private static let nozzleLabelKeywords: Set<String> = ["nozzle", "noz", "extruder", "hotend", "print", "pt"]
    private static let bedLabelKeywords: Set<String> = ["bed", "hotbed", "buildplate", "bt"]

    private static func inferredBedTemp(for material: String?) -> Int? {
        guard let material else { return nil }
        let materials = OCRVocabularyLoader.shared.vocabulary().materials
        return materials.first { $0.name.uppercased() == material.uppercased() }?.inferredBedTemp
    }

    static func parse(lines: [String], trace: OCRParseTrace? = nil) -> OCRParsedCandidate {
        let joined = lines.joined(separator: "\n")
        let canonical = joined.replacingOccurrences(of: "\n", with: " ")
                              .replacingOccurrences(of: "\r", with: " ")
        var tracker = TextConsumptionTracker()
        trace?.record(decision: "canonicalText", outcome: "info", input: canonical, note: "\(lines.count) line(s)")

        var material = parseMaterial(in: canonical, tracker: &tracker)
        if let material {
            trace?.record(field: "material", decision: "exactVocab", outcome: "accepted", value: material)
        } else {
            material = parseMaterialFuzzy(in: canonical, tracker: &tracker)
            if let material {
                trace?.record(field: "material", decision: "fuzzyVocab", outcome: "accepted", value: material)
            } else {
                trace?.record(field: "material", decision: "vocab", outcome: "notFound")
            }
        }
        let brands = OCRVocabularyLoader.shared.vocabulary().brands
        var brand = brands.first(where: { canonical.lowercased().contains($0.lowercased()) })
        if let brand {
            trace?.record(field: "brand", decision: "exactVocab", outcome: "accepted", value: brand)
        } else {
            brand = parseBrandFuzzy(in: canonical, brands: brands)
            if let brand {
                trace?.record(field: "brand", decision: "fuzzyVocab", outcome: "accepted", value: brand)
            } else {
                trace?.record(field: "brand", decision: "vocab", outcome: "notFound")
            }
        }

        let (colorHex, colorName) = OCRColorResolver.resolveHexAndName(from: canonical)
        trace?.record(field: "colorHex", decision: "colorResolver",
                      outcome: colorHex != nil ? "accepted" : "notFound",
                      value: colorHex, note: colorName.map { "name=\($0)" })
        let serialNumber = parseSerialNumber(in: canonical, tracker: &tracker)
        trace?.record(field: "serialNumber", decision: "labeledSerial",
                      outcome: serialNumber != nil ? "accepted" : "notFound", value: serialNumber)
        let diameterMM = parseDiameter(in: lines, trace: trace)
        let subtype = OCRSubtypeNormalizer.normalize(rawText: joined)
        trace?.record(field: "subtype", decision: "subtypeNormalizer",
                      outcome: subtype != nil ? "accepted" : "notFound", value: subtype)
        let netWeightG = parseNetWeight(in: canonical, tracker: &tracker, trace: trace)

        let filamentName = buildFilamentName(material: material, subtype: subtype, colorName: colorName, lines: lines, brand: brand, joinedText: joined, trace: trace)

        // Temperatures select from typed number tokens: each number carries its unit and nearest
        // field label, so a nozzle/bed range is the min/max of temperature-compatible, in-domain
        // tokens whose nearest label is a nozzle/bed keyword. Multi-tier per-speed rows resolve
        // because each shares the same label; a neighbouring field's number ("Length 330m") can't
        // leak because it carries that field's label and unit.
        let numberTokens = OCRNumberTokenizer.tokenize(canonical)
        let nozzleLabeled = labeledTemperature(from: numberTokens, labels: nozzleLabelKeywords,
                                               domain: nozzleDomain, tracker: &tracker,
                                               traceField: "nozzleTemp", trace: trace)
        let bedLabeled = labeledTemperature(from: numberTokens, labels: bedLabelKeywords,
                                            domain: bedDomain, tracker: &tracker,
                                            traceField: "bedTemp", trace: trace)

        var nozzle = nozzleLabeled
        var bed = bedLabeled
        let wasNozzleExplicitlyLabeled = nozzleLabeled != nil
        let wasBedExplicitlyLabeled = bedLabeled != nil

        if nozzle == nil || bed == nil {
            applyUnlabeledTemperatureHeuristics(tokens: numberTokens, nozzle: &nozzle, bed: &bed, tracker: &tracker, trace: trace)
        }

        var isBedTempInferred = false

        let inferredBed = inferredBedTemp(for: material)

        // Validate scanned bed temp against material inference bounds (±50% deviation)
        if material != nil, let inferredBed, let bedValue = bed {
            let lowerBound = Int((Double(inferredBed) * 0.5).rounded())
            let upperBound = Int((Double(inferredBed) * 1.5).rounded())
            if bedValue.min < lowerBound || bedValue.max > upperBound {
                trace?.record(field: "bedTemp", decision: "materialInferenceValidation", outcome: "inferred",
                              value: "\(inferredBed)", note: "scanned \(bedValue.min)-\(bedValue.max) outside ±50% of \(inferredBed)")
                bed = (min: inferredBed, max: inferredBed)
                isBedTempInferred = true
            }
        }

        // Fallback: infer bed temp from material when nothing was scanned
        if bed == nil, material != nil, let inferredBed {
            trace?.record(field: "bedTemp", decision: "materialInferenceFallback", outcome: "inferred",
                          value: "\(inferredBed)", note: "no bed temp scanned; inferred from material \(material ?? "")")
            bed = (min: inferredBed, max: inferredBed)
            isBedTempInferred = true
        }

        let rawCandidate = OCRParsedCandidate(
            material: material,
            subtype: subtype,
            brand: brand,
            filamentName: filamentName,
            colorHex: colorHex,
            serialNumber: serialNumber,
            diameterMM: diameterMM,
            netWeightG: netWeightG,
            minNozzleTemp: nozzle?.min,
            maxNozzleTemp: nozzle?.max,
            minBedTemp: bed?.min,
            maxBedTemp: bed?.max,
            isBedTempInferred: isBedTempInferred,
            wasNozzleExplicitlyLabeled: wasNozzleExplicitlyLabeled,
            wasBedExplicitlyLabeled: wasBedExplicitlyLabeled,
            confidenceByField: [:],
            rawLines: lines
        )
        var annotated = OCRConfidenceScoringService.annotate(candidate: rawCandidate)
        annotated = applyNozzleFallback(candidate: annotated, joinedText: joined, trace: trace)
        return annotated
    }

    // MARK: - Labeled temperature parsing (token-based)

    /// Labeled temperature range from typed tokens: the min/max of every token whose nearest label
    /// is a nozzle (or bed) keyword, whose unit is temperature-compatible, that falls in `domain`,
    /// and whose span isn't already claimed by an earlier field. Multi-tier per-speed rows resolve
    /// because each per-speed temperature shares the same nearest label — no character-window scan
    /// or degree-fold needed.
    private static func labeledTemperature(
        from tokens: [OCRNumberToken],
        labels: Set<String>,
        domain: ClosedRange<Int>,
        tracker: inout TextConsumptionTracker,
        traceField: String,
        trace: OCRParseTrace?
    ) -> (min: Int, max: Int)? {
        let picked = tokens.filter {
            guard let label = $0.label, labels.contains(label) else { return false }
            return $0.unit.isTemperatureCompatible && domain.contains($0.value) && !tracker.isConsumed($0.range)
        }
        guard let lo = picked.map(\.value).min(), let hi = picked.map(\.value).max() else {
            trace?.record(field: traceField, decision: "labeledTemperature(token)", outcome: "notFound",
                          note: "no temperature-compatible in-domain token under a \(traceField) label")
            return nil
        }
        for token in picked { tracker.consume(token.range) }
        trace?.record(field: traceField, decision: "labeledTemperature(token)", outcome: "accepted",
                      value: "\(lo)-\(hi)", note: "from tokens \(picked.map(\.value))")
        return (min: lo, max: hi)
    }

    // MARK: - Serial, diameter, name, weight

    private static func parseSerialNumber(in text: String, tracker: inout TextConsumptionTracker) -> String? {
        let pattern = "(?i)\\b(?:serial(?:\\s*number)?|s\\/?n|sn)\\b\\s*[:#-]?\\s*([A-Z0-9][A-Z0-9-]{2,})"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              !tracker.isConsumed(match.range) else { return nil }
        tracker.consume(match.range)
        return ns.substring(with: match.range(at: 1))
    }

    private static func parseDiameter(in lines: [String], trace: OCRParseTrace? = nil) -> Double? {
        for line in lines {
            let lower = line.lowercased()
            if containsAnyKeyword(in: lower, keywordPatterns: nozzleKeywordPatterns) {
                continue
            }

            if let labeled = firstDoubleMatch(
                pattern: "(?i)\\b(?:diameter|dia|filament(?:\\s*diameter)?)\\b[^0-9]{0,8}(\\d(?:[.,]\\d{1,2})?)(?:\\s*[±+\\-–—/]+\\s*\\d+(?:[.,]\\d{1,2})?)?\\s*mm\\b",
                in: line
            ) {
                if isAllowedFilamentDiameter(labeled) {
                    trace?.record(field: "diameterMM", decision: "labeled", outcome: "accepted", value: String(format: "%.2f", labeled), input: line)
                    return labeled
                }
                trace?.record(field: "diameterMM", decision: "labeled", outcome: "rejected", value: String(format: "%.2f", labeled), input: line, note: "not in whitelist {1.75, 2.85, 3.0}")
            }

            if let unlabeled = firstDoubleMatch(
                pattern: "(?i)\\b(\\d(?:[.,]\\d{1,2})?)(?:\\s*[±+\\-–—/]+\\s*\\d+(?:[.,]\\d{1,2})?)?\\s*mm\\b",
                in: line
            ) {
                if isAllowedFilamentDiameter(unlabeled) {
                    trace?.record(field: "diameterMM", decision: "unlabeled", outcome: "accepted", value: String(format: "%.2f", unlabeled), input: line)
                    return unlabeled
                }
                trace?.record(field: "diameterMM", decision: "unlabeled", outcome: "rejected", value: String(format: "%.2f", unlabeled), input: line, note: "not in whitelist {1.75, 2.85, 3.0}")
            }
        }

        trace?.record(field: "diameterMM", decision: "diameter", outcome: "notFound")
        return nil
    }

    // MARK: - Unlabeled temperature heuristics

    private static func applyUnlabeledTemperatureHeuristics(
        tokens: [OCRNumberToken],
        nozzle: inout (min: Int, max: Int)?,
        bed: inout (min: Int, max: Int)?,
        tracker: inout TextConsumptionTracker,
        trace: OCRParseTrace? = nil
    ) {
        // Tokens with NO temperature label (label nil, or a non-temp field label) supply a nozzle
        // range first, then bed, by domain — mirroring the old per-line heuristic but driven by
        // attribution, so a number under "Length"/"Weight" can never become a stray temperature.
        let isTempLabel: (String?) -> Bool = { label in
            guard let label else { return false }
            return nozzleLabelKeywords.contains(label) || bedLabelKeywords.contains(label)
        }
        let free = tokens.filter {
            $0.unit.isTemperatureCompatible && !isTempLabel($0.label) && !tracker.isConsumed($0.range)
        }
        if nozzle == nil {
            let inDomain = free.filter { nozzleDomain.contains($0.value) }
            if let lo = inDomain.map(\.value).min(), let hi = inDomain.map(\.value).max() {
                nozzle = (min: lo, max: hi)
                for token in inDomain { tracker.consume(token.range) }
                trace?.record(field: "nozzleTemp", decision: "unlabeledToken", outcome: "accepted", value: "\(lo)-\(hi)")
            }
        }
        if bed == nil {
            let inDomain = free.filter { bedDomain.contains($0.value) && !tracker.isConsumed($0.range) }
            if let lo = inDomain.map(\.value).min(), let hi = inDomain.map(\.value).max() {
                bed = (min: lo, max: hi)
                for token in inDomain { tracker.consume(token.range) }
                trace?.record(field: "bedTemp", decision: "unlabeledToken", outcome: "accepted", value: "\(lo)-\(hi)")
            }
        }
    }

    private static func containsAnyKeyword(in text: String, keywordPatterns: [String]) -> Bool {
        for keyword in keywordPatterns {
            guard let regex = try? NSRegularExpression(pattern: "(?i)\\b(?:\(keyword))\\w*\\b") else {
                continue
            }
            let ns = text as NSString
            if regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Fuzzy vocabulary fallbacks (fires only when exact match returns nil)

    /// Scans whitespace-delimited tokens (≥ 4 chars) and returns the first that fuzzy-matches
    /// a material vocabulary entry. Consumes the matched span so downstream fields can't reuse it.
    private static func parseMaterialFuzzy(in text: String, tracker: inout TextConsumptionTracker) -> String? {
        let materialNames = OCRVocabularyLoader.shared.vocabulary().materials.map { $0.name }
        let ns = text as NSString
        let trimSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+-")).inverted
        for raw in text.components(separatedBy: .whitespacesAndNewlines) where !raw.isEmpty {
            let token = raw.trimmingCharacters(in: trimSet)
            guard token.count >= 4 else { continue }
            guard let match = OCRFuzzyMatcher.bestFuzzyMatch(token, in: materialNames) else { continue }
            let range = ns.range(of: token, options: .caseInsensitive)
            guard range.location != NSNotFound, !tracker.isConsumed(range) else { continue }
            tracker.consume(range)
            return match.uppercased()
        }
        return nil
    }

    /// Scans whitespace-delimited tokens (≥ 4 chars) and returns the first that fuzzy-matches
    /// a brand vocabulary entry. Brand extraction does not use the tracker (mirrors exact path).
    private static func parseBrandFuzzy(in text: String, brands: [String]) -> String? {
        let trimSet = CharacterSet.alphanumerics.inverted
        for raw in text.components(separatedBy: .whitespacesAndNewlines) where !raw.isEmpty {
            let token = raw.trimmingCharacters(in: trimSet)
            guard token.count >= 4 else { continue }
            if let match = OCRFuzzyMatcher.bestFuzzyMatch(token, in: brands) {
                return match
            }
        }
        return nil
    }

    private static func parseMaterial(in text: String, tracker: inout TextConsumptionTracker) -> String? {
        let materials = OCRVocabularyLoader.shared.vocabulary().materials
        for entry in materials {
            let upperName = entry.name.uppercased()
            let escapedName = NSRegularExpression.escapedPattern(for: upperName)
            let pattern = "(?i)(?<![A-Z0-9])\(escapedName)(?![A-Z0-9])"
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let ns = text as NSString
            if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
               !tracker.isConsumed(match.range) {
                tracker.consume(match.range)
                return upperName
            }
        }
        return nil
    }

    private static func firstDoubleMatch(pattern: String, in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        // European labels use a comma decimal separator (e.g. "1,75mm").
        return Double(ns.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "."))
    }

    private static func parseNetWeight(in text: String, tracker: inout TextConsumptionTracker, trace: OCRParseTrace? = nil) -> Int? {
        let kilogramsPattern = "(?i)\\b(?:net\\s*weight|weight|nw)\\b[^0-9]{0,8}(\\d{1,2}(?:\\.\\d{1,2})?)\\s*kg\\b"
        let gramsPattern = "(?i)\\b(?:net\\s*weight|weight|nw)\\b[^0-9]{0,8}(\\d{2,5})\\s*g\\b"

        if let (range, kg) = firstDoubleMatchWithRange(pattern: kilogramsPattern, in: text), !tracker.isConsumed(range) {
            tracker.consume(range)
            let grams = Int((kg * 1000).rounded())
            trace?.record(field: "netWeightG", decision: "labeledWeight(kg)", outcome: "accepted",
                          value: "\(grams)", note: "consumed \(range.location)..\(range.location + range.length)")
            return grams
        }

        if let (range, grams) = firstIntMatchWithRange(pattern: gramsPattern, in: text), !tracker.isConsumed(range) {
            tracker.consume(range)
            trace?.record(field: "netWeightG", decision: "labeledWeight(g)", outcome: "accepted",
                          value: "\(grams)", note: "consumed \(range.location)..\(range.location + range.length)")
            return grams
        }

        // Unlabeled fallback: many labels print the weight with no "net weight" label
        // ("1000g-White", "1.75mm 1KG"). Accept it ONLY when the text yields a single distinct
        // weight value, so multi-weight labels (the 200g/400g/600g/1000g spool diagram on Jayo
        // reels) never guess. A labeled weight, parsed above, always takes precedence.
        if let grams = uniqueUnlabeledWeightG(in: text) {
            trace?.record(field: "netWeightG", decision: "unlabeledWeight", outcome: "accepted", value: "\(grams)")
            return grams
        }

        trace?.record(field: "netWeightG", decision: "labeledWeight", outcome: "notFound")
        return nil
    }

    /// Distinct weight in grams if the text contains exactly one weight value (kg or g forms),
    /// else nil. "1000g" and "1KG" both resolve to 1000, so they collapse to a single value.
    private static func uniqueUnlabeledWeightG(in text: String) -> Int? {
        var grams: Set<Int> = []
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let kg = try? NSRegularExpression(pattern: "(?i)\\b(\\d{1,2}(?:[.,]\\d{1,2})?)\\s*kg\\b") {
            for m in kg.matches(in: text, range: full) {
                let raw = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")
                if let v = Double(raw) { grams.insert(Int((v * 1000).rounded())) }
            }
        }
        if let g = try? NSRegularExpression(pattern: "(?i)\\b(\\d{3,5})\\s*g\\b") {
            for m in g.matches(in: text, range: full) {
                if let v = Int(ns.substring(with: m.range(at: 1))) { grams.insert(v) }
            }
        }
        return grams.count == 1 ? grams.first : nil
    }

    private static func firstDoubleMatchWithRange(pattern: String, in text: String) -> (NSRange, Double)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        guard let value = Double(ns.substring(with: match.range(at: 1))) else { return nil }
        return (match.range, value)
    }
    
    private static func firstIntMatchWithRange(pattern: String, in text: String) -> (NSRange, Int)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        guard let value = Int(ns.substring(with: match.range(at: 1))) else { return nil }
        return (match.range, value)
    }

    private static func isAllowedFilamentDiameter(_ value: Double) -> Bool {
        let rounded = (value * 100).rounded() / 100
        return rounded == 1.75 || rounded == 2.85 || rounded == 3.0
    }

    private static func firstColorMatch(
        in entries: [OcrFilamentTempEntry],
        joinedText: String
    ) -> OcrFilamentTempEntry? {
        let lowerJoined = joinedText.lowercased()
        let normalized = lowerJoined.replacingOccurrences(
            of: "[^a-z0-9]+", with: " ", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let sortedByLength = entries.sorted { $0.colorName.count > $1.colorName.count }

        for entry in sortedByLength {
            let colorLower = entry.colorName.lowercased()
            let pattern = "(^|\\s)" + NSRegularExpression.escapedPattern(for: colorLower) + "($|\\s)"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = normalized as NSString
            if regex.firstMatch(in: normalized, range: NSRange(location: 0, length: ns.length)) != nil {
                return entry
            }
        }
        return nil
    }

    private static func applyNozzleFallback(
        candidate: OCRParsedCandidate,
        joinedText: String,
        trace: OCRParseTrace? = nil
    ) -> OCRParsedCandidate {
        let nozzleConf = candidate.confidenceByField[.minNozzleTemp] ?? .none
        guard nozzleConf == .low || nozzleConf == .medium else { return candidate }
        // Protect a genuinely-scanned temperature RANGE (min < max): the catalogue value is a
        // generic prior and must not overwrite a real range reading (e.g. a label's "190°C—230°C"
        // being replaced by a narrower catalogue 190-220). Single-point/partial scans (min == max)
        // are still enriched below.
        if let scannedMin = candidate.minNozzleTemp, let scannedMax = candidate.maxNozzleTemp, scannedMin < scannedMax {
            trace?.record(field: "nozzleTemp", decision: "catalogueFallback", outcome: "info",
                          value: "\(scannedMin)-\(scannedMax)",
                          note: "kept scanned range over catalogue (\(nozzleConf.rawValue) confidence)")
            return candidate
        }
        guard let brand = candidate.brand,
              let material = candidate.material,
              candidate.colorHex != nil else { return candidate }

        let temps = OCRVocabularyLoader.shared.vocabulary().filamentTemps
        let matching = temps.filter { entry in
            entry.brand.lowercased() == brand.lowercased() &&
            entry.material.uppercased() == material.uppercased()
        }
        guard let entry = firstColorMatch(in: matching, joinedText: joinedText) else {
            trace?.record(field: "nozzleTemp", decision: "catalogueFallback", outcome: "notFound",
                          note: "no catalogue entry for \(brand)/\(material) matching the scanned color (nozzle confidence \(nozzleConf.rawValue))")
            return candidate
        }

        var updated = candidate
        if let nMin = entry.nozzleMin {
            updated.minNozzleTemp = nMin
            updated.confidenceByField[.minNozzleTemp] = .medium
        }
        if let nMax = entry.nozzleMax {
            updated.maxNozzleTemp = nMax
            updated.confidenceByField[.maxNozzleTemp] = .medium
        }
        trace?.record(field: "nozzleTemp", decision: "catalogueFallback", outcome: "fallback",
                      value: "\(entry.nozzleMin.map(String.init) ?? "?")-\(entry.nozzleMax.map(String.init) ?? "?")",
                      note: "replaced \(nozzleConf.rawValue)-confidence scan with \(brand)/\(material)/\(entry.colorName) catalogue value")
        return updated
    }

    /// Cleans a resolved catalogue color name for use in the filament name. Polluted catalogue
    /// phrases prefix the material ("PLA - Black") or append an index digit ("White 1"); both
    /// leak into the name. Strips a single leading material token and a trailing 1–2 digit index,
    /// never reducing the result to empty. Does not touch the resolved hex.
    private static func sanitizeColorName(_ colorName: String) -> String {
        var result = colorName.trimmingCharacters(in: .whitespacesAndNewlines)
        let materials = OCRVocabularyLoader.shared.vocabulary().materials
            .map { $0.name }
            .sorted { $0.count > $1.count }
        for mat in materials {
            let escaped = NSRegularExpression.escapedPattern(for: mat)
            // Material token must be followed by a separator and more text (so "Peach" isn't cut by "PE").
            guard let regex = try? NSRegularExpression(pattern: "(?i)^\(escaped)[\\s:/_–—-]+(?=\\S)") else { continue }
            let ns = result as NSString
            if let m = regex.firstMatch(in: result, range: NSRange(location: 0, length: ns.length)) {
                result = ns.substring(from: m.range.length).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        if let regex = try? NSRegularExpression(pattern: "(?i)^(.*\\p{L}.*?)\\s+\\d{1,2}$") {
            let ns = result as NSString
            if let m = regex.firstMatch(in: result, range: NSRange(location: 0, length: ns.length)) {
                result = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return result.isEmpty ? colorName : result
    }

    private static func buildFilamentName(
        material: String?,
        subtype: String?,
        colorName: String?,
        lines: [String],
        brand: String?,
        joinedText: String,
        trace: OCRParseTrace? = nil
    ) -> String? {
        if let mat = material, let rawColor = colorName {
            let color = sanitizeColorName(rawColor)
            var droppedSubtype = false
            let effectiveSubtype: String? = {
                guard let sub = subtype else { return nil }
                let subLower = sub.lowercased()
                let colorLower = color.lowercased()
                // Omit subtype when color already leads with the same word (case-insensitive,
                // leading-word boundary only) — prevents "PLA Matte Matte Army Green".
                if colorLower == subLower || colorLower.hasPrefix(subLower + " ") {
                    droppedSubtype = true
                    return nil
                }
                return sub
            }()
            let name = [mat, effectiveSubtype, color].compactMap { $0 }.joined(separator: " ")
            trace?.record(field: "filamentName", decision: "material+color", outcome: "accepted", value: name,
                          note: droppedSubtype ? "subtype '\(subtype ?? "")' dropped (color leads with it)" : nil)
            return name
        }
        if let first = lines.first, !first.isEmpty {
            trace?.record(field: "filamentName", decision: "firstLine", outcome: "accepted", value: first,
                          note: "no material+color; fell back to first OCR line")
            return first
        }
        guard let brand else {
            trace?.record(field: "filamentName", decision: "name", outcome: "notFound")
            return nil
        }
        let temps = OCRVocabularyLoader.shared.vocabulary().filamentTemps
        let matching = temps.filter { $0.brand.lowercased() == brand.lowercased() }
        let name = firstColorMatch(in: matching, joinedText: joinedText)?.colorName
        trace?.record(field: "filamentName", decision: "brandCatalogue", outcome: name != nil ? "accepted" : "notFound", value: name)
        return name
    }
}
