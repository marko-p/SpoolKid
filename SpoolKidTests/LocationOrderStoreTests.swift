//
//  LocationOrderStoreTests.swift
//  SpoolKidTests
//
//  Purpose: The arrangement survives a relaunch, and one backend's shelves
//  never shuffle another's.
//

import Combine
import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct LocationOrderStoreTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "LocationOrderStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func anUntouchedStoreHasNoOpinion() {
        let store = LocationOrderStore(backendKind: .spoolman, defaults: makeDefaults())

        #expect(store.order.keys.isEmpty)
        #expect(store.order.arranged(["Shelf B", "Shelf A"]) == ["Shelf A", "Shelf B"])
    }

    @Test func aMoveSurvivesARelaunch() {
        let defaults = makeDefaults()
        let first = LocationOrderStore(backendKind: .spoolman, defaults: defaults)

        first.move("Shelf C", to: 0, within: ["Shelf A", "Shelf B", "Shelf C"])

        let second = LocationOrderStore(backendKind: .spoolman, defaults: defaults)
        #expect(second.order.arranged(["Shelf A", "Shelf B", "Shelf C"]) == ["Shelf C", "Shelf A", "Shelf B"])
    }

    @Test func eachBackendKeepsItsOwnArrangement() {
        let defaults = makeDefaults()
        let spoolman = LocationOrderStore(backendKind: .spoolman, defaults: defaults)
        let filaman = LocationOrderStore(backendKind: .filaman, defaults: defaults)

        spoolman.move("Shelf C", to: 0, within: ["Shelf A", "Shelf B", "Shelf C"])

        #expect(filaman.order.keys.isEmpty)
        #expect(LocationOrderStore(backendKind: .filaman, defaults: defaults).order.keys.isEmpty)
    }

    @Test func aRenameCarriesTheShelfsPositionAndPersists() {
        let defaults = makeDefaults()
        let store = LocationOrderStore(backendKind: .local, defaults: defaults)
        store.move("Shelf C", to: 0, within: ["Shelf A", "Shelf B", "Shelf C"])

        store.rename(from: "Shelf C", to: "Bin Gamma")

        let reloaded = LocationOrderStore(backendKind: .local, defaults: defaults)
        #expect(reloaded.order.arranged(["Shelf A", "Shelf B", "Bin Gamma"]) == ["Bin Gamma", "Shelf A", "Shelf B"])
    }

    @Test func pruneForgetsShelvesAndPersistsTheForgetting() {
        let defaults = makeDefaults()
        let store = LocationOrderStore(backendKind: .local, defaults: defaults)
        store.move("Shelf C", to: 0, within: ["Shelf A", "Shelf B", "Shelf C"])

        store.prune(keeping: ["Shelf A", "Shelf C"])

        #expect(LocationOrderStore(backendKind: .local, defaults: defaults).order.keys == ["shelf c", "shelf a"])
    }

    @Test func aPruneThatChangesNothingDoesNotRepublish() {
        let defaults = makeDefaults()
        let store = LocationOrderStore(backendKind: .local, defaults: defaults)
        store.move("Shelf B", to: 0, within: ["Shelf A", "Shelf B"])

        var emissions = 0
        let subscription = store.objectWillChange.sink { _ in emissions += 1 }

        store.prune(keeping: ["Shelf A", "Shelf B"])
        #expect(emissions == 0)

        store.prune(keeping: ["Shelf B"])
        #expect(emissions == 1)

        subscription.cancel()
    }

    @Test func corruptStoredDataIsIgnoredRatherThanCrashing() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: AppConfig.locationManualOrderKey)

        let store = LocationOrderStore(backendKind: .local, defaults: defaults)

        #expect(store.order.keys.isEmpty)
    }
}
