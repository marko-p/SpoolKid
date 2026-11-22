//
//  MigrationReviewView.swift
//  SpoolKid
//
//  Purpose: Pre-flight review for the one-shot local → server migration.
//  Lets the user flip each conflict between Reuse and Create, then executes the
//  resolved plan and surfaces progress, full-success confirmation, and partial-
//  failure retry.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// Pure helpers that format the migration review copy. Kept testable and
/// free of view state.
struct MigrationReviewSummary {
    static func header(vendors: Int, filaments: Int, spools: Int, conflicts: Int) -> String {
        let entitySummary = "\(vendors) \(vendors == 1 ? "manufacturer" : "manufacturers"), \(filaments) \(filaments == 1 ? "filament" : "filaments"), \(spools) \(spools == 1 ? "spool" : "spools")"
        if conflicts == 0 {
            return entitySummary
        }
        return "\(entitySummary) · \(conflicts) \(conflicts == 1 ? "conflict" : "conflicts") to review"
    }

    static func createLine(creates: Int, reuses: Int) -> String {
        let created = "+\(creates) new \(creates == 1 ? "item" : "items") will be created"
        guard reuses > 0 else { return created }
        return created + " · \(reuses) will be linked to \(reuses == 1 ? "a record" : "records") "
            + "the server already has"
    }

    /// Counts CREATES, not planned rows. It read "Upload 2 items" beside a note
    /// saying "+1 new item will be created" whenever a manufacturer was reused
    /// — the reused row is linked, not uploaded (device finding, 2026-08-29).
    /// With nothing to create there is still work to do, and a different verb
    /// for it: every row is linked to a record the server already has.
    static func uploadTitle(creates: Int, reuses: Int) -> String {
        guard creates > 0 else {
            return "Link \(reuses) \(reuses == 1 ? "item" : "items")"
        }
        return "Upload \(creates) \(creates == 1 ? "item" : "items")"
    }

    /// What one blocked row is missing, for the review list. Names the fields
    /// rather than repeating the backend's sentence: the sheet behind the Fix
    /// button renders exactly these, so the row and the sheet agree.
    static func missingLine(_ requirements: [FilamentCreateRequirement]) -> String {
        "Needs " + requirements.map(\.label).joined(separator: ", ")
    }

    static func blockedLine(count: Int) -> String {
        "\(count) \(count == 1 ? "item" : "items") can't be uploaded yet"
    }

    /// Counts the rows that never reached the server. When every row did and
    /// only some of their details stayed behind, there is no such count — what
    /// goes is the on-device copy of those details.
    static func discardTitle(result: MigrationResult) -> String {
        let count = result.failed.count + result.skipped.count
        guard count > 0 else { return "Delete the on-device copies?" }
        return "Discard \(count) \(count == 1 ? "item" : "items")?"
    }

    /// The partial-run screen's title. A run where every row uploaded and only
    /// some details stayed behind is not an incomplete upload.
    static func resultTitle(result: MigrationResult) -> String {
        result.failed.isEmpty && result.skipped.isEmpty ? "Some Details Not Uploaded" : "Upload Incomplete"
    }

    /// The review form's discard, which is about the WHOLE pending library
    /// rather than the leftovers of a partial run — so it says "everything",
    /// not a count that could be read as "some of it".
    static func discardEverythingTitle() -> String {
        "Discard your on-device library?"
    }

    static func discardEverythingMessage(backend: String) -> String {
        "Nothing is uploaded to \(backend), and every spool, filament and "
            + "manufacturer on this iPhone is deleted. This cannot be undone."
    }

    static func discardMessage(backend: String, result: MigrationResult) -> String {
        let unuploaded = result.failed.count + result.skipped.count
        guard !result.notStored.isEmpty else {
            return "They stay off \(backend) and are removed from this iPhone. "
                + "Items that were uploaded are not affected."
        }
        guard unuploaded > 0 else {
            return "Everything is on \(backend). The details it could not store, listed above, "
                + "are deleted from this iPhone. This cannot be undone."
        }
        return "They stay off \(backend) and are removed from this iPhone, together with the "
            + "details \(backend) could not store for the items that were uploaded. This cannot be undone."
    }

    /// The one-line tally above the per-item list.
    static func outcomeLine(result: MigrationResult) -> String {
        let line = "\(result.created) created, \(result.reused) reused · "
            + "\(result.failed.count) failed, \(result.skipped.count) skipped"
        guard !result.notStored.isEmpty else { return line }
        return line + " · \(result.notStored.count) saved without some details"
    }
}

