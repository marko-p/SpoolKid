//
//  SpoolLinkSKUTests.swift
//  SpoolKidTests
//
//  `SM<id>` in an Anycubic ACE tag's SKU is how multiACE, through SpoolLink,
//  finds the spool a tag belongs to. The ACE's reader reports no tag UID, so
//  on that hardware the SKU is the only identifier there is (issue #5: the
//  same tag with its UID already linked resolved no spool under the filament
//  name, and bound to spool 75 as `SM75`).
//

import Testing
import Foundation
@testable import SpoolKid

struct SpoolLinkSKUTests {

    // MARK: - The convention

    @Test func spellsASpoolIDTheWayMultiACEReadsIt() {
        #expect(SpoolLinkSKU.sku(forSpoolID: 75) == "SM75")
    }

    @Test func readsTheSpoolIDBackOutOfTheSKU() {
        #expect(SpoolLinkSKU.spoolID(fromSKU: "SM75") == 75)
        #expect(SpoolLinkSKU.spoolID(fromSKU: "SM1") == 1)
    }

    /// Only the exact convention is claimed. A factory SKU, a filament name, or
    /// a bare number someone typed stays a name — a tag misread as belonging to
    /// a spool is worse than one that belongs to none.
    @Test(arguments: ["AHPLVO-107", "White PETG Basic", "75", "SM", "SM7a", "sm75", "SM 75", "SM-75", "SM0", "", "SM99999999999999999999"])
    func anythingElseIsNotASpoolID(_ sku: String) {
        #expect(SpoolLinkSKU.spoolID(fromSKU: sku) == nil)
    }

    // MARK: - Which backends it means something on

    /// Spoolman's IDs are what SpoolLink addresses. FilaMan's are too: its
    /// Spoolman-compat layer serves the native IDs unchanged (measured on the
    /// owner's instance, 2026-08-25). The on-device Library's IDs mean nothing
    /// to anything outside the app.
    @Test func spoolIDsResolveViaSpoolLinkOnServerBackendsOnly() {
        #expect(BackendCapabilities.spoolman.spoolIDsResolveViaSpoolLink)
        #expect(BackendCapabilities.filaman.spoolIDsResolveViaSpoolLink)
        #expect(!BackendCapabilities.local.spoolIDsResolveViaSpoolLink)
    }

    // MARK: - The write form's default

    @Test func theSKUDefaultsToTheSpoolIDWhereSpoolLinkCanResolveIt() {
        let sku = WriteTagFormAssembler.defaultACESKU(
            name: "White PETG Basic", spoolID: 75, spoolIDsResolveViaSpoolLink: true)
        #expect(sku == "SM75")
    }

    /// An `SM<id>` minted from an on-device ID would be resolved confidently to
    /// whatever Spoolman spool happens to share the number.
    @Test func theSKUStaysTheNameWhereTheIDMeansNothingToSpoolLink() {
        let sku = WriteTagFormAssembler.defaultACESKU(
            name: "White PETG Basic", spoolID: 75, spoolIDsResolveViaSpoolLink: false)
        #expect(sku == "White PETG Basic")
    }

    @Test func theSKUStaysTheNameWithoutASpool() {
        let sku = WriteTagFormAssembler.defaultACESKU(
            name: "White PETG Basic", spoolID: nil, spoolIDsResolveViaSpoolLink: true)
        #expect(sku == "White PETG Basic")
    }

    /// Owner, 2026-10-09: the ACE unit shows the printer only the tag's
    /// contents, never its UID, so the SKU carries SM<id> in every mode.
    @Test func theSKUCarriesTheSpoolIDInEveryMode() {
        let sku = WriteTagFormAssembler.defaultACESKU(name: "White PETG Basic", spoolID: 75, spoolIDsResolveViaSpoolLink: true)
        #expect(sku == "SM75")
    }

    @Test func anACETagWritesTheSKUItWasGiven() {
        let data = buildTagData(format: .anycubicACE, name: "White PETG Basic", sku: "SM75")
        #expect(data.name == "SM75")
        // The ID travels in the SKU. `spoolmanId` is OpenSpool's field.
        #expect(data.spoolmanId == nil)
    }

