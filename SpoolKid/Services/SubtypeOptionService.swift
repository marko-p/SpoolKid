import Foundation

enum SubtypeOptionService {
    static let presetOptions: [String] = [
        "Basic", "Rapid", "HF", "Silk", "Matte", "Glossy", "Translucent", "Transparent", "Glitter", "Glow", "Carbon Fiber", "Wood", "Flexible", "Semi Flexible", "Support", "PVA"
    ]

    static func resolve(userInput: String) -> String {
        userInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
