//
//  SpoolIDMismatchCard.swift
//  SpoolKid
//
//  Purpose: The hub's question for a spool-ID tag whose filament differs from
//  the spool it names (Tag Links, spec 2026-10-09 §3).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct SpoolIDMismatchCard: View {
    let mismatch: SpoolIDMismatch
    let isWorking: Bool
    let onLinkAnyway: () -> Void
    let onOverwrite: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                "This tag carries the ID of \(mismatch.spool.listTitle) (#\(mismatch.spool.id)), but its filament differs.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.headline)
            if let linkError = mismatch.linkError {
                Text("Couldn't link this tag: \(linkError)")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Tag: \(mismatch.tagSummary)")
                Text("Spool: \(mismatch.spoolSummary)")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            // Full-width labels at `.large` (at least 44 pt) for the bench.
            // All three bordered: the sections below keep their own primary
            // action, and a screen has one.
            VStack(spacing: 12) {
                Button(action: onLinkAnyway) {
                    Text("Link Anyway").frame(maxWidth: .infinity)
                }
                Button(action: onOverwrite) {
                    Text("Overwrite Tag from Spool").frame(maxWidth: .infinity)
                }
                Button(action: onCreate) {
                    Text("Create New Spool from Tag").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .disabled(isWorking)
        .padding()
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}
