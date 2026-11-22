//
//  SaveOutcomeTests.swift
//  SpoolKidTests
//
//  Purpose: Task 17b (plan defect I1) — a partial success must not present as
//  a clean success. Pins the three-way classification the forms route their
//  save results through, and the one case that used to be invisible: a write
//  that landed while carrying a message about what it could not do.
//

import Foundation
import Testing
@testable import SpoolKid

struct SaveOutcomeTests {
    private let fallback = "The spool could not be saved."

    @Test func aCleanSuccessCarriesNoMessage() {
        let outcome = SaveOutcome.classify(didSave: true, message: nil, failureFallback: fallback)

        #expect(outcome == .saved)
    }

    /// The I1 defect: `addFilament`'s colour warning, `applyFilamentColors`'
    /// write failure and `addSpool`'s location warning all arrive alongside a
    /// `true`, and both forms only ever read the message on the failure branch.
    @Test func aSuccessCarryingAMessageIsACaveatNotACleanSave() {
        let outcome = SaveOutcome.classify(
            didSave: true,
            message: "The filament was saved without its colour: nope.",
            failureFallback: fallback
        )

        #expect(outcome == .savedWithCaveat("The filament was saved without its colour: nope."))
    }

    @Test func aFailureCarriesTheRepositorysOwnMessage() {
        let outcome = SaveOutcome.classify(didSave: false, message: "Server said no.", failureFallback: fallback)

        #expect(outcome == .notSaved("Server said no."))
    }

    @Test func aFailureWithNoMessageFallsBackToTheFormsWording() {
        let outcome = SaveOutcome.classify(didSave: false, message: nil, failureFallback: fallback)

        #expect(outcome == .notSaved(fallback))
    }

    /// A blank message is not a caveat. Backends that never report partial
    /// failures (Spoolman, Local) must keep landing on `.saved`, which is what
    /// makes this classification backend-agnostic rather than a FilaMan branch.
    @Test func aBlankMessageOnASuccessIsStillACleanSave() {
        #expect(SaveOutcome.classify(didSave: true, message: "", failureFallback: fallback) == .saved)
        #expect(SaveOutcome.classify(didSave: true, message: "   \n", failureFallback: fallback) == .saved)
    }

    @Test func aBlankMessageOnAFailureFallsBackToTheFormsWording() {
        #expect(
            SaveOutcome.classify(didSave: false, message: "  ", failureFallback: fallback) == .notSaved(fallback)
        )
    }

    // MARK: - What the form does with each outcome

    /// The record exists on the server in both saved cases, so both dismiss.
    /// Trapping the user in a form over a swatch that did not write is worse
    /// than letting them out with a note.
    @Test func bothSavedOutcomesDismissTheForm() {
        #expect(SaveOutcome.saved.didWrite)
        #expect(SaveOutcome.savedWithCaveat("x").didWrite)
        #expect(SaveOutcome.notSaved("x").didWrite == false)
    }

    /// A caveat must not borrow the success haptic.
    @Test func onlyACleanSaveEarnsTheSuccessHaptic() {
        #expect(SaveOutcome.saved.feedback == .success)
        #expect(SaveOutcome.savedWithCaveat("x").feedback == .warning)
        #expect(SaveOutcome.notSaved("x").feedback == nil)
    }

    /// A caveat is surfaced after the form goes away; a failure is surfaced in
    /// the form the user is still standing in. Neither may be dropped.
    @Test func eachOutcomeRoutesItsMessageToExactlyOnePlace() {
        #expect(SaveOutcome.saved.caveat == nil)
        #expect(SaveOutcome.saved.failure == nil)

        #expect(SaveOutcome.savedWithCaveat("caveat").caveat == "caveat")
        #expect(SaveOutcome.savedWithCaveat("caveat").failure == nil)

        #expect(SaveOutcome.notSaved("boom").caveat == nil)
        #expect(SaveOutcome.notSaved("boom").failure == "boom")
    }

    // MARK: - I3: a follow-up write's failure must not vanish

    /// A tag mapping written after the spool already landed. `failure` alone
    /// is not enough for a follow-up — `SpoolFormView` only reads it on the
    /// branch where the form stays open, which a follow-up never reaches, so
    /// a mapping that was refused outright reported a clean save.
    @Test func aFollowUpsFailureIsStillSomethingToSay() {
        #expect(SaveOutcome.notSaved("The tag mapping was not written.").followUpNote
            == "The tag mapping was not written.")
    }

    /// A caveat reaches the user by the same route: the record is on the
    /// server either way, so the two collapse here and only here.
    @Test func aFollowUpsCaveatTakesTheSameRouteAsItsFailure() {
        #expect(SaveOutcome.savedWithCaveat("partly").followUpNote == "partly")
    }

    /// Nothing to say covers both "it worked" and "there was nothing to do" —
    /// a follow-up that wrote nothing because nothing changed must not
    /// downgrade a clean save.
    @Test func aCleanFollowUpLeavesNothingToReport() {
        #expect(SaveOutcome.saved.followUpNote == nil)
    }
}
