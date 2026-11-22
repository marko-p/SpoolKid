import Foundation

// Swift twin of the script that builds the bundled OCR vocabulary: the same rules (filler materials,
// minimum count, base families, label denylist, colour-name cleaning, bed-temp inference),
// applied at runtime to SpoolmanDB so the bundled OCR vocabulary can be topped up.
// Keep the two in step; the script's header names this file in turn.
// One difference: this side also drops a colour phrase whose key equals a material name
// (`materialKeys` in `newColors`); the script does not.

/// One entry of SpoolmanDB's `materials.json`.
nonisolated struct SpoolmanDBMaterial: Codable, Sendable {
    let material: String
    let density: Double?
    let extruderTemp: Int?
    let bedTemp: Int?

    enum CodingKeys: String, CodingKey {
        case material
        case density
        case extruderTemp = "extruder_temp"
        case bedTemp = "bed_temp"
    }
}

nonisolated enum OCRVocabularyDerivation {

    // Constants copied verbatim from the script.
    private static let fillerNotMaterial: Set<String> = [
        "WOOD", "CF", "GF", "PEARL", "FLAX", "SMP", "GLOW", "SILK",
        "MARBLE", "METAL", "GLITTER", "SPARKLE", "GALAXY",
    ]
    private static let minMaterialCount = 3
    private static let baseFamilies = ["PCTG", "PETG", "HIPS", "APLA", "CPE", "PVB", "PVA", "TPE",
                                       "TPU", "PHA", "ASA", "ABS", "PLA", "PET", "PA", "PC", "PP", "PE"]
    private static let labelWordDenylist: Set<String> = [
        "color", "colour", "material", "filament", "brand", "type",
        "weight", "net weight", "net", "spool", "diameter",
        "temperature", "temp", "nozzle", "bed",
    ]
    private static let separatorClass = "[\\s:/_–—-]"
    private static let edgePunctuation = CharacterSet(charactersIn: " .,;:!|/")

    private static let nonAlnum = try! NSRegularExpression(pattern: "[^a-z0-9]+")
    private static let whitespaceRun = try! NSRegularExpression(pattern: "\\s+")
    private static let trailingIndex = try! NSRegularExpression(pattern: "^(.*\\w.*?)\\s+\\d{1,2}$")
    private static let alphabetic = try! NSRegularExpression(pattern: "[^\\W\\d_]")
    private static let hex6 = try! NSRegularExpression(pattern: "^[0-9A-F]{6}$")

    /// Only the entries `filaments` and `materials` add to `bundle`; each list sorted
    /// longest-first. Bundled entries are never repeated.
    static func delta(
        filaments: [SpoolmanDBFilament],
        materials: [SpoolmanDBMaterial],
        bundle: OCRVocabularyLists
    ) -> OCRVocabularyLists {
        let brands = newBrands(filaments, bundle: bundle)
        let materialList = newMaterials(filaments, materials, bundle: bundle)
        let stripNames = bundle.materials.map(\.name) + materialList.map(\.name)
        return OCRVocabularyLists(
            colorMap: newColors(filaments, materialNames: stripNames, bundle: bundle),
            brands: brands,
            materials: materialList,
            filamentTemps: newTemps(filaments, bundle: bundle)
        )
    }

    // MARK: Brands

    private static func newBrands(_ filaments: [SpoolmanDBFilament], bundle: OCRVocabularyLists) -> [OCRVocabularyBrandEntry] {
        var seen = Set(bundle.brands.map { $0.name.lowercased() })
        var out: [String] = []
        for f in filaments {
            let name = f.manufacturer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, seen.insert(name.lowercased()).inserted { out.append(name) }
        }
        return longestFirst(out, by: { $0 }).map(OCRVocabularyBrandEntry.init(name:))
    }

    // MARK: Materials

    private static func newMaterials(
        _ filaments: [SpoolmanDBFilament],
        _ catalogue: [SpoolmanDBMaterial],
        bundle: OCRVocabularyLists
    ) -> [OCRVocabularyMaterialEntry] {
        let bedTable = bedTempTable(filaments)
        let catalogueBed = Dictionary(
            catalogue.compactMap { m in m.bedTemp.map { (m.material.trimmingCharacters(in: .whitespaces).uppercased(), $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        var chosen: [String: String] = [:]  // lowercase -> name
        var order: [String] = []
        let bundled = Set(bundle.materials.map { $0.name.lowercased() })
        func add(_ name: String) {
            let key = name.lowercased()
            if bundled.contains(key) || chosen[key] != nil { return }
            chosen[key] = name
            order.append(key)
        }
        for m in catalogue {
            let name = m.material.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { add(name) }
        }
        var counts: [String: Int] = [:]
        var seenOrder: [String] = []
        for f in filaments {
            let name = f.material.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            if counts[name] == nil { seenOrder.append(name) }
            counts[name, default: 0] += 1
        }
        for name in seenOrder where counts[name, default: 0] >= minMaterialCount {
            if fillerNotMaterial.contains(name.uppercased()) { continue }
            add(name)
        }
        let entries = order.compactMap { chosen[$0] }.map { name in
            OCRVocabularyMaterialEntry(
                name: name,
                key: name.lowercased(),
                inferredBedTemp: inferredBedTemp(name, table: bedTable, catalogueBed: catalogueBed)
            )
        }
        return longestFirst(entries, by: \.name)
    }

    /// Median of `bed_temp` per exact material name, as `compute_bed_temp_table`.
    private static func bedTempTable(_ filaments: [SpoolmanDBFilament]) -> [String: Int] {
        var samples: [String: [Int]] = [:]
        for f in filaments {
            let name = f.material.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, let bed = f.bedTemp { samples[name, default: []].append(bed) }
        }
        return samples.mapValues(medianRounded)
    }

    /// `inferred_bed_temp`, with the catalogue's own `bed_temp` between the direct
    /// median and the base-family median.
    private static func inferredBedTemp(_ name: String, table: [String: Int], catalogueBed: [String: Int]) -> Int? {
        if let v = table[name] { return v }
        let upper = name.uppercased()
        if let v = table.first(where: { $0.key.uppercased() == upper })?.value { return v }
        if let v = catalogueBed[upper] { return v }
        for base in baseFamilies.sorted(by: { $0.count > $1.count }) where upper.hasPrefix(base) {
            let family = table.filter { $0.key.uppercased().hasPrefix(base) }.map(\.value)
            if !family.isEmpty { return medianRounded(family) }
        }
        return nil
    }

    /// Python's `int(round(median(...)))`: round half to even.
    private static func medianRounded(_ values: [Int]) -> Int {
        let s = values.sorted()
        if s.count % 2 == 1 { return s[s.count / 2] }
        let mid = Double(s[s.count / 2 - 1] + s[s.count / 2]) / 2
        return Int(mid.rounded(.toNearestOrEven))
    }

    // MARK: Colours

    private static func newColors(
        _ filaments: [SpoolmanDBFilament],
        materialNames: [String],
        bundle: OCRVocabularyLists
    ) -> [OCRVocabularyColorEntry] {
        let stripRegex = materialStripRegex(materialNames)
        let bundled = Set(bundle.colorMap.map { matchKey($0.phrase) })
        let materialKeys = Set(materialNames.map(matchKey))
        var chosen: [String: (phrase: String, hex: String, clean: Bool)] = [:]
        var order: [String] = []
        for f in filaments {
            guard let hex = normalizedHex(f.colorHex) else { continue }
            let name = collapseWhitespace(f.name).trimmingCharacters(in: edgePunctuation)
            if name.isEmpty { continue }
            let (cleaned0, stripped) = cleanColorName(name, stripRegex)
            let cleaned = cleaned0.trimmingCharacters(in: edgePunctuation)
            let key = matchKey(cleaned)
            if key.isEmpty || labelWordDenylist.contains(key)
                || materialKeys.contains(key) || bundled.contains(key) { continue }
            if let existing = chosen[key] {
                if !stripped && !existing.clean { chosen[key] = (cleaned, hex, true) }
            } else {
                chosen[key] = (cleaned, hex, !stripped)
                order.append(key)
            }
        }
        let entries = order.compactMap { chosen[$0] }.map { OCRVocabularyColorEntry(phrase: $0.phrase, hex: $0.hex) }
        return longestFirst(entries, by: \.phrase)
    }

    private static func matchKey(_ phrase: String) -> String {
        let lower = phrase.lowercased()
        return nonAlnum.stringByReplacingMatches(in: lower, range: NSRange(lower.startIndex..., in: lower), withTemplate: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func materialStripRegex(_ names: [String]) -> NSRegularExpression? {
        let ordered = Set(names.filter { !$0.isEmpty }).sorted { $0.count > $1.count || ($0.count == $1.count && $0 < $1) }
        guard !ordered.isEmpty else { return nil }
        let alternation = ordered.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        return try? NSRegularExpression(pattern: "^(?:\(alternation))\(separatorClass)+(?=\\S)", options: .caseInsensitive)
    }

    private static func hasAlphabetic(_ s: String) -> Bool {
        alphabetic.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func cleanColorName(_ name: String, _ stripRegex: NSRegularExpression?) -> (String, Bool) {
        var result = name
        var stripped = false
        if let stripRegex {
            while let m = stripRegex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
                  let r = Range(m.range, in: result) {
                let candidate = result[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !hasAlphabetic(candidate) { break }
                result = candidate
                stripped = true
            }
        }
        if let m = trailingIndex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let r = Range(m.range(at: 1), in: result) {
            let candidate = result[r].trimmingCharacters(in: .whitespacesAndNewlines)
            if hasAlphabetic(candidate) {
                result = candidate
                stripped = true
            }
        }
        return (result, stripped)
    }

    private static func normalizedHex(_ hex: String?) -> String? {
        guard let hex else { return nil }
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("#") { s.removeFirst() }
        s = s.uppercased()
        return hex6.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil ? s : nil
    }

    private static func collapseWhitespace(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return whitespaceRun.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: " ")
    }

    // MARK: Temperatures

    private static func newTemps(_ filaments: [SpoolmanDBFilament], bundle: OCRVocabularyLists) -> [OcrFilamentTempEntry] {
        func key(_ brand: String, _ material: String, _ color: String) -> String {
            "\(brand.lowercased())\u{1F}\(material.uppercased())\u{1F}\(color.lowercased())"
        }
        var seen = Set(bundle.filamentTemps.map { key($0.brand, $0.material, $0.colorName) })
        var out: [OcrFilamentTempEntry] = []
        for f in filaments {
            var nozzleMin = f.extruderTemp
            var nozzleMax = f.extruderTemp
            if let range = f.extruderTempRange, range.count >= 2 {
                nozzleMin = range[0]
                nozzleMax = range[1]
            }
            if nozzleMin == nil && nozzleMax == nil && f.bedTemp == nil { continue }
            let brand = f.manufacturer.trimmingCharacters(in: .whitespacesAndNewlines)
            let material = f.material.trimmingCharacters(in: .whitespacesAndNewlines)
            let color = collapseWhitespace(f.name)
            if brand.isEmpty || material.isEmpty || color.isEmpty { continue }
            if labelWordDenylist.contains(matchKey(color)) { continue }
            guard seen.insert(key(brand, material, color)).inserted else { continue }
            out.append(OcrFilamentTempEntry(brand: brand, material: material, colorName: color,
                                            nozzleMin: nozzleMin, nozzleMax: nozzleMax, bedTemp: f.bedTemp))
        }
        return out
    }

    // MARK: Sorting

    /// Stable longest-first sort (ties keep their input order).
    private static func longestFirst<T>(_ items: [T], by text: (T) -> String) -> [T] {
        items.enumerated()
            .sorted { a, b in
                let la = text(a.element).count, lb = text(b.element).count
                return la != lb ? la > lb : a.offset < b.offset
            }
            .map(\.element)
    }
}
