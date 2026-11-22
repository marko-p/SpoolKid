//
//  LocationRegistrySyncTests.swift
//  SpoolKidTests
//
//  Purpose: `SpoolDataStore` is the single place that keeps the device-local
//  registry in step with renames, deletes and creates, so no repository has to.
//

import Foundation
import SwiftData
import Testing
@testable import SpoolKid

@MainActor
struct LocationRegistrySyncTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self,
                 LocalIdSequence.self, LocationRegistryEntry.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeStore(_ context: ModelContext) -> (SpoolDataStore, LocationRegistry) {
        let registry = LocationRegistry(context: context, backendKind: .local)
        let store = SpoolDataStore(repository: LocalRepository(context: context), registry: registry)
        return (store, registry)
    }

    @Test func addLocationRegistersTheNameOnADerivedBackend() async throws {
        let (store, registry) = makeStore(try makeContext())

        let outcome = await store.addLocation(name: "Shelf D")

        #expect(outcome == .registeredOnDeviceOnly)
        #expect(registry.records.map(\.name) == ["Shelf D"])
        #expect(store.registeredLocations.map(\.name) == ["Shelf D"])
    }

    @Test func addLocationDoesNotRegisterAFailedCreate() async throws {
        let (store, registry) = makeStore(try makeContext())

        let outcome = await store.addLocation(name: "   ")

        #expect(outcome == .failed("A location needs a name."))
        #expect(registry.records.isEmpty)
    }

    @Test func renameLocationCarriesTheRegistryEntryWithIt() async throws {
        let (store, registry) = makeStore(try makeContext())
        await store.addLocation(name: "Shelf A")
        let uuid = try #require(registry.records.first?.uuid)

        _ = await store.renameLocation(currentName: "Shelf A", newName: "Shelf Alpha")

        #expect(registry.records.map(\.name) == ["Shelf Alpha"])
        #expect(registry.records.first?.uuid == uuid)
    }

    @Test func deleteLocationDropsTheRegistryEntry() async throws {
        let (store, registry) = makeStore(try makeContext())
        await store.addLocation(name: "Shelf A")

        _ = await store.deleteLocation("Shelf A")

        #expect(registry.records.isEmpty)
    }

    @Test func deletingSeveralLocationsDropsEveryNamedRegistryEntry() async throws {
        let (store, registry) = makeStore(try makeContext())
        await store.addLocation(name: "Shelf A")
        await store.addLocation(name: "Shelf B")
        await store.addLocation(name: "Shelf C")

        _ = await store.deleteLocation("Shelf A")
        _ = await store.deleteLocation("Shelf C")

        #expect(registry.records.map(\.name) == ["Shelf B"])
    }

    @Test func aStoreWithNoRegistryStillWorksAndReportsNoRecords() async throws {
        let store = SpoolDataStore(repository: LocalRepository(context: try makeContext()))

        let outcome = await store.addLocation(name: "Shelf D")

        #expect(outcome == .registeredOnDeviceOnly)
        #expect(store.registeredLocations.isEmpty)
    }

    @Test func matchRepointsTheRegistryEntryWithoutTouchingTheBackend() async throws {
        let context = try makeContext()
        let (store, registry) = makeStore(context)
        await store.addLocation(name: "Shelf A")
        let uuid = try #require(registry.records.first?.uuid)

        store.matchRegisteredLocation(currentName: "Shelf A", to: "Shelf Alpha")

        #expect(registry.records.map(\.name) == ["Shelf Alpha"])
        #expect(registry.records.first?.uuid == uuid)
        // The backend was never asked to rename anything — no spool moved.
        #expect(store.spools.isEmpty)
    }

    @Test func forgetDropsTheEntryOnly() async throws {
        let (store, registry) = makeStore(try makeContext())
        await store.addLocation(name: "Shelf A")

        store.forgetRegisteredLocation(named: "Shelf A")

        #expect(registry.records.isEmpty)
    }

    /// A tag written on another device carries a uuid this device has never
    /// seen. Registering under a FRESH one would leave that tag unrecognised on
    /// every future scan, however many times "Add" is tapped.
    @Test func addLocationAdoptsAScannedTagsUUIDAndRecordsItsUID() async throws {
        let (store, registry) = makeStore(try makeContext())
        let uuid = UUID()

        let outcome = await store.addLocation(name: "Shelf D", adoptingUUID: uuid, tagUID: "aabbccdd")

        #expect(outcome == .registeredOnDeviceOnly)
        #expect(registry.records.first?.uuid == uuid)
        #expect(registry.records.first?.tagUIDs == ["AABBCCDD"])
    }

    @Test func addLocationWithNoAdoptedUUIDStillMintsAFreshOne() async throws {
        let (store, registry) = makeStore(try makeContext())

        await store.addLocation(name: "Shelf D")

        #expect(registry.records.count == 1)
        #expect(registry.records.first?.tagUIDs.isEmpty == true)
    }

    /// I7: a location that exists ONLY in the registry has no server half to
    /// rename — Spoolman's `PATCH /location/<name>` fails for a name no spool
    /// references. The rename must succeed as a registry-only operation, so the
    /// tag-rewrite offer that follows a successful rename can fire.
    @Test func renamingAPendingOnDeviceLocationSucceedsWithoutABackendWrite() async throws {
        let (store, registry) = makeStore(try makeContext())
        await store.addLocation(name: "Shelf D")
        let uuid = try #require(registry.records.first?.uuid)
        let writesBefore = store.writeCount

        let renamed = await store.renameLocation(currentName: "Shelf D", newName: "Shelf Delta")

        #expect(renamed)
        #expect(registry.records.map(\.name) == ["Shelf Delta"])
        #expect(registry.records.first?.uuid == uuid)
        // No repository call was made, so nothing was counted as written.
        #expect(store.writeCount == writesBefore)
    }

    @Test func renamingAPendingLocationThatIsNotRegisteredReportsFailure() async throws {
        let (store, _) = makeStore(try makeContext())

        #expect(await store.renameLocation(currentName: "Shelf Z", newName: "Shelf Zeta") == false)
    }

    /// The other side of the same branch: once a spool names the location, the
    /// backend knows it and the repository does the rename as before.
    @Test func renamingALocationASpoolIsInGoesThroughTheBackend() async throws {
        let (store, registry) = makeStore(try makeContext())
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA")))
        _ = await store.addSpool(draft: SpoolDraft(
            filamentId: filament.id, remainingWeight: .set(1000), location: .set("Shelf A")
        ))
        await store.addLocation(name: "Shelf A")
        await store.fetchLocations()

        let renamed = await store.renameLocation(currentName: "Shelf A", newName: "Shelf Alpha")

        #expect(renamed)
        #expect(registry.records.map(\.name) == ["Shelf Alpha"])
        #expect(store.spools.first?.location == "Shelf Alpha")
    }

    @Test func syncStateIsInSyncForALocationWithNoRegistryEntry() throws {
        let (store, _) = makeStore(try makeContext())

        #expect(store.syncState(forLocationNamed: "Shelf Z") == .inSync)
    }

    @Test func syncStateReportsAnUntaggedRegistryOnlyLocationAsPending() async throws {
        let (store, _) = makeStore(try makeContext())
        await store.addLocation(name: "Shelf D")

        #expect(store.syncState(forLocationNamed: "Shelf D") == .pendingOnDevice)
    }

    @Test func renameCarriesTheArrangementPositionToo() async throws {
        let suite = "LocationRegistrySyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let context = try makeContext()
        let orderStore = LocationOrderStore(backendKind: .local, defaults: defaults)
        let store = SpoolDataStore(
            repository: LocalRepository(context: context),
            registry: LocationRegistry(context: context, backendKind: .local),
            order: orderStore
        )
        await store.addLocation(name: "Shelf A")
        orderStore.move("Shelf A", to: 0, within: ["Shelf A", "Shelf B"])

        _ = await store.renameLocation(currentName: "Shelf A", newName: "Shelf Alpha")

        #expect(orderStore.order.keys.first == "shelf alpha")
    }

    @Test func matchingARegistryEntryCarriesTheArrangementPositionToo() async throws {
        let suite = "LocationRegistrySyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let context = try makeContext()
        let orderStore = LocationOrderStore(backendKind: .local, defaults: defaults)
        let store = SpoolDataStore(
            repository: LocalRepository(context: context),
            registry: LocationRegistry(context: context, backendKind: .local),
            order: orderStore
        )
        await store.addLocation(name: "Shelf A")
        orderStore.move("Shelf A", to: 0, within: ["Shelf A", "Shelf B"])

        store.matchRegisteredLocation(currentName: "Shelf A", to: "Rack One")

        #expect(orderStore.order.keys.first == "rack one")
    }
}
