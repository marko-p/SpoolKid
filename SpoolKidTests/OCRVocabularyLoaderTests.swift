import Testing
@testable import SpoolKid

struct OCRVocabularyLoaderTests {
    @Test func loaderDecodesAllBundledFiles() {
        let vocab = OCRVocabularyLoader.shared.vocabulary()
        #expect(!vocab.colorMap.isEmpty)
        #expect(!vocab.brands.isEmpty)
        #expect(!vocab.materials.isEmpty)
        #expect(!vocab.filamentTemps.isEmpty)
    }

    @Test func colorMapIsSortedByPhraseLengthDescending() {
        let vocab = OCRVocabularyLoader.shared.vocabulary()
        for i in 0..<(vocab.colorMap.count - 1) {
            #expect(vocab.colorMap[i].phrase.count >= vocab.colorMap[i + 1].phrase.count)
        }
    }

    @Test func materialsAreSortedByNameLengthDescending() {
        let vocab = OCRVocabularyLoader.shared.vocabulary()
        for i in 0..<(vocab.materials.count - 1) {
            #expect(vocab.materials[i].name.count >= vocab.materials[i + 1].name.count)
        }
    }

    @Test func colorMapContainsNoNullHexValues() {
        let vocab = OCRVocabularyLoader.shared.vocabulary()
        for entry in vocab.colorMap {
            #expect(!entry.hex.isEmpty)
        }
    }

    @Test func filamentTempsHaveAtLeastOneNonNullTemperature() {
        let vocab = OCRVocabularyLoader.shared.vocabulary()
        for entry in vocab.filamentTemps {
            #expect(entry.nozzleMin != nil || entry.nozzleMax != nil || entry.bedTemp != nil)
        }
    }
}
