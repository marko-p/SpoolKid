//
//  LoadoutPlannerTests.swift
//  SpoolKidTests
//
//  Color Matching: each picked color's closest spools of the plan's material
//  (owner, 2026-11-13: no mixing, no toolheads).
//

import Testing
import Foundation
@testable import SpoolKid

private func spool(
    _ id: Int, _ hex: String, material: String = "PLA", grams: Double = 500, filament: Int? = nil,
    multi: Bool = false, colors: [String] = []
) -> LoadoutPlanner.Spool {
    LoadoutPlanner.Spool(
        id: id, filamentID: filament ?? id * 10, title: "Filament \(filament ?? id * 10)", material: material, hex: hex,
        remaining: grams, isMultiColor: multi || !colors.isEmpty, colorHexes: colors
    )
}

private func request(
    _ hexes: [String], _ spools: [LoadoutPlanner.Spool], material: String = "PLA", minimum: Double = 50,
    multiColor: Bool = false
) -> LoadoutPlanner.Request {
    LoadoutPlanner.Request(
        hexes: hexes, spools: spools, primaryMaterial: material, minimumRemaining: minimum, includesMultiColor: multiColor
    )
}

private func match(_ request: LoadoutPlanner.Request) throws -> [LoadoutPlanner.ColorResult] {
    try LoadoutPlanner.match(request).get()
}

struct MaterialPairingTests {
    @Test(arguments: [("PLA", "PLA"), ("PLA+", "PLA"), ("pla silk", "PLA"), ("PETG-CF", "PETG"), (" ASA ", "ASA"), ("PA12", "PA12")])
    func baseMaterial(raw: String, base: String) {
        #expect(MaterialPairing.baseMaterial(raw) == base)
    }
}

struct LoadoutPicksTests {
    private func picks(_ count: Int) -> LoadoutPicks {
        var picks = LoadoutPicks()
        for index in 0..<count { picks.add(hex: String(format: "%06X", index)) }
        return picks
    }

    @Test func theCapIsTwelve() {
        var full = picks(12)
        let added = full.add(hex: "FFFFFF")
        #expect(!added)
        #expect(full.picks.count == 12)
    }

    @Test func removingKeepsTheOthersInOrder() {
        var three = picks(3)
        let hexes = three.picks.map(\.hex)
        three.remove(id: three.picks[1].id)
        #expect(three.picks.map(\.hex) == [hexes[0], hexes[2]])
    }

    @Test func movingKeepsEveryPick() {
        var three = picks(3)
        let hexes = three.picks.map(\.hex)
        three.move(from: [2], to: 0)
        #expect(three.picks.map(\.hex) == [hexes[2], hexes[0], hexes[1]])
    }
}

struct LoadoutPlanTextTests {
    @Test(arguments: [(0.5, "Looks the same"), (1.99, "Looks the same"), (2.0, "Close"), (4.9, "Close"), (5.0, "Visible difference")])
    func labels(deltaE: Double, label: String) {
        #expect(LoadoutPlanText.label(deltaE: deltaE) == label)
    }
}

struct PlannerImageTests {
    private func grid() -> PixelGrid {
        let red = LinearRGB(r: 1, g: 0, b: 0)
        let blue = LinearRGB(r: 0, g: 0, b: 1)
        return PixelGrid(width: 100, height: 100, pixels: (0..<10000).map { $0 % 100 < 75 ? red : blue })
    }

    @Test func aTapReadsTheColorUnderIt() {
        #expect(PlannerImage(grid: grid()).color(at: CGPoint(x: 0.2, y: 0.5)) == "FF0000")
        #expect(PlannerImage(grid: grid()).color(at: CGPoint(x: 0.9, y: 0.5)) == "0000FF")
    }

    @Test func aTapOffThePictureReadsNothing() {
        #expect(PlannerImage(grid: grid()).color(at: CGPoint(x: 5, y: 5)) == nil)
    }

    @Test func suggestionsFindTheColorsLargestFirst() {
        #expect(PlannerImage(grid: grid()).suggestedColors(count: 2).map(\.hex) == ["FF0000", "0000FF"])
    }

    @Test func eachSuggestionIsMarkedWhereThePictureHasItsColor() {
        let image = PlannerImage(grid: grid())
        for suggested in image.suggestedColors(count: 2) {
            #expect(image.color(at: suggested.point) == suggested.hex)
        }
    }

    @Test func eachSuggestionIsMarkedInsideItsColorNotOnAnEdge() throws {
        // Red fills x 0...0.75, blue 0.75...1, top to bottom.
        let suggested = PlannerImage(grid: grid()).suggestedColors(count: 2)
        let red = try #require(suggested.first { $0.hex == "FF0000" })
        let blue = try #require(suggested.first { $0.hex == "0000FF" })
        #expect((0.2...0.55).contains(red.point.x))
        #expect((0.8...0.95).contains(blue.point.x))
        for point in [red.point, blue.point] {
            #expect((0.2...0.8).contains(point.y))
        }
    }

