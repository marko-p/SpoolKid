//
//  SpoolPageTests.swift
//  SpoolKidTests
//
//  Purpose: The rules the Spool page renders: its action tiles, which tags it
//  lists and which of them it can unlink, its detail rows, and when it closes
//  itself.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
import Foundation
@testable import SpoolKid

struct SpoolPageTests {
    private var filament: Filament {
        Filament(id: 7, name: "Original WHITE", material: "PETG", vendor: Vendor(id: 1, name: "AzureFilm"))
    }

    private func spool(
        location: String? = nil, price: Double? = nil, lotNr: String? = nil, comment: String? = nil,
        cardUIDs: [String] = [], rfidUID: String? = nil
    ) -> Spool {
        Spool(id: 3, filament: filament, price: price, location: location, lotNr: lotNr, comment: comment,
              extra: cardUIDs.isEmpty ? nil : ["card_uids": "\"\(cardUIDs.joined(separator: ","))\""],
              rfidUID: rfidUID, statusId: nil, externalId: nil, purchaseDate: nil)
    }

    @Test func tilesWithLinks() {
        #expect(SpoolPage.tiles(writesLinks: true, isLinkScanning: false).map(\.id)
            == [.linkTag, .writeTag, .setLocation, .weigh])
    }

    @Test func tilesWithoutLinks() {
        #expect(SpoolPage.tiles(writesLinks: false, isLinkScanning: false).map(\.id)
            == [.writeTag, .setLocation, .weigh])
    }

    @Test func linkTileScanningTitle() {
        let link = SpoolPage.tiles(writesLinks: true, isLinkScanning: true).first { $0.id == .linkTag }
        #expect(link?.title == "Scanning…")
    }

    @Test func rfidOnlyTagCannotUnlink() {
        let rows = SpoolPage.tagRows(for: spool(cardUIDs: ["AA01"], rfidUID: "bb02"))
        #expect(rows == [SpoolPageTag(uid: "AA01", canUnlink: true), SpoolPageTag(uid: "BB02", canUnlink: false)])
    }

    @Test func detailRowsGateAndOrder() {
        let rows = SpoolPage.detailRows(
            for: spool(location: "Shelf A", price: 21.5, lotNr: "L7", comment: "x"),
            visibleFieldIDs: ["location", "comment"], statusName: nil
        )
        #expect(rows.map(\.label) == ["Location", "Price", "Lot/Batch", "Comment"])
        #expect(rows.first { $0.label == "Price" }?.value == "21.50")
    }

    @Test func detailRowsHideGatedLocation() {
        let labels = SpoolPage.detailRows(
            for: spool(location: "Shelf A", price: 21.5, lotNr: "L7", comment: "x"),
            visibleFieldIDs: [], statusName: nil
        ).map(\.label)
        #expect(!labels.contains("Location"))
        #expect(!labels.contains("Comment"))
    }

    @Test func dismissOnlyAfterFound() {
        #expect(SpoolPage.shouldDismiss(wasFound: false, spool: nil) == false)
        #expect(SpoolPage.shouldDismiss(wasFound: true, spool: nil) == true)
        #expect(SpoolPage.shouldDismiss(wasFound: true, spool: spool()) == false)
    }

    @MainActor @Test func locationFromScanIgnoresSpoolTags() {
        let spoolTag = ScanResult(cardUID: "04AA03", tagData: FilamentTagData(material: "PLA", brand: "X", colorHex: "FF0000", minNozzleTemp: 200, maxNozzleTemp: 220, minBedTemp: 60, maxBedTemp: 60), format: nil)
        #expect(SpoolPage.locationFromScan(spoolTag, registry: nil) == nil)

        let shelf = ScanResult(
            cardUID: "04AA04", tagData: nil, format: nil,
            locationTag: LocationTagPayload(uuid: UUID(), name: "Shelf C")
        )
        #expect(SpoolPage.locationFromScan(shelf, registry: nil) == "Shelf C")
    }

    // MARK: - Final review fixes

    /// C1: a write's reset (`false`) must not use up the pending write, or the
    /// second write on the page is never recorded or linked.
    @Test func aWritesResetEdgeKeepsItPending() {
        #expect(SpoolPage.writeResult(pending: .write, succeeded: false) == .init(handles: false, pendingAfter: .write))
        #expect(SpoolPage.writeResult(pending: .write, succeeded: true) == .init(handles: true, pendingAfter: nil))
        #expect(SpoolPage.writeResult(pending: nil, succeeded: true) == .init(handles: false, pendingAfter: nil))
        #expect(SpoolPage.writeResult(pending: .link, succeeded: true) == .init(handles: false, pendingAfter: .link))
    }

    /// I1: the start-in-Edit request applies once, not on every reappearance.
    @Test func aStartRequestAppliesOnce() {
        #expect(SpoolPage.appliesOnce(requested: true, applied: false))
        #expect(!SpoolPage.appliesOnce(requested: true, applied: true))
        #expect(!SpoolPage.appliesOnce(requested: false, applied: false))
    }

    /// I2: a refused write or scan reaches the user; an empty message is none.
    @Test func anNFCMessageIsAFailureUnlessEmpty() {
        #expect(SpoolPage.nfcFailure("NFC is not available on this device.") == "NFC is not available on this device.")
        #expect(SpoolPage.nfcFailure("") == nil)
    }
}
