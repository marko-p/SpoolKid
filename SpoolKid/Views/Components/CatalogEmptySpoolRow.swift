//
//  CatalogEmptySpoolRow.swift
//  SpoolKid
//
//  Purpose: One catalogue empty-spool weight in the Empty Spools picker —
//  spool type, the net sizes and products it holds, and its grams.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct CatalogEmptySpoolRow: View {
    let row: CatalogEmptySpool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(for: row))
                    .foregroundStyle(.primary)
                Text(Self.detail(for: row))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Text("\(SpoolWeightMath.formatWeight(row.grams)) g")
                .font(.body.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: row))
    }

    static func title(for row: CatalogEmptySpool) -> String {
        guard let type = row.spoolType else { return "Spool" }
        return "\(type.prefix(1).uppercased())\(type.dropFirst()) spool"
    }

    static func detail(for row: CatalogEmptySpool) -> String {
        let products = row.productCount == 1
            ? "1 product: \(row.exampleName)"
            : "\(row.productCount) products, e.g. \(row.exampleName)"
        guard !row.netWeights.isEmpty else { return products }
        return "\(row.netWeights.map { size($0) }.joined(separator: ", ")) · \(products)"
    }

    /// Whole hundreds from 1 kg up read as kilograms; anything else as grams.
    static func size(_ grams: Double) -> String {
        guard grams >= 1000, grams.truncatingRemainder(dividingBy: 100) == 0 else {
            return "\(SpoolWeightMath.formatWeight(grams)) g"
        }
        return "\(SpoolWeightMath.formatWeight(grams / 1000)) kg"
    }

    static func accessibilityLabel(for row: CatalogEmptySpool) -> String {
        "\(title(for: row)), \(SpoolWeightMath.formatWeight(row.grams)) grams, \(detail(for: row))"
    }
}
