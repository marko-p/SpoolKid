//
//  TagStoreCopyView.swift
//  SpoolKid
//
//  Purpose: Copies tag links into one tag store, then says what landed. The
//  Library tab opens it to move SpoolLink links into Spoolman Tags; the Tag
//  Mapping delete flow opens it when the store to be kept is missing links.
//  The work itself is `TagStoreSync.copy`.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct TagStoreCopyView: View {
    let title: String
    /// What the sheet says before anything runs.
    let intro: String
    /// False when nothing CAN be copied — only filament conflicts remain, and
    /// those are the user's to settle in Spoolman. The sheet then explains
    /// and offers nothing to tap but Done.
    var canCopy = true
    /// Called once the copy has run, whatever its outcome.
    var onCopied: (() -> Void)?
    /// The copy itself. A store-to-store copy by default; the Backend page's
    /// on-device record copy passes its own (issue #24).
    let perform: @MainActor (SpoolDataStore) async -> TagStoreSync.TagCopyResult

    init(
        title: String, intro: String, canCopy: Bool = true, onCopied: (() -> Void)? = nil,
        perform: @escaping @MainActor (SpoolDataStore) async -> TagStoreSync.TagCopyResult
    ) {
        self.title = title
        self.intro = intro
        self.canCopy = canCopy
        self.onCopied = onCopied
        self.perform = perform
    }

    init(target: TagStore, intro: String, canCopy: Bool = true, onCopied: (() -> Void)? = nil) {
        self.init(
            title: "Copy to \(target.displayName)", intro: intro, canCopy: canCopy, onCopied: onCopied,
            perform: { await TagStoreSync.copy(into: target, in: $0) }
        )
    }

    @EnvironmentObject private var store: SpoolDataStore
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case ready
        case copying
        case done(TagStoreSync.TagCopyResult)
    }

    @State private var phase: Phase = .ready

    var body: some View {
        Group {
            switch phase {
            case .ready:
                readyForm
            case .copying:
                ProgressView("Copying…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done(let result):
                doneView(result)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(phase == .ready && canCopy ? "Cancel" : "Done") { dismiss() }
                    .disabled(phase == .copying)
            }
        }
        .interactiveDismissDisabled(phase == .copying)
    }

    private var readyForm: some View {
        Form {
            Section {
                Text(intro)
                    .font(.body)
                    .padding(.vertical, 4)
            }

            if canCopy {
                Section {
                    Button(action: copy) {
                        Text("Copy Links")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .listRowBackground(Color.clear)
            }
        }
    }

    @ViewBuilder
    private func doneView(_ result: TagStoreSync.TagCopyResult) -> some View {
        Form {
            Section {
                Label(
                    TagStoreText.copyResultSummary(copied: result.copied),
                    systemImage: result.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle"
                )
                .font(.body)
                .foregroundStyle(result.failures.isEmpty ? .green : .orange)
            }

            if !result.failures.isEmpty {
                Section("Not Copied") {
                    ForEach(result.failures, id: \.self) { failure in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(failure.label)
                                .font(.body)
                            Text(failure.message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func copy() {
        phase = .copying
        Task {
            let result = await perform(store)
            phase = .done(result)
            onCopied?()
        }
    }
}
