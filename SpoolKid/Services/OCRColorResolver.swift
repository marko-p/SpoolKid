import Foundation

enum OCRColorResolver {
    static func resolveHex(from text: String) -> String? {
        let (hex, _) = resolveHexAndName(from: text)
        return hex
    }

    static func resolveHexAndName(from text: String) -> (hex: String?, name: String?) {
        let vocab = OCRVocabularyLoader.shared.vocabulary()
        let normalized = OCRVocabularyLoader.normalizeColorPhrase(text)
        let tokens = normalized.split(separator: " ")

        var best: ColorPhraseEntry?

        for wordCount in vocab.colorPhraseWordCounts {
            guard wordCount > 0, wordCount <= tokens.count else { continue }
            for start in 0...(tokens.count - wordCount) {
                let ngram = tokens[start..<start + wordCount].joined(separator: " ")
                if let entry = vocab.colorPhraseIndex[ngram] {
                    if best == nil || entry.arrayIndex < best!.arrayIndex {
                        best = entry
                    }
                }
            }
        }

        return (best?.hex, best?.phrase)
    }
}
