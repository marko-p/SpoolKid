//
//  OCRVocabularyDerivationTests.swift
//  SpoolKidTests
//
//  The SpoolmanDB -> vocabulary delta rules, ported from the script
//  that builds the bundled OCR vocabulary.
//

import Foundation
import Testing

@testable import SpoolKid

@Suite struct OCRVocabularyDerivationTests {

    private let bundle = OCRVocabularyLists(
        colorMap: [
            OCRVocabularyColorEntry(phrase: "Blue", hex: "0000FF"),
            OCRVocabularyColorEntry(phrase: "Red", hex: "FF0000"),
        ],
        brands: [OCRVocabularyBrandEntry(name: "eSun")],
        materials: [
            OCRVocabularyMaterialEntry(name: "PLA", key: "pla", inferredBedTemp: 60),
            OCRVocabularyMaterialEntry(name: "PETG", key: "petg", inferredBedTemp: 80),
        ],
        filamentTemps: [
            OcrFilamentTempEntry(brand: "eSun", material: "PLA", colorName: "Blue",
                                 nozzleMin: 190, nozzleMax: 220, bedTemp: 60)
        ]
    )

    private func filament(
        _ id: String = UUID().uuidString,
        brand: String = "Acme",
        name: String = "Thing",
        material: String = "PLA",
        hex: String? = "112233",
        hexes: [String]? = nil,
        temp: Int? = nil,
        range: [Int]? = nil,
        bed: Int? = nil
    ) -> SpoolmanDBFilament {
        SpoolmanDBFilament(
            id: id, manufacturer: brand, name: name, material: material, spoolType: nil,
            density: 1.24, weight: 1000, spoolWeight: 200, diameter: 1.75,
            colorHex: hex, colorHexes: hexes, extruderTemp: temp, bedTemp: bed,
            extruderTempRange: range
        )
    }

    private func delta(_ f: [SpoolmanDBFilament], materials: [SpoolmanDBMaterial] = []) -> OCRVocabularyLists {
        OCRVocabularyDerivation.delta(filaments: f, materials: materials, bundle: bundle)
    }

    @Test func newBrandIsAdded() {
        let d = delta([filament(brand: "Acme")])
        #expect(d.brands.map(\.name) == ["Acme"])
    }

    @Test func bundledBrandIsNotRepeatedIgnoringCase() {
        #expect(delta([filament(brand: "ESUN")]).brands.isEmpty)
    }

    @Test func catalogueMaterialNeedsThreeFilaments() {
        let two = delta((0..<2).map { _ in filament(material: "PEKK") })
        #expect(!two.materials.contains { $0.name == "PEKK" })
        let three = delta((0..<3).map { _ in filament(material: "PEKK") })
        #expect(three.materials.contains { $0.name == "PEKK" })
    }

    @Test func fillerMaterialIsNeverAdded() {
        let d = delta((0..<5).map { _ in filament(material: "WOOD") })
        #expect(!d.materials.contains { $0.name == "WOOD" })
    }

    @Test func materialsJSONEntryIsAlwaysAdded() {
        let d = delta([], materials: [SpoolmanDBMaterial(material: "PPS", density: 1.3, extruderTemp: nil, bedTemp: nil)])
        #expect(d.materials.map(\.name) == ["PPS"])
        #expect(d.materials.first?.key == "pps")
    }

    @Test func inferredBedTempIsMedianThenMaterialsJSONThenFamily() {
        let pekk = [100, 110, 120].map { filament(material: "PEKK", bed: $0) }
        let petg = [filament(material: "PETG", bed: 80), filament(material: "PETG", bed: 80)]
        let mats = [
            SpoolmanDBMaterial(material: "PPS", density: nil, extruderTemp: nil, bedTemp: 90),
            SpoolmanDBMaterial(material: "PETG-HF", density: nil, extruderTemp: nil, bedTemp: nil),
        ]
        let d = delta(pekk + petg, materials: mats)
        func bed(_ n: String) -> Int? { d.materials.first { $0.name == n }?.inferredBedTemp }
        #expect(bed("PEKK") == 110)
        #expect(bed("PPS") == 90)
        #expect(bed("PETG-HF") == 80)
    }

    @Test func colorPrefixAndIndexAreStripped() {
        let d = delta([filament(name: "PLA - Sky Blue", hex: "87CEEB"),
                       filament(name: "Sky Blue 2", hex: "87CEEB")])
        #expect(d.colorMap.map(\.phrase) == ["Sky Blue"])
        #expect(d.colorMap.first?.hex == "87CEEB")
    }

    @Test func materialOnlyNameIsDropped() {
        #expect(delta([filament(name: "PLA")]).colorMap.isEmpty)
    }

    @Test func labelWordIsDropped() {
        #expect(delta([filament(name: "Color")]).colorMap.isEmpty)
    }

    @Test func bundledColourKeyIsNotRepeated() {
        #expect(delta([filament(name: "Blue.")]).colorMap.isEmpty)
    }

    @Test func multiColourFilamentIsSkipped() {
        let d = delta([filament(name: "Rainbow", hex: nil, hexes: ["FF0000", "00FF00"])])
        #expect(d.colorMap.isEmpty)
    }

    @Test func deltaIsSortedLongestFirst() {
        let d = delta([
            filament(brand: "Bo", name: "Ash", hex: "111111"),
            filament(brand: "Longer Brand", name: "Midnight Navy Blue", hex: "000080"),
            filament(brand: "Mid Brand", name: "Teal", hex: "008080"),
        ])
        #expect(d.colorMap.map(\.phrase) == ["Midnight Navy Blue", "Teal", "Ash"])
        #expect(d.brands.map(\.name) == ["Longer Brand", "Mid Brand", "Bo"])
    }

    @Test func tempsUseRangeElseSingleValue() {
        let d = delta([
            filament(name: "Alpha", range: [230, 270], bed: 100),
            filament(name: "Beta", temp: 215),
            filament(name: "Gamma"),
            filament(brand: "eSun", name: "Blue", temp: 200),
        ])
        let alpha = d.filamentTemps.first { $0.colorName == "Alpha" }
        #expect(alpha?.nozzleMin == 230 && alpha?.nozzleMax == 270 && alpha?.bedTemp == 100)
        let beta = d.filamentTemps.first { $0.colorName == "Beta" }
        #expect(beta?.nozzleMin == 215 && beta?.nozzleMax == 215)
        #expect(!d.filamentTemps.contains { $0.colorName == "Gamma" })
        #expect(!d.filamentTemps.contains { $0.brand == "eSun" })
    }
}
