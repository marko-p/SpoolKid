//
//  WipeLocalStoreTests.swift
//  SpoolKidTests
//
//  Purpose: Verifies that SpoolKidApp.wipeLocalStore(_:) deletes every local
//  SwiftData row (vendors, filaments, spools, id-sequence counters) and resets
//  the monotonic id sequence so new rows start from 1 again — while leaving
//  other backends' location-registry entries, which only Reset clears.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import SwiftData
import Testing
@testable import SpoolKid

@MainActor
struct WipeLocalStoreTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            LocationRegistryEntry.self,
            configurations: config
        )
    }

    @Test func wipeLocalStoreEmptiesEveryModelAndRestartsIds() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = LocalRepository(context: context)

        // Seed the store with at least one of each entity.
        let vendor = try #require(await repo.addVendor(name: "Polymaker"))
        let filament = try #require(await repo.addFilament(
            draft: FilamentDraft(name: "PolyTerra PLA", vendorId: .set(vendor.id), material: "PLA")
        ))
        _ = try #require(await repo.addSpool(draft: SpoolDraft(filamentId: filament.id)))

        // Precondition: rows and sequence counters exist.
        #expect(try context.fetchCount(FetchDescriptor<LocalVendor>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<LocalFilament>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<LocalSpool>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<LocalIdSequence>()) > 0)

        SpoolKidApp.wipeLocalStore(context)

        // Every model type should be empty.
        #expect(try context.fetchCount(FetchDescriptor<LocalVendor>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<LocalFilament>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<LocalSpool>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<LocalIdSequence>()) == 0)

        // Id counters reset: the next created row gets localId 1 again.
        let freshContext = ModelContext(container)
        let freshRepo = LocalRepository(context: freshContext)
        let freshVendor = try #require(await freshRepo.addVendor(name: "Bambu Lab"))
        #expect(freshVendor.id == 1)
    }

    private func seedRegistry(_ context: ModelContext) throws {
        for kind in BackendKind.allCases {
            context.insert(LocationRegistryEntry(name: "Shelf \(kind.rawValue)", backendKind: kind.rawValue))
        }
        try context.save()
    }

    private func registryKinds(_ context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<LocationRegistryEntry>()).map(\.backendKind))
    }

    /// The migration calls this wipe too: a server's empty locations and
    /// location tags must survive it.
    @Test func wipeLocalStoreKeepsOtherBackendsRegistryEntries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        try seedRegistry(context)

        SpoolKidApp.wipeLocalStore(context)

        #expect(try registryKinds(context) == [BackendKind.spoolman.rawValue, BackendKind.filaman.rawValue])
    }

    @Test func wipeLocationRegistryClearsEveryBackend() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        try seedRegistry(context)

        SpoolKidApp.wipeLocationRegistry(context)

        #expect(try registryKinds(context).isEmpty)
    }
}
