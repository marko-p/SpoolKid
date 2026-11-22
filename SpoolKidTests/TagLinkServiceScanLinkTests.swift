//
//  TagLinkServiceScanLinkTests.swift
//  SpoolKidTests
//
//  Purpose: Linking a scanned tag to a known spool and unlinking one, the
//  shared paths behind the hub's Add Another Tag / Unlink and the Spool
//  page's Link Tag / Unlink. A location tag must never become a spool tag.
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
struct TagLinkServiceScanLinkTests {
    private func makeStore() throws -> SpoolDataStore {
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(TagIdentityMode.tagLinks.rawValue, forKey: AppConfig.tagIdentityModeKey)
        return SpoolDataStore(repository: LocalRepository(context: ModelContext(container)), defaults: defaults)
    }

    private func makeSpool(in store: SpoolDataStore) async throws -> Spool {
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "PLA Basic")))
        return try #require(await store.addSpool(draft: SpoolDraft(filamentId: filament.id)))
    }

    @Test func locationTagIsRefused() async throws {
        let store = try makeStore()
        let spool = try await makeSpool(in: store)
        let scan = ScanResult(
            cardUID: "04AA01", tagData: nil, format: nil,
            locationTag: LocationTagPayload(uuid: UUID(), name: "Shelf B")
        )

        let message = await TagLinkService.linkScanned(scan, to: spool, in: store)

        #expect(message?.contains("labels Shelf B") == true)
        #expect(store.owner(ofTagUID: "04AA01") == .none)
    }

    @Test func noUIDWritesNothing() async throws {
        let store = try makeStore()
        let spool = try await makeSpool(in: store)
        let scan = ScanResult(cardUID: nil, tagData: nil, format: nil)

        #expect(await TagLinkService.linkScanned(scan, to: spool, in: store) == nil)
    }

    @Test func scannedTagIsLinkedThenUnlinked() async throws {
        let store = try makeStore()
        let spool = try await makeSpool(in: store)

        #expect(await TagLinkService.linkScanned(
            ScanResult(cardUID: "04aa02", tagData: nil, format: nil), to: spool, in: store
        ) == nil)
        #expect(store.owner(ofTagUID: "04AA02") == .spool(id: spool.id, label: spool.listTitle))

        let linked = try #require(store.spools.first { $0.id == spool.id })
        #expect(await TagLinkService.unlink("04AA02", from: linked, in: store) == nil)
        #expect(store.owner(ofTagUID: "04AA02") == .none)
    }
}
