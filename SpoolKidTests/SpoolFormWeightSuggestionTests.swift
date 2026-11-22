//
//  SpoolFormWeightSuggestionTests.swift
//  SpoolKidTests
//
//  Two follow-ups from the 2026-08-24 device pass:
//  - a used weight is never negative; when the spool's own numbers make it so,
//    the field says nothing rather than something impossible;
//  - on a NEW spool, a scale reading that disagrees with the initial weight can
//    be offered to whichever field is still empty.
//

import Foundation
import Testing
@testable import SpoolKid

struct SpoolFormWeightSuggestionTests {
    private typealias Suggestion = SpoolFormView.MeasuredWeightSuggestion

    // MARK: - Used is never negative

    @Test func usedIsTheOrdinaryDifference() {
        #expect(SpoolFormView.weightInputText(for: .used, netRemaining: 750, initialWeight: "1000") == "250")
    }

    @Test func afullSpoolHasUsedNothing() {
        #expect(SpoolFormView.weightInputText(for: .used, netRemaining: 1000, initialWeight: "1000") == "0")
    }

    /// A spool holding MORE than its stated initial weight — exactly what an
    /// initial weight entered as a gross figure leaves behind — used to render
    /// "-238" into a field the user types into.
    @Test func aSpoolHoldingMoreThanItsInitialShowsNoUsedWeight() {
        #expect(SpoolFormView.weightInputText(for: .used, netRemaining: 1238, initialWeight: "1000") == "")
    }

    /// And it says why, rather than leaving an unexplained empty field.
    @Test func theImpossibleCaseIsExplained() {
        let note = SpoolFormView.usedWeightUnavailableNote(netRemaining: 1238, initialWeight: "1000")
        #expect(note != nil)
        #expect(note?.contains("Initial Filament Weight") == true)
    }

    @Test func anOrdinarySpoolNeedsNoExplanation() {
        #expect(SpoolFormView.usedWeightUnavailableNote(netRemaining: 750, initialWeight: "1000") == nil)
        #expect(SpoolFormView.usedWeightUnavailableNote(netRemaining: 1000, initialWeight: "1000") == nil)
        #expect(SpoolFormView.usedWeightUnavailableNote(netRemaining: nil, initialWeight: "1000") == nil)
        #expect(SpoolFormView.usedWeightUnavailableNote(netRemaining: 1238, initialWeight: "") == nil)
    }

    /// Switching Remaining → Used → Remaining must not lose the weight just
    /// because Used had nothing to show: an empty field reads as nil, and the
    /// anchor is what carries the value across.
    @Test func anUnshowableUsedWeightDoesNotDestroyTheRemainingOne() {
        #expect(
            SpoolFormView.netRemaining(
                input: "", mode: .used, initialWeight: "1000", spoolWeight: "238"
            ) == nil
        )
    }

    // MARK: - Assigning the difference on a new spool

    /// Measured is heavier than the filament alone, and no core weight has been
    /// entered — the surplus is the spool.
    @Test func aSurplusOverInitialIsOfferedAsTheEmptySpoolWeight() {
        #expect(
            SpoolFormView.measuredWeightSuggestion(
                measured: "1238", initialWeight: "1000", spoolWeight: "", isNewSpool: true
            ) == .setEmptySpoolWeight(238)
        )
    }

    /// The core weight is known, so a scale reading below the full gross figure
    /// is filament already gone.
    @Test func aShortfallAgainstTheGrossTotalIsOfferedAsUsedFilament() {
        #expect(
            SpoolFormView.measuredWeightSuggestion(
                measured: "988", initialWeight: "1000", spoolWeight: "238", isNewSpool: true
            ) == .setUsedFilament(250)
        )
    }

    /// With no core weight entered, a reading BELOW the initial weight is
    /// ambiguous — it could be a light spool or a part-used one, and guessing
    /// would write a number the user never chose.
    @Test func aShortfallWithNoCoreWeightSuggestsNothing() {
        #expect(
            SpoolFormView.measuredWeightSuggestion(
                measured: "900", initialWeight: "1000", spoolWeight: "", isNewSpool: true
            ) == nil
        )
    }

    /// The core weight is already filled in, so nothing is offered for it.
    @Test func aKnownCoreWeightIsNeverOverwritten() {
        #expect(
            SpoolFormView.measuredWeightSuggestion(
                measured: "1500", initialWeight: "1000", spoolWeight: "238", isNewSpool: true
            ) == nil
        )
    }

    @Test func numbersThatAlreadyAgreeSuggestNothing() {
        #expect(
            SpoolFormView.measuredWeightSuggestion(
                measured: "1000", initialWeight: "1000", spoolWeight: "", isNewSpool: true
            ) == nil
        )
        #expect(
            SpoolFormView.measuredWeightSuggestion(
                measured: "1238", initialWeight: "1000", spoolWeight: "238", isNewSpool: true
            ) == nil
        )
    }

    @Test func anIncompleteFormSuggestsNothing() {
        #expect(
            SpoolFormView.measuredWeightSuggestion(
                measured: "", initialWeight: "1000", spoolWeight: "", isNewSpool: true
            ) == nil
        )
        #expect(
            SpoolFormView.measuredWeightSuggestion(
                measured: "1238", initialWeight: "", spoolWeight: "", isNewSpool: true
            ) == nil
        )
    }

    /// An existing spool's weights are facts already recorded; a scale reading
    /// there is a measurement of what is left, not a chance to redefine the
    /// spool. Offering to rewrite its core weight from one reading would move
    /// the reported remaining weight of every past print (F32).
    @Test func anExistingSpoolIsNeverOfferedTheDifference() {
        #expect(
            SpoolFormView.measuredWeightSuggestion(
                measured: "1238", initialWeight: "1000", spoolWeight: "", isNewSpool: false
            ) == nil
        )
    }

    @Test func aCommaDecimalIsAccepted() {
        #expect(
            SpoolFormView.measuredWeightSuggestion(
                measured: "1238,5", initialWeight: "1000", spoolWeight: "", isNewSpool: true
            ) == .setEmptySpoolWeight(238.5)
        )
    }

    // MARK: - How the offer reads

    @Test func eachSuggestionNamesTheFieldItWouldFill() {
        #expect(Suggestion.setEmptySpoolWeight(238).prompt.contains("Empty Spool Weight"))
        #expect(Suggestion.setEmptySpoolWeight(238).prompt.contains("238"))
        #expect(Suggestion.setUsedFilament(250).prompt.contains("250"))
    }
}
