//
//  SpoolBatchTests.swift
//  SpoolKidTests
//
//  Purpose: `SpoolBatch` and `SpoolDataStore.addSpools(drafts:)` — Add Spools
//  creates N identical spools in order, stops at the first one that does not
//  confirm, keeps each caveat once, and gives only the first spool the tags.
//  In-memory store.
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
struct SpoolBatchTests {
    private func makeRepository(quotaLimit: Int? = nil) throws -> LocalRepository {
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return LocalRepository(context: ModelContext(container), quotaLimit: quotaLimit)
    }

    private func defaults(mode: TagIdentityMode) -> UserDefaults {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(mode.rawValue, forKey: AppConfig.tagIdentityModeKey)
        return defaults
    }

    @Test func createsEachSpoolInOrder() async throws {
        let store = SpoolDataStore(repository: try makeRepository(), defaults: defaults(mode: .tagLinks))
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        let drafts = Array(repeating: SpoolDraft(filamentId: filament.id), count: 3)

        let result = await store.addSpools(drafts: drafts)

        #expect(result.created.count == 3)
        // Strictly increasing also means distinct: a sort alone passes for repeats.
        let ids = result.created.map(\.id)
        #expect(zip(ids, ids.dropFirst()).allSatisfy { $0 < $1 })
        #expect(result.failure == nil)
        #expect(store.spools.count == 3)
        #expect(result.outcome == .saved)
    }

    /// Count 1 is the single-spool save it always was: the batch path adds nothing to it.
    @Test func aBatchOfOneIsASingleCreate() async throws {
        let batchStore = SpoolDataStore(repository: try makeRepository(), defaults: defaults(mode: .tagLinks))
        let singleStore = SpoolDataStore(repository: try makeRepository(), defaults: defaults(mode: .tagLinks))
        let batchFilament = try #require(await batchStore.addFilament(draft: FilamentDraft(name: "PLA")))
        let singleFilament = try #require(await singleStore.addFilament(draft: FilamentDraft(name: "PLA")))
        func draft(for filament: Filament) -> SpoolDraft {
            var draft = SpoolDraft(filamentId: filament.id)
            draft.initialWeight = .set(1000)
            draft.spoolWeight = .set(250)
            draft.cardUIDs = ["04AA"]
            return draft
        }

        let batch = await batchStore.addSpools(drafts: SpoolBatch.drafts(from: draft(for: batchFilament), count: 1))
        let single = try #require(await singleStore.addSpool(draft: draft(for: singleFilament)))

        let created = try #require(batch.created.first)
        #expect(batch.created.count == 1)
        #expect(batch.failure == nil)
        #expect(created.filament.id == single.filament.id)
        #expect(created.initialWeight == single.initialWeight)
        #expect(created.spoolWeight == single.spoolWeight)
        #expect(created.mappedCardUIDs == single.mappedCardUIDs)
    }

