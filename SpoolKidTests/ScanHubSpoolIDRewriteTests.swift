//
//  ScanHubSpoolIDRewriteTests.swift
//  SpoolKidTests
//
//  Writing a spool ID to a scanned tag keeps every field the tag carries.
//  Rebuilding the tag field by field once dropped the extra colors.
//

import Testing
import Foundation
@testable import SpoolKid

@MainActor
struct ScanHubSpoolIDRewriteTests {

    @Test func rewriteKeepsTheExtraColorsAndSetsTheSpoolID() {
        let existing = FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "2D39C9", additionalColorHexes: ["A51A52"],
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60, spoolmanId: 7
        )
        let rewritten = ScanResultHubView.withSpoolID(42, from: existing)

        #expect(rewritten.spoolmanId == 42)
        #expect(rewritten.colors.hexes == ["2D39C9", "A51A52"])
        #expect(rewritten.colors.pattern == existing.colors.pattern)
    }

    @Test func rewriteKeepsDiameterConsumedWeightAndStatedFlags() {
        var existing = FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "2D39C9",
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60, spoolmanId: 7,
            diameter: 2.85, consumedWeight: 123
        )
        existing.nozzleTempsStated = false
        existing.bedTempsStated = false
        let rewritten = ScanResultHubView.withSpoolID(42, from: existing)

        #expect(rewritten.diameter == 2.85)
        #expect(rewritten.consumedWeight == 123)
        #expect(rewritten.nozzleTempsStated == false)
        #expect(rewritten.bedTempsStated == false)
    }
}
