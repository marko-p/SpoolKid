//
//  EmptySpoolRow.swift
//  SpoolKid
//
//  Purpose: One empty spool in a list — thumbnail, name, grams, and a
//  "Default" mark. Shared by the picker and the manage screen.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct EmptySpoolRow: View {
    let record: EmptySpoolRecord

    var body: some View {
        HStack(spacing: 12) {
            EmptySpoolThumbnail(photo: record.photo, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.listTitle)
                    .foregroundStyle(.primary)
                Text("\(SpoolWeightMath.formatWeight(record.weight)) g")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Stacked, so a long title is not squeezed by two badges side by side.
            VStack(alignment: .trailing, spacing: 4) {
                if record.isDefault { badge("Default") }
                if record.isManufacturerDefault { badge("Brand Default") }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: record))
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            .foregroundStyle(Color.accentColor)
    }

    static func accessibilityLabel(for record: EmptySpoolRecord) -> String {
        var label = "\(record.listTitle), \(SpoolWeightMath.formatWeight(record.weight)) grams"
        if record.isDefault { label += ", default" }
        if record.isManufacturerDefault { label += ", default for \(record.manufacturer) spools" }
        return label
    }
}
