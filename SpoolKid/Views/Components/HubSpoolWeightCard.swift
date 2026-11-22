//
//  HubSpoolWeightCard.swift
//  SpoolKid
//
//  Purpose: The inline weight card under a spool in the Scan Result Hub — the
//  spool's remaining weight, the Used and Measured inputs shared with Edit
//  Spool, and Save Weight. Views render and route; the arithmetic lives in
//  `SpoolWeightAdjustment` and the write in `SpoolWeightAdjustService`.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct HubSpoolWeightCard: View {

    let spool: Spool
    /// Opens Edit Spool, where the empty-spool weight is set.
    let onEditSpool: () -> Void
    /// Hands the hub the spool as the store now holds it after a save, so the
    /// hub's own copy (the row, Edit Spool) stops showing the pre-save weight.
    let onSaved: (Spool) -> Void

    @EnvironmentObject private var store: SpoolDataStore

    @State private var usedInput = ""
    @State private var measuredInput = ""
    @State private var isSaving = false
    @State private var savedNote: String?
    /// A caveat the write reported on a save that still landed. Rendered
    /// inline as well as posted to the root banner.
    @State private var savedCaveat: String?
    @State private var alertMessage: String?
    @FocusState private var focus: SpoolWeightAdjustRows.Field?

    /// The store's copy, so the shown remaining weight and the preview follow
    /// a save or a Klipper report, not the snapshot the hub was opened with.
    private var liveSpool: Spool {
        ScanResultHubView.refreshedSpool(id: spool.id, from: store.spools) ?? spool
    }

    private var input: SpoolWeightAdjustment.Input? {
        SpoolWeightAdjustment.input(used: usedInput, measured: measuredInput)
    }

    private var preview: SpoolWeightAdjustment.Preview? {
        guard let input else { return nil }
        return SpoolWeightAdjustment.Preview(
            before: liveSpool.remainingWeight,
            outcome: SpoolWeightAdjustment.outcome(
                of: input,
                currentRemaining: liveSpool.remainingWeight,
                emptySpoolWeight: liveSpool.spoolWeight
            )
        )
    }

    private var canSave: Bool {
        guard !isSaving, let preview else { return false }
        if case .remaining = preview.outcome { return true }
        return false
    }

    private var remainingLine: String {
        guard let remaining = liveSpool.remainingWeight else { return "Remaining: not recorded" }
        return "Remaining: \(SpoolWeightMath.displayWeight(remaining)) g"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(remainingLine)
                .font(.headline)

            SpoolWeightAdjustRows(
                usedInput: $usedInput,
                measuredInput: $measuredInput,
                showsUsed: true,
                measuring: liveSpool.spoolWeight == nil
                    ? .needsEmptySpoolWeight(onSetUp: onEditSpool)
                    : .available,
                preview: preview,
                focus: $focus
            )

            Button(action: save) {
                Text("Save Weight")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSave)

            if let savedNote {
                Text(savedNote)
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
            if let savedCaveat {
                Text(savedCaveat)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
        // A new value makes the last confirmation stale. Only a non-empty box
        // clears it: a successful save empties both boxes, and that must not
        // clear the line it has just set.
        .onChange(of: usedInput) { _, newValue in
            if !newValue.isEmpty { clearSavedLines() }
        }
        .onChange(of: measuredInput) { _, newValue in
            if !newValue.isEmpty { clearSavedLines() }
        }
        .alert(
            "Weight not saved",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func save() {
        guard let input else { return }
        focus = nil
        isSaving = true
        clearSavedLines()
        Task {
            let result = await SpoolWeightAdjustService.save(input, spoolID: spool.id, store: store)
            isSaving = false
            switch result {
            case .saved(let remaining, let caveat):
                usedInput = ""
                measuredInput = ""
                savedNote = SpoolWeightAdjustService.savedMessage(remaining: remaining)
                savedCaveat = caveat
                if let refreshed = ScanResultHubView.refreshedSpool(id: spool.id, from: store.spools) {
                    onSaved(refreshed)
                }
            case .refused(let message), .failed(let message):
                alertMessage = message
            }
        }
    }

    private func clearSavedLines() {
        savedNote = nil
        savedCaveat = nil
    }
}
