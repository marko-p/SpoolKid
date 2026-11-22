//
//  EmptySpoolLibraryTests.swift
//  SpoolKidTests
//
//  Purpose: `EmptySpoolLibrary` — the device-local library of empty-spool
//  weights: writes report failure, one default at most, default-first order,
//  and Reset All Data empties it. In-memory store.
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
struct EmptySpoolLibraryTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: EmptySpoolEntry.self, configurations: config)
        return ModelContext(container)
    }

    private func makeLibrary() throws -> EmptySpoolLibrary {
        EmptySpoolLibrary(context: try makeContext())
    }

    private let photo = Data([0xFF, 0xD8, 0xFF, 0xE0])

    // MARK: - Writes

    @Test func addAppearsInEntries() throws {
        let library = try makeLibrary()

        #expect(library.add(name: "Bambu reusable", weight: 250, photo: photo, isDefault: false))

        #expect(library.entries.count == 1)
        let entry = try #require(library.entries.first)
        #expect(entry.name == "Bambu reusable")
        #expect(entry.weight == 250)
        #expect(entry.photo == photo)
        #expect(!entry.isDefault)
    }

    @Test func addTrimsTheName() throws {
        let library = try makeLibrary()

        #expect(library.add(name: "  Sunlu cardboard \n", weight: 132.5, photo: nil, isDefault: false))

        #expect(library.entries.map(\.name) == ["Sunlu cardboard"])
    }

    @Test func updateChangesNameWeightAndPhoto() throws {
        let library = try makeLibrary()
        #expect(library.add(name: "Old", weight: 100, photo: nil, isDefault: false))
        let id = try #require(library.entries.first?.id)

        #expect(library.update(id, manufacturer: "", name: "New", weight: 180, photo: photo, isDefault: false, isManufacturerDefault: false))

        let entry = try #require(library.entries.first)
        #expect(entry.id == id)
        #expect(entry.name == "New")
        #expect(entry.weight == 180)
        #expect(entry.photo == photo)
    }

    @Test func updateCanRemoveThePhoto() throws {
        let library = try makeLibrary()
        #expect(library.add(name: "Spool", weight: 100, photo: photo, isDefault: false))
        let id = try #require(library.entries.first?.id)

        #expect(library.update(id, manufacturer: "", name: "Spool", weight: 100, photo: nil, isDefault: false, isManufacturerDefault: false))

        #expect(library.entries.first?.photo == nil)
    }

    @Test func deleteRemovesTheEntry() throws {
        let library = try makeLibrary()
        #expect(library.add(name: "Gone", weight: 100, photo: nil, isDefault: false))
        let id = try #require(library.entries.first?.id)

        #expect(library.delete(id))

        #expect(library.entries.isEmpty)
    }

    @Test func writesToAnUnknownEntryFail() throws {
        let library = try makeLibrary()
        let unknown = UUID()

        #expect(!library.update(unknown, manufacturer: "", name: "X", weight: 1, photo: nil, isDefault: false, isManufacturerDefault: false))
        #expect(!library.delete(unknown))
        #expect(!library.setDefault(unknown))
        #expect(library.entries.isEmpty)
    }

    @Test func aFailedSaveStoresNothingAndLeavesNothingPending() throws {
        let context = try SaveFailureInjection.makeContext(for: [EmptySpoolEntry.self])
        let library = EmptySpoolLibrary(context: context)
        #expect(library.add(name: "Kept", weight: 250, photo: nil, isDefault: false))
        try SaveFailureInjection.arm(context)

        #expect(!library.add(name: "Lost", weight: 200, photo: nil, isDefault: false))
        #expect(library.entries.map(\.name) == ["Kept"])
        #expect(!context.hasChanges)
    }

    @Test func manufacturerIsOptionalAndStoredTrimmed() throws {
        let library = try makeLibrary()

        #expect(library.add(manufacturer: "  Elegoo ", name: "Cardboard", weight: 132, photo: nil, isDefault: false))
        #expect(library.add(name: "Refill ring", weight: 40, photo: nil, isDefault: false))

        #expect(library.entries.map(\.manufacturer) == ["Elegoo", ""])
        #expect(library.entries.map(\.listTitle) == ["Elegoo Cardboard", "Refill ring"])
    }

    @Test func updateChangesAndClearsTheManufacturer() throws {
        let library = try makeLibrary()
        #expect(library.add(manufacturer: "Sunlu", name: "Cardboard", weight: 130, photo: nil, isDefault: false))
        let id = try #require(library.entries.first?.id)

        #expect(library.update(id, manufacturer: "Elegoo", name: "Cardboard", weight: 130, photo: nil, isDefault: false, isManufacturerDefault: false))
        #expect(library.entries.first?.manufacturer == "Elegoo")

        #expect(library.update(id, manufacturer: "  ", name: "Cardboard", weight: 130, photo: nil, isDefault: false, isManufacturerDefault: false))
        #expect(library.entries.first?.manufacturer == "")
    }

    @Test func entriesSortByManufacturerAndName() throws {
        let library = try makeLibrary()
        #expect(library.add(manufacturer: "Sunlu", name: "cardboard", weight: 1, photo: nil, isDefault: false))
        #expect(library.add(name: "Bambu reusable", weight: 2, photo: nil, isDefault: false))
        #expect(library.add(manufacturer: "Elegoo", name: "plastic", weight: 3, photo: nil, isDefault: false))

        #expect(library.entries.map(\.listTitle) == ["Bambu reusable", "Elegoo plastic", "Sunlu cardboard"])
    }

    // MARK: - Validation

    @Test func invalidAddsStoreNothing() throws {
        let library = try makeLibrary()

        #expect(!library.add(name: "", weight: 100, photo: nil, isDefault: false))
        #expect(!library.add(name: "   ", weight: 100, photo: nil, isDefault: false))
        #expect(!library.add(name: "Negative", weight: -1, photo: nil, isDefault: false))
        #expect(!library.add(name: "Infinite", weight: .infinity, photo: nil, isDefault: false))
        #expect(!library.add(name: "NaN", weight: .nan, photo: nil, isDefault: false))

        #expect(library.entries.isEmpty)
    }

    @Test func zeroGramsIsValid() throws {
        let library = try makeLibrary()

        #expect(library.add(name: "Refill, no spool", weight: 0, photo: nil, isDefault: false))

        #expect(library.entries.first?.weight == 0)
    }

    @Test func anInvalidUpdateLeavesTheEntryUnchanged() throws {
        let library = try makeLibrary()
        #expect(library.add(name: "Keep", weight: 200, photo: nil, isDefault: false))
        let id = try #require(library.entries.first?.id)

        #expect(!library.update(id, manufacturer: "", name: " ", weight: 200, photo: nil, isDefault: false, isManufacturerDefault: false))
        #expect(!library.update(id, manufacturer: "", name: "Keep", weight: -5, photo: nil, isDefault: false, isManufacturerDefault: false))

        #expect(library.entries.first?.name == "Keep")
        #expect(library.entries.first?.weight == 200)
    }

    @Test func isValidNeedsANameAndAFiniteNonNegativeWeight() {
        #expect(EmptySpoolLibrary.isValid(name: "A", weight: 0))
        #expect(EmptySpoolLibrary.isValid(name: "A", weight: 250.5))
        #expect(!EmptySpoolLibrary.isValid(name: "A", weight: nil))
        #expect(!EmptySpoolLibrary.isValid(name: "A", weight: -0.1))
        #expect(!EmptySpoolLibrary.isValid(name: "A", weight: .infinity))
        #expect(!EmptySpoolLibrary.isValid(name: " ", weight: 100))
    }

    // MARK: - Default

    @Test func setDefaultMarksOneAndClearsThePrevious() throws {
        let library = try makeLibrary()
        #expect(library.add(name: "A", weight: 100, photo: nil, isDefault: false))
        #expect(library.add(name: "B", weight: 200, photo: nil, isDefault: false))
        let a = try #require(library.entries.first { $0.name == "A" }?.id)
        let b = try #require(library.entries.first { $0.name == "B" }?.id)

        #expect(library.setDefault(a))
        #expect(library.defaultEntry?.id == a)

        #expect(library.setDefault(b))
        #expect(library.defaultEntry?.id == b)
        #expect(library.entries.filter(\.isDefault).count == 1)
    }

    @Test func addingADefaultClearsThePreviousDefault() throws {
        let library = try makeLibrary()
        #expect(library.add(name: "A", weight: 100, photo: nil, isDefault: true))
        #expect(library.add(name: "B", weight: 200, photo: nil, isDefault: true))

        #expect(library.defaultEntry?.name == "B")
        #expect(library.entries.filter(\.isDefault).count == 1)
    }

    @Test func updatingToDefaultClearsThePreviousDefault() throws {
        let library = try makeLibrary()
        #expect(library.add(name: "A", weight: 100, photo: nil, isDefault: true))
        #expect(library.add(name: "B", weight: 200, photo: nil, isDefault: false))
        let b = try #require(library.entries.first { $0.name == "B" }?.id)

        #expect(library.update(b, manufacturer: "", name: "B", weight: 200, photo: nil, isDefault: true, isManufacturerDefault: false))

        #expect(library.defaultEntry?.name == "B")
        #expect(library.entries.filter(\.isDefault).count == 1)
    }

    @Test func setDefaultNilClearsTheDefault() throws {
        let library = try makeLibrary()
        #expect(library.add(name: "A", weight: 100, photo: nil, isDefault: true))

        #expect(library.setDefault(nil))

        #expect(library.defaultEntry == nil)
    }

    @Test func deletingTheDefaultLeavesNoDefault() throws {
        let library = try makeLibrary()
        #expect(library.add(name: "A", weight: 100, photo: nil, isDefault: true))
        #expect(library.add(name: "B", weight: 200, photo: nil, isDefault: false))
        let a = try #require(library.defaultEntry?.id)

        #expect(library.delete(a))

        #expect(library.defaultEntry == nil)
        #expect(library.entries.map(\.name) == ["B"])
    }

    // MARK: - Order and persistence

    @Test func entriesAreDefaultFirstThenNameAToZ() throws {
        let library = try makeLibrary()
        #expect(library.add(name: "bravo", weight: 1, photo: nil, isDefault: false))
        #expect(library.add(name: "Alpha", weight: 2, photo: nil, isDefault: false))
        #expect(library.add(name: "charlie", weight: 3, photo: nil, isDefault: true))

        #expect(library.entries.map(\.name) == ["charlie", "Alpha", "bravo"])
    }

    /// A backend switch rebuilds `ContentView`, which builds a new library
    /// over the same store.
    @Test func aNewLibraryOverTheSameStoreSeesTheEntries() throws {
        let context = try makeContext()
        let first = EmptySpoolLibrary(context: context)
        #expect(first.add(name: "Kept", weight: 210, photo: nil, isDefault: true))

        let second = EmptySpoolLibrary(context: context)

        #expect(second.entries.map(\.name) == ["Kept"])
        #expect(second.defaultEntry?.weight == 210)
    }

    // MARK: - Reset All Data, and what survives a migration

    private func makeFullContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self,
                 LocalIdSequence.self, LocationRegistryEntry.self, EmptySpoolEntry.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test func wipeEmptySpoolLibraryDeletesEveryEntry() throws {
        let context = try makeFullContext()
        let library = EmptySpoolLibrary(context: context)
        #expect(library.add(name: "Wiped", weight: 100, photo: nil, isDefault: true))
        #expect(library.add(name: "Also wiped", weight: 120, photo: nil, isDefault: false))

        SpoolKidApp.wipeEmptySpoolLibrary(context)

        #expect(try context.fetchCount(FetchDescriptor<EmptySpoolEntry>()) == 0)
    }

    /// `wipeLocalStore` also runs after a completed Library → server migration
    /// (`MigrationService`). The library belongs to the device, so it stays.
    @Test func wipeLocalStoreKeepsTheEmptySpoolLibrary() throws {
        let context = try makeFullContext()
        let library = EmptySpoolLibrary(context: context)
        #expect(library.add(name: "Kept", weight: 100, photo: nil, isDefault: true))

        SpoolKidApp.wipeLocalStore(context)

        #expect(try context.fetchCount(FetchDescriptor<EmptySpoolEntry>()) == 1)
    }

    // MARK: - Brand defaults

    private func named(_ name: String, in library: EmptySpoolLibrary) throws -> EmptySpoolRecord {
        try #require(library.entries.first { $0.name == name })
    }

    @Test func markingABrandDefaultUnmarksThatBrandsPrevious() throws {
        let library = try makeLibrary()
        #expect(library.add(manufacturer: "Polymaker", name: "A", weight: 140, photo: nil, isDefault: false, isManufacturerDefault: true))
        #expect(library.add(manufacturer: "Polymaker", name: "B", weight: 215, photo: nil, isDefault: false, isManufacturerDefault: true))
        #expect(try !named("A", in: library).isManufacturerDefault)
        #expect(try named("B", in: library).isManufacturerDefault)
    }

    @Test func anotherBrandKeepsItsOwnDefault() throws {
        let library = try makeLibrary()
        #expect(library.add(manufacturer: "Polymaker", name: "A", weight: 140, photo: nil, isDefault: false, isManufacturerDefault: true))
        #expect(library.add(manufacturer: "eSun", name: "C", weight: 224, photo: nil, isDefault: false, isManufacturerDefault: true))
        #expect(try named("A", in: library).isManufacturerDefault)
        #expect(try named("C", in: library).isManufacturerDefault)
    }

    @Test func brandsMatchIgnoringCaseAndSpaces() throws {
        let library = try makeLibrary()
        #expect(library.add(manufacturer: "Polymaker", name: "A", weight: 140, photo: nil, isDefault: false, isManufacturerDefault: true))
        #expect(library.add(manufacturer: " polymaker ", name: "B", weight: 215, photo: nil, isDefault: false, isManufacturerDefault: true))
        #expect(try !named("A", in: library).isManufacturerDefault)
        #expect(try named("B", in: library).isManufacturerDefault)
    }

    @Test func aBlankManufacturerNeverHoldsABrandDefault() throws {
        let library = try makeLibrary()
        #expect(library.add(manufacturer: "  ", name: "A", weight: 140, photo: nil, isDefault: false, isManufacturerDefault: true))
        #expect(try !named("A", in: library).isManufacturerDefault)
    }

    @Test func changingTheManufacturerCarriesTheBrandDefault() throws {
        let library = try makeLibrary()
        #expect(library.add(manufacturer: "Polymaker", name: "A", weight: 140, photo: nil, isDefault: false, isManufacturerDefault: true))
        #expect(library.add(manufacturer: "eSun", name: "C", weight: 224, photo: nil, isDefault: false, isManufacturerDefault: true))
        let a = try named("A", in: library).id
        #expect(library.update(a, manufacturer: "eSun", name: "A", weight: 140, photo: nil, isDefault: false, isManufacturerDefault: true))
        #expect(try named("A", in: library).isManufacturerDefault)
        #expect(try !named("C", in: library).isManufacturerDefault)
    }

    @Test func clearingTheManufacturerDropsTheBrandDefault() throws {
        let library = try makeLibrary()
        #expect(library.add(manufacturer: "Polymaker", name: "A", weight: 140, photo: nil, isDefault: false, isManufacturerDefault: true))
        let a = try named("A", in: library).id
        #expect(library.update(a, manufacturer: "", name: "A", weight: 140, photo: nil, isDefault: false, isManufacturerDefault: true))
        #expect(try !named("A", in: library).isManufacturerDefault)
    }

    @Test func setManufacturerDefaultTurnsOnAndOff() throws {
        let library = try makeLibrary()
        #expect(library.add(manufacturer: "Polymaker", name: "A", weight: 140, photo: nil, isDefault: false, isManufacturerDefault: true))
        #expect(library.add(manufacturer: "Polymaker", name: "B", weight: 215, photo: nil, isDefault: false))
        let b = try named("B", in: library).id
        #expect(library.setManufacturerDefault(b, true))
        #expect(try !named("A", in: library).isManufacturerDefault)
        #expect(try named("B", in: library).isManufacturerDefault)
        #expect(library.setManufacturerDefault(b, false))
        #expect(try !named("B", in: library).isManufacturerDefault)
    }

    @Test func setManufacturerDefaultRefusesWhatItCannotMark() throws {
        let library = try makeLibrary()
        #expect(library.add(name: "Plain", weight: 100, photo: nil, isDefault: false))
        let plain = try named("Plain", in: library).id
        #expect(!library.setManufacturerDefault(UUID(), true))
        #expect(!library.setManufacturerDefault(plain, true))
        #expect(try !named("Plain", in: library).isManufacturerDefault)
    }

    @Test func brandAndGeneralDefaultsAreIndependent() throws {
        let library = try makeLibrary()
        #expect(library.add(manufacturer: "Polymaker", name: "A", weight: 140, photo: nil, isDefault: true, isManufacturerDefault: true))
        #expect(library.add(manufacturer: "Polymaker", name: "B", weight: 215, photo: nil, isDefault: false, isManufacturerDefault: true))
        #expect(try named("A", in: library).isDefault)
        #expect(library.setDefault(nil))
        #expect(try named("B", in: library).isManufacturerDefault)
    }
}
