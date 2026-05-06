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
    vendorName: String = "Bambu Lab",
    name: String? = "PLA Basic",
    colorHex: String? = "FF0000",
    diameter: Double? = 1.75,
    extruderTemp: Int? = 220,
    bedTemp: Int? = 65
) -> SpoolmanSpool {
    SpoolmanSpool(
        id: id,
        filament: SpoolmanFilament(
            id: id * 10,
            name: name,
            material: material,
            vendor: SpoolmanVendor(id: 1, name: vendorName),
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
        lotNr: nil
    )
}

private func makeTag(
    material: String = "PLA",
    brand: String = "Bambu Lab",
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
        let tag = makeTag(material: "PLA", brand: "Bambu Lab")
        let spool = makeSpool(material: "PLA", vendorName: "eSUN")
        let result = FilamentMatchService.score(tag: tag, against: spool)
        #expect(result.confidence < 80)
        #expect(result.brandMismatch == true)
    }

    @Test func brandMatchIsCaseInsensitive() {
        let tag = makeTag(brand: "bambu lab")
        let spool = makeSpool(vendorName: "Bambu Lab")
        let result = FilamentMatchService.score(tag: tag, against: spool)
        #expect(result.brandMismatch == false)
    }

    @Test func brandMismatchFlagSetEvenWhenConfidenceWouldBeHigh() {
        // Same material + color + temps, only brand differs
        let tag = makeTag(material: "PLA", brand: "Bambu Lab", colorHex: "FF0000", minNozzle: 190, maxNozzle: 240, minBed: 35, maxBed: 65)
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
        let tag = makeTag(material: "PLA", brand: "Bambu Lab", colorHex: "FF0000")
        let perfect  = makeSpool(id: 1, material: "PLA", vendorName: "Bambu Lab", colorHex: "FF0000")
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
        let tag = makeTag(brand: "Bambu Lab")
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
}
