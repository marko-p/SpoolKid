//
//  FilamentColorsTests.swift
//  SpoolKidTests
//
//  Purpose: The multi-color filament value type. Pins the reading rule
//  (junk-tolerant parsing of Spoolman/FilaMan fields), the editor's row
//  rules, and the draft fields each save path sends.
//

import SwiftUI
import Testing
@testable import SpoolKid

struct FilamentColorsTests {

    // MARK: - Reading

    @Test func parsesAndNormalizesJunk() {
        let colors = FilamentColors(
            colorHex: nil,
            multiColorHexes: "#ff0000, ,ZZZ,00ff00",
            multiColorDirection: "longitudinal"
        )
        #expect(colors.hexes == ["FF0000", "00FF00"])
        #expect(colors.pattern == .gradient)
        #expect(colors.isMulti)
    }

    @Test func unknownDirectionIsCoextruded() {
        let none = FilamentColors(colorHex: nil, multiColorHexes: "2D39C9,A51A52", multiColorDirection: nil)
        let striped = FilamentColors(colorHex: nil, multiColorHexes: "2D39C9,A51A52", multiColorDirection: "striped")
        #expect(none.pattern == .coextruded)
        #expect(striped.pattern == .coextruded)
    }

    @Test func primaryHexFallsBackToMulti() {
        let colors = FilamentColors(colorHex: nil, multiColorHexes: "2D39C9,A51A52", multiColorDirection: "coaxial")
        #expect(colors.primaryHex == "2D39C9")
    }

    @Test func singlePartMultiIsSingle() {
        let colors = FilamentColors(colorHex: nil, multiColorHexes: "ABCDEF", multiColorDirection: nil)
        #expect(colors.hexes == ["ABCDEF"])
        #expect(!colors.isMulti)
    }

    @Test func colorHexWinsWhenMultiHasOne() {
        let colors = FilamentColors(colorHex: "DADADA", multiColorHexes: nil, multiColorDirection: nil)
        #expect(colors.hexes == ["DADADA"])
    }

    @Test func keepsAlphaSuffix() {
        let colors = FilamentColors(colorHex: nil, multiColorHexes: "FF000080,00FF00", multiColorDirection: nil)
        #expect(colors.hexes.first == "FF000080")
    }

    @Test func moreThanFiveKept() {
        let colors = FilamentColors(
            colorHex: nil,
            multiColorHexes: "111111,222222,333333,444444,555555,666666",
            multiColorDirection: "coaxial"
        )
        #expect(colors.hexes.count == 6)
        #expect(colors.isValid)
        #expect(!colors.canAddColor)
    }

    // MARK: - Editing

    @Test func editing() {
        var colors = FilamentColors(colorHex: "DADADA", multiColorHexes: nil, multiColorDirection: nil)

        colors.switchToMulti()
        #expect(colors.hexes == ["DADADA", ""])
        #expect(!colors.isValid)

        colors.hexes[1] = "a51a52"
        #expect(colors.isValid)

        colors.addColor()
        colors.addColor()
        colors.addColor()
        #expect(colors.hexes.count == 5)
        #expect(!colors.canAddColor)
        colors.addColor()
        #expect(colors.hexes.count == 5)

        colors.removeColor(at: 2)
        colors.removeColor(at: 2)
        colors.removeColor(at: 2)
        #expect(colors.hexes == ["DADADA", "a51a52"])
        colors.removeColor(at: 0)
        #expect(colors.hexes == ["DADADA", "a51a52"])

        colors.switchToSingle()
        #expect(colors.hexes == ["DADADA"])
    }

    // MARK: - Draft fields

    @Test func newMultiDraft() {
        let colors = FilamentColors(hexes: ["2D39C9", "A51A52"], pattern: .coextruded)
        let draft = colors.draftFields(loaded: nil)
        #expect(draft.colorHex == nil)
        #expect(draft.multiColorHexes == .set("2D39C9,A51A52"))
        #expect(draft.multiColorDirection == .set("coaxial"))
    }

    @Test func unchangedMultiDraftIgnoresColors() {
        let colors = FilamentColors(hexes: ["2D39C9", "A51A52"], pattern: .coextruded)
        let draft = colors.draftFields(loaded: colors)
        #expect(draft.colorHex == nil)
        #expect(draft.multiColorHexes == .ignore)
        #expect(draft.multiColorDirection == .ignore)
    }

