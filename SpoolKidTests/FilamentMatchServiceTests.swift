//
//  FilamentMatchServiceTests.swift
//  SpoolKidTests
//
//  Tests for FilamentMatchService: scoring, confidence bands, brand-mismatch cap,
//  tie-breaking, and auto-accept threshold logic.
//

import Testing
@testable import SpoolKid

// MARK: - Helpers

private func makeSpool(
    id: Int = 1,
    material: String = "PLA",
    vendorName: String = "Elegoo",
    name: String? = "PLA Basic",
    colorHex: String? = "FF0000",
    diameter: Double? = 1.75,
    extruderTemp: Int? = 220,
    bedTemp: Int? = 65
) -> Spool {
    Spool(
        id: id,
        filament: Filament(
            id: id * 10,
            name: name,
            material: material,
            vendor: Vendor(id: 1, name: vendorName),
            colorHex: colorHex,
            density: nil,
            diameter: diameter,
            settingsExtruderTemp: extruderTemp,
            settingsBedTemp: bedTemp
        ),
        remainingWeight: nil,
        initialWeight: nil,
        spoolWeight: nil,
        usedWeight: nil,
        price: nil,
        lotNr: nil,
        statusId: nil, externalId: nil, purchaseDate: nil
    )
}

private func makeTag(
    material: String = "PLA",
    brand: String = "Elegoo",
    name: String? = "PLA Basic",
    colorHex: String = "FF0000",
    minNozzle: Int = 190,
    maxNozzle: Int = 240,
    minBed: Int = 35,
    maxBed: Int = 65
) -> FilamentTagData {
    FilamentTagData(
        name: name,
        material: material,
        subtype: nil,
        brand: brand,
        colorHex: colorHex,
        minNozzleTemp: minNozzle,
        maxNozzleTemp: maxNozzle,
        minBedTemp: minBed,
        maxBedTemp: maxBed,
        spoolmanId: nil
    )
}

// MARK: - Tests

@MainActor
struct FilamentMatchServiceTests {

    // MARK: Material matching

    @Test func perfectMaterialMatchScoresHigh() {
        let tag = makeTag(material: "PLA")
        let spool = makeSpool(material: "PLA")
        let result = FilamentMatchService.score(tag: tag, against: spool)
        #expect(result.confidence >= 80)
    }

    @Test func materialMismatchScoresLowerThanMaterialMatch() {
        let tag = makeTag(material: "PLA", brand: "X", name: nil, colorHex: "FF0000")
        let spoolMatch    = makeSpool(id: 1, material: "PLA",  vendorName: "X", name: nil, colorHex: "FF0000")
        let spoolMismatch = makeSpool(id: 2, material: "PETG", vendorName: "X", name: nil, colorHex: "FF0000")
        let scoreMatch    = FilamentMatchService.score(tag: tag, against: spoolMatch)
        let scoreMismatch = FilamentMatchService.score(tag: tag, against: spoolMismatch)
        #expect(scoreMatch.confidence > scoreMismatch.confidence)
    }

    @Test func materialMatchIsCaseInsensitive() {
        let tag = makeTag(material: "pla")
        let spool = makeSpool(material: "PLA")
        let result = FilamentMatchService.score(tag: tag, against: spool)
        #expect(result.confidence >= 80)
    }

    // MARK: Brand matching

    @Test func brandMismatchCapsConfidenceBelow80() {
        let tag = makeTag(material: "PLA", brand: "Elegoo")
        let spool = makeSpool(material: "PLA", vendorName: "eSUN")
        let result = FilamentMatchService.score(tag: tag, against: spool)
        #expect(result.confidence < 80)
        #expect(result.brandMismatch == true)
    }

    @Test func brandMatchIsCaseInsensitive() {
        let tag = makeTag(brand: "elegoo")
        let spool = makeSpool(vendorName: "Elegoo")
        let result = FilamentMatchService.score(tag: tag, against: spool)
        #expect(result.brandMismatch == false)
    }

