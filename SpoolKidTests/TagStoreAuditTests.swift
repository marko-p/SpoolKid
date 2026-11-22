//
//  TagStoreAuditTests.swift
//  SpoolKidTests
//
//  Deleting a tag store is irreversible and other software reads it. These
//  pin the one rule that makes it safe: a store can be deleted only when the
//  remaining store already holds every link SpoolKid would otherwise lose.
//

import Testing
@testable import SpoolKid

@MainActor
struct TagStoreAuditTests {
    private let both: Set<TagStore> = [.cardUIDs, .spoolmanTags]
    private let filamentWithTag = Filament(id: 9, name: "Silk", nativeTagUIDs: ["FF"])

    private func spool(_ id: Int, card: [String] = [], lot: [String] = [], native: [String] = []) -> Spool {
        Spool(
            id: id, filament: Filament(id: 1, name: "PLA"),
            lotNr: lot.isEmpty ? nil : lot.map { "card_uid:\($0)" }.joined(separator: ","),
            extra: card.isEmpty ? nil : ["card_uids": CardUIDsCodec.encode(card)],
            statusId: nil, externalId: nil, purchaseDate: nil, nativeTagUIDs: native
        )
    }

    // MARK: - Copy into Spoolman Tags

    @Test func copyIntoNativeFindsCardUIDsLinks() {
        let m = TagStoreAudit.missingLinks(
            into: .spoolmanTags, spools: [spool(1, card: ["AA"], lot: ["BB"], native: ["CC"])],
            filaments: []
        )
        #expect(m.copyable.map(\.uid) == ["AA"])
        #expect(m.stale.isEmpty && m.filamentConflicts.isEmpty)
    }

    /// Since 2026-10-11 a `lot_nr` token is lot text, not a link: nothing to copy.
    @Test func aLotNrTokenIsNeverCopied() {
        let m = TagStoreAudit.missingLinks(into: .spoolmanTags, spools: [spool(1, lot: ["BB"])], filaments: [])
        #expect(m.copyable.isEmpty && m.stale.isEmpty)
    }

    @Test func aCopyAnotherSpoolHoldsNativelyIsStale() {
        let m = TagStoreAudit.missingLinks(
            into: .spoolmanTags, spools: [spool(1, card: ["AA"]), spool(2, native: ["AA"])],
            filaments: []
        )
        #expect(m.copyable.isEmpty)
        #expect(m.stale.map(\.spoolId) == [1])
    }

    /// Two spools claiming one UID through card_uids is a pre-existing double
    /// claim; only the spool the UID resolves to is copied.
    @Test func aDuplicateCardUIDsClaimCopiesOnlyTheResolvingSpool() {
        let m = TagStoreAudit.missingLinks(
            into: .spoolmanTags, spools: [spool(1, card: ["AA"]), spool(2, card: ["AA"])],
            filaments: []
        )
        #expect(m.copyable.map(\.spoolId) == [1])
        #expect(m.stale.map(\.spoolId) == [2])
    }

    @Test func aFilamentTagCannotBeCopied() {
        let m = TagStoreAudit.missingLinks(
            into: .spoolmanTags, spools: [spool(1, card: ["FF"])], filaments: [filamentWithTag]
        )
        #expect(m.filamentConflicts.map(\.filamentLabel) == ["Silk"])
        #expect(m.copyable.isEmpty)
    }

    // MARK: - Copy into card_uids

    @Test func copyIntoCardUIDsFindsNativeLinksAndStaleDisagreements() {
        let m = TagStoreAudit.missingLinks(
            into: .cardUIDs, spools: [spool(1, native: ["AA"]), spool(2, card: ["AA"])],
            filaments: []
        )
        #expect(m.copyable.map(\.spoolId) == [1])
        #expect(m.stale.map(\.spoolId) == [2])
    }

    // MARK: - Deletion

