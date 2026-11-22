//
//  StaleSpoolIDTests.swift
//  SpoolKidTests
//
//  A pre-filled spool ID (Recent Tags, a re-written scanned tag) names the
//  spool the data was written FOR. Once that spool is deleted its ID can be
//  handed to a different spool, and writing the stale ID linked the new tag
//  to the stranger (device report, 2026-10-03).
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct StaleSpoolIDTests {
    private static let galaxyBlack = Filament(
        id: 5, name: "Galaxy Black", material: "ASA", vendor: Vendor(id: 1, name: "Prusament"),
        colorHex: "3D3E3D", density: 1.07
    )
    private static let acPLA = Filament(
        id: 9, name: "AHPLPBK-108", material: "PLA+", vendor: Vendor(id: 2, name: "AC"),
        colorHex: "1A1F1A", density: 1.24
    )

    private static func spool(_ id: Int, _ filament: Filament) -> Spool {
        Spool(
            id: id, filament: filament, remainingWeight: 1000, extra: nil,
            rfidUID: nil, statusId: nil, externalId: nil, purchaseDate: nil
        )
    }

    private static func galaxyBlackTag(spoolmanId: Int?) -> FilamentTagData {
        FilamentTagData(
            name: "Galaxy Black", material: "ASA", subtype: "Basic", brand: "Prusament", colorHex: "3D3E3D",
            minNozzleTemp: 240, maxNozzleTemp: 260, minBedTemp: 100, maxBedTemp: 110, spoolmanId: spoolmanId
        )
    }

    @Test func anIDNowHeldByADifferentFilamentIsStale() {
        // Galaxy Black was #37, was deleted, and FilaMan gave #37 to the next spool.
        let stale = WriteTagFormAssembler.staleSpoolID(
            in: Self.galaxyBlackTag(spoolmanId: 37),
            spools: [Self.spool(36, Self.galaxyBlack), Self.spool(37, Self.acPLA)]
        )
        #expect(stale == .changed(id: 37, nowHolds: "AC AHPLPBK-108"))
    }

    @Test func anIDNoSpoolHoldsIsStale() {
        let stale = WriteTagFormAssembler.staleSpoolID(
            in: Self.galaxyBlackTag(spoolmanId: 37),
            spools: [Self.spool(36, Self.acPLA)]
        )
        #expect(stale == .notFound(id: 37))
    }

    @Test func theSpoolItWasWrittenForIsNotStale() {
        // Renaming alone does not count — the hub's "tag differs" rule ignores names.
        var renamed = Self.galaxyBlackTag(spoolmanId: 37)
        renamed.name = "Prusament ASA Galaxy Black"
        let spools = [Self.spool(37, Self.galaxyBlack)]
        #expect(WriteTagFormAssembler.staleSpoolID(in: Self.galaxyBlackTag(spoolmanId: 37), spools: spools) == nil)
        #expect(WriteTagFormAssembler.staleSpoolID(in: renamed, spools: spools) == nil)
    }

    @Test func dataWithoutASpoolIDIsNeverStale() {
        let stale = WriteTagFormAssembler.staleSpoolID(
            in: Self.galaxyBlackTag(spoolmanId: nil),
            spools: [Self.spool(37, Self.acPLA)]
        )
        #expect(stale == nil)
    }

    @Test func anUnloadedSpoolListJudgesNothing() {
        // Before the first fetch lands, "no spool has this ID" is not known.
        #expect(WriteTagFormAssembler.staleSpoolID(in: Self.galaxyBlackTag(spoolmanId: 37), spools: []) == nil)
    }

    // MARK: - An ACE SKU recorded as the name

    @Test func anACESKUNameIsReadAsTheSpoolIDItNames() {
        // What Write Tag recorded for an ACE write: the SKU in `name`, no ID.
        var ace = Self.galaxyBlackTag(spoolmanId: nil)
        ace.name = "SM37"
        let read = ace.readingSpoolLinkSKU()
        #expect(read.spoolmanId == 37)
        #expect(read.name == nil)
        #expect(WriteTagFormAssembler.staleSpoolID(in: read, spools: [Self.spool(37, Self.acPLA)])
            == .changed(id: 37, nowHolds: "AC AHPLPBK-108"))
    }

    @Test func anOrdinaryNameOrAnExistingIDIsLeftAlone() {
        let named = Self.galaxyBlackTag(spoolmanId: nil).readingSpoolLinkSKU()
        #expect(named.name == "Galaxy Black")
        #expect(named.spoolmanId == nil)

        var both = Self.galaxyBlackTag(spoolmanId: 5)
        both.name = "SM37"
        let kept = both.readingSpoolLinkSKU()
        #expect(kept.spoolmanId == 5)
        #expect(kept.name == "SM37")
    }
}