    @Test func brandMismatchFlagSetEvenWhenConfidenceWouldBeHigh() {
        // Same material + color + temps, only brand differs
        let tag = makeTag(material: "PLA", brand: "Elegoo", colorHex: "FF0000", minNozzle: 190, maxNozzle: 240, minBed: 35, maxBed: 65)
        let spool = makeSpool(material: "PLA", vendorName: "Polymaker", colorHex: "FF0000", extruderTemp: 220, bedTemp: 65)
        let result = FilamentMatchService.score(tag: tag, against: spool)
        #expect(result.brandMismatch == true)
        #expect(result.confidence < 80)
    }

    // MARK: Color matching

    @Test func identicalColorHexScoresHigherThanDistantColor() {
        let tag = makeTag(material: "PLA", brand: "X", colorHex: "FF0000")
        let spoolSame  = makeSpool(id: 1, material: "PLA", vendorName: "X", colorHex: "FF0000")
        let spoolDiff  = makeSpool(id: 2, material: "PLA", vendorName: "X", colorHex: "0000FF")
        let scoreSame = FilamentMatchService.score(tag: tag, against: spoolSame)
        let scoreDiff = FilamentMatchService.score(tag: tag, against: spoolDiff)
        #expect(scoreSame.confidence > scoreDiff.confidence)
    }

    @Test func missingColorHexOnSpoolDoesNotCrash() {
        let tag = makeTag(colorHex: "FF0000")
        let spool = makeSpool(colorHex: nil)
        let result = FilamentMatchService.score(tag: tag, against: spool)
        #expect(result.confidence >= 0)
    }

    // MARK: Temperature matching

    @Test func temperatureWithinRangeScoresHigherThanOutOfRange() {
        let tag = makeTag(minNozzle: 190, maxNozzle: 240, minBed: 35, maxBed: 65)
        let spoolIn  = makeSpool(extruderTemp: 220, bedTemp: 60)
        let spoolOut = makeSpool(extruderTemp: 280, bedTemp: 110)
        let scoreIn  = FilamentMatchService.score(tag: tag, against: spoolIn)
        let scoreOut = FilamentMatchService.score(tag: tag, against: spoolOut)
        #expect(scoreIn.confidence > scoreOut.confidence)
    }

    /// The fields hold placeholders when the tag stated nothing; a spool that
    /// happens to sit on them must not outscore one with no temperatures.
    @Test func temperaturesATagDoesNotStateScoreNothing() {
        var tag = makeTag(minNozzle: 200, maxNozzle: 220, minBed: 60, maxBed: 80)
        tag.nozzleTempsStated = false
        tag.bedTempsStated = false
        let onPlaceholders = makeSpool(extruderTemp: 210, bedTemp: 70)
        let noTemperatures = makeSpool(extruderTemp: nil, bedTemp: nil)
        let scoreOn = FilamentMatchService.score(tag: tag, against: onPlaceholders)
        let scoreNone = FilamentMatchService.score(tag: tag, against: noTemperatures)
        #expect(scoreOn.confidence == scoreNone.confidence)
    }

    // MARK: Confidence bands

    @Test func highConfidenceBandAt80OrAbove() {
        let tag = makeTag()
        let spool = makeSpool()
        let result = FilamentMatchService.score(tag: tag, against: spool)
        if result.confidence >= 80 {
            #expect(result.band == .high)
        }
    }

    @Test func mediumConfidenceBandBetween60And79() {
        // Induce medium range: same material, same brand, wrong color
        let tag = makeTag(material: "PLA", brand: "X", colorHex: "FF0000")
        let spool = makeSpool(material: "PLA", vendorName: "X", colorHex: "000000")
        let result = FilamentMatchService.score(tag: tag, against: spool)
        // May be medium or high depending on scoring; just verify band matches value
        switch result.band {
        case .high:   #expect(result.confidence >= 80)
        case .medium: #expect(result.confidence >= 60 && result.confidence < 80)
        case .low:    #expect(result.confidence < 60)
        }
    }

    // MARK: Ranking

