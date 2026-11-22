//
//  TagWritePlanTests.swift
//  SpoolKidTests
//
//  On a Spoolman 0.27+ server a spool's tag list lives in two stores. These
//  pin which store receives a new link, what a list change turns into, and
//  the two rules that keep a write from taking a tag it was not asked to:
//  stale copies are dropped, and only a UID the caller is ADDING may move.
//

import Testing
@testable import SpoolKid

@MainActor
struct TagWritePlanTests {
    private let filament = Filament(id: 1, name: "PLA")
    private let both: Set<TagStore> = [.cardUIDs, .spoolmanTags]

    private func spool(_ id: Int, card: [String] = [], lot: [String] = [], native: [String] = []) -> Spool {
        Spool(
            id: id, filament: filament,
            lotNr: lot.isEmpty ? nil : lot.map { "card_uid:\($0)" }.joined(separator: ","),
            extra: card.isEmpty ? nil : ["card_uids": CardUIDsCodec.encode(card)],
            statusId: nil, externalId: nil, purchaseDate: nil, nativeTagUIDs: native
        )
    }

    private func plan(
        _ s: Spool, _ desired: [String], _ targets: Set<TagStore>,
        holders: [String: TagWritePlan.NativeTagHolder] = [:]
    ) -> TagWritePlan.Result {
        TagWritePlan.make(spool: s, desired: desired, targets: targets, nativeHolder: { holders[$0] })
    }

    // MARK: - Targets

    @Test func olderServersAlwaysWriteCardUIDs() {
        #expect(TagWriteTargets.resolve(available: [.cardUIDs], nativeEnabled: true, spoolLinkEnabled: false) == [.cardUIDs])
        #expect(TagWriteTargets.resolve(available: [], nativeEnabled: false, spoolLinkEnabled: false) == [.cardUIDs])
    }

    @Test func nativeServersFollowTheSwitches() {
        #expect(TagWriteTargets.resolve(available: both, nativeEnabled: true, spoolLinkEnabled: true) == both)
        #expect(TagWriteTargets.resolve(available: both, nativeEnabled: true, spoolLinkEnabled: false) == [.spoolmanTags])
        #expect(TagWriteTargets.resolve(available: both, nativeEnabled: false, spoolLinkEnabled: true) == [.cardUIDs])
    }

    @Test func bothSwitchesOffStillLeavesSomewhereToWrite() {
        #expect(TagWriteTargets.resolve(available: both, nativeEnabled: false, spoolLinkEnabled: false) == [.spoolmanTags])
    }

    @Test func fullyLinkedMeansEveryTargetOnNativeServers() {
        #expect(TagWriteTargets.isFullyLinked(uid: "AA", on: spool(1, card: ["AA"]), targets: both, available: both) == false)
        #expect(TagWriteTargets.isFullyLinked(uid: "AA", on: spool(1, card: ["AA"], native: ["AA"]), targets: both, available: both))
        #expect(TagWriteTargets.isFullyLinked(uid: "AA", on: spool(1, native: ["AA"]), targets: [.spoolmanTags], available: both))
    }

    @Test func fullyLinkedIsTodaysRuleOnOlderServers() {
        #expect(TagWriteTargets.isFullyLinked(uid: "AA", on: spool(1, card: ["AA"]), targets: [.cardUIDs], available: [.cardUIDs]))
        #expect(TagWriteTargets.isFullyLinked(uid: "AA", on: spool(1, lot: ["AA"]), targets: [.cardUIDs], available: [.cardUIDs]) == false)
        #expect(TagWriteTargets.isFullyLinked(uid: "BB", on: spool(1, card: ["AA"]), targets: [.cardUIDs], available: [.cardUIDs]) == false)
    }

    // MARK: - Plan

    @Test func addingWritesEveryTargetStore() {
        let r = plan(spool(1), ["aa"], both)
        #expect(r.ops == [.link(uid: "AA", moveFromSpool: nil), .setCardUIDs(["AA"])])
        #expect(r.skips.isEmpty)
    }

    @Test func aNewUIDAnotherSpoolHoldsIsMoved() {
        let r = plan(spool(1), ["AA"], both, holders: ["AA": .spool(id: 2)])
        #expect(r.ops == [.link(uid: "AA", moveFromSpool: 2), .setCardUIDs(["AA"])])
    }