    @Test func multiToSingleDraft() {
        let colors = FilamentColors(hexes: ["2D39C9"], pattern: .coextruded)
        let loaded = FilamentColors(hexes: ["2D39C9", "A51A52"], pattern: .coextruded)
        let draft = colors.draftFields(loaded: loaded)
        #expect(draft.colorHex == "2D39C9")
        #expect(draft.multiColorHexes == .setNil)
        #expect(draft.multiColorDirection == .setNil)
    }

    @Test func singleDraft() {
        let colors = FilamentColors(hexes: ["DADADA"], pattern: .coextruded)
        let loaded = FilamentColors(hexes: ["DADADA"], pattern: .coextruded)
        let draft = colors.draftFields(loaded: loaded)
        #expect(draft.colorHex == "DADADA")
        #expect(draft.multiColorHexes == .ignore)
        #expect(draft.multiColorDirection == .ignore)
    }

    @Test func invalidMultiDraftIsNoOp() {
        for rows in [["2D39C9", ""], ["2D39C9", "ZZZ"]] {
            let colors = FilamentColors(hexes: rows, pattern: .coextruded)
            let draft = colors.draftFields(loaded: nil)
            #expect(draft.colorHex == nil)
            #expect(draft.multiColorHexes == .ignore)
            #expect(draft.multiColorDirection == .ignore)
        }
    }

    @Test func invalidSingleDraftIsNoOp() {
        let colors = FilamentColors(hexes: ["ZZZ"], pattern: .coextruded)
        let draft = colors.draftFields(loaded: nil)
        #expect(draft.colorHex == nil)
        #expect(draft.multiColorHexes == .ignore)
        #expect(draft.multiColorDirection == .ignore)
    }

    @Test func directlyAssignedRowIsSentNormalized() {
        var colors = FilamentColors(hexes: ["2D39C9"], pattern: .coextruded)
        colors.switchToMulti()
        colors.hexes[1] = "a51a52"
        let draft = colors.draftFields(loaded: nil)
        #expect(draft.multiColorHexes == .set("2D39C9,A51A52"))
        #expect(draft.multiColorDirection == .set("coaxial"))
    }

    @Test func lowercaseRetypingOfLoadedValueIsUnchanged() {
        let loaded = FilamentColors(hexes: ["2D39C9", "A51A52"], pattern: .coextruded)
        var colors = loaded
        colors.hexes = ["2d39c9", "#a51a52"]
        let draft = colors.draftFields(loaded: loaded)
        #expect(draft.multiColorHexes == .ignore)
        #expect(draft.multiColorDirection == .ignore)
    }

    @Test func lowercaseRowIsSentNormalized() {
        let colors = FilamentColors(hexes: ["2d39c9", "#a51a52"], pattern: .gradient)
        let draft = colors.draftFields(loaded: nil)
        #expect(draft.multiColorHexes == .set("2D39C9,A51A52"))
        #expect(draft.multiColorDirection == .set("longitudinal"))
    }

    // MARK: - FilaMan styles

    @Test func filaManStyles() {
        #expect(FilamentColors.Pattern(filaManStyle: " Striped ") == .coextruded)
        #expect(FilamentColors.Pattern(filaManStyle: "gradient") == .gradient)
        #expect(FilamentColors.Pattern(filaManStyle: "coaxial") == nil)
    }
}

@Suite("Tag colors")
@MainActor
struct TagColorsTests {

    @Test func fromMultiFilament() {
        let filament = Filament(id: 1, name: "Multi", material: "PLA", colorHex: nil, multiColorHexes: "2D39C9,A51A52")
        let data = FilamentTagData.from(filament: filament)
        #expect(data.colorHex == "2D39C9")
        #expect(data.additionalColorHexes == ["A51A52"])
    }

    @Test func fromSingleFilament() {
        let filament = Filament(id: 2, name: "Single", material: "PLA", colorHex: "2D39C9")
        let data = FilamentTagData.from(filament: filament)
        #expect(data.additionalColorHexes == nil)
    }

    @Test func tagColorsAreCoextruded() {
        let data = FilamentTagData(
            name: "Multi", material: "PLA", brand: "Brand", colorHex: "2D39C9", additionalColorHexes: ["A51A52"],
            minNozzleTemp: 200, maxNozzleTemp: 220, minBedTemp: 50, maxBedTemp: 60
        )
        #expect(data.colors.pattern == .coextruded)
        #expect(data.colors.hexes == ["2D39C9", "A51A52"])
    }

