//
//  LocalStoreSchemaTests.swift
//  SpoolKidTests
//
//  Purpose: Proves the SwiftData local-store schema (LocalVendor / LocalFilament
//  / LocalSpool) persists, refetches, wires relationships, and honors its delete
//  rules. Uses an in-memory ModelContainer so the suite leaves no on-disk store.
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
struct LocalStoreSchemaTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test func vendorPersistsAndRefetchesWithDormantSyncMetadata() throws {
        let context = try makeContext()
        context.insert(LocalVendor(localId: 1, name: "Bambu Lab", emptySpoolWeight: 250))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<LocalVendor>())
        #expect(fetched.count == 1)
        let vendor = try #require(fetched.first)
        #expect(vendor.name == "Bambu Lab")
        #expect(vendor.emptySpoolWeight == 250)
        // Sync metadata defaults — dormant until M3.
        #expect(vendor.serverId == nil)
        #expect(vendor.isDirty == false)
    }

    @Test func filamentLinksToVendorBothDirections() throws {
        let context = try makeContext()
        let vendor = LocalVendor(localId: 1, name: "Polymaker")
        let filament = LocalFilament(localId: 1, name: "PolyTerra PLA", material: "PLA", colorHex: "1B5E20", vendor: vendor)
        context.insert(filament)
        try context.save()

        let filaments = try context.fetch(FetchDescriptor<LocalFilament>())
        #expect(filaments.count == 1)
        #expect(filaments.first?.vendor?.name == "Polymaker")
        // Inverse is maintained automatically.
        let vendors = try context.fetch(FetchDescriptor<LocalVendor>())
        #expect(vendors.first?.filaments.count == 1)
    }

    @Test func spoolLinksToFilamentAndCarriesLotNr() throws {
        let context = try makeContext()
        let filament = LocalFilament(localId: 1, name: "PLA Basic", material: "PLA")
        let spool = LocalSpool(localId: 1, remainingWeight: 1000, lotNr: "card_uid:04a1b2c3", filament: filament)
        context.insert(spool)
        try context.save()

        let spools = try context.fetch(FetchDescriptor<LocalSpool>())
        #expect(spools.count == 1)
        #expect(spools.first?.lotNr == "card_uid:04a1b2c3")
        #expect(spools.first?.remainingWeight == 1000)
        #expect(spools.first?.filament?.name == "PLA Basic")
    }

    @Test func deletingFilamentCascadesToItsSpools() throws {
        let context = try makeContext()
        let filament = LocalFilament(localId: 1, name: "PETG")
        context.insert(LocalSpool(localId: 1, remainingWeight: 800, filament: filament))
        context.insert(LocalSpool(localId: 2, remainingWeight: 500, filament: filament))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<LocalSpool>()) == 2)

        context.delete(filament)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<LocalFilament>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<LocalSpool>()) == 0)
    }

    @Test func deletingVendorNullifiesFilamentVendorButKeepsFilament() throws {
        let context = try makeContext()
        let vendor = LocalVendor(localId: 1, name: "Sunlu")
        let filament = LocalFilament(localId: 1, name: "PLA Meta", vendor: vendor)
        context.insert(filament)
        try context.save()

        context.delete(vendor)
        try context.save()

        let filaments = try context.fetch(FetchDescriptor<LocalFilament>())
        #expect(filaments.count == 1)
        #expect(filaments.first?.vendor == nil)
    }

    @Test func extraDictionaryRoundTrips() throws {
        let context = try makeContext()
        context.insert(LocalFilament(localId: 1, name: "PLA-CF", extra: ["variant": "Carbon Fiber", "subtype": "CF"]))
        try context.save()

        let filaments = try context.fetch(FetchDescriptor<LocalFilament>())
        #expect(filaments.first?.extra?["variant"] == "Carbon Fiber")
        #expect(filaments.first?.extra?["subtype"] == "CF")
    }
}
