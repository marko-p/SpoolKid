//
//  LocationRegistrySaveFailureTests.swift
//  SpoolKidTests
//
//  Purpose: A `LocationRegistry` save that fails is rolled back and reported,
//  and `SpoolDataStore` turns it into a failure where the registry is the
//  only copy, or a notice where the backend's half succeeded. Saves are made
//  to fail with `SaveFailureInjection`.
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
struct LocationRegistrySaveFailureTests {
    private func makeRegistryContext() throws -> ModelContext {
        try SaveFailureInjection.makeContext(for: [LocationRegistryEntry.self])
    }

    private func storedNames(_ context: ModelContext) throws -> [String] {
        try context.fetch(FetchDescriptor<LocationRegistryEntry>()).map(\.name).sorted()
    }

    // MARK: - Registry writes

    @Test func addReportsAFailedSave() throws {
        let context = try makeRegistryContext()
        let registry = LocationRegistry(context: context, backendKind: .local)
        try SaveFailureInjection.arm(context)

        #expect(registry.add(name: "Shelf A") == nil)
        #expect(registry.errorMessage != nil)
        #expect(try storedNames(context).isEmpty)
        #expect(registry.records.isEmpty)
        #expect(!context.hasChanges)
    }

    @Test func adoptReportsAFailedSave() throws {
        let context = try makeRegistryContext()
        let registry = LocationRegistry(context: context, backendKind: .local)
        try SaveFailureInjection.arm(context)

        #expect(registry.adopt(uuid: UUID(), name: "Shelf A", tagUID: "04AA") == nil)
        #expect(try storedNames(context).isEmpty)
        #expect(!context.hasChanges)
    }

    @Test func adoptingIntoAnExistingEntryReportsAFailedSave() throws {
        let context = try makeRegistryContext()
        let registry = LocationRegistry(context: context, backendKind: .local)
        #expect(registry.add(name: "Shelf A") != nil)
        try SaveFailureInjection.arm(context)

        #expect(registry.adopt(uuid: UUID(), name: "Shelf A", tagUID: "04AA") == nil)
        #expect(registry.record(named: "Shelf A")?.tagUIDs == [])
        #expect(!context.hasChanges)
    }

    @Test func renameReportsAFailedSave() throws {
        let context = try makeRegistryContext()
        let registry = LocationRegistry(context: context, backendKind: .local)
        #expect(registry.add(name: "Shelf A") != nil)
        try SaveFailureInjection.arm(context)

        #expect(!registry.rename(from: "Shelf A", to: "Shelf B"))
        #expect(try storedNames(context) == ["Shelf A"])
        #expect(registry.records.map(\.name) == ["Shelf A"])
        #expect(!context.hasChanges)
    }

    @Test func removeReportsAFailedSave() throws {
        let context = try makeRegistryContext()
        let registry = LocationRegistry(context: context, backendKind: .local)
        #expect(registry.add(name: "Shelf A") != nil)
        try SaveFailureInjection.arm(context)

        #expect(!registry.remove(named: "Shelf A"))
        #expect(try storedNames(context) == ["Shelf A"])
        #expect(!context.hasChanges)
    }

    /// Nothing to remove is not a failure: a location the backend holds has
    /// no entry until a tag is written for it.
    @Test func removingAnUnregisteredNameSucceeds() throws {
        let registry = LocationRegistry(context: try makeRegistryContext(), backendKind: .local)

        #expect(registry.remove(named: "Shelf Z"))
    }

    @Test func attachTagReportsAFailedSave() throws {
        let context = try makeRegistryContext()
        let registry = LocationRegistry(context: context, backendKind: .local)
        let uuid = try #require(registry.add(name: "Shelf A")?.uuid)
        try SaveFailureInjection.arm(context)

        #expect(!registry.attachTag(uid: "04AA", to: uuid))
        #expect(registry.record(forTagUID: "04AA") == nil)
        #expect(!context.hasChanges)
    }

    @Test func attachTagToAnUnknownEntryFails() throws {
        let registry = LocationRegistry(context: try makeRegistryContext(), backendKind: .local)

        #expect(!registry.attachTag(uid: "04AA", to: UUID()))
    }

