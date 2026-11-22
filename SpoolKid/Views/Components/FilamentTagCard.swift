//
//  FilamentTagCard.swift
//  SpoolKid
//
//  Purpose: The hub's answer for a tag linked to a filament type (spec 4), in
//  the hub's own layout (2026-10-11): the filament's section — its row and
//  its tiles — then the spools of that filament to open.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct FilamentTagCard: View {
    let filament: Filament
    let spools: [Spool]
    let section: HubSection
    let backendName: String
    var errorMessage: String? = nil
    /// Spec 2026-10-11: Transfer Tag also reaches filaments.
    var offersFilamentTargets: Bool = false
    var onTile: (HubTileID) -> Void
    var onOpenSpool: (Spool) -> Void
    var onEditFilament: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HubEntitySection(
                title: "Filament", section: section, showsTagData: .constant(false),
                backendName: backendName,
                infoLines: HubActionPlan.filamentTagInfoLines(
                    for: section, filamentTitle: filament.listTitle, backendName: backendName,
                    offersFilamentTargets: offersFilamentTargets
                ),
                showsIntroTip: true,
                onTile: onTile
            ) {
                HubEntityRow(
                    title: filament.listTitle,
                    subtitle: Self.detail(for: filament),
                    swatchColors: filament.colors,
                    onTap: onEditFilament
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.body)
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Spools of This Filament".uppercased())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if spools.isEmpty {
                    Text("No spools of this filament yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(spools) { spool in
                        Button {
                            onOpenSpool(spool)
                        } label: {
                            SpoolUsageRow(spool: spool, style: .underFilament)
                                .frame(minHeight: SpoolUsageRow.compactRowHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Vendor · Material", whichever are known; empty when neither is.
    nonisolated static func detail(for filament: Filament) -> String {
        [filament.vendor?.name, filament.material]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
