//
//  TagIdentityExplanationView.swift
//  SpoolKid
//
//  Purpose: The one-time explanation for an upgrade that had both Write Spool
//  ID and tag links on (spec 2026-10-09 §5).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct TagIdentityExplanationView: View {
    /// Taken once, when the sheet presents, and held: "Use Spool ID Instead"
    /// changes the policy the lines name while the sheet animates away.
    @State private var lines: [String]
    let onKeep: () -> Void
    let onUseSpoolID: () -> Void

    init(lines: [String], onKeep: @escaping () -> Void, onUseSpoolID: @escaping () -> Void) {
        _lines = State(initialValue: lines)
        self.onKeep = onKeep
        self.onUseSpoolID = onUseSpoolID
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(lines, id: \.self) { Text($0) }
                }
                .padding()
            }
            .navigationTitle(TagStoreText.explanationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    // The frame goes on the label, so the whole width is the
                    // button; `.large` makes it at least 44 pt tall.
                    Button(action: onKeep) {
                        Text(TagStoreText.keepTagLinks).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("tagIdentityKeep")
                    Button(action: onUseSpoolID) {
                        Text(TagStoreText.useSpoolIDInstead).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("tagIdentityUseSpoolID")
                    Text(TagStoreText.spoolIDKeepsLinks)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.bar)
            }
        }
    }
}