    @Test func otherFormatsIgnoreTheSKU() {
        let data = buildTagData(format: .openTag3D, name: "White PETG Basic", sku: "SM75")
        #expect(data.name == "White PETG Basic")
    }

    // MARK: - A spool's own write (spool form, Write Tag)

    @Test func aSpoolsOpenSpoolWriteCarriesItsIDOnlyInSpoolIDMode() {
        #expect(WriteTagFormAssembler.spoolWriteData(for: spool, format: .openSpool, writesSpoolID: true, spoolIDsResolveViaSpoolLink: true).spoolmanId == 75)
        #expect(WriteTagFormAssembler.spoolWriteData(for: spool, format: .openSpool, writesSpoolID: false, spoolIDsResolveViaSpoolLink: true).spoolmanId == nil)
    }

    @Test func aSpoolsACEWriteCarriesSMIDInEveryMode() {
        let data = WriteTagFormAssembler.spoolWriteData(for: spool, format: .anycubicACE, writesSpoolID: false, spoolIDsResolveViaSpoolLink: true)
        #expect(data.name == "SM75")
        #expect(data.spoolmanId == nil)
    }

    @Test func aSpoolsACEWriteKeepsTheNameWhereTheIDMeansNothing() {
        let data = WriteTagFormAssembler.spoolWriteData(for: spool, format: .anycubicACE, writesSpoolID: true, spoolIDsResolveViaSpoolLink: false)
        #expect(data.name == "White PETG Basic")
    }

    @Test func otherFormatsNeverCarryTheID() {
        for format in [TagFormat.openPrintTag, .openTag3D, .elegoo, .tigerTag] {
            #expect(WriteTagFormAssembler.spoolWriteData(for: spool, format: format, writesSpoolID: true, spoolIDsResolveViaSpoolLink: true).spoolmanId == nil)
        }
    }

    // MARK: - Reading it back

    /// SpoolKid used to read its own `SM75` tag back as a filament *named*
    /// "SM75" — worse at reading the very tags it had just written.
    @Test func anACETagCarryingASpoolIDReadsBackAsThatSpool() throws {
        var data = aceSample
        data.name = "SM75"
        let decoded = try #require(AnycubicACEPayload.decode(from: pagesWritten(from: data)))

        #expect(decoded.spoolmanId == 75)
        #expect(decoded.name == nil)
        #expect(decoded.material == "PETG")
    }

    @Test func anACETagCarryingANameStillReadsBackAsAName() throws {
        let decoded = try #require(AnycubicACEPayload.decode(from: pagesWritten(from: aceSample)))

        #expect(decoded.name == "White PETG Basic")
        #expect(decoded.spoolmanId == nil)
    }

    // MARK: - Fixtures

    private let spool = Spool(
        id: 75,
        filament: Filament(id: 1, name: "White PETG Basic", material: "PETG"),
        statusId: nil, externalId: nil, purchaseDate: nil
    )

    private let aceSample = FilamentTagData(
        name: "White PETG Basic",
        material: "PETG",
        subtype: nil,
        brand: "Polar Filament",
        colorHex: "FFFFFF",
        minNozzleTemp: 250,
        maxNozzleTemp: 260,
        minBedTemp: 70,
        maxBedTemp: 75
    )

    private func buildTagData(format: TagFormat, name: String, sku: String) -> FilamentTagData {
        WriteTagFormAssembler.buildTagData(
            format: format,
            name: name,
            sku: sku,
            material: "PETG",
            subtype: "",
            brand: "Polar Filament",
            colorHex: "FFFFFF",
            minNozzleTemp: 250,
            maxNozzleTemp: 260,
            minBedTemp: 70,
            maxBedTemp: 75,
            spoolmanId: 75,
            writeSpoolID: true
        )
    }

    private func pagesWritten(from data: FilamentTagData) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 45 * AnycubicACEPayload.bytesPerPage)
        for page in AnycubicACEPayload.encodePages(from: data) {
            let offset = page.page * AnycubicACEPayload.bytesPerPage
            bytes.replaceSubrange(offset..<(offset + 4), with: page.data)
        }
        return bytes
    }
}
