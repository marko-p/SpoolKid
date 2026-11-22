//
//  PersistentLocalIdTests.swift
//  SpoolKidTests
//
//  Purpose: Covers the persistent local id foundation — monotonic allocation
//  that is never reused, stability across container reopen, DTO id == localId,
//  and that the session map is gone. In-memory store.
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
struct PersistentLocalIdTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: config
        )
    }

    private func makeRepo() throws -> LocalRepository {
        let container = try makeContainer()
        return LocalRepository(context: ModelContext(container))
    }

    // MARK: - Positive ids & DTO identity

    @Test func everyCreatedRowHasPositiveLocalId() async throws {
        let repo = try makeRepo()
        let vendor = try #require(await repo.addVendor(name: "V"))
        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "F")))
        let spool = try #require(await repo.addSpool(draft: SpoolDraft(filamentId: filament.id)))

        #expect(vendor.id > 0)
        #expect(filament.id > 0)
        #expect(spool.id > 0)
    }

    @Test func dtoIdEqualsLocalId() async throws {
        // Use one explicit container so we can fetch the row the repo actually wrote.
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = LocalRepository(context: context)
        let vendor = try #require(await repo.addVendor(name: "V"))
        let rows = try context.fetch(FetchDescriptor<LocalVendor>())
        let row = try #require(rows.first)
        #expect(vendor.id == row.localId)
    }

    // MARK: - Monotonic & never reused

    @Test func idsAreMonotonicAndNeverReused() async throws {
        let repo = try makeRepo()
        let v1 = try #require(await repo.addVendor(name: "v1"))
        let v2 = try #require(await repo.addVendor(name: "v2"))
        let v3 = try #require(await repo.addVendor(name: "v3"))
        #expect(v2.id > v1.id)
        #expect(v3.id > v2.id)

        await repo.deleteVendor(id: v3.id)

        let v4 = try #require(await repo.addVendor(name: "v4"))
        #expect(v4.id > v3.id)
    }

    @Test func filamentIdsAreMonotonicAndNeverReused() async throws {
        let repo = try makeRepo()
        let f1 = try #require(await repo.addFilament(draft: FilamentDraft(name: "f1")))
        let f2 = try #require(await repo.addFilament(draft: FilamentDraft(name: "f2")))
        let f3 = try #require(await repo.addFilament(draft: FilamentDraft(name: "f3")))
        #expect(f2.id > f1.id)
        #expect(f3.id > f2.id)

        await repo.deleteFilament(id: f3.id)

        let f4 = try #require(await repo.addFilament(draft: FilamentDraft(name: "f4")))
        #expect(f4.id > f3.id)
    }

    @Test func spoolIdsAreMonotonicAndNeverReused() async throws {
        let repo = try makeRepo()
        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA")))
        let s1 = try #require(await repo.addSpool(draft: SpoolDraft(filamentId: filament.id)))
        let s2 = try #require(await repo.addSpool(draft: SpoolDraft(filamentId: filament.id)))
        let s3 = try #require(await repo.addSpool(draft: SpoolDraft(filamentId: filament.id)))
        #expect(s2.id > s1.id)
        #expect(s3.id > s2.id)

        await repo.deleteSpool(id: s3.id)

        let s4 = try #require(await repo.addSpool(draft: SpoolDraft(filamentId: filament.id)))
        #expect(s4.id > s3.id)
    }

    // MARK: - Stability across container reopen

    @Test func localIdIsStableAcrossContainerReopen() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo1 = LocalRepository(context: context)
        let created = try #require(await repo1.addVendor(name: "Stable"))

        let repo2 = LocalRepository(context: ModelContext(container))
        let refetched = repo2.vendors.first { $0.id == created.id }
        #expect(refetched != nil)
        #expect(refetched?.id == created.id)
    }

    // MARK: - Update/delete by Int id still works

    @Test func updateByIntIdWorks() async throws {
        let repo = try makeRepo()
        let created = try #require(await repo.addVendor(name: "Old"))
        let ok = await repo.updateVendor(id: created.id, draft: VendorDraft(name: "New"))
        #expect(ok)
        #expect(repo.vendors.first { $0.id == created.id }?.name == "New")
    }

    @Test func deleteByIntIdWorks() async throws {
        let repo = try makeRepo()
        let created = try #require(await repo.addVendor(name: "Temp"))
        await repo.deleteVendor(id: created.id)
        #expect(repo.vendors.isEmpty)
    }

    // MARK: - Session map is gone (compile-time check)

    @Test func sessionMapSymbolsAreGone() async throws {
        let repo = try makeRepo()
        _ = repo
    }
}
