//
//  UndetachableUIDReportingTests.swift
//  SpoolKidTests
//
//  `setCardUIDs` writes Spoolman's native tags and `card_uids`, never
//  FilaMan's `rfid_uid`. A UID that also lives in `rfid_uid` survives that
//  write — the PATCH returns 200 and the UID is still mapped. Both detach
//  paths reported `.saved` for it (I1).
//
//  These pin the INTERIM fix: say so. Actually removing such a UID needs a
//  policy decision on `rfid_uid` and is filed as debt.
//

import Testing
@testable import SpoolKid

@MainActor
struct UndetachableUIDReportingTests {
    private let filament = Filament(id: 1, name: "White PLA", material: "PLA", vendor: nil)

    private func spool(
        lotNr: String? = nil, cardUIDs: String? = nil, rfidUID: String? = nil, rfidWritable: Bool = false
    ) -> Spool {
        Spool(
            id: 7,
            filament: filament,
            lotNr: lotNr,
            extra: cardUIDs.map { ["card_uids": $0] },
            rfidUID: rfidUID,
            statusId: nil, externalId: nil, purchaseDate: nil,
            rfidUIDWritable: rfidWritable
        )
    }

    /// A writable `rfid_uid` can be detached, so it is not undetachable.
    @Test func aWritableRFIDUIDIsNotUndetachable() {
        let spool = spool(cardUIDs: "AABBCCDD", rfidUID: "045d7774ce2a81", rfidWritable: true)
        #expect(spool.undetachableCardUIDs.isEmpty)
        #expect(spool.mappedCardUIDs.contains("045D7774CE2A81"))
    }

    @Test func anEmptyRFIDUIDIsNeverUndetachable() {
        #expect(spool(cardUIDs: "AABBCCDD", rfidUID: "", rfidWritable: true).undetachableCardUIDs.isEmpty)
    }

    // MARK: - Which UIDs a write cannot reach

    @Test func aUIDHeldOnlyInCardUIDsIsDetachable() {
        #expect(spool(cardUIDs: "AABBCCDD").undetachableCardUIDs.isEmpty)
    }

    @Test func filaManHardwareBindingIsUndetachable() {
        #expect(spool(rfidUID: "045d7774ce2a81").undetachableCardUIDs == ["045D7774CE2A81"])
    }

    /// Since 2026-10-11 a `lot_nr` token is lot text, not a link: nothing to
    /// detach.
    @Test func aLotNrTokenIsNotUndetachable() {
        #expect(spool(lotNr: "batch-7,card_uid:AABBCCDD").undetachableCardUIDs.isEmpty)
    }

    /// The dangerous shape: the UID IS in `card_uids`, so the write has
    /// something to remove and succeeds — but `rfid_uid` still holds it, so
    /// the spool still owns the tag afterwards.
    @Test func aUIDInBothCardUIDsAndRFIDUIDIsStillUndetachable() {
        let both = spool(cardUIDs: "AABBCCDD", rfidUID: "aabbccdd")

        #expect(both.cardUIDs == ["AABBCCDD"])
        #expect(both.undetachableCardUIDs == ["AABBCCDD"])
    }

    @Test func onlyTheRFIDUIDIsUndetachable() {
        let spool = spool(lotNr: "card_uid:AABBCCDD", rfidUID: "99887766")

        #expect(spool.undetachableCardUIDs == ["99887766"])
    }

    @Test func everyUndetachableUIDStillResolvesToTheSpool() {
        let spool = spool(cardUIDs: "EEFF0011", rfidUID: "99887766")

        for uid in spool.undetachableCardUIDs {
            #expect(spool.mappedCardUIDs.contains(uid))
        }
    }

    // MARK: - The hub's single-owner assign

    @Test func assignIsACleanSaveWhenNothingIsLeftBehind() {
        #expect(TagLinkService.assignOutcome(unclearedOwners: [], undetachableOwners: []) == .saved)
    }

    /// The write succeeded and the spool still owns the tag. Reporting `.saved`
    /// here is the defect: it claims a detach that provably did not happen.
    @Test func anOwnerThatCannotBeDetachedIsACaveatNotACleanSave() {
        let outcome = TagLinkService.assignOutcome(
            unclearedOwners: [],
            undetachableOwners: ["TestVendor PLA+"]
        )

        #expect(outcome != .saved)
        #expect(outcome.didWrite)
        #expect(outcome.feedback != .success)
        #expect(outcome.followUpNote?.contains("TestVendor PLA+") == true)
    }

    /// "Scan it again to finish moving it" is true of a failed write and false
    /// of one that cannot succeed. Retrying an undetachable UID loops forever.
    @Test func anUndetachableOwnerIsNotToldToRescan() {
        let note = TagLinkService.assignOutcome(
            unclearedOwners: [],
            undetachableOwners: ["Spool #3"]
        ).followUpNote

        #expect(note?.contains("Scan it again") == false)
    }

    @Test func aFailedWriteIsStillToldToRescan() {
        let note = TagLinkService.assignOutcome(
            unclearedOwners: ["Spool #3"],
            undetachableOwners: []
        ).followUpNote

        #expect(note?.contains("Scan it again") == true)
    }

    @Test func bothKindsOfLeftoverOwnerAreNamed() {
        let note = TagLinkService.assignOutcome(
            unclearedOwners: ["Spool #3"],
            undetachableOwners: ["Spool #9"]
        ).followUpNote

        #expect(note?.contains("Spool #3") == true)
        #expect(note?.contains("Spool #9") == true)
    }

    // MARK: - The spool form's removable chip list

