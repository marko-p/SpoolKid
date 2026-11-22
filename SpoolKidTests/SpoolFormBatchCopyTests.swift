//
//  SpoolFormBatchCopyTests.swift
//  SpoolKidTests
//
//  Purpose: The copy the spool form shows for a batch: its title by count, the
//  Cancel that becomes Done once spools exist, and the alert a stopped batch
//  raises.
//

import Testing
@testable import SpoolKid

@MainActor
struct SpoolFormBatchCopyTests {
    @Test func titles() {
        #expect(SpoolFormView.formTitle(isEditing: false, count: 1) == "Add Spool")
        #expect(SpoolFormView.formTitle(isEditing: false, count: 3) == "Add Spools")
        #expect(SpoolFormView.formTitle(isEditing: true, count: 1) == "Edit Spool")
    }

    @Test func cancelBecomesDoneOnceSaved() {
        #expect(SpoolFormView.cancelTitle(isSaved: false) == "Cancel")
        #expect(SpoolFormView.cancelTitle(isSaved: true) == "Done")
    }

    @Test func incompleteBatchAlert() {
        let alert = SpoolFormAlert.batchIncomplete("Created #12.")
        #expect(alert.title == "Saving Stopped Early")
        #expect(alert.message == "Created #12.")
    }

    @Test func sectionTitles() {
        #expect(SpoolFormView.tagSectionTitle(position: 1, savedSpoolID: nil) == "Spool 1")
        #expect(SpoolFormView.tagSectionTitle(position: 2, savedSpoolID: 13) == "Spool #13")
    }

    @Test func saveFirstNotes() {
        #expect(SpoolFormView.saveFirstNote(count: 1, writesLinks: true) == "Writing or linking a tag saves the spool first.")
        #expect(SpoolFormView.saveFirstNote(count: 2, writesLinks: true) == "Writing or linking a tag saves both spools first.")
        #expect(SpoolFormView.saveFirstNote(count: 3, writesLinks: true) == "Writing or linking a tag saves all 3 spools first.")
    }

    /// Outside Tag Links no Link Tag is shown, so the note must not mention linking.
    @Test func saveFirstNotesWithoutLinks() {
        #expect(SpoolFormView.saveFirstNote(count: 1, writesLinks: false) == "Writing a tag saves the spool first.")
        #expect(SpoolFormView.saveFirstNote(count: 2, writesLinks: false) == "Writing a tag saves both spools first.")
        #expect(SpoolFormView.saveFirstNote(count: 3, writesLinks: false) == "Writing a tag saves all 3 spools first.")
    }

    /// A banner about one of several same-filament spools is told apart by its number.
    @Test func bannersNameASavedSpoolByNumber() {
        #expect(SpoolFormView.savedSpoolLabel(id: 12, filamentName: "PLA Matte") == "Spool #12 · PLA Matte")
        #expect(SpoolFormView.savedSpoolLabel(id: 12, filamentName: nil) == "Spool #12")
    }

    // MARK: - One tag, one owner across sections

