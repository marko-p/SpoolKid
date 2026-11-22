//
//  SpoolFoldRow.swift
//  SpoolKid
//
//  Purpose: One fold of identical unused spools in the grouped spool list. It
//  stands for its members until the user expands it. Its label is the count and
//  the weight each spool started with; the rules that decide what folds live in
//  SpoolListGrouping (conventions A2/A3).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct SpoolFoldRow: View {
    let fold: SpoolFold
    let isExpanded: Bool
    let onToggle: () -> Void

    init(fold: SpoolFold, isExpanded: Bool, onToggle: @escaping () -> Void) {
        self.fold = fold
        self.isExpanded = isExpanded
        self.onToggle = onToggle
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                chevron
                countLine
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: SpoolUsageRow.compactRowHeight, alignment: .leading)
            .contentShape(Rectangle())
            // Fixed colours: a List button tints its label and the hierarchical
            // styles resolve against that tint.
            .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.accessibilityLabel(for: fold))
        // The chevron is hidden, so the state is announced on the button itself.
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    private var countLine: some View {
        Text(Self.label(for: fold))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.secondary)
            .lineLimit(1)
    }

    /// Collapsed, the chevron points right. The button label already reads the
    /// text, so the glyph is hidden from VoiceOver.
    private var chevron: some View {
        Image(systemName: "chevron.down")
            .foregroundStyle(Color.secondary)
            .rotationEffect(.degrees(isExpanded ? 0 : -90))
            .accessibilityHidden(true)
    }

    /// The count of unused spools and the weight each one started with. The basis
    /// is never unknown for a fold (`SpoolListGrouping` only folds spools with a
    /// weight basis), so the "each" phrase is always true.
    static func label(for fold: SpoolFold) -> String {
        "\(fold.spools.count) unused · \(SpoolUsage.weightText(fold.basis)) each"
    }

    /// What VoiceOver reads: the count and the weight each spool started with,
    /// spelled out. "·" is a symbol a screen reader would stumble over.
    static func accessibilityLabel(for fold: SpoolFold) -> String {
        "\(fold.spools.count) unused spools, \(SpoolUsage.spokenWeight(fold.basis)) each"
    }
}