    /// Deleting the chip and saving wrote `card_uids` without it, succeeded,
    /// and the chip came back on the next refresh.
    @Test func removingAnUndetachableChipEarnsACaveat() {
        let note = SpoolFormView.undetachableRemovalNote(
            removed: ["045D7774CE2A81"],
            undetachable: ["045D7774CE2A81"]
        )

        #expect(note?.contains("045D7774CE2A81") == true)
    }

    @Test func removingADetachableChipSaysNothing() {
        #expect(SpoolFormView.undetachableRemovalNote(removed: ["AABBCCDD"], undetachable: []) == nil)
    }

    /// An undetachable UID the user did NOT touch is not a caveat — it is just
    /// a tag that is still mapped, which is what the user asked for.
    @Test func keepingAnUndetachableChipSaysNothing() {
        #expect(SpoolFormView.undetachableRemovalNote(removed: [], undetachable: ["045D7774CE2A81"]) == nil)
    }

    @Test func everyUndetachableRemovalIsNamed() {
        let note = SpoolFormView.undetachableRemovalNote(
            removed: ["AABBCCDD", "045D7774CE2A81"],
            undetachable: ["AABBCCDD", "045D7774CE2A81"]
        )

        #expect(note?.contains("AABBCCDD") == true)
        #expect(note?.contains("045D7774CE2A81") == true)
    }

    // MARK: - The copy names FilaMan alone (2026-10-11)

    @Test func theAssignCaveatNamesFilaMansTagBinding() {
        #expect(TagLinkService.assignOutcome(unclearedOwners: [], undetachableOwners: ["Spool #9"]).followUpNote
            == "The tag is mapped to this spool, but Spool #9 still holds it in FilaMan's own tag binding, "
            + "which SpoolKid cannot change. Clear it in FilaMan to finish the move.")
    }

    @Test func theUnlinkCaveatNamesFilaMansTagBinding() {
        let held = spool(cardUIDs: "AABBCCDD", rfidUID: "aabbccdd")
        #expect(TagLinkService.unlinkCaveat(uid: "AABBCCDD", spool: held)
            == "\(held.listTitle) still holds this tag in FilaMan's own tag binding, which SpoolKid cannot change. "
            + "Clear it in FilaMan to finish unlinking.")
    }

    @Test func theChipRemovalNoteNamesFilaMansTagBinding() {
        #expect(SpoolFormView.undetachableRemovalNote(removed: ["045D7774CE2A81"], undetachable: ["045D7774CE2A81"])
            == "The spool was saved, but 045D7774CE2A81 is still mapped to it through FilaMan's own tag binding, "
            + "which SpoolKid cannot change.")
    }

    // MARK: - The spool form's write list (final review FR-2)

    /// Every mapped UID shows as a chip, FilaMan's `rfid_uid` included, but a
    /// save must not copy that binding into `card_uids`.
    @Test func addingATagWritesEveryChipButTheRFIDUID() {
        let loaded = spool(cardUIDs: "AABBCCDD", rfidUID: "045d7774ce2a81")
        let shown = loaded.mappedCardUIDs + ["EEFF0011"]

        #expect(SpoolFormView.cardUIDsToWrite(
            shown: shown, previous: loaded.mappedCardUIDs, writable: loaded.writableCardUIDs
        ) == ["AABBCCDD", "EEFF0011"])
    }

    @Test func anUntouchedChipListWritesNothing() {
        let loaded = spool(cardUIDs: "AABBCCDD", rfidUID: "045d7774ce2a81")

        #expect(SpoolFormView.cardUIDsToWrite(
            shown: loaded.mappedCardUIDs, previous: loaded.mappedCardUIDs, writable: loaded.writableCardUIDs
        ) == nil)
    }

    /// Deleting the `rfid_uid` chip leaves nothing SpoolKid can write — and
    /// the removal is still reported, from the unfiltered lists.
    @Test func deletingTheRFIDUIDChipWritesNothingAndIsReported() {
        let loaded = spool(cardUIDs: "AABBCCDD", rfidUID: "045d7774ce2a81")
        let shown = ["AABBCCDD"]

        #expect(SpoolFormView.cardUIDsToWrite(
            shown: shown, previous: loaded.mappedCardUIDs, writable: loaded.writableCardUIDs
        ) == nil)
        let note = SpoolFormView.undetachableRemovalNote(
            removed: loaded.mappedCardUIDs.filter { !shown.contains($0) },
            undetachable: loaded.undetachableCardUIDs
        )
        #expect(note?.contains("045D7774CE2A81") == true)
    }

    /// A UID held in `card_uids` AND `rfid_uid` is already in `card_uids`, so
    /// deleting its chip removes that copy — writing it is not a copy.
    @Test func aUIDInBothCardUIDsAndRFIDUIDIsStillWritable() {
        let loaded = spool(cardUIDs: "AABBCCDD,045D7774CE2A81", rfidUID: "045d7774ce2a81")

        #expect(SpoolFormView.cardUIDsToWrite(
            shown: ["AABBCCDD"], previous: loaded.mappedCardUIDs, writable: loaded.writableCardUIDs
        ) == ["AABBCCDD"])
    }

    /// A `lot_nr` token is not a chip and is never written into `card_uids`.
    @Test func aLotNrTokenIsNeverCarriedIntoCardUIDs() {
        let loaded = spool(lotNr: "card_uid:AABBCCDD", cardUIDs: "EEFF0011")

        #expect(loaded.mappedCardUIDs == ["EEFF0011"])
        #expect(SpoolFormView.cardUIDsToWrite(
            shown: loaded.mappedCardUIDs + ["11223344"], previous: loaded.mappedCardUIDs,
            writable: loaded.writableCardUIDs
        ) == ["EEFF0011", "11223344"])
    }
}
