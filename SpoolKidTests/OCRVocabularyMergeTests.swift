import Foundation
import Testing
@testable import SpoolKid

struct OCRVocabularyMergeTests {
    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("vocab-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private static func write(_ json: String, _ name: String, in dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try json.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private static func lists(
        colors: [(String, String)] = [], brands: [String] = [],
        materials: [(String, String, Int?)] = [], temps: [OcrFilamentTempEntry] = []
    ) -> OCRVocabularyLists {
        OCRVocabularyLists(
            colorMap: colors.map { OCRVocabularyColorEntry(phrase: $0.0, hex: $0.1) },
            brands: brands.map { OCRVocabularyBrandEntry(name: $0) },
            materials: materials.map { OCRVocabularyMaterialEntry(name: $0.0, key: $0.1, inferredBedTemp: $0.2) },
            filamentTemps: temps
        )
    }

    @Test func mergeKeepsBundledEntryOverDelta() {
        let bundleTemp = OcrFilamentTempEntry(brand: "Acme", material: "PLA", colorName: "Red", nozzleMin: 200, nozzleMax: 210, bedTemp: 60)
        let deltaTemp = OcrFilamentTempEntry(brand: "ACME", material: "pla", colorName: "RED", nozzleMin: 1, nozzleMax: 2, bedTemp: 3)
        let merged = OCRVocabularyLoader.merge(
            bundle: Self.lists(colors: [("Sky Blue", "#111111")], brands: ["Acme"], temps: [bundleTemp]),
            delta: Self.lists(colors: [("sky-blue", "#222222")], brands: ["ACME", "Other"], temps: [deltaTemp])
        )
        #expect(merged.colorMap.count == 1)
        #expect(merged.colorMap[0].hex == "#111111")
        #expect(merged.brands.map(\.name) == ["Other", "Acme"])
        #expect(merged.filamentTemps == [bundleTemp])
    }

    @Test func mergeSortsLongestFirst() {
        let merged = OCRVocabularyLoader.merge(
            bundle: Self.lists(colors: [("red", "#1")], brands: ["Prusa"], materials: [("PLA", "pla", nil)]),
            delta: Self.lists(colors: [("deep ocean blue", "#2")], brands: ["Prusa Research"], materials: [("PLA Silk Plus", "pla silk plus", nil)])
        )
        #expect(merged.colorMap.map(\.phrase) == ["deep ocean blue", "red"])
        #expect(merged.materials.map(\.name) == ["PLA Silk Plus", "PLA"])
        #expect(merged.brands.map(\.name) == ["Prusa Research", "Prusa"])
    }

    @Test func staleBuildCannotOverwriteNewerOne() throws {
        let dir = Self.temporaryDirectory()
        let loader = OCRVocabularyLoader(deltaDirectory: dir)
        let older = loader.beginReload()
        let newer = loader.beginReload()
        try Self.write(#"[{"name":"New Brand"}]"#, "OCRBrandList.json", in: dir)
        let newVocab = loader.build()
        loader.commit(newVocab, generation: newer)
        loader.commit(OCRVocabulary(colorMap: [], brands: [], materials: [], filamentTemps: [], colorPhraseIndex: [:], colorPhraseWordCounts: []), generation: older)
        #expect(loader.vocabulary().brands.contains("New Brand"))
    }

    @Test func noDeltaDirectoryMeansBundleOnly() {
        let loader = OCRVocabularyLoader(deltaDirectory: Self.temporaryDirectory())
        let vocab = loader.vocabulary()
        let bundled = loader.bundleLists()
        #expect(vocab.colorMap.count == bundled.colorMap.count)
        #expect(vocab.brands.count == bundled.brands.count)
        #expect(vocab.materials.count == bundled.materials.count)
        #expect(vocab.filamentTemps.count == bundled.filamentTemps.count)
        #expect(!vocab.colorMap.isEmpty)
    }

    @Test func corruptDeltaFileIsIgnoredOthersApply() throws {
        let dir = Self.temporaryDirectory()
        try Self.write("not json {", "OCRColorMap.json", in: dir)
        try Self.write(#"[{"name":"Zzz Brand"}]"#, "OCRBrandList.json", in: dir)
        let loader = OCRVocabularyLoader(deltaDirectory: dir)
        let vocab = loader.vocabulary()
        #expect(vocab.brands.contains("Zzz Brand"))
        #expect(vocab.colorMap.count == loader.bundleLists().colorMap.count)
    }

    @Test func reloadPicksUpNewDelta() throws {
        let dir = Self.temporaryDirectory()
        let loader = OCRVocabularyLoader(deltaDirectory: dir)
        #expect(!loader.vocabulary().brands.contains("Yyy Brand"))
        try Self.write(#"[{"name":"Yyy Brand"}]"#, "OCRBrandList.json", in: dir)
        loader.reload()
        #expect(loader.vocabulary().brands.contains("Yyy Brand"))
    }

    @Test func materialNamesAreAlphabeticalAndIncludeDelta() throws {
        let dir = Self.temporaryDirectory()
        try Self.write(#"[{"name":"AAA Test Mat","key":"aaa test mat","inferredBedTemp":null}]"#, "OCRMaterialList.json", in: dir)
        let loader = OCRVocabularyLoader(deltaDirectory: dir)
        let names = loader.materialNames()
        #expect(names.first == "AAA Test Mat")
        #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        #expect(Set(names.map { $0.lowercased() }).count == names.count)
    }

    @Test func concurrentReadsDuringReloadDoNotDeadlock() async {
        let loader = OCRVocabularyLoader(deltaDirectory: Self.temporaryDirectory())
        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<100 { group.addTask { loader.vocabulary().brands.count } }
            group.addTask { loader.reload(); return 0 }
            for await _ in group {}
        }
        #expect(!loader.vocabulary().brands.isEmpty)
    }
}
