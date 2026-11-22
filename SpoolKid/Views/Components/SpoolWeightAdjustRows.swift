//
//  SpoolWeightAdjustRows.swift
//  SpoolKid
//
//  Purpose: The rows that adjust a spool's remaining weight after a print —
//  grams the print used, or a scale reading — and the preview of what the
//  adjustment leaves. Shared by Edit Spool and the Scan Result Hub so the two
//  cannot disagree about the words, the fields or the preview.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// The Used-this-print and Measured rows, with the preview beneath them.
///
/// Filling one of the two clears the other: an adjustment is one or the other,
/// never both. The caller owns the strings and turns them into a change; this
/// view only renders them and says what they would leave.
struct SpoolWeightAdjustRows: View {

    nonisolated enum Field: Hashable {
        case used, measured
    }

    /// Whether a scale reading can be taken on this spool. A spool with no
    /// empty-spool weight cannot turn a gross reading into remaining weight, so
    /// the caller offers to set that up instead.
    nonisolated enum Measuring {
        case available
        case needsEmptySpoolWeight(onSetUp: () -> Void)
    }

    @Binding var usedInput: String
    @Binding var measuredInput: String
    let showsUsed: Bool
    let measuring: Measuring
    let preview: SpoolWeightAdjustment.Preview?
    var focus: FocusState<Field?>.Binding

    var body: some View {
        Group {
            if showsUsed {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Used (g)")
                        Spacer()
                        TextField("0", text: $usedInput)
                            .keyboardType(.decimalPad)
                            .focused(focus, equals: .used)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    Text(SpoolWeightAdjustment.usedCaption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            measuringRows

            previewRows
        }
        .onChange(of: usedInput) { _, newValue in
            if !newValue.isEmpty { measuredInput = "" }
        }
        .onChange(of: measuredInput) { _, newValue in
            if !newValue.isEmpty { usedInput = "" }
        }
    }

    @ViewBuilder
    private var measuringRows: some View {
        switch measuring {
        case .available:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Measured Weight (g)")
                    Spacer()
                    TextField("0", text: $measuredInput)
                        .keyboardType(.decimalPad)
                        .focused(focus, equals: .measured)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                Text(SpoolFormView.measuredWeightFrame)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScaleWeightRow { grams in
                    measuredInput = String(grams)
                    focus.wrappedValue = nil
                }
            }
        case .needsEmptySpoolWeight(let onSetUp):
            // Borderless, or the enclosing Form row swallows the tap (see
            // `ScaleWeightRow`).
            Button(SpoolWeightAdjustment.needsEmptySpoolWeightNote, action: onSetUp)
                .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var previewRows: some View {
        if let preview {
            VStack(alignment: .leading, spacing: 4) {
                if let text = SpoolWeightAdjustment.previewText(preview) {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(isNegative(preview.outcome) ? .orange : .secondary)
                }
                if case .negative = preview.outcome {
                    Text(SpoolWeightAdjustment.negativeNote)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                if case .needsCurrentRemaining = preview.outcome {
                    Text(SpoolWeightAdjustment.needsCurrentRemainingNote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func isNegative(_ outcome: SpoolWeightAdjustment.Outcome) -> Bool {
        if case .negative = outcome { return true }
        return false
    }
}