    /// The tag moved into the changed section, and the store no longer gives it to the sibling.
    @Test func aTagMovedOffASiblingLeavesItsSection() {
        #expect(SpoolFormView.siblingTagsAfterMove(
            sibling: ["04AA", "04BB"], movedIntoChanged: ["04AA"], heldBySibling: ["04BB"]
        ) == ["04BB"])
    }

    /// A failed detach: the store still gives the sibling the tag, so the list stays truthful.
    @Test func aTagTheStoreStillGivesTheSiblingStays() {
        #expect(SpoolFormView.siblingTagsAfterMove(
            sibling: ["04AA", "04BB"], movedIntoChanged: ["04AA"], heldBySibling: ["04AA", "04BB"]
        ) == ["04AA", "04BB"])
    }

    /// A sibling tag the store does not list yet (an add still queued) is not the changed section's business.
    @Test func aTagUnrelatedToTheChangedSectionIsUntouched() {
        #expect(SpoolFormView.siblingTagsAfterMove(
            sibling: ["04CC"], movedIntoChanged: ["04AA"], heldBySibling: []
        ) == ["04CC"])
        #expect(SpoolFormView.siblingTagsAfterMove(
            sibling: [], movedIntoChanged: ["04AA"], heldBySibling: []
        ) == [])
    }

    // MARK: - The section's buttons

    @Test func sectionButtonsFollowTheTagIdentityMode() {
        #expect(SpoolFormView.tagSectionActions(writesLinks: true) == [.write, .link])
        #expect(SpoolFormView.tagSectionActions(writesLinks: false) == [.write])
    }

    /// The control names the spool it acts on, before and after the save.
    @Test func sectionButtonsNameTheirSpool() {
        #expect(SpoolFormView.tagButtonAccessibilityLabel(.write, position: 2, savedSpoolID: nil, isScanning: false) == "Write Tag to Spool 2")
        #expect(SpoolFormView.tagButtonAccessibilityLabel(.write, position: 2, savedSpoolID: 13, isScanning: false) == "Write Tag to Spool #13")
        #expect(SpoolFormView.tagButtonAccessibilityLabel(.link, position: 1, savedSpoolID: 12, isScanning: false) == "Link Tag to Spool #12")
    }

    /// The visible "Scanning…" is spoken too, still naming the spool.
    @Test func aScanningButtonSaysSoAndNamesItsSpool() {
        #expect(SpoolFormView.tagButtonAccessibilityLabel(.link, position: 2, savedSpoolID: 13, isScanning: true) == "Scanning for Spool #13")
        #expect(SpoolFormView.tagButtonAccessibilityLabel(.link, position: 2, savedSpoolID: nil, isScanning: true) == "Scanning for Spool 2")
    }

    // MARK: - Tag buttons wait for in-flight tag writes

    /// A claim decided while an earlier tag write has not landed would read a
    /// store that does not show it yet, so no tag button starts then.
    @Test func tagButtonsWaitForInFlightTagWrites() {
        #expect(SpoolFormView.canStartTagAction(hasFilament: true, isSaving: false, isScanning: false, tagWritesPending: 0))
        #expect(!SpoolFormView.canStartTagAction(hasFilament: true, isSaving: false, isScanning: false, tagWritesPending: 1))
        #expect(!SpoolFormView.canStartTagAction(hasFilament: true, isSaving: false, isScanning: false, tagWritesPending: 3))
    }

    @Test func tagButtonsAlsoWaitForTheirOwnPreconditions() {
        #expect(!SpoolFormView.canStartTagAction(hasFilament: false, isSaving: false, isScanning: false, tagWritesPending: 0))
        #expect(!SpoolFormView.canStartTagAction(hasFilament: true, isSaving: true, isScanning: false, tagWritesPending: 0))
        #expect(!SpoolFormView.canStartTagAction(hasFilament: true, isSaving: false, isScanning: true, tagWritesPending: 0))
    }

    // MARK: - A Move belongs to the section that agreed it

    private func move(from id: Int, section: Int) -> SpoolFormView.PendingMove {
        SpoolFormView.PendingMove(holder: .spool(id: id, label: "Spool #\(id)"), section: section)
    }

    /// Section 1 agreed to take 04AA from spool 7; section 0's queued write must not consume it.
    @Test func aSectionReleasesOnlyTheMovesItAgreed() {
        let agreed = ["04AA": move(from: 7, section: 1)]
        #expect(SpoolFormView.movesToRelease(section: 0, listed: ["04AA", "04BB"], agreed: agreed).isEmpty)
        let released = SpoolFormView.movesToRelease(section: 1, listed: ["04AA"], agreed: agreed)
        #expect(released.map { $0.uid } == ["04AA"])
        #expect(released.map { $0.holder } == [.spool(id: 7, label: "Spool #7")])
    }

    /// A move whose tag the section no longer lists was taken back: nothing to release.
    @Test func aMoveForATagNoLongerListedIsNotReleased() {
        let agreed = ["04AA": move(from: 7, section: 1)]
        #expect(SpoolFormView.movesToRelease(section: 1, listed: ["04BB"], agreed: agreed).isEmpty)
    }

    @Test func eachSectionGetsItsOwnMovesInListOrder() {
        let agreed = [
            "04AA": move(from: 7, section: 0),
            "04BB": move(from: 8, section: 1),
            "04CC": move(from: 9, section: 0),
        ]
        #expect(SpoolFormView.movesToRelease(section: 0, listed: ["04CC", "04BB", "04AA"], agreed: agreed).map { $0.uid } == ["04CC", "04AA"])
        #expect(SpoolFormView.movesToRelease(section: 1, listed: ["04CC", "04BB", "04AA"], agreed: agreed).map { $0.uid } == ["04BB"])
    }

    // MARK: - The shared fields lock once an Add has saved

    @Test func sharedFieldsLockOnlyAfterAnAddSaved() {
        #expect(SpoolFormView.sharedFieldsLocked(isEditing: false, isSaved: true))
        #expect(!SpoolFormView.sharedFieldsLocked(isEditing: false, isSaved: false))
        // Edit Spool is where details change, saved or not.
        #expect(!SpoolFormView.sharedFieldsLocked(isEditing: true, isSaved: true))
        #expect(!SpoolFormView.sharedFieldsLocked(isEditing: true, isSaved: false))
    }
}
