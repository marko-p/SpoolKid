//
//  FilamentManufacturerChangeTests.swift
//  SpoolKidTests
//
//  Purpose: Changing a filament's manufacturer writes only its vendor, and
//  reports what happened: unchanged, changed, or failed with the reason. A
//  new name is created first, as the filament form does at Save.
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
struct FilamentManufacturerChangeTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: config
        )
        return ModelContext(container)
    }

    /// Two manufacturers, "Prusa" and "Polymaker", and a PLA filament from Prusa.
    private func seed(_ store: SpoolDataStore) async throws -> Filament {
        let prusa = try #require(await store.addVendor(name: "Prusa"))
        _ = try #require(await store.addVendor(name: "Polymaker"))
        return try #require(await store.addFilament(draft: FilamentDraft(
            name: "PLA Basic", vendorId: .set(prusa.id), material: "PLA"
        )))
    }

    private func vendorID(named name: String, in store: SpoolDataStore) throws -> Int {
        try #require(store.vendors.first { $0.name == name }?.id)
    }

    /// The filament as the store holds it now.
    private func reloaded(_ filament: Filament, in store: SpoolDataStore) async throws -> Filament {
        await store.fetchFilaments()
        return try #require(store.filaments.first { $0.id == filament.id })
    }

    @Test func changingToAnotherManufacturerUpdatesOnlyTheVendor() async throws {
        let store = SpoolDataStore(repository: LocalRepository(context: try makeContext()))
        let filament = try await seed(store)
        let polymaker = try vendorID(named: "Polymaker", in: store)

        let outcome = await FilamentManufacturerChange.apply(
            .existing(id: polymaker, name: "Polymaker"), toFilament: filament, store: store
        )

        #expect(outcome == .changed)
        let after = try await reloaded(filament, in: store)
        #expect(after.vendor?.id == polymaker)
        #expect(after.name == "PLA Basic")
        #expect(after.material == "PLA")
    }

    @Test func pickingTheCurrentManufacturerChangesNothing() async throws {
        let store = SpoolDataStore(repository: LocalRepository(context: try makeContext()))
        let filament = try await seed(store)
        let prusa = try #require(filament.vendor?.id)

        let outcome = await FilamentManufacturerChange.apply(
            .existing(id: prusa, name: "Prusa"), toFilament: filament, store: store
        )

        #expect(outcome == .unchanged)
        let after = try await reloaded(filament, in: store)
        #expect(after.vendor?.id == prusa)
    }

    @Test func noneChangesNothing() async throws {
        let store = SpoolDataStore(repository: LocalRepository(context: try makeContext()))
        let filament = try await seed(store)
        let prusa = try #require(filament.vendor?.id)

        let outcome = await FilamentManufacturerChange.apply(.none, toFilament: filament, store: store)

        #expect(outcome == .unchanged)
        let after = try await reloaded(filament, in: store)
        #expect(after.vendor?.id == prusa)
    }

    @Test func newManufacturerIsCreatedThenAssigned() async throws {
        let store = SpoolDataStore(repository: LocalRepository(context: try makeContext()))
        let filament = try await seed(store)

        let outcome = await FilamentManufacturerChange.apply(
            .new(name: "Prusament"), toFilament: filament, store: store
        )

        #expect(outcome == .changed)
        let created = try vendorID(named: "Prusament", in: store)
        let after = try await reloaded(filament, in: store)
        #expect(after.vendor?.id == created)
    }

    @Test func aNewNameForTheCurrentManufacturerChangesNothing() async throws {
        let store = SpoolDataStore(repository: LocalRepository(context: try makeContext()))
        let filament = try await seed(store)

        let outcome = await FilamentManufacturerChange.apply(
            .new(name: "prusa"), toFilament: filament, store: store
        )

        #expect(outcome == .unchanged)
        #expect(store.vendors.filter { $0.name.lowercased() == "prusa" }.count == 1)
    }

    @Test func newManufacturerThatCannotBeCreatedChangesNothing() async throws {
        let context = try SaveFailureInjection.makeContext(for: [
            LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self, EmptySpoolEntry.self
        ])
        let store = SpoolDataStore(repository: LocalRepository(context: context))
        let filament = try await seed(store)
        let prusa = try #require(filament.vendor?.id)
        try SaveFailureInjection.arm(context)

        let outcome = await FilamentManufacturerChange.apply(
            .new(name: "Bambu"), toFilament: filament, store: store
        )

        let reason = try #require(store.errorMessage)
        #expect(outcome == .failed("Bambu could not be added as a manufacturer. \(reason)"))
        let after = try await reloaded(filament, in: store)
        #expect(after.vendor?.id == prusa)
    }

    @Test func aFailedSaveOfTheChangeIsReported() async throws {
        let context = try SaveFailureInjection.makeContext(for: [
            LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self, EmptySpoolEntry.self
        ])
        let store = SpoolDataStore(repository: LocalRepository(context: context))
        let filament = try await seed(store)
        let prusa = try #require(filament.vendor?.id)
        let polymaker = try vendorID(named: "Polymaker", in: store)
        try SaveFailureInjection.arm(context)

        let outcome = await FilamentManufacturerChange.apply(
            .existing(id: polymaker, name: "Polymaker"), toFilament: filament, store: store
        )

        let reason = try #require(store.errorMessage)
        #expect(outcome == .failed(reason))
        let after = try await reloaded(filament, in: store)
        #expect(after.vendor?.id == prusa)
    }
}
