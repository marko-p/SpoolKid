//
//  SpoolWritableCardUIDsTests.swift
//  SpoolKidTests
//
//  `Spool.writableCardUIDs`: the UID list a `card_uids` write may carry back —
//  Spoolman's native tags and `card_uids`, never a `lot_nr` token or FilaMan's
//  `rfid_uid` (I1, fix round 1; moved off `TagLinkService` so `unlinkTag` and
//  the spool form share it, final review FR-2).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

struct SpoolWritableCardUIDsTests {
    private static let testFilament = Filament(
        id: 10, name: "PLA+", material: "PLA", vendor: Vendor(id: 1, name: "TestVendor"),
        colorHex: "FF0000", density: 1.24
    )

    private static func spool(
        cardUIDs: [String] = [], lotNr: String? = nil, rfidUID: String? = nil, rfidWritable: Bool = false
    ) -> Spool {
        Spool(
            id: 1, filament: testFilament, lotNr: lotNr,
            extra: cardUIDs.isEmpty ? nil : ["card_uids": CardUIDsCodec.encode(cardUIDs)],
            rfidUID: rfidUID, statusId: nil, externalId: nil, purchaseDate: nil, rfidUIDWritable: rfidWritable
        )
    }

    @Test func cardUIDsOnly() {
        #expect(Self.spool(cardUIDs: ["04AA", "04BB"]).writableCardUIDs == ["04AA", "04BB"])
    }

    @Test func aLotNrTokenIsNeverWritable() {
        let spool = Self.spool(cardUIDs: ["04AA"], lotNr: "card_uid:04bb")
        #expect(spool.writableCardUIDs == ["04AA"])
    }

    /// `rfid_uid` is FilaMan's hardware binding: never carried into a
    /// `card_uids` write, unlike `Spool.mappedCardUIDs` which unions it.
    @Test func cardUIDsPlusRFIDUIDExcludesTheRFIDUID() {
        let spool = Self.spool(cardUIDs: ["04AA"], rfidUID: "04CC")
        #expect(spool.writableCardUIDs == ["04AA"])
    }

    /// While FilaMan Tags is on, `rfid_uid` is writable and leads the list.
    @Test func writableRFIDUIDLeadsTheWritableList() {
        let spool = Self.spool(cardUIDs: ["BB", "CC"], rfidUID: "aa", rfidWritable: true)
        #expect(spool.writableCardUIDs == ["AA", "BB", "CC"])
    }

    /// An empty `rfid_uid` is no tag, writable or not.
    @Test func emptyRFIDUIDIsNoTagEitherWay() {
        #expect(Self.spool(cardUIDs: ["BB", "CC"], rfidUID: "", rfidWritable: true).writableCardUIDs == ["BB", "CC"])
        #expect(Self.spool(cardUIDs: ["BB", "CC"], rfidUID: "", rfidWritable: false).writableCardUIDs == ["BB", "CC"])
    }
}