    @Test func stopsAtTheFirstFailureAndSaysWhere() async throws {
        let store = SpoolDataStore(repository: try makeRepository(quotaLimit: 2), defaults: defaults(mode: .tagLinks))
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        let drafts = Array(repeating: SpoolDraft(filamentId: filament.id), count: 4)

        let result = await store.addSpools(drafts: drafts)

        #expect(result.created.count == 2)
        #expect(result.failure == SpoolBatchFailure(position: 3, total: 4,
            reason: QuotaError(entity: .spools, limit: 2).errorDescription!))
        #expect(store.spools.count == 2)
        let failure = try #require(result.failure)
        #expect(result.outcome == .savedWithCaveat(
            SpoolBatch.incompleteMessage(createdIDs: result.created.map(\.id), failure: failure)))
    }

    /// A partial batch's stop message leads, and the create caveats that landed follow it.
    @Test func partialBatchKeepsCreateCaveatsAfterTheStopMessage() async throws {
        let store = SpoolDataStore(repository: try makeRepository(quotaLimit: 2), defaults: defaults(mode: .neither))
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        var draft = SpoolDraft(filamentId: filament.id)
        draft.cardUIDs = ["04AA"]

        let result = await store.addSpools(drafts: SpoolBatch.drafts(from: draft, count: 3))

        #expect(result.created.count == 2)
        let failure = try #require(result.failure)
        let caveat = try #require(result.outcome.caveat)
        #expect(caveat.hasPrefix(SpoolBatch.incompleteMessage(createdIDs: result.created.map(\.id), failure: failure)))
        #expect(caveat.contains("04AA"))
    }

    @Test func nothingCreatedIsNotSaved() async throws {
        // The quota caps filaments too, so a limit of 1 still fits the one filament.
        let store = SpoolDataStore(repository: try makeRepository(quotaLimit: 1), defaults: defaults(mode: .tagLinks))
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        await store.addSpool(draft: SpoolDraft(filamentId: filament.id))
        let drafts = Array(repeating: SpoolDraft(filamentId: filament.id), count: 2)

        let result = await store.addSpools(drafts: drafts)

        #expect(result.created.isEmpty)
        #expect(result.failure?.position == 1)
        #expect(result.outcome == .notSaved(QuotaError(entity: .spools, limit: 1).errorDescription!))
    }

    @Test func onlyTheFirstDraftCarriesTags() {
        var draft = SpoolDraft(filamentId: 1)
        draft.cardUIDs = ["04AA"]

        #expect(SpoolBatch.drafts(from: draft, count: 3).map(\.cardUIDs) == [["04AA"], nil, nil])
        #expect(SpoolBatch.drafts(from: draft, count: 1).map(\.cardUIDs) == [["04AA"]])
    }

    @Test func theFirstSpoolGetsItsTags() async throws {
        let store = SpoolDataStore(repository: try makeRepository(), defaults: defaults(mode: .tagLinks))
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        var draft = SpoolDraft(filamentId: filament.id)
        draft.cardUIDs = ["04AA"]

        let result = await store.addSpools(drafts: SpoolBatch.drafts(from: draft, count: 2))

        try #require(result.created.count == 2)
        #expect(result.created[0].mappedCardUIDs == ["04AA"])
        #expect(result.created[1].mappedCardUIDs == [])
    }

    @Test func aCreateCaveatIsKept() async throws {
        let store = SpoolDataStore(repository: try makeRepository(), defaults: defaults(mode: .neither))
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        var draft = SpoolDraft(filamentId: filament.id)
        draft.cardUIDs = ["04AA"]

        let result = await store.addSpools(drafts: SpoolBatch.drafts(from: draft, count: 2))

        #expect(result.created.count == 2)
        try #require(result.caveats.count == 1)
        #expect(result.caveats[0].contains("04AA"))
        #expect(result.outcome.caveat != nil)
    }

    /// A complete batch's caveat is a banner; nothing stopped, so no alert.
    @Test func completeBatchRoutesItsCaveatToTheBanner() async throws {
        let store = SpoolDataStore(repository: try makeRepository(), defaults: defaults(mode: .neither))
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        var draft = SpoolDraft(filamentId: filament.id)
        draft.cardUIDs = ["04AA"]

        let result = await store.addSpools(drafts: SpoolBatch.drafts(from: draft, count: 2))

        #expect(result.failure == nil)
        #expect(result.bannerCaveat != nil)
        #expect(result.stopAlertMessage == nil)
    }

    /// A partial batch's caveat is the alert's message, and the banner stays empty.
    @Test func partialBatchRoutesItsStopToTheAlert() async throws {
        let store = SpoolDataStore(repository: try makeRepository(quotaLimit: 2), defaults: defaults(mode: .neither))
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        var draft = SpoolDraft(filamentId: filament.id)
        draft.cardUIDs = ["04AA"]

        let result = await store.addSpools(drafts: SpoolBatch.drafts(from: draft, count: 4))

        let failure = try #require(result.failure)
        #expect(result.bannerCaveat == nil)
        #expect(result.stopAlertMessage == result.outcome.caveat)
        let message = try #require(result.stopAlertMessage)
        #expect(message.hasPrefix(SpoolBatch.incompleteMessage(createdIDs: result.created.map(\.id), failure: failure)))
        #expect(message.contains("04AA"))
    }

    /// Nothing landed, so there is neither a banner nor a stop alert: the form shows its failure alert.
    @Test func nothingCreatedRoutesNowhere() async throws {
        let store = SpoolDataStore(repository: try makeRepository(quotaLimit: 1), defaults: defaults(mode: .tagLinks))
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        await store.addSpool(draft: SpoolDraft(filamentId: filament.id))

        let result = await store.addSpools(drafts: Array(repeating: SpoolDraft(filamentId: filament.id), count: 2))

        #expect(result.created.isEmpty)
        #expect(result.bannerCaveat == nil)
        #expect(result.stopAlertMessage == nil)
    }

    @Test func incompleteMessageNamesWhatExists() {
        let reason = "Spool was created, but its filament could not be found locally. Refresh to see it."
        #expect(SpoolBatch.incompleteMessage(createdIDs: [12, 13],
            failure: SpoolBatchFailure(position: 3, total: 5, reason: reason))
            == "Created #12 and #13. Spool 3 of 5: \(reason) The last 2 spools were not created.")
        #expect(SpoolBatch.incompleteMessage(createdIDs: [12],
            failure: SpoolBatchFailure(position: 2, total: 3, reason: "Server error"))
            == "Created #12. Spool 2 of 3: Server error. The last spool was not created.")
        #expect(SpoolBatch.incompleteMessage(createdIDs: [12, 13, 14],
            failure: SpoolBatchFailure(position: 4, total: 4, reason: "Timed out."))
            == "Created #12, #13 and #14. Spool 4 of 4: Timed out.")
    }

    /// What the form's first tap gates on: only a batch with nothing missing goes on to write or scan.
    @Test func completenessSaysHowMuchOfTheBatchExists() async throws {
        let complete = SpoolDataStore(repository: try makeRepository(), defaults: defaults(mode: .tagLinks))
        let filament = try #require(await complete.addFilament(draft: FilamentDraft(name: "PLA")))
        let all = await complete.addSpools(drafts: Array(repeating: SpoolDraft(filamentId: filament.id), count: 3))
        #expect(all.completeness == .complete)

        let partial = SpoolDataStore(repository: try makeRepository(quotaLimit: 2), defaults: defaults(mode: .tagLinks))
        let partialFilament = try #require(await partial.addFilament(draft: FilamentDraft(name: "PLA")))
        let some = await partial.addSpools(drafts: Array(repeating: SpoolDraft(filamentId: partialFilament.id), count: 4))
        #expect(some.completeness == .partial)

        let full = SpoolDataStore(repository: try makeRepository(quotaLimit: 1), defaults: defaults(mode: .tagLinks))
        let fullFilament = try #require(await full.addFilament(draft: FilamentDraft(name: "PLA")))
        await full.addSpool(draft: SpoolDraft(filamentId: fullFilament.id))
        let none = await full.addSpools(drafts: Array(repeating: SpoolDraft(filamentId: fullFilament.id), count: 2))
        #expect(none.completeness == SpoolBatchCompleteness.none)
    }
}
