//
//  LocationDetailView.swift
//  SpoolKid
//
//  Purpose: One location — what is in it, how to put spools in or take them
//  out, and how to rename or delete it. Assignment goes through the ordinary
//  spool save, so each backend's own mechanism does the work unchanged.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct LocationDetailView: View {
    @ObservedObject var store: SpoolDataStore
    let locationName: String

    @Environment(\.dismiss) private var dismiss

    @State private var showRename = false
    @State private var showSpoolPicker = false
    @State private var showAssignment = false
    @State private var isAssigning = false

    @StateObject private var nfcManager = NFCManager()
    @State private var blockedUID: String?
    @State private var renamedTo: String?
    @State private var offerTagPrompt = false
    /// Set by the rename sheet, consumed by its `onDismiss`. Raising the alert
    /// from inside the sheet's own callback presents it while the sheet is
    /// still dismissing, and SwiftUI renders that alert inert — both buttons
    /// greyed out, neither responding. The prompt waits for the sheet to be
    /// gone.
    @State private var pendingRenamePrompt = false
    /// Why "Match to…" or "Remove From This Device" could not be saved; the
    /// screen stays open to show it.
    @State private var reconcileError: String?

    /// The name this screen is currently showing. Starts as the pushed-in
    /// `locationName`, but a rename in this session re-points every lookup
    /// (and the nav title) at the new name instead — `locationName` alone
    /// would go stale the moment the registry entry underneath it is renamed.
    ///
    /// Deliberately never reset back to `nil`: `offerTagPrompt` alone tracks
    /// whether the rewrite alert should still show, so dismissing that alert
    /// can't also yank this screen's notion of "current name" back to a name
    /// the registry no longer has an entry under.
    private var effectiveName: String { renamedTo ?? locationName }

    private var spoolsHere: [Spool] {
        LocationGrouping.spools(in: effectiveName, from: store.activeSpools)
    }

    private var record: LocationRecord? {
        store.locationRegistry?.record(named: effectiveName)
    }

    /// `nil` when there is nothing to offer. The tags keep working either way —
    /// resolution is by uuid and the on-tag name is a cached label — so this is
    /// about a tag not lying, not about it breaking.
    static func tagPromptCopy(tagCount: Int) -> String? {
        guard tagCount > 0 else { return nil }
        return tagCount == 1
            ? "This location is on 1 tag. Write the new name to it?"
            : "This location is on \(tagCount) tags. Write the new name to them?"
    }

    var body: some View {
        List {
            let syncState = store.syncState(forLocationNamed: effectiveName)
            if let banner = LocationReconciliation.banner(
                state: syncState,
                locationName: effectiveName,
                storageNoun: store.capabilities.storageNoun
            ) {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(banner.title)
                            .font(.headline)
                        Text(banner.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if syncState == .missingFromBackend {
                            let candidates = LocationReconciliation.unclaimedBackendLocations(
                                store.locations, records: store.registeredLocations
                            )
                            if candidates.isEmpty {
                                Text("There is no unmatched location in \(store.capabilities.storageNoun) to match it to.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                Menu("Match to…") {
                                    ForEach(candidates, id: \.self) { candidate in
                                        Button(candidate) {
                                            if store.matchRegisteredLocation(currentName: effectiveName, to: candidate) {
                                                dismiss()
                                            } else {
                                                reconcileError = "\(effectiveName) could not be matched to \(candidate)."
                                                    + (store.errorMessage.map { " \($0)" } ?? "")
                                            }
                                        }
                                    }
                                }
                                .accessibilityIdentifier("location.matchTo")
                            }

                            Button("Remove From This Device", role: .destructive) {
                                if store.forgetRegisteredLocation(named: effectiveName) {
                                    dismiss()
                                } else {
                                    reconcileError = "\(effectiveName) could not be removed from this device."
                                        + (store.errorMessage.map { " \($0)" } ?? "")
                                }
                            }

                            if let reconcileError {
                                Text(reconcileError)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                if spoolsHere.isEmpty {
                    Text("No spools are in \(effectiveName).")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(spoolsHere) { spool in
                        SpoolUsageRow(spool: spool, style: .withFilament)
                            .swipeActions(edge: .trailing) {
                                Button("Remove", role: .destructive) {
                                    assign(spool: spool, to: .setNil)
                                }
                                .needsServer()
                            }
                    }
                }
            } header: {
                Text(SpoolUsage.spoolCountText(spoolsHere.count))
            }
            .environment(\.spoolIDDigits, SpoolUsageRow.idDigits(for: spoolsHere))

            Section {
                Button {
                    showSpoolPicker = true
                } label: {
                    Label("Assign a Spool", systemImage: "plus.circle")
                }
                .disabled(isAssigning)
                .accessibilityIdentifier("location.assignSpool")

                Button {
                    showAssignment = true
                } label: {
                    Label("Scan Spools Into \(effectiveName)", systemImage: "wave.3.right")
                }
                .accessibilityIdentifier("location.scanSpoolsIn")
            }
            .needsServer()

            Section("NFC") {
                Button {
                    startTagWrite()
                } label: {
                    Label(
                        (record?.tagUIDs.count ?? 0) == 0 ? "Write Location Tag" : "Write Another Tag",
                        systemImage: "wave.3.right"
                    )
                }
                .disabled(nfcManager.isScanning)
                .accessibilityIdentifier("location.writeTag")

                if let count = record?.tagUIDs.count, count > 0 {
                    Text("\(count) \(count == 1 ? "tag carries" : "tags carry") this location.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .needsServer()
        }
        .staleWhileServerDown()
        .navigationTitle(effectiveName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Rename") { showRename = true }
            }
        }
        .sheet(isPresented: $showRename, onDismiss: {
            guard pendingRenamePrompt else { return }
            pendingRenamePrompt = false
            offerTagPrompt = true
        }) {
            NavigationStack {
                LocationFormView(store: store, currentLocation: effectiveName) { newName in
                    renamedTo = newName
                    pendingRenamePrompt = true
                }
            }
        }
        .sheet(isPresented: $showSpoolPicker) {
            NavigationStack {
                SpoolSelectionView { spool in
                    showSpoolPicker = false
                    assign(spool: spool, to: .set(effectiveName))
                }
            }
        }
        .sheet(isPresented: $showAssignment) {
            NavigationStack {
                LocationAssignmentView(initialLocationName: effectiveName)
            }
        }
        .refreshable { await store.fetchSpools() }
        .onChange(of: nfcManager.lastLocationWrite) { _, result in
            switch result {
            case .written(let uid):
                if let uid, let record {
                    store.recordWrittenLocationTag(uid: uid, to: record.uuid, locationName: record.name)
                }
                // Whatever was just written carries the current name — nothing
                // left to offer, even if this write came from the rename alert
                // itself.
                offerTagPrompt = false
                mirrorTagUID(uid)
            case .blocked(let uid):
                blockedUID = uid
            case .failed(let reason):
                store.postSaveNotice(reason, record: effectiveName)
            case nil:
                break
            }
        }
        .alert(Self.blockedTitle(owner: blockedUID.map(store.owner(ofTagUID:)) ?? .none), isPresented: Binding(
            get: { blockedUID != nil },
            set: { if !$0 { blockedUID = nil } }
        ), presenting: blockedUID) { uid in
            if Self.canUnlinkBlockedTag(owner: store.owner(ofTagUID: uid)) {
                Button("Unlink and Continue", role: .destructive) {
                    Task {
                        let unlinked = await store.unlinkTag(uid: uid)
                        blockedUID = nil
                        guard unlinked else {
                            store.postSaveNotice("The tag could not be unlinked from its spool.", record: effectiveName)
                            return
                        }
                        startTagWrite()
                    }
                }
                Button("Cancel", role: .cancel) { blockedUID = nil }
            } else {
                Button("OK", role: .cancel) { blockedUID = nil }
            }
        } message: { uid in
            Text(blockedMessage(for: uid))
        }
        .alert("Update the Tag?", isPresented: Binding(
            get: { offerTagPrompt && Self.tagPromptCopy(tagCount: record?.tagUIDs.count ?? 0) != nil },
            set: { if !$0 { offerTagPrompt = false } }
        )) {
            Button("Write Tag") { offerTagPrompt = false; startTagWrite() }
            Button("Later", role: .cancel) { offerTagPrompt = false }
        } message: {
            Text(Self.tagPromptCopy(tagCount: record?.tagUIDs.count ?? 0) ?? "")
        }
    }

    private func assign(spool: Spool, to location: SpoolmanPatchValue<String>) {
        Task {
            isAssigning = true
            defer { isAssigning = false }

            let ok = await store.updateSpool(id: spool.id, draft: .locationAssignment(location))
            if !ok {
                store.postSaveNotice(
                    store.errorMessage ?? "The spool could not be moved.",
                    record: spool.listTitle
                )
            }
        }
    }

    /// Records the tag on the backend's own location row, where the backend has
    /// a field for it — FilaMan's `locations.identifier` today. Silent on every
    /// backend that has none, and on a location the backend has not heard of
    /// yet: the tag works either way, because a location tag resolves by the
    /// uuid it carries against the device registry.
    ///
    /// A failure is reported but never retried and never undoes the write: the
    /// tag is written and registered, and the mirror is what the backend's
    /// other clients read.
    private func mirrorTagUID(_ uid: String?) {
        guard let uid else { return }
        Task {
            let outcome = await store.setLocationTagUID(locationName: effectiveName, uid: uid)
            if let note = outcome.note {
                store.postSaveNotice(note, record: effectiveName)
            }
        }
    }

    private func startTagWrite() {
        // A location must exist in the registry before it can be tagged — the
        // uuid on the tag is the registry entry's.
        Task {
            if record == nil {
                let outcome = await store.addLocation(name: effectiveName)
                // A failed create leaves no registry entry, so there is no uuid
                // to put on a tag — and without this the button would be tapped
                // and nothing at all would happen: no alert, no NFC session.
                if case .failed(let reason) = outcome {
                    store.postSaveNotice(reason, record: effectiveName)
                    return
                }
            }
            guard let record else {
                store.postSaveNotice(
                    "\(effectiveName) could not be saved on this device, so there is no tag to write.",
                    record: effectiveName
                )
                return
            }
            nfcManager.writeLocationTag(
                LocationTagPayload(uuid: record.uuid, name: record.name),
                // A filament's tag is refused too: a shelf taking it would
                // make it owned twice.
                blockedUIDs: store.tagMappedUIDs.union(store.filamentTagUIDs)
            )
        }
    }

    nonisolated static func blockedTitle(owner: TagOwner) -> String {
        if case .filament = owner { return "Tag Belongs to a Filament" }
        return "Tag Is Linked to a Spool"
    }

    /// A spool's claim can be released from here; a filament's is released
    /// from the filament, in its form or from its scan.
    nonisolated static func canUnlinkBlockedTag(owner: TagOwner) -> Bool {
        if case .filament = owner { return false }
        return true
    }

    private func blockedMessage(for uid: String) -> String {
        let owner = store.owner(ofTagUID: uid)
        if case .filament = owner, let refusal = owner.claimRefusal(attemptedBy: .location(name: effectiveName)) {
            return refusal
        }
        return spoolClaimMessage(for: uid)
    }

    private func spoolClaimMessage(for uid: String) -> String {
        if let spool = store.findSpool(byCardUID: uid) {
            return "This tag is linked to \(spool.listTitle). Writing a location tag will unlink it."
        }
        return "This tag is linked to a spool. Writing a location tag will unlink it."
    }
}
