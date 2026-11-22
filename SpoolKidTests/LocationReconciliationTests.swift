//
//  LocationReconciliationTests.swift
//  SpoolKidTests
//
//  Purpose: Classifying registry entries against live backend locations, and
//  the copy each state carries. Pure — no store, no network.
//

import Foundation
import Testing
@testable import SpoolKid

struct LocationReconciliationTests {
    private func record(_ name: String, tagUIDs: [String] = []) -> LocationRecord {
        LocationRecord(uuid: UUID(), name: name, tagUIDs: tagUIDs)
    }

    @Test func aNameTheBackendListsIsInSync() {
        let state = LocationReconciliation.state(
            for: record("Shelf A"), backendLocations: ["Shelf A", "Bin C"]
        )

        #expect(state == .inSync)
    }

    @Test func matchingIgnoresCaseAndSurroundingWhitespace() {
        let state = LocationReconciliation.state(
            for: record("Shelf A"), backendLocations: [" shelf a "]
        )

        #expect(state == .inSync)
    }

    @Test func anUntaggedNameTheBackendLacksIsMerelyPending() {
        let state = LocationReconciliation.state(
            for: record("Shelf D"), backendLocations: ["Shelf A"]
        )

        #expect(state == .pendingOnDevice)
    }

    @Test func aTaggedNameTheBackendLacksNeedsResolving() {
        let state = LocationReconciliation.state(
            for: record("Shelf A", tagUIDs: ["AABBCCDD"]), backendLocations: ["Shelf Alpha"]
        )

        #expect(state == .missingFromBackend)
    }

    @Test func unclaimedBackendLocationsExcludeEveryNameARecordHolds() {
        let records = [record("Shelf A"), record("Bin C")]

        let unclaimed = LocationReconciliation.unclaimedBackendLocations(
            ["Shelf Alpha", "shelf a", "Bin C", "Drawer 2"], records: records
        )

        #expect(unclaimed == ["Drawer 2", "Shelf Alpha"])
    }

    @Test func inSyncHasNothingToSay() {
        #expect(LocationReconciliation.banner(
            state: .inSync, locationName: "Shelf A", storageNoun: "Spoolman"
        ) == nil)
    }

    @Test func pendingExplainsWhereTheLocationLives() {
        let banner = LocationReconciliation.banner(
            state: .pendingOnDevice, locationName: "Shelf D", storageNoun: "Spoolman"
        )

        #expect(banner?.title == "Saved on this device")
        #expect(banner?.message == "Shelf D appears in Spoolman once you assign a spool to it.")
    }

    @Test func missingNamesTheHazardWithoutClaimingADeletion() {
        let banner = LocationReconciliation.banner(
            state: .missingFromBackend, locationName: "Shelf A", storageNoun: "Spoolman"
        )

        #expect(banner?.title == "No spools are in Shelf A")
        #expect(banner?.message == """
        This location isn't listed in Spoolman. Its tag still works — but if you renamed it there, \
        match it up now, or your next assignment will create Shelf A again alongside the new name.
        """)
    }

    @Test func missingReadsCorrectlyForTheOnDeviceLibrary() {
        let banner = LocationReconciliation.banner(
            state: .missingFromBackend, locationName: "Shelf A", storageNoun: "your library"
        )

        #expect(banner?.message.contains("isn't listed in your library.") == true)
    }

    // MARK: - Does the backend know this name (the rename question)

    @Test func backendKnowsALocationItLists() {
        #expect(LocationReconciliation.backendKnows(
            name: " shelf a ", backendLocations: ["Shelf A"], spoolLocations: []
        ))
    }

    @Test func backendKnowsALocationOnlyASpoolNames() {
        // Spoolman lists a location because a spool sits in it, so a fetch that
        // has not run yet must not make the name look device-only.
        #expect(LocationReconciliation.backendKnows(
            name: "Shelf A", backendLocations: [], spoolLocations: ["Shelf A"]
        ))
    }

    @Test func backendDoesNotKnowAPendingOnDeviceLocation() {
        #expect(LocationReconciliation.backendKnows(
            name: "Shelf D", backendLocations: ["Shelf A"], spoolLocations: ["Shelf A"]
        ) == false)
    }

    @Test func backendKnowsNothingAboutABlankName() {
        #expect(LocationReconciliation.backendKnows(
            name: "  ", backendLocations: [""], spoolLocations: []
        ) == false)
    }
}