struct MigrationReviewView: View {
    /// `@StateObject`, not `@ObservedObject`, and built from an autoclosure so
    /// the object is created ONCE per presentation.
    ///
    /// The sheet's content closure in `ContentView` constructs the service
    /// inline, and every write during an upload republishes `SpoolDataStore`
    /// (each repository call ends in `refresh()`), which re-runs that closure.
    /// As an `@ObservedObject` the view then swapped to a brand-new service
    /// whose `lastResult` was `nil`, so it fell straight back to the review
    /// form: the Upload button looked like it did nothing, however many times
    /// it was tapped, even though the upload had run and failed (device
    /// finding, 2026-08-29).
    @StateObject private var service: MigrationService
    @State private var plan: MigrationPlan?
    @State private var buildFailed = false
    @State private var isUploading = false
    @State private var showSuccess = false
    /// Rows the active backend would refuse, keyed by local id — computed from
    /// the plan the moment it is built, so the refusal is on screen with a way
    /// to act on it BEFORE the Upload button is ever tapped.
    @State private var blocked: [Int: [FilamentCreateRequirement]] = [:]
    @State private var fixTarget: BlockedRow?
    @State private var confirmDiscard = false
    @Environment(\.dismiss) private var dismiss

    init(service: @autoclosure @escaping () -> MigrationService) {
        _service = StateObject(wrappedValue: service())
    }

