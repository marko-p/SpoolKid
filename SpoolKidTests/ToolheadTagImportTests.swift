//
//  ToolheadTagImportTests.swift
//  SpoolKidTests
//
//  Purpose: A U1 toolhead's tag read becomes tag data for the Library. The
//  fixture is the owner's T1 read on 2026-11-10 (AzureFilm PETG Transparent).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
@testable import SpoolKid

struct ToolheadTagImportTests {
    static func info(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var info: [String: Any] = [
            "CARD_UID": [4, 222, 21, 86, 201, 42, 129], "CARD_TYPE": "NTAG",
            "VENDOR": "AzureFilm", "MAIN_TYPE": "PETG", "SUB_TYPE": "Transparent",
            "ALPHA": 6, "COLOR_NUMS": 1, "RGB_1": 2454168,
            "HOTEND_MIN_TEMP": 230, "HOTEND_MAX_TEMP": 240, "BED_TEMP": 70,
            "WEIGHT": 0, "DIAMETER": 0, "OFFICIAL": true
        ]
        info.merge(overrides) { _, new in new }
        return info
    }

    static func toolhead(_ overrides: [String: Any] = [:], index: Int = 0) -> ToolheadState {
        let info = info(overrides)
        return ToolheadState(
            index: index, material: "PETG", vendor: "AzureFilm", colorHexes: ["257298"], alpha: 6,
            isLoaded: true, isOfficial: true, tagUID: ToolheadState.uid(from: info["CARD_UID"]),
            tagType: "NTAG", tag: ToolheadTagData.parse(info)
        )
    }

    @Test func thePrintersReadBecomesTagData() throws {
        let data = try #require(ToolheadTagImport.tagData(from: Self.toolhead()))
        #expect(data.brand == "AzureFilm")
        #expect(data.material == "PETG")
        #expect(data.subtype == "Transparent")
        #expect(data.colorHex == "257298")
        #expect(data.colorAlpha == 6)
        #expect(data.minNozzleTemp == 230)
        #expect(data.maxNozzleTemp == 240)
        #expect(data.minBedTemp == 70)
        #expect(data.maxBedTemp == 70)
        #expect(data.nozzleTempsStated)
        #expect(data.bedTempsStated)
        #expect(data.diameter == nil)
        #expect(data.nominalNetWeight == nil)
    }

    @Test func zeroWeightAndDiameterAreUnknown() throws {
        let tag = try #require(ToolheadTagData.parse(Self.info()))
        #expect(tag.weight == nil)
        #expect(tag.diameter == nil)
        #expect(tag.hotendMinTemp == 230)
        #expect(tag.hotendMaxTemp == 240)
        #expect(tag.bedTemp == 70)
    }

    @Test func aReportedWeightIsKept() throws {
        let data = try #require(ToolheadTagImport.tagData(from: Self.toolhead(["WEIGHT": 1000, "DIAMETER": 175])))
        #expect(data.nominalNetWeight == 1000)
        #expect(data.diameter == 1.75)
    }

