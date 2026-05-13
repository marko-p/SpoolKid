import Foundation

enum SubtypeOptionService {
    static let presetOptions: [String] = [
        "Basic", "Rapid", "HF", "Silk", "Matte", "Glossy", "Translucent", "Transparent", "Glitter", "Glow", "Carbon Fiber", "Wood", "Flexible", "Semi Flexible", "Support", "PVA"
    ]

    static func resolve(userInput: String) -> String {
        userInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func derive(from name: String) -> String {
        let lowercaseName = name.lowercased()
        
        let subtypeMappings: [(keywords: [String], subtype: String)] = [
            (["matte"], "Matte"),
            (["silk"], "Silk"),
            (["glossy", "gloss"], "Glossy"),
            (["translucent", "translucentpetg"], "Translucent"),
            (["transparent", "clear"], "Transparent"),
            (["glitter"], "Glitter"),
            (["glow"], "Glow"),
            (["carbon", "cf", "cf15", "cf10"], "Carbon Fiber"),
            (["wood"], "Wood"),
            (["support", "pva"], "Support"),
            (["basic"], "Basic"),
            (["hf", "high speed", "hs", "hyperspeed"], "HF"),
            (["rapid"], "Rapid"),
            (["tpu", "flex", "flexible", "soft"], "Flexible"),
            (["semi flexible", "semi-flexible", "fpe"], "Semi Flexible")
        ]
        
        for mapping in subtypeMappings {
            for keyword in mapping.keywords {
                if lowercaseName.contains(keyword) {
                    return mapping.subtype
                }
            }
        }
        
        return "Basic"
    }
}
