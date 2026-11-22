//
//  ToolheadActionButtons.swift
//  SpoolKid
//
//  Purpose: The toolhead sheet's large buttons (owner's layout "B, flipped",
//  2026-11-11): tiles in rows of two, then the situation's big action at the
//  bottom, closest to the thumb.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct ToolheadTile: Identifiable {
    let title: String
    let systemImage: String
    var destructive = false
    var isEnabled = true
    let action: () -> Void

    var id: String { title }
}

/// Which of Read Tag and Write Tag the toolhead sheet offers. Pure rules.
nonisolated enum ToolheadTagActions {
    enum Write: Equatable {
        case hidden
        case enabled
        case disabled(reason: String)
    }

    /// Both are hidden unless the printer is online (the plugin's status can
    /// stay `.ready` after the socket closes), the plugin is usable and the
    /// toolhead reports a tag. A busy printer disables Write Tag with the busy note; Read Tag
    /// stays offered, and the sheet's grid disables it while the printer is busy.
    static func available(
        connection: PrinterConnection, plugin: PrinterTagPlugin, toolhead: ToolheadState,
        hasLibrarySpool: Bool, isPrinterBusy: Bool
    ) -> (read: Bool, write: Write) {
        guard case .online = connection, plugin.isUsable, let uid = toolhead.tagUID, !uid.isEmpty else { return (false, .hidden) }
        guard hasLibrarySpool else { return (true, .hidden) }
        if isPrinterBusy { return (true, .disabled(reason: TagReaderOption.busyNote)) }
        // 4 bytes (8 hex characters) is MIFARE Classic, which the printer cannot write.
        if uid.count == 8 {
            return (true, .disabled(reason: toolhead.isOfficial
                ? TagReaderOption.snapmakerReason : TagReaderOption.unwritableReason))
        }
        return (true, .enabled)
    }
}

/// Rows of up to two tiles. An empty row is left out; a lone tile fills its row.
struct ToolheadTileGrid: View {
    let rows: [[ToolheadTile]]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(rows.filter { !$0.isEmpty }.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { tile in
                        ToolheadTileButton(tile: tile).disabled(!tile.isEnabled)
                    }
                }
            }
        }
    }
}

private struct ToolheadTileButton: View {
    let tile: ToolheadTile
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: tile.action) {
            VStack(spacing: 6) {
                Image(systemName: tile.systemImage).font(.title3)
                Text(tile.title).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
            }
            .foregroundStyle(isEnabled ? (tile.destructive ? Color.red : Color.accentColor) : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemGroupedBackground)))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

/// A full-width action. `prominent` is the sheet's one primary action.
struct ToolheadBigButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(prominent ? Color.white : (isEnabled ? Color.accentColor : Color.secondary))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    RoundedRectangle(cornerRadius: 14).fill(
                        prominent
                            ? (isEnabled ? Color.accentColor : Color.secondary.opacity(0.5))
                            : Color(uiColor: .secondarySystemGroupedBackground)
                    )
                )
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