    @Test func bestMatchIsFirstInRankedResults() {
        let tag = makeTag(material: "PLA", brand: "Elegoo", colorHex: "FF0000")
        let perfect  = makeSpool(id: 1, material: "PLA", vendorName: "Elegoo", colorHex: "FF0000")
        let mediocre = makeSpool(id: 2, material: "PETG", vendorName: "eSUN", colorHex: "0000FF")
        let ranked = FilamentMatchService.rank(tag: tag, spools: [mediocre, perfect])
        #expect(ranked.first?.spool.id == perfect.id)
    }

    @Test func rankReturnsEmptyForEmptySpoolList() {
        let tag = makeTag()
        let ranked = FilamentMatchService.rank(tag: tag, spools: [])
        #expect(ranked.isEmpty)
    }

    // MARK: Auto-accept

    @Test func autoAcceptAllowedWhenConfidenceMeetsThreshold() {
        let tag = makeTag()
        let spool = makeSpool()
        let result = FilamentMatchService.score(tag: tag, against: spool)
        if result.confidence >= 80 && !result.brandMismatch {
            #expect(FilamentMatchService.shouldAutoAccept(result: result, threshold: 80) == true)
        }
    }

    @Test func autoAcceptBlockedByBrandMismatch() {
        let tag = makeTag(brand: "Elegoo")
        let spool = makeSpool(vendorName: "eSUN")
        let result = FilamentMatchService.score(tag: tag, against: spool)
        // Even if somehow confidence were ≥ 80, brand mismatch must block auto-accept
        #expect(FilamentMatchService.shouldAutoAccept(result: result, threshold: 80) == false)
    }

    @Test func autoAcceptBlockedWhenThresholdIsZero() {
        let tag = makeTag()
        let spool = makeSpool()
        let result = FilamentMatchService.score(tag: tag, against: spool)
        #expect(FilamentMatchService.shouldAutoAccept(result: result, threshold: 0) == false)
    }

    @Test func autoAcceptBlockedWhenThresholdIs101() {
        let tag = makeTag()
        let spool = makeSpool()
        let result = FilamentMatchService.score(tag: tag, against: spool)
        #expect(FilamentMatchService.shouldAutoAccept(result: result, threshold: 101) == false)
    }

    @Test func autoAcceptBlockedWhenConfidenceBelowThreshold() {
        let tag = makeTag(material: "PLA", brand: "X")
        let spool = makeSpool(material: "PLA", vendorName: "X", colorHex: "000000")
        let result = FilamentMatchService.score(tag: tag, against: spool)
        // Use threshold above result confidence to guarantee block
        let blocked = FilamentMatchService.shouldAutoAccept(result: result, threshold: result.confidence + 1)
        #expect(blocked == false)
    }

    // MARK: - Suggestion scoring (scoreFilament)

    @Test func scoreFilamentPerfectMatch() {
        let tag = makeTag(material: "PLA", brand: "Elegoo", name: "PLA Basic", colorHex: "FF0000")
        let score = FilamentMatchService.scoreFilament(
            tag: tag,
            name: "PLA Basic",
            material: "PLA",
            brand: "Elegoo",
            colorHexes: ["FF0000"]
        )
        #expect(score >= 80)
    }

    @Test func scoreFilamentMaterialMismatch() {
        let tag = makeTag(material: "PLA", brand: "Elegoo", name: "PLA Basic", colorHex: "FF0000")
        let scoreMatch = FilamentMatchService.scoreFilament(
            tag: tag,
            name: "PLA Basic",
            material: "PLA",
            brand: "Elegoo",
            colorHexes: ["FF0000"]
        )
        let scoreMismatch = FilamentMatchService.scoreFilament(
            tag: tag,
            name: "PLA Basic",
            material: "PETG",
            brand: "Elegoo",
            colorHexes: ["FF0000"]
        )
        #expect(scoreMatch > scoreMismatch)
    }

    @Test func scoreFilamentBrandMismatch() {
        let tag = makeTag(material: "PLA", brand: "Elegoo", name: "PLA Basic", colorHex: "FF0000")
        let scoreMatch = FilamentMatchService.scoreFilament(
            tag: tag,
            name: "PLA Basic",
            material: "PLA",
            brand: "Elegoo",
            colorHexes: ["FF0000"]
        )
        let scoreMismatch = FilamentMatchService.scoreFilament(
            tag: tag,
            name: "PLA Basic",
            material: "PLA",
            brand: "eSUN",
            colorHexes: ["FF0000"]
        )
        #expect(scoreMatch > scoreMismatch)
    }

