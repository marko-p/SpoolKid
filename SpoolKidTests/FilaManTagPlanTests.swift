//
//  FilaManTagPlanTests.swift
//  SpoolKidTests
//
//  With FilaMan Tags on, a spool's rfid_uid is a writable tag store beside
//  card_uids. These pin what a tag list becomes: which UID rfid_uid holds,
//  how an unlink promotes the next tag, and that a UID another spool holds
//  is never taken.
//

import Testing
@testable import SpoolKid

@MainActor
struct FilaManTagPlanTests {
    private let filament = Filament(id: 1, name: "PLA")
    private let both: Set<TagStore> = [.cardUIDs, .filamanTags]
    private let available: Set<TagStore> = [.cardUIDs, .filamanTags]

    private func spool(_ id: Int, card: [String] = [], rfid: String? = nil, writable: Bool = true) -> Spool {
        Spool(
            id: id, filament: filament,
            lotNr: nil,
            extra: card.isEmpty ? nil : ["card_uids": CardUIDsCodec.encode(card)],
            rfidUID: rfid,
            statusId: nil, externalId: nil, purchaseDate: nil,
            rfidUIDWritable: writable
        )
    }

    /// Holders are looked up the way Task 4's repository does: other spools,
    /// compared after normalizing their raw `rfid_uid`.
    private func holder(_ others: [Spool]) -> (String) -> Int? {
        { uid in others.first { SpoolMappingService.normalizeUID($0.rfidUID ?? "") == uid }?.id }
    }

    private func plan(
        _ s: Spool, _ desired: [String], _ targets: Set<TagStore>, held: [Spool] = []
    ) -> FilaManTagPlan.Result {
        FilaManTagPlan.make(spool: s, desired: desired, targets: targets, rfidHolder: holder(held))
    }

    @Test func rOnlyLinkIntoEmptySpoolSetsRFID() {
        let r = plan(spool(1), ["T"], [.filamanTags])
        #expect(r.cardUIDs == nil)
        #expect(r.rfid == .set("T"))
        #expect(r.heldElsewhere.isEmpty)
    }

    @Test func rPlusSKeepsExistingRFID() {
        let r = plan(spool(1, card: ["A"], rfid: "A"), ["A", "B"], both)
        #expect(r.cardUIDs == ["A", "B"])
        #expect(r.rfid == .keep)
    }

    @Test func unlinkPromotesNextTag() {
        let r = plan(spool(1, card: ["A", "B"], rfid: "A"), ["B"], both)
        #expect(r.cardUIDs == ["B"])
        #expect(r.rfid == .set("B"))
    }

    @Test func promotionSkipsHeldUID() {
        let s = spool(1, rfid: "A")
        let r = plan(s, ["B", "C"], [.filamanTags], held: [spool(9, rfid: "b")])
        #expect(r.rfid == .set("C"))
        #expect(r.heldElsewhere == ["B"])
    }

    @Test func promotionClearsWhenEveryCandidateIsHeld() {
        let s = spool(1, rfid: "A")
        let r = plan(s, ["B", "C"], [.filamanTags], held: [spool(8, rfid: "B"), spool(9, rfid: "C")])
        #expect(r.rfid == .clear)
        #expect(r.heldElsewhere == ["B", "C"])
    }

    @Test func rOnlyReplaceDropsLeftoverCardUIDs() {
        let r = plan(spool(1, card: ["X", "Y"], rfid: "A"), ["T"], [.filamanTags])
        #expect(r.cardUIDs == [])
        #expect(r.rfid == .set("T"))
    }

    @Test func notWritableNeverTouchesRFID() {
        let r = plan(spool(1, card: ["A"], rfid: "A", writable: false), [], both)
        #expect(r.rfid == .keep)
        #expect(r.cardUIDs == [])
    }

    @Test func rfidHolderIsCaseInsensitive() {
        let r = plan(spool(1), ["11AA22BB"], [.filamanTags], held: [spool(2, rfid: "11aa22bb")])
        #expect(r.rfid == .keep)
        #expect(r.heldElsewhere == ["11AA22BB"])
    }

    @Test func clearIsNullNeverEmptyString() {
        #expect(FilaManTagPlan.wireValue("04:A1:b2") == "04a1b2")
        let r = plan(spool(1, rfid: "A"), [], [.filamanTags])
        #expect(r.rfid == .clear)
        #expect(r.rfid != .set(""))
    }

    @Test func emptyRFIDIsNoTag() {
        let r = plan(spool(1, rfid: ""), [], [.filamanTags])
        #expect(r.rfid == .keep)
    }