    @Test func aCarriedOverCopyAnotherSpoolHoldsNativelyIsStale() {
        let r = plan(spool(1, card: ["AA", "BB"]), ["AA", "BB"], both, holders: ["AA": .spool(id: 2)])
        #expect(r.ops == [.link(uid: "BB", moveFromSpool: nil), .setCardUIDs(["BB"])])
        #expect(r.skips == [.staleHeldBySpool(uid: "AA", spoolId: 2)])
    }

    @Test func staleCopiesAreDroppedEvenWhenNativeIsNotATarget() {
        let r = plan(spool(1, card: ["AA"]), ["AA"], [.cardUIDs], holders: ["AA": .spool(id: 2)])
        #expect(r.ops == [.setCardUIDs([])])
    }

    @Test func aRequestedFilamentTagIsRefused() {
        let r = plan(spool(1), ["AA"], both, holders: ["AA": .filament(id: 9, label: "PLA")])
        #expect(r.ops.isEmpty)
        #expect(r.skips == [.heldByFilament(uid: "AA", label: "PLA", requested: true)])
    }

    @Test func aCarriedOverFilamentConflictStaysInCardUIDs() {
        let r = plan(spool(1, card: ["AA"]), ["AA"], both, holders: ["AA": .filament(id: 9, label: "PLA")])
        #expect(r.ops.isEmpty)
        #expect(r.skips == [.heldByFilament(uid: "AA", label: "PLA", requested: false)])
    }

    @Test func removingCleansEveryStoreWhateverTheTargets() {
        let r = plan(spool(1, card: ["AA"], native: ["AA"]), [], [.spoolmanTags])
        #expect(r.ops == [.unlink(uid: "AA"), .setCardUIDs([])])
    }

    @Test func cardUIDsIsNeverAddedToWhenItIsNotATarget() {
        let r = plan(spool(1, card: ["BB"]), ["AA", "BB"], [.spoolmanTags])
        #expect(r.ops == [.link(uid: "AA", moveFromSpool: nil), .link(uid: "BB", moveFromSpool: nil)])
    }

    @Test func nativeOnlyLinksAreCopiedIntoCardUIDsWhenItIsATarget() {
        let r = plan(spool(1, native: ["AA"]), ["AA"], both)
        #expect(r.ops == [.setCardUIDs(["AA"])])
    }

    @Test func anUnchangedListWritesNothing() {
        #expect(plan(spool(1, card: ["AA"], native: ["AA"]), ["AA"], both).ops.isEmpty)
    }

    @Test func lotNumberUIDsAreLinkedButLotNumberIsNeverTouched() {
        let r = plan(spool(1, lot: ["CC"]), ["CC"], [.spoolmanTags])
        #expect(r.ops == [.link(uid: "CC", moveFromSpool: nil)])
    }

    // MARK: - Repair on scan

    @Test func repairIsOnlyForNativeServers() {
        let s = spool(1, card: ["AA"])
        #expect(TagWriteTargets.needsRepair(uid: "AA", resolved: s, spools: [s], targets: [.cardUIDs], available: [.cardUIDs]) == false)
    }

    @Test func aCardUIDsOnlyLinkIsRepairedIntoNativeTags() {
        let s = spool(1, card: ["AA"])
        #expect(TagWriteTargets.needsRepair(uid: "AA", resolved: s, spools: [s], targets: both, available: both))
    }

    @Test func aStaleCopyElsewhereNeedsRepair() {
        let holder = spool(1, card: ["AA"], native: ["AA"])
        let stale = spool(2, card: ["AA"])
        #expect(TagWriteTargets.needsRepair(uid: "AA", resolved: holder, spools: [holder, stale], targets: both, available: both))
    }

    @Test func aCompleteLinkNeedsNothing() {
        let s = spool(1, card: ["AA"], native: ["AA"])
        #expect(TagWriteTargets.needsRepair(uid: "AA", resolved: s, spools: [s], targets: both, available: both) == false)
    }

    /// Spool ID / Neither reach `setCardUIDs` only to remove (Unlink, a
    /// deleted form chip). With no targets the plan adds nothing and still
    /// removes from every store.
    @Test func emptyTargetsRemoveButNeverAdd() {
        let result = plan(spool(1, card: ["AA", "BB"], native: ["AA"]), ["CC"], [])
        #expect(result.ops.contains(.unlink(uid: "AA")))
        #expect(result.ops.contains(.setCardUIDs([])))
        #expect(!result.ops.contains { if case .link = $0 { return true } else { return false } })
    }
}