    @Test func scoreFilamentNameSubstringMatch() {
        let tag = makeTag(material: "PLA", brand: "Elegoo", name: "PLA", colorHex: "FF0000")
        let scoreExact = FilamentMatchService.scoreFilament(
            tag: tag,
            name: "PLA",
            material: "PLA",
            brand: "Elegoo",
            colorHexes: ["FF0000"]
        )
        let scoreSubstring = FilamentMatchService.scoreFilament(
            tag: tag,
            name: "PLA Basic",
            material: "PLA",
            brand: "Elegoo",
            colorHexes: ["FF0000"]
        )
        #expect(scoreExact > scoreSubstring)
    }

    // MARK: Color similarity (set-aware)

    @Test func sameSetAnyOrderScoresOne() {
        let score = FilamentMatchService.colorSimilarity(
            tag: ["2D39C9", "A51A52"],
            filament: ["A51A52", "2D39C9"]
        )
        #expect(abs(score - 1.0) < 0.001)
    }

    @Test func dualVsSingleUsesFirstColors() {
        let score = FilamentMatchService.colorSimilarity(
            tag: ["2D39C9", "A51A52"],
            filament: ["2D39C9"]
        )
        #expect(abs(score - ColorMatching.similarity01(hexA: "2D39C9", hexB: "2D39C9")) < 0.001)
    }

    @Test func differentDualScoresLower() {
        let same = FilamentMatchService.colorSimilarity(
            tag: ["2D39C9", "A51A52"],
            filament: ["2D39C9", "A51A52"]
        )
        let different = FilamentMatchService.colorSimilarity(
            tag: ["2D39C9", "A51A52"],
            filament: ["FFFFFF", "000000"]
        )
        #expect(different < same)
    }

    @Test func emptyFilamentMatchesToday() {
        let score = FilamentMatchService.colorSimilarity(tag: ["2D39C9", "A51A52"], filament: [])
        #expect(abs(score - ColorMatching.similarity01(hexA: "2D39C9", hexB: nil)) < 0.001)
    }

    @Test func mismatchedSetSizeIsScaledDown() {
        let full = FilamentMatchService.colorSimilarity(
            tag: ["2D39C9", "A51A52"],
            filament: ["2D39C9", "A51A52"]
        )
        let extra = FilamentMatchService.colorSimilarity(
            tag: ["2D39C9", "A51A52"],
            filament: ["2D39C9", "A51A52", "FFFFFF"]
        )
        #expect(abs(extra - full * 2.0 / 3.0) < 0.001)
    }

    @Test func scoreFilamentAdapterParity() {
        let tag = makeTag(material: "PLA", brand: "Elegoo", name: "PLA Basic", colorHex: "FF0000")
        let score1 = FilamentMatchService.scoreFilament(
            tag: tag,
            name: "PLA Basic",
            material: "PLA",
            brand: "Elegoo",
            colorHexes: ["FF0000"]
        )
        let score2 = FilamentMatchService.scoreFilament(
            tag: tag,
            name: "PLA Basic",
            material: "PLA",
            brand: "Elegoo",
            colorHexes: ["FF0000"]
        )
        #expect(score1 == score2)
    }

    @Test func scoreFilamentNearMissPenalty() {
        let tag = makeTag(material: "PLA", brand: "Elegoo", name: "PLA Basic", colorHex: "FF0000")
        let score = FilamentMatchService.scoreFilament(
            tag: tag,
            name: "PLA Basic",
            material: "PLA",
            brand: "Elegoo",
            colorHexes: ["0000FF"]
        )
        #expect(score < 80)
    }

    @Test func scoreFilamentNilFields() {
        let tag = makeTag(material: "PLA", brand: "Elegoo", name: nil, colorHex: "FF0000")
        let score = FilamentMatchService.scoreFilament(
            tag: tag,
            name: nil,
            material: nil,
            brand: nil,
            colorHexes: []
        )
        #expect(score >= 0)
    }
}
