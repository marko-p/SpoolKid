//
//  LocationBulkAssignTests.swift
//  SpoolKidTests
//
//  Purpose: Assigning a shelf to a selection reports what it actually did.
//

import Foundation
import SwiftData
import Testing
@testable import SpoolKid

@MainActor
struct LocationBulkAssignTests {
    private func makeStore() throws -> SpoolDataStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self,
                 LocalIdSequence.self, LocationRegistryEntry.self,
            configurations: config
        )
        return SpoolDataStore(repository: LocalRepository(context: ModelContext(container)))
    }

    private func seedSpool(_ store: SpoolDataStore, location: String?) async throws -> Int {
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA", material: "PLA")))
        var draft = SpoolDraft()
        draft.filamentId = filament.id
        draft.location = location.map { SpoolmanPatchValue.set($0) } ?? .ignore
        let spool = try #require(await store.addSpool(draft: draft))
        return spool.id
    }

    @Test func assigningAShelfToTwoSpoolsMovesBoth() async throws {
        let store = try makeStore()
        let a = try await seedSpool(store, location: "Shelf A")
        let b = try await seedSpool(store, location: nil)

        let result = await store.assignLocation(spoolIDs: [a, b], to: .set("Shelf B"))

        #expect(result.succeeded == 2)
        #expect(result.isCompleteSuccess)
        #expect(store.spools.filter { $0.location == "Shelf B" }.count == 2)
    }

    @Test func assigningNilClearsTheLocationRatherThanWritingAWord() async throws {
        let store = try makeStore()
        let a = try await seedSpool(store, location: "Shelf A")

        let result = await store.assignLocation(spoolIDs: [a], to: .setNil)

        #expect(result.isCompleteSuccess)
        let spool = try #require(store.spools.first { $0.id == a })
        #expect(LocationName.trimmed(spool.location ?? "").isEmpty)
        #expect(spool.location != "Unassigned")
    }

    @Test func aSpoolThatDoesNotExistIsCountedAsAFailureNotIgnored() async throws {
        let store = try makeStore()
        let a = try await seedSpool(store, location: nil)

        let result = await store.assignLocation(spoolIDs: [a, 99_999], to: .set("Shelf B"))

        #expect(result.succeeded == 1)
        #expect(result.failed == 1)
        #expect(result.total == 2)
        #expect(!result.isCompleteSuccess)
    }

    @Test func anEmptySelectionIsACompleteSuccessOverNothing() async throws {
        let store = try makeStore()

        let result = await store.assignLocation(spoolIDs: [], to: .set("Shelf B"))

        #expect(result.total == 0)
        #expect(result.isCompleteSuccess)
    }
}
