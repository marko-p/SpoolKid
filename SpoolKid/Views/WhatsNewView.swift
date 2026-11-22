//
//  WhatsNewView.swift
//  SpoolKid
//
//  Purpose: Renders release notes. One view, two presentations — the sheet
//  that appears after an upgrade, and the history pushed from Settings.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct WhatsNewView: View {

    /// The sheet carries the opt-out and a way out; the history screen is a
    /// plain pushed list. Nothing else differs.
    enum Presentation {
        case sheet
        case history
    }

    let entries: [ChangelogEntry]
    let presentation: Presentation

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppConfig.changelogAutoShowKey) private var autoShow: Bool = true

    var body: some View {
        switch presentation {
        case .sheet:
            // The Continue bar is attached ONLY here. Attaching
            // `safeAreaInset` unconditionally and emptying its content for the
            // history case still reserves the modifier's default spacing,
            // leaving a gap beneath the list on the screen that lives longest.
            NavigationStack {
                list.safeAreaInset(edge: .bottom) { continueBar }
            }
        case .history:
            list
        }
    }

    private var continueBar: some View {
        Button {
            dismiss()
        } label: {
            Text("Continue")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var list: some View {
        List {
            if entries.isEmpty {
                Section {
                    Text("No release notes yet.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(entries) { entry in
                Section {
                    ForEach(entry.changes) { change in
                        ChangeRow(change: change)
                    }
                } header: {
                    VersionHeader(entry: entry)
                }
            }

            if presentation == .sheet {
                Section {
                    Toggle("Show After Each Update", isOn: $autoShow)
                } footer: {
                    Text("You can always read past release notes in Settings.")
                }
            }
        }
        .navigationTitle("What's New")
        .navigationBarTitleDisplayMode(presentation == .sheet ? .large : .inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct VersionHeader: View {
    let entry: ChangelogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Version \(entry.version)")
                    .font(.headline)
                    .textCase(nil)
                Spacer()
                if let date = entry.formattedDate {
                    Text(date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
            if let headline = entry.headline {
                Text(headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ChangeRow: View {
    let change: ChangelogChange

    private var tint: Color {
        switch change.kind {
        case .added:    return .green
        case .improved: return .blue
        case .fixed:    return .orange
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: change.kind.symbolName)
                .foregroundStyle(tint)
                .font(.body)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(change.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(change.kind.rawValue.capitalized): \(change.text)")
    }
}