    @Test func fullyLinkedRules() {
        // rfid_uid is a target: it must hold this tag.
        #expect(TagWriteTargets.isFullyLinked(uid: "AA", on: spool(1, card: ["AA"], rfid: "AA"), targets: [.filamanTags], available: available))
        #expect(TagWriteTargets.isFullyLinked(uid: "AA", on: spool(1, rfid: nil), targets: [.filamanTags], available: available) == false)
        #expect(TagWriteTargets.isFullyLinked(uid: "AA", on: spool(1, rfid: "BB"), targets: [.filamanTags], available: available) == false)
        #expect(TagWriteTargets.isFullyLinked(uid: "AA", on: spool(1, rfid: ""), targets: [.filamanTags], available: available) == false)
        // R + S: card_uids keeps its own copy, so rfid_uid may hold another tag.
        #expect(TagWriteTargets.isFullyLinked(uid: "AA", on: spool(1, card: ["AA"], rfid: "BB"), targets: both, available: available))
        #expect(TagWriteTargets.isFullyLinked(uid: "AA", on: spool(1, card: [], rfid: "AA"), targets: both, available: available) == false)
        // card_uids is a target: it must carry the tag.
        #expect(TagWriteTargets.isFullyLinked(uid: "AA", on: spool(1, card: ["AA"]), targets: [.cardUIDs], available: available))
        #expect(TagWriteTargets.isFullyLinked(uid: "AA", on: spool(1), targets: [.cardUIDs], available: available) == false)
    }

    /// F8: outside FilaMan-Tags targets (Spool ID mode: none) a removal on a
    /// spool with an empty rfid_uid must not fill it with another tag.
    @Test func removalOutsideFilamanTargetsKeepsEmptyRFID() {
        let r = plan(spool(1, card: ["A", "B"]), ["B"], [])
        #expect(r.rfid == .keep)
        #expect(r.cardUIDs == ["B"])
    }

    /// F8: promotion still runs with no targets — the held tag is going away.
    @Test func promotionWorksWithEmptyTargets() {
        let r = plan(spool(1, card: ["A", "B"], rfid: "A"), ["B"], [])
        #expect(r.rfid == .set("B"))
    }

    /// F2: FilaMan Tags off (targets [.cardUIDs]) — a tag in the read-only
    /// rfid_uid already resolves here, exactly as on develop.
    @Test func tagsOffRFIDOnlyTagIsFullyLinked() {
        let s = spool(1, rfid: "aa", writable: false)
        #expect(TagWriteTargets.isFullyLinked(uid: "AA", on: s, targets: [.cardUIDs], available: available))
    }

    /// F5: writability comes from the switch at write time, not from a
    /// cached spool a failed refetch left behind.
    @Test func writeInputsTakeWritabilityFromTheSwitch() {
        let stale = spool(1, card: ["B"], rfid: "a", writable: true)
        let (s, uids) = FilaManRepository.tagWriteInputs(spool: stale, uids: ["A", "B"], writable: false)
        #expect(s.rfidUIDWritable == false)
        // Off: the read-only rfid tag is never copied into card_uids.
        #expect(uids == ["B"])
        #expect(FilaManTagPlan.make(spool: s, desired: uids, targets: [.cardUIDs], rfidHolder: { _ in nil }).isEmpty)
    }

    @Test func writeInputsKeepRFIDTagAlsoInCardUIDs() {
        let s = spool(1, card: ["A", "B"], rfid: "a", writable: false)
        #expect(FilaManRepository.tagWriteInputs(spool: s, uids: ["A", "B"], writable: false).1 == ["A", "B"])
        let on = FilaManRepository.tagWriteInputs(spool: spool(1, rfid: "a", writable: false), uids: ["A"], writable: true)
        #expect(on.0.rfidUIDWritable)
        #expect(on.1 == ["A"])
    }

    private func unplaced(_ s: Spool, _ desired: [String], _ targets: Set<TagStore>, held: [Spool] = []) -> [String] {
        FilaManTagPlan.unplaced(spool: s, desired: desired, result: plan(s, desired, targets, held: held))
    }

    @Test func unplacedFindsTagsStoredNowhere() {
        #expect(unplaced(spool(1, rfid: "a"), ["A", "B"], [.filamanTags]) == ["B"])
        #expect(unplaced(spool(1, rfid: "a"), ["A", "B"], both).isEmpty)
        #expect(unplaced(spool(1), ["B"], [.filamanTags], held: [spool(2, rfid: "b")]) == ["B"])
        #expect(unplaced(spool(1, rfid: "a"), [], [.filamanTags]).isEmpty)
    }
}
