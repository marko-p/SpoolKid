//
//  DeleteConfirmationFlow.swift
//  SpoolKid
//
//  Purpose: Which dialog a vendor or filament delete shows next, given what
//  depends on the selection and the "Confirm Before Deleting" preference.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// The owner-approved dialog table (2026-09-15):
///
/// | dependents | confirm toggle | dialogs |
/// |---|---|---|
/// | none | on  | confirm → delete |
/// | none | off | delete |
/// | some | on  | dependents notice → final warning → cascade |
/// | some | off | dependents notice → cascade |
///
/// The dependents notice ignores the toggle: it is information the user has
/// not seen, not a second "are you sure" — only the final warning is that.
/// Cancelling at any step ends the flow and is the caller's to handle.
nonisolated enum DeleteConfirmationFlow {
    enum Step: Equatable, Sendable {
        case confirm
        case dependents(DeletionImpact)
        case finalWarning(DeletionImpact)
        case perform(cascade: Bool)
    }

    static func start(impact: DeletionImpact, confirmBeforeDelete: Bool) -> Step {
        if !impact.isEmpty { return .dependents(impact) }
        return confirmBeforeDelete ? .confirm : .perform(cascade: false)
    }

    static func next(afterAccepting step: Step, confirmBeforeDelete: Bool) -> Step {
        switch step {
        case .confirm:
            return .perform(cascade: false)
        case .dependents(let impact):
            return confirmBeforeDelete ? .finalWarning(impact) : .perform(cascade: true)
        case .finalWarning:
            return .perform(cascade: true)
        case .perform:
            return step
        }
    }
}
