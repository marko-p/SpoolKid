//
//  CascadeDeleteDialogs.swift
//  SpoolKid
//
//  Purpose: The dialog sequence a vendor or filament delete runs through —
//  plain confirm, dependents notice, final warning — shared by the edit forms
//  (CascadeDeleteButton) and the Manage lists' bulk bars, so one delete story
//  is told in one voice.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// Renders whichever dialog `step` names and hands the accepted step back
/// through `onAccept`. It owns no decisions: `DeleteConfirmationFlow` decides
/// what comes next and the caller performs the delete.
struct CascadeDeleteDialogs: ViewModifier {
    @Binding var step: DeleteConfirmationFlow.Step?
    /// "Polymaker", or "3 manufacturers" for a selection.
    let subject: String
    let isPlural: Bool
    /// How many records the user selected — the final warning counts them in.
    let selectedCount: Int
    /// "Delete Manufacturer?" / "Delete 3 Manufacturers?"
    let confirmTitle: String
    /// The destructive button in the plain confirm: "Delete Manufacturer" / "Delete".
    let confirmActionTitle: String
    /// "Manufacturer Has Filaments" / "Filament Has Spools".
    let dependentsTitle: String
    let storageNoun: String
    let confirmBeforeDelete: Bool
    /// Runs the delete. `cascade` is true when the dependents go too.
    let perform: (_ cascade: Bool) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                confirmTitle,
                isPresented: presented { $0 == .confirm },
                titleVisibility: .visible
            ) {
                Button(confirmActionTitle, role: .destructive) { advance() }
                Button("Cancel", role: .cancel) { step = nil }
            } message: {
                Text("\(subject) will be permanently deleted from \(storageNoun).")
            }
            .confirmationDialog(
                dependentsTitle,
                isPresented: presented { if case .dependents = $0 { true } else { false } },
                titleVisibility: .visible
            ) {
                Button("Delete All…", role: .destructive) { advance() }
                Button("Cancel", role: .cancel) { step = nil }
            } message: {
                if case .dependents(let impact) = step {
                    Text(Self.dependentsMessage(subject: subject, isPlural: isPlural, impact: impact))
                }
            }
            .confirmationDialog(
                finalWarningTitle,
                isPresented: presented { if case .finalWarning = $0 { true } else { false } },
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) { advance() }
                Button("Cancel", role: .cancel) { step = nil }
            } message: {
                if case .finalWarning(let impact) = step {
                    Text(Self.finalWarningMessage(subject: subject, impact: impact, storageNoun: storageNoun))
                }
            }
    }

    // MARK: - Copy

    static func dependentsMessage(subject: String, isPlural: Bool, impact: DeletionImpact) -> String {
        "\(subject) \(isPlural ? "are" : "is") used by \(impact.dependentsPhrase). "
            + "Deleting \(isPlural ? "them" : "it") deletes them too."
    }

    static func finalWarningTitle(impact: DeletionImpact, selectedCount: Int) -> String {
        "Permanently Delete \(impact.totalItemCount(selected: selectedCount)) Items?"
    }

    static func finalWarningMessage(subject: String, impact: DeletionImpact, storageNoun: String) -> String {
        let tags = impact.spoolIDs.isEmpty ? "" : "Tags mapped to those spools will no longer find them. "
        return "\(subject), along with \(impact.dependentsPhrase), will be permanently deleted from \(storageNoun). "
            + tags + "This cannot be undone."
    }

    /// The title is read before the dialog's own body runs, so it falls back to
    /// the plain wording rather than counting a step that is not showing.
    private var finalWarningTitle: String {
        if case .finalWarning(let impact) = step {
            return Self.finalWarningTitle(impact: impact, selectedCount: selectedCount)
        }
        return confirmTitle
    }

    /// A dismissal clears the flow only while the step is still this dialog's.
    /// The check is deferred out of the view update: iOS 27 reports a dismissal
    /// a second time from inside one, where `step` still reads the value this
    /// binding was built with — `.dependents` after "Delete All…" had already
    /// moved it to `.finalWarning` — and clearing on that stale read closed the
    /// final warning the moment it opened.
    private func presented(_ matches: @escaping (DeleteConfirmationFlow.Step) -> Bool) -> Binding<Bool> {
        Binding(
            get: { step.map(matches) ?? false },
            set: { shown in
                guard !shown else { return }
                Task { if step.map(matches) ?? false { step = nil } }
            }
        )
    }

    private func advance() {
        guard let current = step else { return }
        let next = DeleteConfirmationFlow.next(afterAccepting: current, confirmBeforeDelete: confirmBeforeDelete)
        step = nil
        if case .perform(let cascade) = next { perform(cascade) } else { step = next }
    }
}

extension View {
    func cascadeDeleteDialogs(
        step: Binding<DeleteConfirmationFlow.Step?>,
        subject: String,
        isPlural: Bool = false,
        selectedCount: Int = 1,
        confirmTitle: String,
        confirmActionTitle: String,
        dependentsTitle: String,
        storageNoun: String,
        confirmBeforeDelete: Bool,
        perform: @escaping (_ cascade: Bool) -> Void
    ) -> some View {
        modifier(CascadeDeleteDialogs(
            step: step,
            subject: subject,
            isPlural: isPlural,
            selectedCount: selectedCount,
            confirmTitle: confirmTitle,
            confirmActionTitle: confirmActionTitle,
            dependentsTitle: dependentsTitle,
            storageNoun: storageNoun,
            confirmBeforeDelete: confirmBeforeDelete,
            perform: perform
        ))
    }
}