    @Test func detachTagReportsAFailedSave() throws {
        let context = try makeRegistryContext()
        let registry = LocationRegistry(context: context, backendKind: .local)
        #expect(registry.adopt(uuid: UUID(), name: "Shelf A", tagUID: "04AA") != nil)
        try SaveFailureInjection.arm(context)

        #expect(!registry.detachTag(uid: "04AA"))
        #expect(registry.record(forTagUID: "04AA")?.name == "Shelf A")
        #expect(!context.hasChanges)
    }

    // MARK: - Store: the registry is the only copy

    /// The backend's spools live in one context and the registry in another,
    /// armed one, so the backend's half of a write succeeds and only the
    /// registry's fails.
    private func makeStore() throws -> (SpoolDataStore, LocationRegistry, ModelContext) {
        let backend = try ModelContext(ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ))
        let registryContext = try makeRegistryContext()
        let registry = LocationRegistry(context: registryContext, backendKind: .local)
        let store = SpoolDataStore(repository: LocalRepository(context: backend), registry: registry)
        return (store, registry, registryContext)
    }

    /// A spool in `name`, so the backend knows the location.
    private func putASpool(in name: String, store: SpoolDataStore) async throws {
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        _ = try #require(await store.addSpool(draft: SpoolDraft(
            filamentId: filament.id, remainingWeight: .set(1000), location: .set(name)
        )))
        await store.fetchLocations()
    }

    @Test func addingADeviceOnlyLocationFailsWhenItCannotBeSaved() async throws {
        let (store, registry, context) = try makeStore()
        try SaveFailureInjection.arm(context)

        let outcome = await store.addLocation(name: "Shelf D")

        guard case .failed(let reason) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(reason.contains("Shelf D"))
        #expect(registry.records.isEmpty)
        #expect(store.saveNotice == nil)
    }

    @Test func renamingADeviceOnlyLocationFailsWithTheSaveError() async throws {
        let (store, registry, context) = try makeStore()
        #expect(await store.addLocation(name: "Shelf D") == .registeredOnDeviceOnly)
        try SaveFailureInjection.arm(context)

        #expect(!(await store.renameLocation(currentName: "Shelf D", newName: "Shelf Delta")))
        #expect(store.errorMessage == registry.errorMessage)
        #expect(store.errorMessage != nil)
        #expect(registry.records.map(\.name) == ["Shelf D"])
    }

    @Test func deletingADeviceOnlyLocationFailsWithTheSaveError() async throws {
        let (store, registry, context) = try makeStore()
        #expect(await store.addLocation(name: "Shelf D") == .registeredOnDeviceOnly)
        try SaveFailureInjection.arm(context)

        #expect(!(await store.deleteLocation("Shelf D")))
        #expect(store.errorMessage == registry.errorMessage)
        #expect(store.errorMessage != nil)
        #expect(registry.records.map(\.name) == ["Shelf D"])
    }

    @Test func matchAndForgetReportAFailedSave() async throws {
        let (store, registry, context) = try makeStore()
        #expect(await store.addLocation(name: "Shelf D") == .registeredOnDeviceOnly)

        try SaveFailureInjection.arm(context)
        #expect(!store.matchRegisteredLocation(currentName: "Shelf D", to: "Shelf Delta"))
        #expect(store.errorMessage != nil)
        try SaveFailureInjection.arm(context)
        #expect(!store.forgetRegisteredLocation(named: "Shelf D"))
        #expect(store.errorMessage != nil)

        #expect(registry.records.map(\.name) == ["Shelf D"])
    }

    @Test func adoptingADeviceOnlyLocationFailsWhenItCannotBeSaved() async throws {
        let (store, registry, context) = try makeStore()
        try SaveFailureInjection.arm(context)

        let outcome = await store.addLocation(name: "Shelf D", adoptingUUID: UUID(), tagUID: "04AA")

        guard case .failed = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(registry.records.isEmpty)
        #expect(store.saveNotice == nil)
    }

    /// The message describes the save that failed, not one before it.
    @Test func aSuccessfulSaveClearsTheLastError() throws {
        let context = try makeRegistryContext()
        let registry = LocationRegistry(context: context, backendKind: .local)
        try SaveFailureInjection.arm(context)
        #expect(registry.add(name: "Shelf A") == nil)

        #expect(registry.add(name: "Shelf B") != nil)
        #expect(registry.errorMessage == nil)
    }

    // MARK: - Store: the backend's half succeeded

    @Test func renamingABackendLocationSucceedsWithANoticeWhenTheRegistryCannotSave() async throws {
        let (store, registry, context) = try makeStore()
        try await putASpool(in: "Shelf A", store: store)
        #expect(await store.addLocation(name: "Shelf A") == .alreadyExists)
        try SaveFailureInjection.arm(context)

        #expect(await store.renameLocation(currentName: "Shelf A", newName: "Shelf Alpha"))

        #expect(store.spools.first?.location == "Shelf Alpha")
        #expect(registry.records.map(\.name) == ["Shelf A"])
        #expect(store.saveNotice?.entries.map(\.record) == ["Shelf Alpha"])
    }

    /// A backend location the registry never held: nothing failed, nothing to
    /// report.
    @Test func renamingAnUnregisteredBackendLocationPostsNoNotice() async throws {
        let (store, _, _) = try makeStore()
        try await putASpool(in: "Shelf A", store: store)

        #expect(await store.renameLocation(currentName: "Shelf A", newName: "Shelf Alpha"))
        #expect(store.saveNotice == nil)
    }

    @Test func deletingABackendLocationSucceedsWithANoticeWhenTheRegistryCannotSave() async throws {
        let (store, registry, context) = try makeStore()
        try await putASpool(in: "Shelf A", store: store)
        #expect(await store.addLocation(name: "Shelf A") == .alreadyExists)
        try SaveFailureInjection.arm(context)

        #expect(await store.deleteLocation("Shelf A"))

        #expect(store.spools.first?.location == nil)
        #expect(registry.records.map(\.name) == ["Shelf A"])
        #expect(store.saveNotice?.entries.map(\.record) == ["Shelf A"])
    }

    /// The location exists, so the outcome stands; the scanned tag is what
    /// was not linked, and the notice says so.
    @Test func adoptingATagForABackendLocationPostsANoticeWhenTheRegistryCannotSave() async throws {
        let (store, registry, context) = try makeStore()
        try await putASpool(in: "Shelf A", store: store)
        try SaveFailureInjection.arm(context)

        let outcome = await store.addLocation(name: "Shelf A", adoptingUUID: UUID(), tagUID: "04AA")

        #expect(outcome == .alreadyExists)
        #expect(registry.records.isEmpty)
        #expect(store.saveNotice?.entries.map(\.record) == ["Shelf A"])
    }

    /// The tag is on the shelf either way; what the notice reports is that a
    /// rename will not know to offer rewriting it.
    @Test func aWrittenTagThatCannotBeListedPostsANotice() async throws {
        let (store, registry, context) = try makeStore()
        #expect(await store.addLocation(name: "Shelf D") == .registeredOnDeviceOnly)
        let uuid = try #require(registry.records.first?.uuid)
        try SaveFailureInjection.arm(context)

        store.recordWrittenLocationTag(uid: "04AA", to: uuid, locationName: "Shelf D")

        #expect(registry.record(forTagUID: "04AA") == nil)
        #expect(store.saveNotice?.entries.map(\.record) == ["Shelf D"])
    }

    @Test func aWrittenTagIsListedWithoutANotice() async throws {
        let (store, registry, _) = try makeStore()
        #expect(await store.addLocation(name: "Shelf D") == .registeredOnDeviceOnly)
        let uuid = try #require(registry.records.first?.uuid)

        store.recordWrittenLocationTag(uid: "04AA", to: uuid, locationName: "Shelf D")

        #expect(registry.record(forTagUID: "04AA")?.name == "Shelf D")
        #expect(store.saveNotice == nil)
    }

    /// Without a tag there is nothing the user asked for that is missing: the
    /// entry is made when a tag is first written, and that path reports its
    /// own failure (`LocationDetailView.startTagWrite`).
    @Test func addingABackendLocationWithoutATagPostsNoNotice() async throws {
        let (store, _, context) = try makeStore()
        try await putASpool(in: "Shelf A", store: store)
        try SaveFailureInjection.arm(context)

        #expect(await store.addLocation(name: "Shelf A") == .alreadyExists)
        #expect(store.saveNotice == nil)
    }
}
