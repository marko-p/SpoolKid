//
//  TagLinkServiceFilaManTests.swift
//  SpoolKidTests
//
//  Purpose: FilaMan Tags in `TagLinkService.assign`: the one-tag limit,
//  release-before-claim with one restore, and the background-never-takes rule.
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
struct TagLinkServiceFilaManTests {
    private func spool(id: Int, rfid: String? = nil, cards: [String] = []) -> Spool {
        Spool(
            id: id, filament: Filament(id: id, name: "PLA \(id)", material: "PLA", vendor: nil, diameter: 1.75, weight: 1000),
            extra: cards.isEmpty ? nil : [CardUIDsCodec.fieldKey: CardUIDsCodec.encode(cards)],
            rfidUID: rfid, statusId: nil, externalId: nil, purchaseDate: nil, rfidUIDWritable: true
        )
    }

    /// FilaMan with Tag Links on and both switches as given.
    private func makeStore(
        spools: [Spool], filamanTags: Bool = true, spoolLink: Bool = false
    ) -> (SpoolDataStore, MockMigrationWriter) {
        let writer = MockMigrationWriter(serverSpools: spools, capabilities: .filaman)
        writer.availableTagStores = [.cardUIDs, .filamanTags]
        writer.modelsFilaManWrites = true
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("tagLinks", forKey: AppConfig.tagIdentityModeKey)
        defaults.set(true, forKey: AppConfig.filamanConnectionValidKey)
        defaults.set(filamanTags, forKey: AppConfig.filamanTagsEnabledKey)
        defaults.set(spoolLink, forKey: AppConfig.filamanSpoolLinkEnabledKey)
        return (SpoolDataStore(repository: writer, defaults: defaults), writer)
    }

    /// F7: Copy to FilaMan Tags counts a spool only when its rfid_uid
    /// actually changed — a write that reports success and stores nothing
    /// (here: the double ignores it) is not a copy.
    @Test(arguments: [true, false])
    func copyCountsOnlyAChangedRFID(writeLands: Bool) async {
        let (store, writer) = makeStore(spools: [spool(id: 1, cards: ["BB"])], spoolLink: true)
        writer.modelsFilaManWrites = writeLands
        let result = await TagStoreSync.copy(into: .filamanTags, in: store)
        #expect(writer.setCardUIDsCalls.count == 1)
        #expect(result.copied == (writeLands ? 1 : 0))
    }

    /// F4: a hub move in R + S releases the source's rfid_uid before the
    /// destination claims it, so the tag ends in the destination's rfid_uid
    /// and on no other spool.
    @Test func moveTagsReleasesBeforeClaiming() async {
        let (store, writer) = makeStore(spools: [spool(id: 1, rfid: "t", cards: ["X"]), spool(id: 2)], spoolLink: true)
        let outcome = await TagLinkService.moveTags(["T"], to: store.spools[1], in: store)
        #expect(outcome == .saved)
        #expect(writer.setCardUIDsCalls.map(\.spoolId) == [1, 2])
        #expect(writer.setCardUIDsCalls[0].uids == ["X"])
        #expect(store.spools.first { $0.id == 2 }?.rfidUID == "t")
        #expect(store.spools.filter { $0.mappedCardUIDs.contains("T") }.map(\.id) == [2])
    }

    /// F4: a failed claim reports the assign's own note, not a generic one.
    @Test func moveTagsReportsTheFailure() async {
        let (store, writer) = makeStore(spools: [spool(id: 1, rfid: "t", cards: ["X"]), spool(id: 2)], spoolLink: true)
        writer.failSetCardUIDsCalls = [2]
        let outcome = await TagLinkService.moveTags(["T"], to: store.spools[1], in: store)
        #expect(outcome == .notSaved(TagStoreText.claimFailedNote(holder: store.spools[0].listTitle, restored: true)))
    }

    @Test func conflictOnlyInROnly() {
        let held = spool(id: 1, rfid: "a")
        #expect(TagLinkService.replacementConflict(uid: "T", spool: held, targets: [.filamanTags]) == "A")
        #expect(TagLinkService.replacementConflict(uid: "T", spool: held, targets: [.filamanTags, .cardUIDs]) == nil)
        #expect(TagLinkService.replacementConflict(uid: "a", spool: held, targets: [.filamanTags]) == nil)
        #expect(TagLinkService.replacementConflict(uid: "T", spool: held, targets: []) == nil)
    }