    @Test func suggestionsAreRepeatable() {
        let image = PlannerImage(grid: grid())
        #expect(image.suggestedColors(count: 3) == image.suggestedColors(count: 3))
    }

    @Test func aSavedPlanRoundTrips() throws {
        var picks = LoadoutPicks()
        picks.add(hex: "FF0000", point: .init(x: 0.5, y: 0.5))
        let saved = try JSONDecoder().decode(LoadoutPicks.self, from: JSONEncoder().encode(picks))
        #expect(saved == picks)
    }
}

struct LoadoutPlannerTests {
    @Test func eachColorGetsItsClosestSpool() throws {
        let shelf = [spool(1, "FF0000"), spool(2, "0000FF"), spool(3, "FFFF00")]
        let results = try match(request(["0000EE", "EE0000"], shelf))
        #expect(results.map(\.hex) == ["0000EE", "EE0000"])
        #expect(results.map { $0.closest?.spool.id } == [2, 1])
        #expect(results[0].closest!.deltaE > 0)
    }

    @Test func twoColorsMayShareASpool() throws {
        let results = try match(request(["FF0000", "EE0000"], [spool(1, "FF0000"), spool(2, "0000FF")]))
        #expect(results.map { $0.closest?.spool.id } == [1, 1])
    }

    @Test func theClosestIsShownHoweverFarItIs() throws {
        let results = try match(request(["FF0000"], [spool(2, "0000FF")]))
        #expect(results[0].closest?.spool.id == 2)
        #expect(results[0].closest!.deltaE > LoadoutPlanner.alternativeDeltaE)
    }

    @Test func alternativesAreCloseEnoughAndClosestFirst() throws {
        let shelf = [spool(1, "FF0000"), spool(2, "F01010"), spool(3, "E02020"), spool(4, "0000FF")]
        let result = try #require(try match(request(["FF0000"], shelf)).first)
        #expect(result.closest?.spool.id == 1)
        #expect(result.alternatives.map(\.spool.id) == [2, 3])
        #expect(result.alternatives.allSatisfy { $0.deltaE <= LoadoutPlanner.alternativeDeltaE })
    }

    @Test func noAlternativeWhenNothingElseIsClose() throws {
        let result = try #require(try match(request(["FF0000"], [spool(1, "FF0000"), spool(4, "0000FF")])).first)
        #expect(result.alternatives.isEmpty)
    }

    @Test func atMostThreeAlternatives() throws {
        let shelf = (1...6).map { spool($0, String(format: "FF%02X%02X", $0 * 4, $0 * 4)) }
        let result = try #require(try match(request(["FF0000"], shelf)).first)
        #expect(result.alternatives.count == LoadoutPlanner.alternativesPerColor)
    }

    @Test func anotherSpoolOfTheSameFilamentIsNoAlternative() throws {
        let shelf = [spool(1, "FF0000", grams: 200, filament: 7), spool(2, "FF0000", grams: 800, filament: 7)]
        let result = try #require(try match(request(["FF0000"], shelf)).first)
        // The fuller spool stands for the filament.
        #expect(result.closest?.spool.id == 2)
        #expect(result.alternatives.isEmpty)
    }

    @Test func otherMaterialsAreLeftOut() throws {
        let results = try match(request(["FF0000"], [spool(1, "FF0000", material: "PETG"), spool(2, "AA0000")]))
        #expect(results[0].closest?.spool.id == 2)
    }

    @Test func variantsCountAsTheBaseMaterial() throws {
        let results = try match(request(["FF0000"], [spool(1, "FF0000", material: "PLA Silk")]))
        #expect(results[0].closest?.spool.id == 1)
    }

    @Test func spoolsBelowTheMinimumAreLeftOut() throws {
        let results = try match(request(["FF0000"], [spool(1, "FF0000", grams: 20), spool(2, "AA0000")]))
        #expect(results[0].closest?.spool.id == 2)
    }

    @Test func multiColorSpoolsAreLeftOutUnlessIncluded() throws {
        let results = try match(request(["FF0000"], [spool(1, "FF0000", multi: true), spool(2, "AA0000")]))
        #expect(results[0].closest?.spool.id == 2)
    }

    @Test func anyColorOfAMultiColorSpoolCanMatch() throws {
        let spools = [spool(1, "00FF00", colors: ["00FF00", "FF0000"]), spool(2, "AA0000")]
        let results = try match(request(["FF0000"], spools, multiColor: true))
        #expect(results[0].closest?.spool.id == 1)
        #expect(results[0].closest?.spool.hex == "FF0000")
        #expect(results[0].closest!.deltaE < 0.001)
    }

    @Test func noTargets() {
        #expect(throws: LoadoutPlanner.Failure.noTargets) { try match(request([], [spool(1, "FF0000")])) }
    }

    @Test func noSpoolOfTheMaterial() {
        #expect(throws: LoadoutPlanner.Failure.noSpools(material: "ASA", minimumRemaining: 50)) {
            try match(request(["FF0000"], [spool(1, "FF0000")], material: "ASA"))
        }
    }
}
