//
//  RecentTagFormatTests.swift
//  SpoolKidTests
//
//  A Recent Tag remembers the format it was written in, keeps one entry per
//  format, and reopens Write Tag in that format (owner request, 2026-10-03).
//

import Foundation
import Testing
import UIKit
@testable import SpoolKid

@MainActor
struct RecentTagFormatTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 781_200_000)

    private static func galaxyBlack(spoolmanId: Int? = 37) -> FilamentTagData {
        FilamentTagData(
            name: "Galaxy Black", material: "ASA", subtype: "Basic", brand: "Prusament", colorHex: "3D3E3D",
            minNozzleTemp: 240, maxNozzleTemp: 260, minBedTemp: 100, maxBedTemp: 110, spoolmanId: spoolmanId
        )
    }

    private static func entry(_ data: FilamentTagData, _ format: TagFormat?) -> RecentTag {
        RecentTag(data: data, format: format, lastUsed: now.addingTimeInterval(-60))
    }

    private static func add(
        _ data: FilamentTagData, _ format: TagFormat?, replacing superseded: FilamentTagData? = nil,
        to tags: [RecentTag], limit: Int = 20
    ) -> [RecentTag] {
        RecentTagManager.adding(data, format: format, replacing: superseded, to: tags, limit: limit, at: now)
    }

    // MARK: - One entry per format

    @Test func theSameFilamentInAnotherFormatIsASecondEntry() {
        let tags = Self.add(Self.galaxyBlack(), .anycubicACE, to: [Self.entry(Self.galaxyBlack(), .openSpool)])
        #expect(tags.map(\.format) == [.anycubicACE, .openSpool])
    }

    @Test func theSameFilamentInTheSameFormatMovesToTheTop() {
        let almond = FilamentTagData(
            name: "Almond", material: "PLA+", subtype: nil, brand: "3D-Fuel", colorHex: "CFBCAE",
            minNozzleTemp: 200, maxNozzleTemp: 230, minBedTemp: 50, maxBedTemp: 60, spoolmanId: 1
        )
        let before = [Self.entry(almond, .openSpool), Self.entry(Self.galaxyBlack(), .openSpool)]
        let tags = Self.add(Self.galaxyBlack(), .openSpool, to: before)
        #expect(tags.count == 2)
        #expect(tags.first?.data.name == "Galaxy Black")
        #expect(tags.first?.lastUsed == Self.now)
    }

    @Test func anEntryFromBeforeFormatsWereRecordedIsReplacedByAnyFormat() {
        // Its format is unknown, so the same content written now supersedes it.
        let tags = Self.add(Self.galaxyBlack(), .openPrintTag, to: [Self.entry(Self.galaxyBlack(), nil)])
        #expect(tags.map(\.format) == [.openPrintTag])
    }

    @Test func aSupersededStaleEntryGoesInEveryFormat() {
        let stale = Self.galaxyBlack(spoolmanId: 37)
        let before = [Self.entry(stale, .anycubicACE), Self.entry(stale, .openSpool)]
        let tags = Self.add(Self.galaxyBlack(spoolmanId: nil), .openSpool, replacing: stale, to: before)
        #expect(tags.count == 1)
        #expect(tags.first?.data.spoolmanId == nil)
    }

    @Test func theListIsTrimmedToTheLimit() {
        let before = (1...3).map { id in Self.entry(Self.galaxyBlack(spoolmanId: id), .openSpool) }
        let tags = Self.add(Self.galaxyBlack(spoolmanId: 99), .openSpool, to: before, limit: 3)
        #expect(tags.map(\.data.spoolmanId) == [99, 1, 2])
    }

    /// Decision 6: a Recent Tag is usually reused for a new spool, so it starts
    /// full. The consumed weight belongs to the spool it was written for.
    @Test func recentTagsForgetTheConsumedWeight() {
        var data = Self.galaxyBlack()
        data.nominalNetWeight = 1000
        data.consumedWeight = 388

        let tags = Self.add(data, .openPrintTag, to: [])

        #expect(tags.first?.data.consumedWeight == nil)
        #expect(tags.first?.data.nominalNetWeight == 1000)
        #expect(data.consumedWeight == 388)
    }

    // MARK: - Stored entries

    @Test func anEntrySavedBeforeFormatsWereRecordedDecodesWithoutOne() throws {
        let json = #"[{"id":"11111111-1111-1111-1111-111111111111","lastUsed":781200000,"data":{"name":"Galaxy Black","material":"ASA","brand":"Prusament","color_hex":"3D3E3D","min_nozzle_temp":240,"max_nozzle_temp":260,"min_bed_temp":100,"max_bed_temp":110}}]"#
        let tags = try JSONDecoder().decode([RecentTag].self, from: Data(json.utf8))
        #expect(tags.count == 1)
        #expect(tags.first?.format == nil)
    }

    @Test func oldRecentTagWithoutAdditionalColorsDecodes() throws {
        let json = #"{"name":"Galaxy Black","material":"ASA","brand":"Prusament","color_hex":"3D3E3D","min_nozzle_temp":240,"max_nozzle_temp":260,"min_bed_temp":100,"max_bed_temp":110}"#
        let data = try JSONDecoder().decode(FilamentTagData.self, from: Data(json.utf8))
        #expect(data.additionalColorHexes == nil)
    }

    @Test func theFormatSurvivesARoundTrip() throws {
        let encoded = try JSONEncoder().encode([Self.entry(Self.galaxyBlack(), .tigerTag)])
        let decoded = try JSONDecoder().decode([RecentTag].self, from: encoded)
        #expect(decoded.first?.format == .tigerTag)
    }

    // MARK: - Which format Write Tag opens in

    @Test func aRecordedFormatWinsOverTheDefault() {
        let format = WriteTagFormAssembler.initialOverride(defaultRawValue: "openspool", recordedFormat: .anycubicACE)
        #expect(format == .anycubicACE)
    }

    @Test func noRecordedFormatOpensInTheDefault() {
        let format = WriteTagFormAssembler.initialOverride(defaultRawValue: "openprinttag", recordedFormat: nil)
        #expect(format == .openPrintTag)
    }

    /// ELEGOO became writable on 2026-10-05; until then a recorded ELEGOO tag
    /// opened in the default instead.
    @Test func aRecordedELEGOOTagOpensInELEGOO() {
        let format = WriteTagFormAssembler.initialOverride(defaultRawValue: "opentag3d", recordedFormat: .elegoo)
        #expect(format == .elegoo)
    }

    // MARK: - No logos

    /// A format is shown by name: its logo is its owner's mark, and SpoolKid
    /// may be sold (owner, 2026-10-05). These are the logos it used to ship.
    @Test(arguments: ["OpenSpoolLogo", "OpenPrintTagLogo", "OpenTag3DLogo", "AnycubicLogo", "TigerTagLogo", "ElegooLogo"])
    func noFormatLogoShips(asset: String) {
        #expect(UIImage(named: asset) == nil)
    }
}
