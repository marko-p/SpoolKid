//
//  LocationGroupingTests.swift
//  SpoolKidTests
//
//  Purpose: What the arrangement list shows — which groups survive a search,
//  which spools show inside them, and when Unassigned exists at all.
//

import Testing
@testable import SpoolKid

struct LocationGroupingTests {
    private func spool(_ id: Int, _ name: String, location: String?, material: String? = "PLA") -> Spool {
        Spool(
            id: id,
            filament: Filament(id: id, name: name, material: material),
            location: location,
            statusId: nil,
            externalId: nil,
            purchaseDate: nil
        )
    }

    private var fixture: [Spool] {
        [
            spool(10, "Galaxy Black", location: "Shelf A"),
            spool(20, "Matte White", location: "Shelf A"),
            spool(30, "Silk Gold", location: "Shelf B", material: "PETG"),
            spool(40, "Loose Reel", location: nil),
            spool(50, "Blank Reel", location: "   ")
        ]
    }

    private func groups(
        _ locations: [String] = ["Shelf A", "Shelf B"],
        query: String = "",
        isDragging: Bool = false,
        override: [Int: String?] = [:]
    ) -> [LocationGroup] {
        LocationGrouping.groups(
            orderedLocations: locations,
            spools: fixture,
            query: query,
            spoolSort: .id,
            spoolAscending: true,
            isDragging: isDragging,
            locationOverride: override
        )
    }

    @Test func spoolsInLocationMatchExactlyNotNormalized() {
        let rows = LocationGrouping.spools(in: "Shelf A", from: [
            spool(1, "a", location: "Shelf A"),
            spool(2, "b", location: "shelf a"),
            spool(3, "c", location: "Shelf A ")
        ])

        #expect(rows.map(\.id) == [1])
    }

    @Test func aBlankQueryShowsEveryLocationWithAllItsSpools() {
        let result = groups()

        #expect(result.map(\.name) == ["", "Shelf A", "Shelf B"])
        #expect(result[1].spoolIDs == [10, 20])
        #expect(result[2].spoolIDs == [30])
        #expect(result.allSatisfy { !$0.forcedOpen })
    }

    @Test func unassignedHoldsSpoolsWithNoLocationAndBlankOnes() {
        #expect(groups()[0].spoolIDs == [40, 50])
        #expect(groups()[0].isUnassigned)
    }

    @Test func unassignedIsOmittedWhenEmptyAndNotDragging() {
        let result = LocationGrouping.groups(
            orderedLocations: ["Shelf A"],
            spools: [spool(10, "Galaxy Black", location: "Shelf A")],
            query: "",
            spoolSort: .id,
            spoolAscending: true,
            isDragging: false
        )

        #expect(result.map(\.name) == ["Shelf A"])
    }

    @Test func unassignedAppearsWhileDraggingEvenWithNothingInIt() {
        let result = LocationGrouping.groups(
            orderedLocations: ["Shelf A"],
            spools: [spool(10, "Galaxy Black", location: "Shelf A")],
            query: "",
            spoolSort: .id,
            spoolAscending: true,
            isDragging: true
        )

        #expect(result.map(\.name) == ["", "Shelf A"])
        #expect(result[0].spoolIDs.isEmpty)
    }

    @Test func aNameMatchShowsEverySpoolAndDoesNotForceOpen() {
        let result = groups(query: "Shelf A")

        #expect(result.map(\.name) == ["Shelf A"])
        #expect(result[0].spoolIDs == [10, 20])
        #expect(result[0].matchedByName)
        #expect(!result[0].forcedOpen)
    }

    @Test func aSpoolMatchShowsOnlyTheMatchesAndForcesTheGroupOpen() {
        let result = groups(query: "Silk")

        #expect(result.map(\.name) == ["Shelf B"])
        #expect(result[0].spoolIDs == [30])
        #expect(!result[0].matchedByName)
        #expect(result[0].forcedOpen)
    }

    @Test func aGroupWithNoMatchAnywhereIsDropped() {
        #expect(groups(query: "zzzz").isEmpty)
    }

    @Test func searchReachesTheDetailLineNotJustTheTitle() {
        let result = groups(query: "PETG")

        #expect(result.map(\.name) == ["Shelf B"])
        #expect(result[0].forcedOpen)
    }

    @Test func searchDoesNotMatchAHiddenLocationPartOnAnUnrelatedShelf() {
        // "Shelf A" is its own token match for Shelf A. Its tokens ("shelf",
        // "a") must not ALSO surface Shelf B by matching Shelf B's own
        // location string inside its spool's hidden detail line — the row
        // renders with `hidesLocation: true`, so a search must not reach
        // what the row itself does not show.
        let locations = ["Shelf A", "Shelf B"]
        let spools = [
            spool(10, "Galaxy Black", location: "Shelf A"),
            spool(30, "Silk Gold", location: "Shelf B", material: "PLA")
        ]
        let result = LocationGrouping.groups(
            orderedLocations: locations,
            spools: spools,
            query: "Shelf A",
            spoolSort: .id,
            spoolAscending: true,
            isDragging: false
        )

        #expect(result.map(\.name) == ["Shelf A"])
    }

    @Test func unassignedIsSearchableByItsOwnName() {
        let result = groups(query: "unassigned")

        #expect(result.map(\.name) == [""])
        #expect(result[0].matchedByName)
    }

    @Test func groupsFollowTheOrderTheyWereGivenNotAlphabetical() {
        let result = groups(["Shelf B", "Shelf A"])

        #expect(result.map(\.name) == ["", "Shelf B", "Shelf A"])
    }

    @Test func aPendingMoveShowsTheSpoolUnderItsNewShelfImmediately() {
        let result = groups(override: [10: "Shelf B"])

        #expect(result.first { $0.name == "Shelf A" }?.spoolIDs == [20])
        #expect(result.first { $0.name == "Shelf B" }?.spoolIDs == [10, 30])
    }

    @Test func aPendingUnassignMovesTheSpoolToUnassignedImmediately() {
        let result = groups(override: [10: nil])

        #expect(result.first { $0.name == "Shelf A" }?.spoolIDs == [20])
        #expect(result[0].spoolIDs == [10, 40, 50])
    }

    @Test func spoolsInsideAGroupHonourTheSpoolSortAndDirection() {
        let descending = LocationGrouping.groups(
            orderedLocations: ["Shelf A"],
            spools: fixture,
            query: "",
            spoolSort: .id,
            spoolAscending: false,
            isDragging: false
        )

        #expect(descending.first(where: { $0.name == "Shelf A" })?.spoolIDs == [20, 10])
    }
}
