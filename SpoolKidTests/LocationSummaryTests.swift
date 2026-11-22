//
//  LocationSummaryTests.swift
//  SpoolKidTests
//
//  Purpose: The two numbers the Locations dashboard card shows.
//

import Foundation
import Testing
@testable import SpoolKid

struct LocationSummaryTests {
    private func spool(_ id: Int, location: String?) -> Spool {
        Spool(
            id: id, filament: Filament(id: 1, name: "PLA"), location: location,
            statusId: nil, externalId: nil, purchaseDate: nil
        )
    }

    @Test func countsLocationsAndSpoolsWithNoLocation() {
        let summary = LocationSummary.make(
            locations: ["Shelf A", "Shelf B"],
            spools: [spool(1, location: "Shelf A"), spool(2, location: nil), spool(3, location: nil)]
        )

        #expect(summary.locationCount == 2)
        #expect(summary.unassignedSpoolCount == 2)
    }

    @Test func aBlankLocationStringCountsAsUnassigned() {
        let summary = LocationSummary.make(locations: [], spools: [spool(1, location: "   ")])

        #expect(summary.unassignedSpoolCount == 1)
    }

    @Test func anEmptyLibraryIsAllZeroes() {
        let summary = LocationSummary.make(locations: [], spools: [])

        #expect(summary.locationCount == 0)
        #expect(summary.unassignedSpoolCount == 0)
    }
}