    @Test func unreportedTemperaturesAreNotStated() throws {
        let data = try #require(ToolheadTagImport.tagData(from: Self.toolhead(
            ["HOTEND_MIN_TEMP": 0, "HOTEND_MAX_TEMP": 0, "BED_TEMP": 0]
        )))
        #expect(!data.nozzleTempsStated)
        #expect(!data.bedTempsStated)
    }

    @Test func aMissingVendorIsGeneric() throws {
        let data = try #require(ToolheadTagImport.tagData(from: Self.toolhead(["VENDOR": "NONE"])))
        #expect(data.brand == "Generic")
    }

    @Test func theUIDIsNormalised() {
        let uid = Self.toolhead().tagUID
        #expect(uid == "04DE1556C92A81")
        #expect(SpoolMappingService.normalizeUID("04:de:15:56:c9:2a:81") == uid)
    }

    @Test func noTagNoTagData() {
        var toolhead = Self.toolhead()
        toolhead.tag = nil
        #expect(ToolheadTagImport.tagData(from: toolhead) == nil)
    }

    @Test func aSecondColourIsKept() throws {
        let data = try #require(ToolheadTagImport.tagData(from: Self.toolhead(["COLOR_NUMS": 2, "RGB_2": 0xFF0000])))
        #expect(data.colorHex == "257298")
        #expect(data.additionalColorHexes == ["FF0000"])
    }

    @Test func anOpaqueTagHasNoAlpha() throws {
        let data = try #require(ToolheadTagImport.tagData(from: Self.toolhead(["ALPHA": 255])))
        #expect(data.colorAlpha == nil)
    }

    // MARK: When the offer appears

    @Test func anUnclaimedTagOnASharedBackendIsOffered() {
        let offer = ToolheadTagImport.offer(for: Self.toolhead(), owner: .none, route: .spoolman, supportsTagMapping: true, writesLinks: true)
        #expect(offer == .unlinked(uid: "04DE1556C92A81"))
    }

    @Test func aTagOwnedByASpoolIsLinked() {
        let offer = ToolheadTagImport.offer(
            for: Self.toolhead(), owner: .spool(id: 7, label: "AzureFilm PETG"), route: .spoolman, supportsTagMapping: true, writesLinks: true
        )
        #expect(offer == .linked(spoolID: 7))
    }

    @Test func aTagOwnedByAFilamentOrLocationGetsNoOffer() {
        for owner in [TagOwner.filament(id: 3, label: "PETG"), .location(name: "Shelf")] {
            #expect(ToolheadTagImport.offer(for: Self.toolhead(), owner: owner, route: .spoolman, supportsTagMapping: true, writesLinks: true) == .none)
        }
    }

    @Test func noRouteNoOffer() {
        #expect(ToolheadTagImport.offer(for: Self.toolhead(), owner: .none, route: nil, supportsTagMapping: true, writesLinks: true) == .none)
    }

    @Test func noTagMappingNoOffer() {
        #expect(ToolheadTagImport.offer(for: Self.toolhead(), owner: .none, route: .filaman, supportsTagMapping: false, writesLinks: true) == .none)
    }

    @Test func noTagNoOffer() {
        var toolhead = Self.toolhead()
        toolhead.tagUID = nil
        #expect(ToolheadTagImport.offer(for: toolhead, owner: .none, route: .spoolman, supportsTagMapping: true, writesLinks: true) == .none)
    }

    @Test func aTagWithoutFilamentDataIsStillOffered() {
        var toolhead = Self.toolhead()
        toolhead.tag = nil
        #expect(ToolheadTagImport.offer(for: toolhead, owner: .none, route: .spoolman, supportsTagMapping: true, writesLinks: true)
            == .unlinked(uid: "04DE1556C92A81"))
    }

    // MARK: Spools to link

    private static func spool(_ id: Int, vendor: String, material: String, color: String) -> Spool {
        Spool(
            id: id,
            filament: Filament(id: id, name: "\(material) \(color)", material: material, vendor: Vendor(id: id, name: vendor), colorHex: color),
            remainingWeight: 1000, extra: nil, rfidUID: nil, statusId: nil, externalId: nil, purchaseDate: nil
        )
    }

    @Test func matchingSpoolsComeFirst() throws {
        let tag = try #require(ToolheadTagImport.tagData(from: Self.toolhead()))
        let polymaker = Self.spool(1, vendor: "Polymaker", material: "PLA", color: "FFFFFF")
        let azure = Self.spool(2, vendor: "AzureFilm", material: "PETG", color: "257298")
        let matches = ToolheadTagImport.linkMatches(for: tag, in: [polymaker, azure, azure])
        #expect(matches.map(\.spool.id) == [2])
    }

    // MARK: The filament Add Spool reuses

    private static func filament(_ id: Int, vendor: String, material: String, color: String, name: String? = nil) -> Filament {
        Filament(id: id, name: name ?? "\(material) \(color)", material: material, vendor: Vendor(id: id, name: vendor), colorHex: color)
    }

    @Test func theSameFilamentIsReused() throws {
        let tag = try #require(ToolheadTagImport.tagData(from: Self.toolhead()))
        let filaments = [
            Self.filament(1, vendor: "Polymaker", material: "PETG", color: "257298"),
            Self.filament(2, vendor: "azurefilm", material: "petg", color: "FF0000"),
            Self.filament(3, vendor: "AZUREFILM", material: "PETG", color: "257399", name: "PETG Transparent"),
            Self.filament(4, vendor: "AzureFilm", material: "PETG", color: "257298", name: "PETG Transparent")
        ]
        #expect(ToolheadTagImport.filament(for: tag, in: filaments)?.id == 4)
    }

    @Test func aDifferentColourIsANewFilament() throws {
        let tag = try #require(ToolheadTagImport.tagData(from: Self.toolhead()))
        #expect(ToolheadTagImport.filament(for: tag, in: [Self.filament(2, vendor: "AzureFilm", material: "PETG", color: "FF0000")]) == nil)
    }

    // MARK: Review fixes

    @Test func noTagLinksNoOffer() {
        // Spool ID mode, or Neither: Add Spool would save the spool without its tag.
        #expect(ToolheadTagImport.offer(for: Self.toolhead(), owner: .none, route: .spoolman, supportsTagMapping: true, writesLinks: false) == .none)
    }

    @Test func anotherSubtypeIsANewFilament() throws {
        let tag = try #require(ToolheadTagImport.tagData(from: Self.toolhead()))
        let silk = Self.filament(1, vendor: "AzureFilm", material: "PETG", color: "257298", name: "PETG Silk Blue")
        let transparent = Self.filament(2, vendor: "AzureFilm", material: "PETG", color: "257298", name: "PETG Transparent Blue")
        #expect(ToolheadTagImport.filament(for: tag, in: [silk]) == nil)
        #expect(ToolheadTagImport.filament(for: tag, in: [silk, transparent])?.id == 2)
    }

    @Test func addSpoolStartsWhereTheTagAllows() throws {
        let tag = try #require(ToolheadTagImport.tagData(from: Self.toolhead()))
        let same = Self.filament(4, vendor: "AzureFilm", material: "PETG", color: "257298", name: "PETG Transparent")
        #expect(ToolheadTagImport.addStart(tagData: tag, filaments: [same]) == .spool(filamentID: 4))
        #expect(ToolheadTagImport.addStart(tagData: tag, filaments: []) == .newFilament)
        // No filament data: the filament search, never the last-used filament.
        #expect(ToolheadTagImport.addStart(tagData: nil, filaments: [same]) == .filamentSearch)
    }
}
