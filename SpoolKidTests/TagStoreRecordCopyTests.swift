//
//  TagStoreRecordCopyTests.swift
//  SpoolKidTests
//
//  Purpose: Issue #24 — copying the tag links only this iPhone's record
//  knows into the backend, through the one linking path.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct TagStoreRecordCopyTests {
    private func spool(id: Int, archived: Bool? = nil, cards: [String] = []) -> Spool {
        Spool(
            id: id, filament: Filament(id: id, name: "PLA \(id)", material: "PLA", vendor: nil, diameter: 1.75, weight: 1000),
            archived: archived,
            extra: cards.isEmpty ? nil : [CardUIDsCodec.fieldKey: CardUIDsCodec.encode(cards)],
            statusId: nil, externalId: nil, purchaseDate: nil
        )
    }

    /// Spoolman below 0.27 (card_uids only), connected, in the given mode.
    private func makeStore(spools: [Spool], mode: String = "tagLinks") -> (SpoolDataStore, MockMigrationWriter) {
        let writer = MockMigrationWriter(serverSpools: spools, capabilities: .spoolman)
        writer.availableTagStores = [.cardUIDs]
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(mode, forKey: AppConfig.tagIdentityModeKey)
        defaults.set(true, forKey: AppConfig.spoolmanConnectionValidKey)
        return (SpoolDataStore(repository: writer, defaults: defaults), writer)
    }

    @Test func recordLinksSortsOwnersAndSkips() {
        let spools = [spool(id: 1), spool(id: 2, archived: true), spool(id: 3, cards: ["CC"])]
        let owners: [String: TagOwner] = ["CC": .spool(id: 3, label: "S3"), "DD": .location(name: "Shelf A")]
        let r = TagStoreSync.recordLinks(
            snapshot: ["aa": 1, "BB": 2, "CC": 3, "DD": 1, "EE": 9],
            spools: spools, owner: { owners[$0] ?? .none }
        )
        #expect(r.copyable == [.init(uid: "AA", spoolId: 1)])
        #expect(r.skipped.map(\.message) == [
            TagStoreText.recordOwnedElsewhereLine(uid: "DD", owner: "Shelf A"),
            TagStoreText.recordSpoolGoneLine(uid: "BB"),
            TagStoreText.recordSpoolGoneLine(uid: "EE"),
        ])
    }

    @Test func aTagAnotherSpoolOwnsIsSkipped() {
        let r = TagStoreSync.recordLinks(
            snapshot: ["AA": 1], spools: [spool(id: 1), spool(id: 2, cards: ["AA"])],
            owner: { _ in .spool(id: 2, label: "PLA 2") }
        )
        #expect(r.copyable.isEmpty)
        #expect(r.skipped.map(\.message) == [TagStoreText.recordOwnedElsewhereLine(uid: "AA", owner: "PLA 2")])
    }

    @Test func copyRecordLinksThroughAssign() async {
        let (store, writer) = makeStore(spools: [spool(id: 1)])
        let result = await TagStoreSync.copyRecord(snapshot: ["AA": 1], in: store)
        #expect(result.copied == 1)
        #expect(result.failures.isEmpty)
        #expect(writer.setCardUIDsCalls.map(\.uids) == [["AA"]])
    }

    @Test func copyRecordRefusesOutsideTagLinks() async {
        let (store, writer) = makeStore(spools: [spool(id: 1)], mode: "spoolID")
        let result = await TagStoreSync.copyRecord(snapshot: ["AA": 1], in: store)
        #expect(result.copied == 0)
        #expect(result.failures.count == 1)
        #expect(writer.setCardUIDsCalls.isEmpty)
    }

    @Test func copyRecordReportsAFailedWrite() async {
        let (store, writer) = makeStore(spools: [spool(id: 1)])
        writer.failSetCardUIDsCalls = [1]
        let result = await TagStoreSync.copyRecord(snapshot: ["AA": 1], in: store)
        #expect(result.copied == 0)
        #expect(result.failures.count == 1)
    }
}