    @Test func trimmedColorsCaps() {
        let data = FilamentTagData(
            name: "Six", material: "PLA", brand: "Brand", colorHex: "111111",
            additionalColorHexes: ["222222", "333333", "444444", "555555", "666666"],
            minNozzleTemp: 200, maxNozzleTemp: 220, minBedTemp: 50, maxBedTemp: 60
        )
        #expect(data.trimmedColors(max: 4).count == 4)
        #expect(data.trimmedColors(max: 4) == ["111111", "222222", "333333", "444444"])
    }

    // MARK: - RGB-only extra colors

    @Test func anInvalidPrimaryDoesNotCostTheFirstExtra() {
        let data = FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "zz", additionalColorHexes: ["A51A52", "112233"],
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60
        )
        #expect(data.extraColorsRGB(maxTotal: 5) == ["A51A52", "112233"])
        #expect(data.trimmedColors(max: 5) == ["A51A52", "112233"])
    }

    @Test func storedAlphaPairsAreDroppedToRGB() {
        let data = FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "2D39C9AA", additionalColorHexes: ["A51A52FF"],
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60
        )
        #expect(data.trimmedColors(max: 5) == ["2D39C9", "A51A52"])
        #expect(data.extraColorsRGB(maxTotal: 5) == ["A51A52"])
    }
}

struct FilamentColorsTagFieldsTests {
    @Test func validMultiGivesFirstAndRest() {
        let fields = FilamentColors(hexes: ["2D39C9", "A51A52", "111111"]).tagColorFields
        #expect(fields.colorHex == "2D39C9")
        #expect(fields.additionalColorHexes == ["A51A52", "111111"])
    }

    @Test func singleGivesHexAndNoExtras() {
        let fields = FilamentColors(hexes: ["2D39C9"]).tagColorFields
        #expect(fields.colorHex == "2D39C9")
        #expect(fields.additionalColorHexes == nil)
    }

    @Test func blankAndJunkRowsNeverReachATag() {
        let fields = FilamentColors(hexes: ["", "A51A52"]).tagColorFields
        #expect(fields.colorHex == "A51A52")
        #expect(fields.additionalColorHexes == nil)
        #expect(!FilamentColors(hexes: ["", "A51A52"]).isValid)
        #expect(!FilamentColors(hexes: ["2D3"]).isValid)
    }

    @Test func orDefaultFillsOnlyAnEmptyEditor() {
        #expect(FilamentColors(hexes: []).orDefault("AABBCC").hexes == ["AABBCC"])
        #expect(FilamentColors(hexes: ["111111"]).orDefault("AABBCC").hexes == ["111111"])
    }
}

struct MultiColorPrefillTests {
    @Test func writeTagStartsMultiForATwoColorTag() {
        let data = FilamentTagData(
            material: "PLA", brand: "B", colorHex: "2D39C9", additionalColorHexes: ["A51A52"],
            minNozzleTemp: 200, maxNozzleTemp: 220, minBedTemp: 50, maxBedTemp: 60
        )
        #expect(data.colors.isMulti)
        #expect(data.colors.hexes == ["2D39C9", "A51A52"])
    }

    @Test func filamentFormStartsMultiWithItsPattern() {
        let filament = Filament(
            id: 1, name: "Dual", material: "PLA", colorHex: nil,
            multiColorHexes: "2D39C9,A51A52", multiColorDirection: "longitudinal"
        )
        let colors = filament.colors.orDefault(AppConfig.Defaults.colorHex)
        #expect(colors.isMulti)
        #expect(colors.pattern == .gradient)
    }
}

struct FilamentSwatchTests {
    @Test func slicesSplitEvenly() {
        let two = FilamentSwatch.slices(count: 2)
        #expect(two.count == 2)
        #expect(two[0].start == .degrees(-90) && two[0].end == .degrees(90))
        #expect(two[1].start == .degrees(90) && two[1].end == .degrees(270))

        let three = FilamentSwatch.slices(count: 3)
        #expect(three.map(\.start) == [.degrees(-90), .degrees(30), .degrees(150)])
        #expect(three.map(\.end) == [.degrees(30), .degrees(150), .degrees(270)])
    }
}
