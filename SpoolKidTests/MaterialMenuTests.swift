import Foundation
import Testing
@testable import SpoolKid

struct MaterialMenuTests {
    @Test func materialMenuKeepsEveryPreset() {
        let menu = Set(AppConfig.materials)
        for key in AppConfig.materialPresets.keys {
            #expect(menu.contains(key))
        }
    }

    @Test func materialMenuAddsVocabularyMaterials() {
        #expect(AppConfig.materials.contains("PLA-CF"))
    }

    @Test func materialMenuHasNoCaseDuplicates() {
        let keys = AppConfig.materials.map { $0.lowercased() }
        #expect(Set(keys).count == keys.count)
    }

    @Test func materialMenuIsAlphabetical() {
        let names = AppConfig.materials
        let sorted = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        #expect(names == sorted)
    }
}
