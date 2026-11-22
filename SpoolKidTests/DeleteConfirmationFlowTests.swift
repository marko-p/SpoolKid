//
//  DeleteConfirmationFlowTests.swift
//  SpoolKidTests
//

import Testing
import Foundation
@testable import SpoolKid

/// One test per row of the owner-approved dialog table (spec, 2026-09-15).
struct DeleteConfirmationFlowTests {
    private let none = DeletionImpact(filamentIDs: [], spoolIDs: [], archivedSpoolCount: 0)
    private let some = DeletionImpact(filamentIDs: [], spoolIDs: [10, 11], archivedSpoolCount: 1)

    @Test func noDependentsWithConfirmationOnAsksOnceThenDeletes() {
        let first = DeleteConfirmationFlow.start(impact: none, confirmBeforeDelete: true)
        #expect(first == .confirm)
        #expect(DeleteConfirmationFlow.next(afterAccepting: first, confirmBeforeDelete: true) == .perform(cascade: false))
    }

    @Test func noDependentsWithConfirmationOffDeletesImmediately() {
        #expect(DeleteConfirmationFlow.start(impact: none, confirmBeforeDelete: false) == .perform(cascade: false))
    }

    @Test func dependentsWithConfirmationOnShowsNoticeThenFinalWarningThenCascades() {
        let first = DeleteConfirmationFlow.start(impact: some, confirmBeforeDelete: true)
        #expect(first == .dependents(some))
        let second = DeleteConfirmationFlow.next(afterAccepting: first, confirmBeforeDelete: true)
        #expect(second == .finalWarning(some))
        #expect(DeleteConfirmationFlow.next(afterAccepting: second, confirmBeforeDelete: true) == .perform(cascade: true))
    }

    /// The notice is new information, so the toggle never skips it; only the
    /// second warning follows the toggle (owner decision 1).
    @Test func dependentsWithConfirmationOffShowsNoticeThenCascades() {
        let first = DeleteConfirmationFlow.start(impact: some, confirmBeforeDelete: false)
        #expect(first == .dependents(some))
        #expect(DeleteConfirmationFlow.next(afterAccepting: first, confirmBeforeDelete: false) == .perform(cascade: true))
    }
}