    @Test func nothingToDeleteWhenTheStoreIsEmpty() {
        #expect(TagStoreAudit.deletionCheck(
            deleting: .cardUIDs, available: both, spools: [spool(1, native: ["AA"])], filaments: []
        ) == .nothingToDelete)
    }

    @Test func withoutASecondStoreDeletionLosesEverything() {
        #expect(TagStoreAudit.deletionCheck(
            deleting: .cardUIDs, available: [.cardUIDs], spools: [spool(1, card: ["AA"])], filaments: []
        ) == .noOtherStore(linkCount: 1))
    }

    @Test func deletingCardUIDsIsBlockedUntilNativeHoldsEveryLink() {
        let blocked = TagStoreAudit.deletionCheck(deleting: .cardUIDs, available: both, spools: [spool(1, card: ["AA"])], filaments: [])
        guard case .blocked(let missing) = blocked else {
            Issue.record("expected blocked, got \(blocked)")
            return
        }
        #expect(missing.copyable.map(\.uid) == ["AA"])
        #expect(TagStoreAudit.deletionCheck(
            deleting: .cardUIDs, available: both, spools: [spool(1, card: ["AA"], native: ["AA"])], filaments: []
        ) == .ready(linkCount: 1, staleCount: 0))
    }

    @Test func staleCopiesNeverBlockDeletingCardUIDs() {
        #expect(TagStoreAudit.deletionCheck(
            deleting: .cardUIDs, available: both, spools: [spool(1, card: ["AA"]), spool(2, native: ["AA"])], filaments: []
        ) == .ready(linkCount: 1, staleCount: 1))
    }

    @Test func legacyLinksNeverBlockDeletingCardUIDs() {
        #expect(TagStoreAudit.deletionCheck(
            deleting: .cardUIDs, available: both, spools: [spool(1, card: ["AA"], lot: ["BB"], native: ["AA"])], filaments: []
        ) == .ready(linkCount: 1, staleCount: 0))
    }

    @Test func filamentConflictsAlwaysBlockDeletingCardUIDs() {
        let check = TagStoreAudit.deletionCheck(
            deleting: .cardUIDs, available: both, spools: [spool(1, card: ["FF"])], filaments: [filamentWithTag]
        )
        guard case .blocked(let missing) = check else {
            Issue.record("expected blocked, got \(check)")
            return
        }
        #expect(missing.filamentConflicts.count == 1)
    }

    @Test func deletingNativeIsBlockedByDisagreeingCardUIDs() {
        let check = TagStoreAudit.deletionCheck(
            deleting: .spoolmanTags, available: both,
            spools: [spool(1, card: ["AA"], native: ["AA"]), spool(2, card: ["AA"])], filaments: []
        )
        guard case .blocked(let missing) = check else {
            Issue.record("expected blocked, got \(check)")
            return
        }
        #expect(missing.stale.map(\.spoolId) == [2])
    }

    @Test func deletingNativeIsReadyWhenCardUIDsAgrees() {
        #expect(TagStoreAudit.deletionCheck(
            deleting: .spoolmanTags, available: both, spools: [spool(1, card: ["AA"], native: ["AA"])], filaments: []
        ) == .ready(linkCount: 1, staleCount: 0))
    }

    // MARK: - FilaMan Tags (rfid_uid as a writable tag store)

    private func filamanSpool(_ id: Int, card: [String] = [], rfid: String? = nil) -> Spool {
        Spool(
            id: id, filament: Filament(id: 1, name: "PLA"),
            extra: card.isEmpty ? nil : ["card_uids": CardUIDsCodec.encode(card)],
            rfidUID: rfid, statusId: nil, externalId: nil, purchaseDate: nil
        )
    }

    @Test func filamanLinksAreTheNormalizedRFIDs() {
        let links = TagStoreAudit.links(in: .filamanTags, spools: [filamanSpool(1, rfid: "aa:bb"), filamanSpool(2, rfid: "")])
        #expect(links.map(\.uid) == ["AABB"])
        #expect(links.map(\.spoolId) == [1])
    }

    @Test func filamanMissingLinksSkipsSpoolsWithRFID() {
        let m = TagStoreAudit.missingLinks(
            into: .filamanTags, spools: [filamanSpool(1, card: ["BB"], rfid: "AA")], filaments: []
        )
        #expect(m.copyable.isEmpty && m.stale.isEmpty)
    }

    @Test func filamanMissingLinksTakesFirstCardUID() {
        let m = TagStoreAudit.missingLinks(
            into: .filamanTags, spools: [filamanSpool(1, card: ["BB", "CC"])], filaments: []
        )
        #expect(m.copyable.map(\.uid) == ["BB"])
        #expect(m.copyable.map(\.spoolId) == [1])
        #expect(m.stale.isEmpty)
    }

    /// A UID another spool holds is reported stale and never taken; the first
    /// free one is the copy. Case does not matter when comparing holders.
    @Test func filamanMissingLinksHeldGoesToStale() {
        let allHeld = TagStoreAudit.missingLinks(
            into: .filamanTags, spools: [filamanSpool(1, card: ["BB"]), filamanSpool(2, rfid: "bb")], filaments: []
        )
        #expect(allHeld.copyable.isEmpty)
        #expect(allHeld.stale.map(\.uid) == ["BB"])

        let partlyHeld = TagStoreAudit.missingLinks(
            into: .filamanTags, spools: [filamanSpool(1, card: ["BB", "CC"]), filamanSpool(2, rfid: "bb")], filaments: []
        )
        #expect(partlyHeld.copyable.map(\.uid) == ["CC"])
        #expect(partlyHeld.stale.map(\.uid) == ["BB"])
    }

    /// Ruling R1: held tags become failures naming the holder, case-insensitively.
    @Test func heldFailuresNameTheHolder() {
        let spools = [filamanSpool(1, card: ["BB"]), filamanSpool(2, rfid: "bb")]
        let m = TagStoreAudit.missingLinks(into: .filamanTags, spools: spools, filaments: [])
        let failures = TagStoreSync.heldFailures(stale: m.stale, spools: spools)
        #expect(failures.count == 1)
        #expect(failures[0].label == spools[0].listTitle)
        #expect(failures[0].message == TagStoreText.filamanHeldLine(uid: "BB", holder: spools[1].listTitle))
    }

    @Test func filamanTagsAreNeverDeletedFromHere() {
        #expect(TagStoreAudit.deletionCheck(
            deleting: .filamanTags, available: [.cardUIDs, .filamanTags],
            spools: [filamanSpool(1, rfid: "AA")], filaments: []
        ) == .nothingToDelete)
    }
}
