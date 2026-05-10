import Foundation

enum OpenPrintTagInference {
    private static let maxMaterialTags = 16

    private static let keywordToTagID: [(patterns: [String], tagID: Int)] = [
        (["MATTE", "MATT"], 16),
        (["SILK"], 17),
        (["GLITTER", "SPARKLE"], 23),
        (["GLOW IN THE DARK", "GLOW", "GITD", "LUMINOUS"], 24),
        (["NEON"], 25),
        (["IRIDESCENT"], 21),
        (["PEARL", "PEARLESCENT"], 22),
        (["TRANSLUCENT"], 19),
        (["TRANSPARENT", "CLEAR", "CRYSTAL"], 20),
        (["COEXTRUD", "DUAL COLOR", "TRI COLOR", "MULTICOLOR", "MULTI COLOR", "RAINBOW"], 29),

        (["ESD", "ANTISTATIC", "ANTI STATIC"], 10),
        (["CONDUCTIVE"], 11),
        (["EMI"], 70),

        (["WATER SOLUBLE", "SOLUBLE", "PVA", "BVOH"], 13),
        (["IPA SOLUBLE"], 14),
        (["LIMONENE"], 15),
        (["BLEND", "ALLOY"], 12),

        (["HIGH SPEED", "HYPERSPEED", "HYPER SPEED", "HS", "HF", "RAPID", "FAST"], 71),
        (["HIGH TEMP", "HIGH TEMPERATURE"], 9),
        (["ABRASIVE"], 4),

        (["FIBERGLASS", "FIBREGLASS", "GLASS FIBER", "GLASS FIBRE", "GF", "GF10", "GF15", "GF20"], 34),
        (["CARBON FIBER", "CARBON FIBRE", "CARBON-FIBER", "CARBON-FIBRE", "CF", "CF10", "CF15", "CF20", "CARBONX"], 31),
        (["CARBON NANO"], 32),
        (["GRAPHENE"], 72),
        (["CARBON"], 30),

        (["WOOD"], 41),
        (["BAMBOO"], 42),
        (["PINE"], 43),
        (["CORK"], 39),
        (["CERAMIC"], 44),

        (["METAL", "METALLIC"], 46),
        (["BRONZE"], 47),
        (["IRON"], 48),
        (["STEEL"], 49),
        (["SILVER"], 50),
        (["COPPER"], 51),
        (["ALUMINIUM", "ALUMINUM"], 52),
        (["BRASS"], 53),
        (["TUNGSTEN"], 54),

        (["RECYCLED", "RPLA", "RPETG", "RPET"], 60),
        (["BIO", "BIOBASED", "BIO-BASED"], 63)
    ]

    static func inferredMaterialTags(name: String?, material: String?, subtype: String?) -> [Int] {
        let joined = [name, material, subtype]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !joined.isEmpty else { return [] }

        let normalized = normalizedText(joined)
        var selected: [Int] = []
        var seen = Set<Int>()

        for entry in keywordToTagID {
            if entry.patterns.contains(where: { containsPattern($0, in: normalized) }) {
                if seen.insert(entry.tagID).inserted {
                    selected.append(entry.tagID)
                }
            }
        }

        return Array(selected.prefix(maxMaterialTags))
    }

    static func mergedMaterialTags(
        existing: [Int]?,
        name: String?,
        material: String?,
        subtype: String?
    ) -> [Int] {
        let inferred = inferredMaterialTags(name: name, material: material, subtype: subtype)
        let allowed = Set(AppConfig.openPrintTagMaterialTags.keys)
        var ordered: [Int] = []
        var seen = Set<Int>()

        for tagID in existing ?? [] where allowed.contains(tagID) {
            if seen.insert(tagID).inserted {
                ordered.append(tagID)
                if ordered.count == maxMaterialTags { return ordered }
            }
        }

        for tagID in inferred where allowed.contains(tagID) {
            if seen.insert(tagID).inserted {
                ordered.append(tagID)
                if ordered.count == maxMaterialTags { break }
            }
        }

        return ordered
    }

    private static func normalizedText(_ raw: String) -> String {
        let upper = raw.uppercased()
        let scalars = upper.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func containsPattern(_ pattern: String, in normalizedHaystack: String) -> Bool {
        let normalizedPattern = normalizedText(pattern)
        guard !normalizedPattern.isEmpty else { return false }
        let paddedHaystack = " \(normalizedHaystack) "
        let paddedPattern = " \(normalizedPattern) "
        return paddedHaystack.contains(paddedPattern)
    }
}