    var body: some View {
        NavigationStack {
            Group {
                if buildFailed {
                    buildFailedView
                } else if showSuccess {
                    successView
                } else if let result = service.lastResult, !result.isComplete {
                    partialResultView(result: result)
                } else if plan != nil {
                    reviewForm(plan: Binding(
                        get: { self.plan! },
                        set: { self.plan = $0 }
                    ))
                } else {
                    ProgressView("Preparing migration…")
                }
            }
            .navigationTitle("Migrate to \(service.capabilities.displayName)")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { await loadPlan() }
        .onChange(of: plan?.resolutions) { _, _ in recheckBlocked() }
        .sheet(item: $fixTarget, onDismiss: reloadAfterFix) { row in
            MigrationFixView(
                label: row.label,
                requirements: row.requirements,
                manufacturers: service.manufacturerOptions(),
                apply: { await service.applyFilamentFix($0) },
                localId: row.localId,
                backendName: service.capabilities.displayName
            )
        }
    }

    // MARK: - Build states

    private var buildFailedView: some View {
        ContentUnavailableView {
            Label("Could Not Reach \(service.capabilities.displayName)", systemImage: "exclamationmark.triangle")
        } description: {
            Text(service.buildError ?? "The server is unreachable.")
        } actions: {
            Button("Retry") {
                buildFailed = false
                Task { await loadPlan() }
            }
            .buttonStyle(.borderedProminent)

            Button("Cancel") {
                dismiss()
            }
        }
    }

    /// A row flipped from Reuse to Create after the plan was built was never
    /// checked against the backend's rules; re-running the pre-flight here is
    /// what lists it with a Fix button instead of letting it fail at upload.
    private func recheckBlocked() {
        guard let plan else { return }
        blocked = service.blockedFilaments(in: plan)
    }

    private func loadPlan() async {
        guard plan == nil && !buildFailed else { return }
        if let built = await service.buildPlan() {
            plan = built
            blocked = service.blockedFilaments(in: built)
        } else {
            buildFailed = true
        }
    }

    /// One filament the backend would refuse, and what it wants.
    struct BlockedRow: Identifiable, Equatable {
        let localId: Int
        let label: String
        let requirements: [FilamentCreateRequirement]
        var id: Int { localId }
    }

    private func blockedRows(in plan: MigrationPlan) -> [BlockedRow] {
        plan.filaments.compactMap { item in
            guard let requirements = blocked[item.localId] else { return nil }
            return BlockedRow(localId: item.localId, label: item.label, requirements: requirements)
        }
    }

    /// Re-plans after a fix rather than patching the plan in place: the fix
    /// wrote to the local row (and may have created a manufacturer, which is a
    /// new row to upload), so the plan built before it is stale.
    private func reloadAfterFix() {
        plan = nil
        blocked = [:]
        Task { await loadPlan() }
    }

    // MARK: - Review form

    private func reviewForm(plan: Binding<MigrationPlan>) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Upload your library to \(service.capabilities.displayName)")
                        .font(.headline)
                    Text(MigrationReviewSummary.header(
                        vendors: plan.wrappedValue.vendors.count,
                        filaments: plan.wrappedValue.filaments.count,
                        spools: plan.wrappedValue.spools.count,
                        conflicts: plan.wrappedValue.conflictCount
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)

            ConflictSection(
                title: "Manufacturers",
                items: plan.vendors,
                candidateLabel: { $0.name }
            )

            ConflictSection(
                title: "Filaments",
                items: plan.filaments,
                candidateLabel: { FilamentMatchKey($0).label }
            )

            ConflictSection(
                title: "Spools",
                items: plan.spools,
                candidateLabel: { FilamentMatchKey($0.filament).label }
            )

            let rows = blockedRows(in: plan.wrappedValue)
            if !rows.isEmpty {
                Section {
                    ForEach(rows) { row in
                        Button {
                            fixTarget = row
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.label)
                                        .foregroundStyle(.primary)
                                    Text(MigrationReviewSummary.missingLine(row.requirements))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("Fix")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                } header: {
                    Label(
                        MigrationReviewSummary.blockedLine(count: rows.count),
                        systemImage: "exclamationmark.triangle"
                    )
                } footer: {
                    Text("\(service.capabilities.displayName) requires these fields. "
                         + "Fix them here, or upload without them — they will fail.")
                }
            }

            if plan.wrappedValue.createCount > 0 {
                Section {
                    Text(MigrationReviewSummary.createLine(
                        creates: plan.wrappedValue.createCount,
                        reuses: plan.wrappedValue.reuseCount
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(action: upload) {
                    if isUploading {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Uploading \(service.progress.done) / \(service.progress.total)")
                        }
                    } else {
                        Text(MigrationReviewSummary.uploadTitle(
                            creates: plan.wrappedValue.createCount,
                            reuses: plan.wrappedValue.reuseCount
                        ))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUploading)
                .needsServer()
                .frame(maxWidth: .infinity)

                // The other answer to the question this screen asks. Without
                // it the only way out was to upload or to back out, and
                // backing out brings the offer straight back on the next
                // launch — the same dead end "Discard and Finish" already
                // fixed for a PARTIAL run, missing from the run that has not
                // started yet.
                Button("Discard", role: .destructive) {
                    confirmDiscard = true
                }
                .disabled(isUploading)
                .frame(maxWidth: .infinity)
                .confirmationDialog(
                    MigrationReviewSummary.discardEverythingTitle(),
                    isPresented: $confirmDiscard,
                    titleVisibility: .visible
                ) {
                    Button("Discard", role: .destructive) {
                        service.discardLocalLibrary()
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(MigrationReviewSummary.discardEverythingMessage(
                        backend: service.capabilities.displayName
                    ))
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    private func upload() {
        guard let plan else { return }
        isUploading = true
        Task {
            let result = await service.execute(plan)
            isUploading = false
            if result.isComplete {
                showSuccess = true
            }
        }
    }

    // MARK: - Result states

    private var successView: some View {
        ContentUnavailableView {
            Label("Migrated", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } description: {
            if let result = service.lastResult {
                Text("\(result.created) created, \(result.reused) reused")
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            dismiss()
        }
    }

    private func partialResultView(result: MigrationResult) -> some View {
        ContentUnavailableView {
            Label(MigrationReviewSummary.resultTitle(result: result), systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 12) {
                Text(MigrationReviewSummary.outcomeLine(result: result))

                // The counts alone cannot be acted on. Each row says which
                // item and, where the backend gave one, why.
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(result.failed + result.skipped + result.notStored) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.label)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if let reason = item.reason {
                                    Text(reason)
                                        .font(.footnote)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        } actions: {
            // Rows that uploaded with details left behind are synced, so a
            // new plan would not contain them — only unuploaded rows can be
            // reviewed again.
            if !(result.failed.isEmpty && result.skipped.isEmpty) {
                Button("Review remaining") {
                    service.lastResult = nil
                    plan = nil
                    blocked = [:]
                    Task { await loadPlan() }
                }
                .buttonStyle(.borderedProminent)
            }

            // The way out that does not leave the migration offer waiting on
            // every launch: give up on what could not be uploaded.
            Button("Discard and Finish", role: .destructive) {
                confirmDiscard = true
            }
            .confirmationDialog(
                MigrationReviewSummary.discardTitle(result: result),
                isPresented: $confirmDiscard,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) {
                    service.discardLocalLibrary()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(MigrationReviewSummary.discardMessage(
                    backend: service.capabilities.displayName,
                    result: result
                ))
            }

            Button("Done") {
                dismiss()
            }
        }
    }
}

// MARK: - Conflict section

private struct ConflictSection<Candidate: Identifiable>: View where Candidate.ID == Int {
    let title: String
    @Binding var items: [MigrationItem<Candidate>]
    let candidateLabel: (Candidate) -> String

    var body: some View {
        if items.contains(where: { !$0.candidates.isEmpty }) {
            Section(title) {
                ForEach($items, id: \.localId) { $item in
                    if !item.candidates.isEmpty {
                        ConflictRow(item: $item, candidateLabel: candidateLabel)
                    }
                }
            }
        }
    }
}

private struct ConflictRow<Candidate: Identifiable>: View where Candidate.ID == Int {
    @Binding var item: MigrationItem<Candidate>
    let candidateLabel: (Candidate) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.label)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)

            Picker("Action", selection: $item.resolution) {
                ForEach(item.candidates) { candidate in
                    Text("Reuse \(candidateLabel(candidate))")
                        .tag(MigrationResolution.reuse(serverId: candidate.id))
                }
                Text("Create new").tag(MigrationResolution.create)
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 4)
    }
}
