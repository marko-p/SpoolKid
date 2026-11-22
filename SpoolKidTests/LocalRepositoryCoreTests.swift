//
//  LocalRepositoryCoreTests.swift
//  SpoolKidTests
//
//  Purpose: Covers the LocalRepository core — Local→DTO mapping (incl. nested
//  filament/vendor and the no-filament guard), vendor CRUD, the free-tier quota
//  on create, and synthesized-id stability across reloads. In-memory store.
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
struct LocalRepositoryCoreTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test func mappingExposesVendorFieldsWithPositiveId() throws {
        let context = try makeContext()
        context.insert(LocalVendor(localId: 1, name: "Bambu Lab", comment: "note", emptySpoolWeight: 250))
        try context.save()

        let repo = LocalRepository(context: context)
        #expect(repo.vendors.count == 1)
        let vendor = try #require(repo.vendors.first)
        #expect(vendor.name == "Bambu Lab")
        #expect(vendor.comment == "note")
        #expect(vendor.emptySpoolWeight == 250)
        #expect(vendor.id > 0)
    }

    @Test func mappingIncludesNestedFilamentAndVendorForSpools() throws {
        let context = try makeContext()
        let vendor = LocalVendor(localId: 1, name: "Polymaker")
        let filament = LocalFilament(localId: 1, name: "PolyTerra PLA", material: "PLA", vendor: vendor)
        context.insert(LocalSpool(localId: 1, remainingWeight: 900, location: "Shelf A", filament: filament))
        try context.save()

        let repo = LocalRepository(context: context)
        #expect(repo.spools.count == 1)
        let spool = try #require(repo.spools.first)
        #expect(spool.remainingWeight == 900)
        #expect(spool.filament.name == "PolyTerra PLA")
        #expect(spool.filament.vendor?.name == "Polymaker")
        #expect(repo.locations == ["Shelf A"])
    }

    @Test func spoolWithoutFilamentIsExcluded() throws {
        let context = try makeContext()
        context.insert(LocalSpool(localId: 1, remainingWeight: 500, filament: nil))
        try context.save()

        let repo = LocalRepository(context: context)
        #expect(repo.spools.isEmpty)
    }

    @Test func addVendorCreatesAndReturnsDTO() async throws {
        let repo = LocalRepository(context: try makeContext())
        let created = await repo.addVendor(draft: VendorDraft(name: "Sunlu", comment: "c"))
        #expect(created?.name == "Sunlu")
        #expect(repo.vendors.map(\.name) == ["Sunlu"])
        #expect(repo.lastQuotaError == nil)
    }

    @Test func freeTierBlocksSixteenthVendor() async throws {
        let repo = LocalRepository(context: try makeContext(), quotaLimit: 15)
        for i in 1...15 {
            let created = await repo.addVendor(name: "v\(i)")
            #expect(created != nil)
        }
        #expect(repo.vendors.count == 15)

        let overflow = await repo.addVendor(name: "v16")
        #expect(overflow == nil)
        #expect(repo.vendors.count == 15)
        #expect(repo.lastQuotaError == QuotaError(entity: .vendors, limit: 15))
    }

    @Test func updateVendorChangesName() async throws {
        let repo = LocalRepository(context: try makeContext())
        let created = try #require(await repo.addVendor(name: "Old"))
        let ok = await repo.updateVendor(id: created.id, draft: VendorDraft(name: "New"))
        #expect(ok)
        #expect(repo.vendors.first(where: { $0.id == created.id })?.name == "New")
    }

    @Test func deleteVendorRemovesIt() async throws {
        let repo = LocalRepository(context: try makeContext())
        let created = try #require(await repo.addVendor(name: "Temp"))
        await repo.deleteVendor(id: created.id)
        #expect(repo.vendors.isEmpty)
    }

    @Test func synthesizedIdIsStableAcrossReloads() async throws {
        let repo = LocalRepository(context: try makeContext())
        let created = try #require(await repo.addVendor(name: "Stable"))
        repo.reload()
        #expect(repo.vendors.first?.id == created.id)
    }

    // MARK: - Reachability

    @Test func onDeviceStorageIsAlwaysAvailableWithoutProbing() async throws {
        let repo = LocalRepository(context: try makeContext())

        // Reported as "no probe needed", not as a successful probe — the rows
        // are on the device and there is no server to have reached.
        #expect(await repo.checkReachability() == .alwaysAvailable)
        #expect(repo.errorMessage == nil)
    }

    @Test func onDeviceStorageHasAStableProbeTarget() throws {
        let repo = LocalRepository(context: try makeContext())

        // The Library tab compares this before and after an await to discard a
        // stale answer; with nothing configurable it must never drift.
        #expect(repo.connectionTarget == LocalRepository(context: try makeContext()).connectionTarget)
    }
}
