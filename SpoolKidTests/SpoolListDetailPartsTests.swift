//
//  SpoolListDetailPartsTests.swift
//  SpoolKidTests
//
//  Purpose: Covers Spool.listDetailParts showing the mapped-tag count
//  ("Tags: N") instead of the legacy lot number, and omitting it at zero.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
@testable import SpoolKid

struct SpoolListDetailPartsTests {
    private func makeSpool(lotNr: String? = nil, cardUIDs: [String] = []) -> Spool {
        Spool(
            id: 7,
            filament: Filament(id: 1, name: "PLA"),
            lotNr: lotNr,
            extra: cardUIDs.isEmpty ? nil : ["card_uids": CardUIDsCodec.encode(cardUIDs)],
            statusId: nil, externalId: nil, purchaseDate: nil
        )
    }

    @Test func showsTagCountFromCardUIDs() {
        let parts = makeSpool(cardUIDs: ["AABBCCDD", "11223344"]).listDetailParts
        #expect(parts.contains("Tags: 2"))
        #expect(!parts.contains { $0.hasPrefix("Lot:") })
    }

    @Test func aLotNrTokenIsNotCounted() {
        // One UID in card_uids; a `card_uid:` token in lot_nr is lot text → 1 tag.
        let parts = makeSpool(lotNr: "card_uid:11223344", cardUIDs: ["AABBCCDD"]).listDetailParts
        #expect(parts.contains("Tags: 1"))
    }

    @Test func omitsTagsWhenNoneMapped() {
        let parts = makeSpool(lotNr: "batch-7").listDetailParts
        #expect(!parts.contains { $0.hasPrefix("Tags:") })
        #expect(!parts.contains { $0.hasPrefix("Lot:") })
    }
}
