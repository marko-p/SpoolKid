//
//  LoadoutPlanView.swift
//  SpoolKid
//
//  Purpose: Suggested Colors: each picked color's closest spool, by filament
//  name, and other filaments close enough to be alternatives.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct LoadoutPlanView: View {
    let picks: LoadoutPicks
    let material: String
    let minimumRemaining: Double
    let includesMultiColor: Bool

    @EnvironmentObject private var store: SpoolDataStore

    private var result: Result<[LoadoutPlanner.ColorResult], LoadoutPlanner.Failure> {
        LoadoutPlanner.match(LoadoutPlanner.Request(
            hexes: picks.hexes, spools: LoadoutSpools.planner(store.activeSpools),
            primaryMaterial: material, minimumRemaining: minimumRemaining, includesMultiColor: includesMultiColor
        ))
    }

    var body: some View {
        List {
            switch result {
            case .failure(let failure):
                Text(failure.message).font(.body).foregroundStyle(.red)
            case .success(let colors):
                Section("Colors") {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                        if let closest = color.closest {
                            matchRow(color.hex, closest)
                        }
                    }
                }
                let alternatives = colors.flatMap { color in color.alternatives.map { (color.hex, $0) } }
                if !alternatives.isEmpty {
                    Section {
                        ForEach(Array(alternatives.enumerated()), id: \.offset) { _, pair in
                            matchRow(pair.0, pair.1)
                        }
                    } header: {
                        Text("Alternatives")
                    } footer: {
                        Text("Other filaments within ΔE \(Int(LoadoutPlanner.alternativeDeltaE)) of a color.")
                    }
                }
            }
        }
        .navigationTitle("Suggested Colors")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The color, the spool's swatch, the filament's name and how close it is.
    private func matchRow(_ hex: String, _ match: LoadoutPlanner.Match) -> some View {
        HStack(spacing: 8) {
            FilamentSwatch(colors: FilamentColors(hexes: [hex], pattern: .coextruded), size: 32)
            Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
            FilamentSwatch(
                colors: FilamentColors(
                    hexes: match.spool.isMultiColor ? match.spool.colorHexes : [match.spool.hex], pattern: .coextruded
                ),
                size: 32
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(match.spool.title)
                Text(detail(match)).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "ΔE %.1f", match.deltaE)).font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(_ match: LoadoutPlanner.Match) -> String {
        var parts = [LoadoutPlanText.label(deltaE: match.deltaE), "\(Int(match.spool.remaining.rounded())) g left"]
        if match.spool.isMultiColor { parts.append("multi-color, matched on \(match.spool.hex)") }
        return parts.joined(separator: " · ")
    }
}