    @Test func rOnlyLinkWithoutReplaceIsRefused() async {
        let (store, writer) = makeStore(spools: [spool(id: 1, rfid: "a")])
        #expect(store.tagIdentity.linkTargets == [.filamanTags])
        let outcome = await TagLinkService.assign("T", to: store.spools[0], in: store)
        #expect(outcome == .notSaved(TagStoreText.filamanOneTagNote(existing: "A")))
        #expect(writer.setCardUIDsCalls.isEmpty)
    }

    @Test func replaceWritesExactlyTheNewTag() async {
        let (store, writer) = makeStore(spools: [spool(id: 1, rfid: "a", cards: ["B"])])
        let outcome = await TagLinkService.assign("T", to: store.spools[0], in: store, replacing: true)
        #expect(outcome.didWrite)
        #expect(writer.setCardUIDsCalls.map(\.spoolId) == [1])
        #expect(writer.setCardUIDsCalls.map(\.uids) == [["T"]])
    }

    @Test func personLinkReleasesHolderFirst() async {
        let (store, writer) = makeStore(spools: [spool(id: 1, rfid: "t", cards: ["X"]), spool(id: 2)])
        let outcome = await TagLinkService.assign("T", to: store.spools[1], in: store)
        #expect(outcome.didWrite)
        #expect(writer.setCardUIDsCalls.map(\.spoolId) == [1, 2])
        #expect(writer.setCardUIDsCalls[0].uids == ["X"])
        #expect(writer.setCardUIDsCalls[1].uids == ["T"])
    }

    @Test func failedClaimRestoresHolderOnce() async {
        let (store, writer) = makeStore(spools: [spool(id: 1, rfid: "t", cards: ["X"]), spool(id: 2)])
        writer.failSetCardUIDsCalls = [2]
        let outcome = await TagLinkService.assign("T", to: store.spools[1], in: store)
        #expect(outcome == .notSaved(TagStoreText.claimFailedNote(holder: store.spools[0].listTitle, restored: true)))
        #expect(writer.setCardUIDsCalls.map(\.spoolId) == [1, 2, 1])
        #expect(writer.setCardUIDsCalls[2].uids == ["T", "X"])
    }

    @Test func failedRestoreSaysTheTagIsOnNoSpool() async {
        let (store, writer) = makeStore(spools: [spool(id: 1, rfid: "t"), spool(id: 2)])
        writer.failSetCardUIDsCalls = [2, 3]
        let outcome = await TagLinkService.assign("T", to: store.spools[1], in: store)
        #expect(outcome == .notSaved(TagStoreText.claimFailedNote(holder: store.spools[0].listTitle, restored: false)))
    }

    @Test func backgroundAssignNeverReplacesOrTakes() async {
        // Replace is refused in the background even when asked for.
        let (store, writer) = makeStore(spools: [spool(id: 1, rfid: "a")])
        let refused = await TagLinkService.assign(
            "T", to: store.spools[0], in: store, replacing: true, personInitiated: false
        )
        #expect(refused == .notSaved(TagStoreText.filamanOneTagNote(existing: "A")))
        #expect(writer.setCardUIDsCalls.isEmpty)

        // And a tag another spool holds in rfid_uid is not taken.
        let (second, secondWriter) = makeStore(spools: [spool(id: 1, rfid: "t"), spool(id: 2)])
        let held = await TagLinkService.assign("T", to: second.spools[1], in: second, personInitiated: false)
        #expect(held == .notSaved(TagStoreText.heldElsewhereNote(holder: second.spools[0].listTitle)))
        #expect(secondWriter.setCardUIDsCalls.isEmpty)
    }

    @Test func relinkingTheSameTagIsNoConflict() {
        let held = spool(id: 1, rfid: "T", cards: ["B"])
        #expect(TagLinkService.replacementConflict(uid: "T", spool: held, targets: [.filamanTags]) == nil)
    }

    @Test func replaceDropsLeftoversEvenWhenTagAlreadyHeld() async {
        let (store, writer) = makeStore(spools: [spool(id: 1, rfid: "t", cards: ["B"])])
        let outcome = await TagLinkService.assign("T", to: store.spools[0], in: store, replacing: true)
        #expect(outcome.didWrite)
        #expect(writer.setCardUIDsCalls.map(\.uids) == [["T"]])
    }

    @Test func holderMatchIsCaseInsensitive() async {
        let (store, writer) = makeStore(spools: [spool(id: 1, rfid: "t"), spool(id: 2)])
        _ = await TagLinkService.assign("T", to: store.spools[1], in: store)
        #expect(writer.setCardUIDsCalls.map(\.spoolId) == [1, 2])
    }
}
