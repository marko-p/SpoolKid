//
//  LocalRepositorySaveFailureTests.swift
//  SpoolKidTests
//
//  Purpose: A LocalRepository write whose save fails reports the failure —
//  nil or false, with `errorMessage` set — and leaves nothing pending on the
//  shared context for the next writer's save to commit. In-memory store, with
//  the save failure injected by `SaveFailureInjection`.
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
struct LocalRepositorySaveFailureTests {
    private func makeContext() throws -> ModelContext {
        try SaveFailureInjection.makeContext(for: [
            LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self, EmptySpoolEntry.self
        ])
    }

    private func storedVendors(_ context: ModelContext) throws -> [LocalVendor] {
        try context.fetch(FetchDescriptor<LocalVendor>())
    }

    private func storedFilaments(_ context: ModelContext) throws -> [LocalFilament] {
        try context.fetch(FetchDescriptor<LocalFilament>())
    }

    private func storedSpools(_ context: ModelContext) throws -> [LocalSpool] {
        try context.fetch(FetchDescriptor<LocalSpool>())
    }

    /// One filament and one spool on it, at "Bin 1", 1000 g left.
    private func seedSpool(_ repo: LocalRepository) async throws -> (Filament, Spool) {
        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA")))
        let spool = try #require(await repo.addSpool(draft: SpoolDraft(
            filamentId: filament.id, remainingWeight: .set(1000), location: .set("Bin 1")
        )))
        return (filament, spool)
    }

    @Test func armedContextRefusesToSave() throws {
        let context = try makeContext()
        try SaveFailureInjection.arm(context)
        #expect(throws: (any Error).self) { try context.save() }
    }

    // MARK: - Vendors

    @Test func addVendorReportsAFailedSave() async throws {
        let context = try makeContext()
        let repo = LocalRepository(context: context)
        try SaveFailureInjection.arm(context)

        #expect(await repo.addVendor(name: "Polymaker") == nil)
        #expect(repo.errorMessage != nil)
        #expect(repo.vendors.isEmpty)
        #expect(try storedVendors(context).isEmpty)
        #expect(!context.hasChanges)
    }

    @Test func updateVendorReportsAFailedSave() async throws {
        let context = try makeContext()
        let repo = LocalRepository(context: context)
        let vendor = try #require(await repo.addVendor(name: "Old"))
        try SaveFailureInjection.arm(context)

        #expect(await repo.updateVendor(id: vendor.id, draft: VendorDraft(name: "New")) == false)
        #expect(repo.errorMessage != nil)
        #expect(repo.vendors.map(\.name) == ["Old"])
        #expect(try storedVendors(context).map(\.name) == ["Old"])
        #expect(!context.hasChanges)
    }

    // MARK: - Filaments

    @Test func addFilamentReportsAFailedSave() async throws {
        let context = try makeContext()
        let repo = LocalRepository(context: context)
        try SaveFailureInjection.arm(context)

        #expect(await repo.addFilament(draft: FilamentDraft(name: "PLA")) == nil)
        #expect(repo.errorMessage != nil)
        #expect(repo.filaments.isEmpty)
        #expect(try storedFilaments(context).isEmpty)
        #expect(!context.hasChanges)
    }

    @Test func updateFilamentReportsAFailedSave() async throws {
        let context = try makeContext()
        let repo = LocalRepository(context: context)
        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "Old")))
        try SaveFailureInjection.arm(context)

        #expect(await repo.updateFilament(id: filament.id, draft: FilamentDraft(name: "New")) == false)
        #expect(repo.errorMessage != nil)
        #expect(repo.filaments.map(\.name) == ["Old"])
        #expect(try storedFilaments(context).map(\.name) == ["Old"])
        #expect(!context.hasChanges)
    }

    // MARK: - Spools

    @Test func addSpoolReportsAFailedSave() async throws {
        let context = try makeContext()
        let repo = LocalRepository(context: context)
        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA")))
        try SaveFailureInjection.arm(context)

        #expect(await repo.addSpool(draft: SpoolDraft(filamentId: filament.id)) == nil)
        #expect(repo.errorMessage != nil)
        #expect(repo.spools.isEmpty)
        #expect(try storedSpools(context).isEmpty)
        #expect(!context.hasChanges)
    }

    @Test func updateSpoolReportsAFailedSave() async throws {
        let context = try makeContext()
        let repo = LocalRepository(context: context)
        let (_, spool) = try await seedSpool(repo)
        try SaveFailureInjection.arm(context)

        #expect(await repo.updateSpool(id: spool.id, draft: SpoolDraft(remainingWeight: .set(500))) == false)
        #expect(repo.errorMessage != nil)
        #expect(repo.spools.map(\.remainingWeight) == [1000])
        #expect(try storedSpools(context).map(\.remainingWeight) == [1000])
        #expect(!context.hasChanges)
    }

    @Test func deleteSpoolReportsAFailedSave() async throws {
        let context = try makeContext()
        let repo = LocalRepository(context: context)
        let (_, spool) = try await seedSpool(repo)
        try SaveFailureInjection.arm(context)

        #expect(await repo.deleteSpool(id: spool.id) == false)
        #expect(repo.errorMessage != nil)
        #expect(repo.spools.map(\.id) == [spool.id])
        #expect(try storedSpools(context).count == 1)
        #expect(!context.hasChanges)
    }

    @Test func setSpoolArchivedReportsAFailedSave() async throws {
        let context = try makeContext()
        let repo = LocalRepository(context: context)
        let (_, spool) = try await seedSpool(repo)
        try SaveFailureInjection.arm(context)

        #expect(await repo.setSpoolArchived(id: spool.id, archived: true) == false)
        #expect(repo.errorMessage != nil)
        #expect(repo.spools.first?.archived != true)
        #expect(try storedSpools(context).first?.archived != true)
        #expect(!context.hasChanges)
    }

    // MARK: - Locations

    @Test func renameLocationReportsAFailedSave() async throws {
        let context = try makeContext()
        let repo = LocalRepository(context: context)
        _ = try await seedSpool(repo)
        try SaveFailureInjection.arm(context)

        #expect(await repo.renameLocation(currentName: "Bin 1", newName: "Bin 2") == false)
        #expect(repo.errorMessage != nil)
        #expect(repo.locations == ["Bin 1"])
        #expect(try storedSpools(context).map(\.location) == ["Bin 1"])
        #expect(!context.hasChanges)
    }

    @Test func deleteLocationReportsAFailedSave() async throws {
        let context = try makeContext()
        let repo = LocalRepository(context: context)
        _ = try await seedSpool(repo)
        try SaveFailureInjection.arm(context)

        #expect(await repo.deleteLocation("Bin 1") == false)
        #expect(repo.errorMessage != nil)
        #expect(repo.locations == ["Bin 1"])
        #expect(try storedSpools(context).map(\.location) == ["Bin 1"])
        #expect(!context.hasChanges)
    }

    // MARK: - Filament tag links

    @Test func linkFilamentTagLeavesNothingPendingWhenItsSaveFails() async throws {
        let context = try makeContext()
        let repo = LocalRepository(context: context)
        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA")))
        try SaveFailureInjection.arm(context)

        let outcome = await repo.linkFilamentTag(filamentId: filament.id, uid: "04A1B2C3")
        #expect(outcome != .linked)
        #expect(try storedFilaments(context).first?.extra == nil)
        #expect(!context.hasChanges)
    }

    @Test func unlinkFilamentTagLeavesNothingPendingWhenItsSaveFails() async throws {
        let context = try makeContext()
        let repo = LocalRepository(context: context)
        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA")))
        #expect(await repo.linkFilamentTag(filamentId: filament.id, uid: "04A1B2C3") == .linked)
        try SaveFailureInjection.arm(context)

        #expect(await repo.unlinkFilamentTag(filamentId: filament.id, uid: "04A1B2C3") == false)
        #expect(repo.filaments.first?.extra?[CardUIDsCodec.fieldKey] != nil)
        #expect(!context.hasChanges)
    }

    // MARK: - Cross-cutting

    /// A create that passed the quota check was not refused by it. A stale
    /// `lastQuotaError` would make the forms show "Limit Reached" for what
    /// was a failed save.
    @Test func aFailedSaveIsNotReportedAsTheQuota() async throws {
        let context = try makeContext()
        let repo = LocalRepository(context: context, quotaLimit: 1)
        let first = try #require(await repo.addVendor(name: "A"))
        #expect(await repo.addVendor(name: "B") == nil)
        #expect(repo.lastQuotaError != nil)
        #expect(await repo.deleteVendor(id: first.id))
        try SaveFailureInjection.arm(context)

        #expect(await repo.addVendor(name: "C") == nil)
        #expect(repo.lastQuotaError == nil)
        #expect(repo.errorMessage != nil)
    }

    /// The empty-spool library saves on the same `ModelContext`. A change a
    /// failed write left pending would ride along with the library's next
    /// save — stored after all, behind a write that reported failure.
    @Test func aFailedWriteLeavesNothingForTheEmptySpoolLibraryToCommit() async throws {
        let context = try makeContext()
        let repo = LocalRepository(context: context)
        let library = EmptySpoolLibrary(context: context)
        let vendor = try #require(await repo.addVendor(name: "Old"))
        try SaveFailureInjection.arm(context)

        #expect(await repo.updateVendor(id: vendor.id, draft: VendorDraft(name: "New")) == false)
        try SaveFailureInjection.disarm(context)
        #expect(library.add(name: "Core", weight: 250, photo: nil, isDefault: false))

        #expect(try storedVendors(context).map(\.name) == ["Old"])
    }
}
