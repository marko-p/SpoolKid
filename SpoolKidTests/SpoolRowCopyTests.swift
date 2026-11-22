//
//  SpoolRowCopyTests.swift
//  SpoolKidTests
//
//  Purpose: Inside a location group the shelf IS the header, so the row must
//  not repeat it — and must still show it everywhere else.
//

import Testing
@testable import SpoolKid

struct SpoolRowCopyTests {
    private var spool: Spool {
        Spool(
            id: 12,
            filament: Filament(id: 1, name: "Galaxy Black", material: "PLA"),
            location: "Shelf A",
            statusId: nil,
            externalId: nil,
            purchaseDate: nil
        )
    }

    @Test func theDefaultDetailLineStillNamesTheLocation() {
        #expect(spool.listDetailParts.contains("Shelf A"))
    }

    @Test func suppressingTheLocationDropsOnlyThatPart() {
        let full = spool.listDetailParts
        let trimmed = spool.listDetailParts(includingLocation: false)

        #expect(!trimmed.contains("Shelf A"))
        #expect(trimmed == full.filter { $0 != "Shelf A" })
        #expect(trimmed.contains("#12"))
    }

    @Test func suppressingTheLocationOnASpoolWithNoneChangesNothing() {
        let loose = Spool(
            id: 13,
            filament: Filament(id: 1, name: "Loose", material: "PLA"),
            location: nil,
            statusId: nil,
            externalId: nil,
            purchaseDate: nil
        )

        #expect(loose.listDetailParts(includingLocation: false) == loose.listDetailParts)
    }
}
