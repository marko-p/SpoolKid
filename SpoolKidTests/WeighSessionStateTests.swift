import Testing
@testable import SpoolKid

struct WeighSessionStateTests {

    private func pending(
        id: Int = 1,
        name: String = "PLA Black",
        empty: Double? = 238,
        input: String = ""
    ) -> WeighSessionState.Pending {
        WeighSessionState.Pending(
            spoolID: id, spoolName: name, emptySpoolWeight: empty, weightInput: input
        )
    }

    // MARK: - Advance intent

    @Test func autoSaveOn_readyReadingCommitsOnAdvance() {
        var state = WeighSessionState()
        state.setPending(pending(input: "1238"))
        #expect(state.advanceIntent(autoSave: true)
                == .commitThenAdvance(spoolID: 1, gross: 1238, net: 1000))
    }

    @Test func autoSaveOff_readyReadingAsksBeforeAdvancing() {
        var state = WeighSessionState()
        state.setPending(pending(input: "1238"))
        // Off means "I decide per spool", so an advance tap must not silently
        // save AND must not silently discard.
        #expect(state.advanceIntent(autoSave: false)
                == .confirmUnsaved(spoolID: 1, gross: 1238, net: 1000))
    }

    @Test func nothingToSave_advancesFreelyRegardlessOfAutoSave() {
        var state = WeighSessionState()
        state.setPending(pending(input: "  "))
        #expect(state.advanceIntent(autoSave: true) == .advance)
        #expect(state.advanceIntent(autoSave: false) == .advance)
    }

    @Test func noPendingSpool_advancesFreely() {
        let state = WeighSessionState()
        #expect(state.advanceIntent(autoSave: true) == .advance)
        #expect(state.advanceIntent(autoSave: false) == .advance)
    }

    @Test func missingEmptySpoolWeight_blocksAdvanceRegardlessOfAutoSave() {
        var state = WeighSessionState()
        state.setPending(pending(empty: nil, input: "1238"))
        // The block is about the reading being unsaveable, not about who
        // decides when to save — turning auto-save off must not smuggle a
        // gross reading past the missing-core guard.
        #expect(state.advanceIntent(autoSave: true) == .blockedNeedsEmptySpoolWeight)
        #expect(state.advanceIntent(autoSave: false) == .blockedNeedsEmptySpoolWeight)
    }

    // MARK: - Commit outcome

    @Test func noPendingSpool_hasNothingToSave() {
        let state = WeighSessionState()
        #expect(state.commitOutcome() == .nothingToSave)
    }

    @Test func emptyWeightField_hasNothingToSave() {
        var state = WeighSessionState()
        state.setPending(pending(input: "   "))
        // A blank box means "I skipped this one", never "record zero".
        #expect(state.commitOutcome() == .nothingToSave)
    }

    @Test func missingEmptySpoolWeight_blocksCommit() {
        var state = WeighSessionState()
        state.setPending(pending(empty: nil, input: "1238"))
        #expect(state.commitOutcome() == .blockedNeedsEmptySpoolWeight)
    }

    @Test func suppliedEmptySpoolWeight_unblocksCommit() {
        var state = WeighSessionState()
        state.setPending(pending(empty: nil, input: "1238"))
        state.setEmptySpoolWeight(238)
        #expect(state.commitOutcome() == .ready(spoolID: 1, gross: 1238, net: 1000))
    }

    @Test func completePending_isReadyWithNetWeight() {
        var state = WeighSessionState()
        state.setPending(pending(input: "1238"))
        #expect(state.commitOutcome() == .ready(spoolID: 1, gross: 1238, net: 1000))
    }

    @Test func updatingWeightInput_changesTheOutcome() {
        var state = WeighSessionState()
        state.setPending(pending(input: "1238"))
        state.updateWeightInput("1000")
        #expect(state.commitOutcome() == .ready(spoolID: 1, gross: 1000, net: 762))
    }

    // MARK: - Log

    @Test func recordingAWrite_appendsToTheLog() {
        var state = WeighSessionState()
        state.recordWrite(spoolID: 1, spoolName: "PLA Black", gross: 1238, net: 1000, outcome: .saved)
        #expect(state.log.count == 1)
        #expect(state.log[0].netWeight == 1000)
        #expect(state.log[0].didWrite)
    }

    @Test func failedWrite_isRecordedAsFailedNotSuccess() {
        var state = WeighSessionState()
        state.recordWrite(spoolID: 1, spoolName: "PLA Black", gross: 1238, net: 1000, outcome: .notSaved("Spoolman said no."))
        #expect(state.log[0].didWrite == false)
        #expect(state.log[0].outcome == .notSaved("Spoolman said no."))
    }

    /// A partial success — the spool's PATCH landed but the measurement it
    /// carried did not. It reached the backend, so it is not a failure; it did
    /// not do all of the work, so it must not read as a clean save either.
    @Test func caveatWrite_isWrittenButKeepsItsCaveat() {
        var state = WeighSessionState()
        state.recordWrite(
            spoolID: 1, spoolName: "PLA Black", gross: 1238, net: 1000,
            outcome: .savedWithCaveat("Measured Weight — not recorded: 502")
        )
        #expect(state.log[0].didWrite)
        #expect(state.log[0].outcome != .saved)
        #expect(state.log[0].outcome.caveat == "Measured Weight — not recorded: 502")
    }

    @Test func retryingACaveatRow_canReachACleanSave() {
        var state = WeighSessionState()
        state.recordWrite(
            spoolID: 1, spoolName: "PLA Black", gross: 1238, net: 1000,
            outcome: .savedWithCaveat("Measured Weight — not recorded: 502")
        )
        state.recordWrite(spoolID: 1, spoolName: "PLA Black", gross: 1238, net: 1000, outcome: .saved)
        #expect(state.log.count == 1)
        #expect(state.log[0].outcome == .saved)
    }

    @Test func sameSpoolTwice_updatesItsRowRatherThanDuplicating() {
        var state = WeighSessionState()
        state.recordWrite(spoolID: 1, spoolName: "PLA Black", gross: 1238, net: 1000, outcome: .saved)
        state.recordWrite(spoolID: 1, spoolName: "PLA Black", gross: 900, net: 662, outcome: .saved)
        #expect(state.log.count == 1)
        #expect(state.log[0].grossWeight == 900)
        #expect(state.log[0].netWeight == 662)
    }

    @Test func retryingAFailedRow_flipsItToWritten() {
        var state = WeighSessionState()
        state.recordWrite(spoolID: 1, spoolName: "PLA Black", gross: 1238, net: 1000, outcome: .notSaved("Spoolman said no."))
        state.recordWrite(spoolID: 1, spoolName: "PLA Black", gross: 1238, net: 1000, outcome: .saved)
        #expect(state.log.count == 1)
        #expect(state.log[0].didWrite)
    }

    // MARK: - Pending lifecycle

    @Test func clearingPending_leavesTheLogIntact() {
        var state = WeighSessionState()
        state.setPending(pending(input: "1238"))
        state.recordWrite(spoolID: 1, spoolName: "PLA Black", gross: 1238, net: 1000, outcome: .saved)
        state.clearPending()
        #expect(state.pending == nil)
        #expect(state.log.count == 1)
        #expect(state.commitOutcome() == .nothingToSave)
    }

    @Test func settingANewPending_replacesTheOldOne() {
        var state = WeighSessionState()
        state.setPending(pending(id: 1, input: "1238"))
        state.setPending(pending(id: 2, name: "PETG White", input: ""))
        #expect(state.pending?.spoolID == 2)
        #expect(state.commitOutcome() == .nothingToSave)
    }
}

/// Where the cursor goes when Weigh Spools hands a spool back to the user.
@MainActor
struct WeighSessionFocusTests {

    @Test func typedWeighingFocusesTheWeightField() {
        #expect(WeighSessionView.focusesWeightOnReturn(weighWithScale: false, hasPairedScale: true))
        #expect(WeighSessionView.focusesWeightOnReturn(weighWithScale: false, hasPairedScale: false))
    }

    @Test func scaleModeLeavesTheKeyboardDown() {
        // The scale fills the field. A raised keyboard covered the scale's row
        // and the Scan, Choose and Finish buttons (owner, 2026-09-25).
        #expect(!WeighSessionView.focusesWeightOnReturn(weighWithScale: true, hasPairedScale: true))
    }

    @Test func aModeLeftOnWithoutAScaleStillTypes() {
        // The toggle is remembered, but with no paired scale nothing renders
        // to fill the field — typing is the only way in.
        #expect(WeighSessionView.focusesWeightOnReturn(weighWithScale: true, hasPairedScale: false))
    }
}
