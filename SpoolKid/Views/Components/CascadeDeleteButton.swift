//
//  CascadeDeleteButton.swift
//  SpoolKid
//
//  Purpose: The delete button for a vendor or filament form. Counts what
//  depends on the record before anything is deleted, and offers the cascade
//  rather than letting a backend refuse (or silently orphan) behind the user's
//  back.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// Replaces `DestructiveFormButton` for the two entities that can have
/// dependents. The step sequence is `DeleteConfirmationFlow`'s, the counting is
/// `SpoolDataStore.deletionImpact`'s, and this view only renders and routes (A2).
///
/// `DestructiveFormButton` stays for spools and locations, which have nothing
/// hanging off them.
struct CascadeDeleteButton: View {
    enum Record {
        case vendor(id: Int, name: String)
        case filament(id: Int, name: String)

        var name: String {
            switch self {
            case .vendor(_, let name), .filament(_, let name): name
            }
        }

        /// "Manufacturer" / "Filament" — the word used in every title on this button.
        var titleNoun: String {
            switch self {
            case .vendor: "Manufacturer"
            case .filament: "Filament"
            }
        }

        /// What a cascade takes: a vendor's filaments, a filament's spools.
        var dependentsTitle: String {
            switch self {
            case .vendor: "Manufacturer Has Filaments"
            case .filament: "Filament Has Spools"
            }
        }
    }

    let record: Record
    @ObservedObject var store: SpoolDataStore
    let confirmBeforeDelete: Bool
    /// Called after the record is actually gone — the form's `dismiss`.
    let onDeleted: () -> Void

    @State private var step: DeleteConfirmationFlow.Step?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Button(role: .destructive) {
            begin()
        } label: {
            if isWorking {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text("Delete \(record.titleNoun)").frame(maxWidth: .infinity)
            }
        }
        .disabled(isWorking)
        .needsServer()
        .cascadeDeleteDialogs(
            step: $step,
            subject: record.name,
            confirmTitle: "Delete \(record.titleNoun)?",
            confirmActionTitle: "Delete \(record.titleNoun)",
            dependentsTitle: record.dependentsTitle,
            storageNoun: store.capabilities.storageNoun,
            confirmBeforeDelete: confirmBeforeDelete,
            perform: { cascade in Task { await perform(cascade: cascade) } }
        )
        .alert(
            "Could Not Delete \(record.titleNoun)",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    // MARK: - Flow

    /// Counting comes first, always: the dialogs cannot be chosen before the
    /// dependents are known, and a count that could not be made deletes nothing.
    private func begin() {
        isWorking = true
        Task {
            let impact = await currentImpact()
            isWorking = false
            guard let impact else {
                errorMessage = store.errorMessage
                    ?? "\(store.capabilities.storageNoun) could not be reached, so nothing was deleted."
                return
            }
            let first = DeleteConfirmationFlow.start(impact: impact, confirmBeforeDelete: confirmBeforeDelete)
            if case .perform(let cascade) = first {
                await perform(cascade: cascade)
            } else {
                step = first
            }
        }
    }

    private func perform(cascade: Bool) async {
        isWorking = true
        let didDelete = await delete(cascade: cascade)
        isWorking = false
        let outcome = SaveOutcome.classify(
            didSave: didDelete,
            message: store.errorMessage,
            failureFallback: "The \(record.titleNoun.lowercased()) could not be deleted."
        )
        if outcome.didWrite { onDeleted() } else { errorMessage = outcome.failure }
    }

    private func currentImpact() async -> DeletionImpact? {
        switch record {
        case .vendor(let id, _): await store.deletionImpact(vendorIDs: [id])
        case .filament(let id, _): await store.deletionImpact(filamentIDs: [id])
        }
    }

    private func delete(cascade: Bool) async -> Bool {
        switch record {
        case .vendor(let id, _):
            cascade ? await store.deleteVendorCascading(id: id) : await store.deleteVendor(id: id)
        case .filament(let id, _):
            cascade ? await store.deleteFilamentCascading(id: id) : await store.deleteFilament(id: id)
        }
    }
}
