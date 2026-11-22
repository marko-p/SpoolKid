//
//  HubEntitySection.swift
//  SpoolKid
//
//  Purpose: One Scan Result Hub section (spec 2026-09-27, D1): a header
//  (label, optional Tag / backend switch), one entity row that edits on tap,
//  and a grid of that entity's tiles. What the section contains is decided by
//  HubActionPlan; this view only draws it.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI
import TipKit

/// Column counts for the tile grid: one row for up to three tiles, 2×2 for four.
enum HubTileGrid {
    nonisolated static func columnCount(forTileCount count: Int) -> Int {
        switch count {
        case ...1: return 1
        case 2, 4: return 2
        default: return 3
        }
    }
}

struct HubEntitySection<Row: View>: View {
    let title: String
    let section: HubSection
    @Binding var showsTagData: Bool
    let backendName: String
    var busyTiles: Set<HubTileID> = []
    @Environment(\.serverLink) private var serverLink
    var infoLines: [String] = []
    var showsIntroTip = false
    let onTile: (HubTileID) -> Void
    @ViewBuilder let row: () -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if section.showsSourceSwitch {
                    Picker("Filament data source", selection: $showsTagData) {
                        Text("Tag").tag(true)
                        Text(backendName).tag(false)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                if !infoLines.isEmpty {
                    InfoButton(title: title, lines: infoLines, introTip: showsIntroTip ? HubInfoTip() : nil)
                }
            }
            row()
            if !section.tiles.isEmpty {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 8),
                        count: HubTileGrid.columnCount(forTileCount: section.tiles.count)
                    ),
                    spacing: 8
                ) {
                    ForEach(section.tiles, id: \.id) { tile in
                        HubTile(action: tile, isBusy: busyTiles.contains(tile.id)) { onTile(tile.id) }
                            .disabled(tile.id.needsServer && serverLink.isDown)
                    }
                }
            }
        }
    }
}

/// The section's one entity row. A nil `onTap` means the row cannot be edited
/// (no chevron, not a button).
struct HubEntityRow: View {
    let title: String
    let subtitle: String?
    var swatchColors: FilamentColors? = nil
    var badge: String? = nil
    var isMuted = false
    let onTap: (() -> Void)?

    var body: some View {
        if let onTap {
            Button(action: onTap) { content(showsChevron: true) }
                .buttonStyle(.plain)
        } else {
            content(showsChevron: false)
        }
    }

    private func content(showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            if let swatchColors, swatchColors.primaryHex != nil {
                FilamentSwatch(colors: swatchColors, size: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(isMuted ? .body : .body.weight(.semibold))
                        .foregroundStyle(isMuted ? .secondary : .primary)
                        .lineLimit(2)
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(Color.accentColor)
                            .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1))
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    VStack(spacing: 24) {
        HubEntitySection(
            title: "Spool",
            section: HubSection(kind: .spool, tiles: [
                HubAction(id: .weigh, title: "Weigh", systemImage: "scalemass"),
                HubAction(id: .transferTag, title: "Transfer Tag", systemImage: "arrow.left.arrow.right"),
                HubAction(id: .unlink, title: "Unlink", systemImage: "xmark.circle"),
            ]),
            showsTagData: .constant(false),
            backendName: "Spoolman",
            onTile: { _ in }
        ) {
            HubEntityRow(title: "Spool #53", subtitle: "918 g left · 2 tags", onTap: {})
        }
        HubEntitySection(
            title: "Filament",
            section: HubSection(kind: .filament, tiles: [
                HubAction(id: .createNewSpool, title: "Create New Spool", systemImage: "plus", isPrimary: true),
            ], showsSourceSwitch: true),
            showsTagData: .constant(false),
            backendName: "Spoolman",
            onTile: { _ in }
        ) {
            HubEntityRow(title: "BROWN", subtitle: "AzureFilm • PLA • Basic", swatchColors: FilamentColors(hexes: ["B58548"]), badge: "tag differs", onTap: {})
        }
    }
    .padding()
}
