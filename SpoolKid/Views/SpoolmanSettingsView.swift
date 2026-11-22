//
//  SpoolmanSettingsView.swift
//  SpoolKid
//
//  Purpose: In-app home for backend configuration: the Backend picker
//  (Library / Spoolman / FilaMan), the selected backend's connection form
//  (URL, auth, Trust All, Test Connection), and the Tag Identity group
//  (Identify spools by, plus the per-store link switches). Pushed from the
//  connection-status menu item in SpoolmanTabView.
//
//  The file keeps its Spoolman name — it is the type's name (C3), and
//  renaming both is a change of its own — but nothing it RENDERS may name a
//  backend the user is not running (I4).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct SpoolmanSettingsView: View {
    @EnvironmentObject private var spoolManService: SpoolmanService
    @EnvironmentObject private var filaManService: FilaManService
    @EnvironmentObject private var store: SpoolDataStore

    /// `tag_identity_mode` is deliberately unregistered (absent = the
    /// one-time upgrade decision), so it is bound as an optional and only ever
    /// written on an actual pick. The picker reads `store.tagIdentity`.
    @AppStorage(AppConfig.tagIdentityModeKey) private var storedIdentityMode: String?
    @AppStorage(AppConfig.spoolmanPersistCardUIDKey) private var spoolLinkEnabled: Bool = false
    @AppStorage(AppConfig.spoolmanNativeTagsEnabledKey) private var nativeTagsEnabled: Bool = true
    @AppStorage(AppConfig.filamanTagsEnabledKey) private var filamanTagsOn: Bool = false
    @AppStorage(AppConfig.filamanSpoolLinkEnabledKey) private var filamanSpoolLinkOn: Bool = true
    /// Spoolman's own flag, read here for exactly one legitimately
    /// Spoolman-specific job: `seedBackendKindSelection`'s legacy derivation for
    /// installs that predate the Backend picker.
    @AppStorage(AppConfig.spoolmanConnectionValidKey) private var isConnectionValid: Bool = false
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = AppConfig.defaultSpoolmanUrl

    /// The ACTIVE backend's flag, for the SpoolLink toggle below — which is not
    /// a Spoolman-only setting, whatever its storage key is called.
    private var availability = BackendAvailability()

    // `AppConfig.backendKindKey` is deliberately unregistered (absent =
    // derive), so it cannot be bound directly via @AppStorage without
    // showing a blank picker on every existing install (see resolveBackendKind's
    // doc comment). "" is the not-yet-seeded sentinel — never a valid
    // BackendKind.rawValue — and is replaced, in onAppear, via
    // SpoolDataStore.seedBackendKindSelection, which carries its own
    // idempotency guard (a non-empty selectedBackendKind is returned
    // unchanged, so a second onAppear never re-derives over a user's pick).
    // Writes to storage happen ONLY through `backendKindSelection`'s setter,
    // i.e. only on an actual user pick; seeding itself never writes.
    @State private var selectedBackendKind: String = ""

    // Deleting a tag store: fresh check → blocked sheet or two-step confirm.
    @State private var deletion: TagStore?
    @State private var deletionCheck: TagStoreAudit.DeletionCheck?
    @State private var showDeleteAlert = false
    @State private var showDeleteFinal = false
    @State private var blockedCopy: BlockedCopy?
    @State private var deleteFailure: String?
    @State private var isCheckingDeletion = false
    /// Set only when the blocked sheet's copy actually ran. Re-checking after
    /// a plain Cancel would reopen the same sheet and trap the user in it.
    @State private var recheckTarget: TagStore?

    /// Issue #24: the Migration Management sheet on screen.
    @State private var migrationCopy: MigrationRow?

    /// One Migration Management action (issue #24).
    nonisolated enum MigrationRow: Hashable, Identifiable, Sendable {
        /// This iPhone's tag record → the backend's link stores.
        case record
        /// Spoolman Tags → `card_uids`.
        case intoCardUIDs
        /// `card_uids` → Spoolman Tags.
        case intoSpoolmanTags

        var id: Self { self }
    }

    /// The rows the Backend page offers. A store copy only where that store
    /// is a link target: a write adds nothing to a store that is not, so the
    /// copy would report work it could not do. Empty hides the section.
    nonisolated static func migrationRows(
        capabilities: BackendCapabilities, available: Set<TagStore>, targets: Set<TagStore>
    ) -> [MigrationRow] {
        var rows: [MigrationRow] = []
        if !capabilities.isOnDeviceStorage, capabilities.supportsTagMapping { rows.append(.record) }
        if available.contains(.spoolmanTags), targets.contains(.cardUIDs) { rows.append(.intoCardUIDs) }
        if targets.contains(.spoolmanTags) { rows.append(.intoSpoolmanTags) }
        return rows
    }

    /// How many links a row would copy now.
    private func missingCount(_ row: MigrationRow) -> Int {
        switch row {
        case .record:
            TagStoreSync.recordLinks(
                snapshot: TagAssociationStore.shared.snapshot(), spools: store.spools, owner: store.owner(ofTagUID:)
            ).copyable.count
        case .intoCardUIDs:
            TagStoreAudit.missingLinks(into: .cardUIDs, spools: store.spools, filaments: store.filaments).copyable.count
        case .intoSpoolmanTags:
            TagStoreAudit.missingLinks(into: .spoolmanTags, spools: store.spools, filaments: store.filaments).copyable.count
        }
    }

    private func rowLabel(_ row: MigrationRow) -> String {
        switch row {
        case .record: TagStoreText.recordCopyRowLabel(displayName: store.capabilities.displayName)
        case .intoCardUIDs: "Copy \(TagStore.spoolmanTags.displayName) to \(TagStore.cardUIDs.displayName)"
        case .intoSpoolmanTags: "Copy \(TagStore.cardUIDs.displayName) to \(TagStore.spoolmanTags.displayName)"
        }
    }

    @ViewBuilder
    private var migrationSection: some View {
        let rows = Self.migrationRows(
            capabilities: store.capabilities, available: store.availableTagStores, targets: store.tagIdentity.linkTargets
        )
        if !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    let count = missingCount(row)
                    Button { migrationCopy = row } label: {
                        HStack {
                            Text(rowLabel(row))
                            Spacer()
                            Text(count == 1 ? "1 missing" : "\(count) missing")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(count == 0 || !store.tagIdentity.writesLinks)
                }
            } header: {
                Text("Migration Management")
            } footer: {
                Text(TagStoreText.migrationManagementFooter(
                    writesLinks: store.tagIdentity.writesLinks,
                    connectionRowLabel: store.capabilities.connectionRowLabel
                ))
            }
        }
    }

    @ViewBuilder
    private func migrationSheet(_ row: MigrationRow) -> some View {
        let count = missingCount(row)
        let onCopied: () -> Void = { Task { await store.fetchSpools() } }
        switch row {
        case .record:
            TagStoreCopyView(
                title: "Copy Tag Links",
                intro: TagStoreText.recordCopyIntro(count: count, displayName: store.capabilities.displayName),
                onCopied: onCopied,
                perform: { await TagStoreSync.copyRecord(snapshot: TagAssociationStore.shared.snapshot(), in: $0) }
            )
        case .intoCardUIDs:
            TagStoreCopyView(target: .cardUIDs, intro: TagStoreText.copyIntoCardUIDsIntro(count: count), onCopied: onCopied)
        case .intoSpoolmanTags:
            TagStoreCopyView(target: .spoolmanTags, intro: TagStoreText.copyIntoNativeIntro(count: count), onCopied: onCopied)
        }
    }

    /// The "copy first" sheet a blocked deletion opens. Dismissing it checks
    /// again, which opens the confirmation once nothing is missing.
    private struct BlockedCopy: Identifiable {
        let id = UUID()
        let deleting: TagStore
        let intro: String
        let canCopy: Bool
    }

    private var backendKind: BackendKind {
        BackendKind(rawValue: selectedBackendKind) ?? .local
    }

    /// What the picker's footer has to say, given the kind now selected.
    ///
    /// The setter below writes the stored kind on the FIRST tap, with no
    /// validation — and must, since a backend cannot be tested before it is
    /// selected and its connection form does not render until it is. The footer
    /// therefore names the consequence: the choice goes live when the screen is
    /// left, whether or not the server ever answers, and the on-device Library
    /// is always there to go back to (F37).
    ///
    /// Leaving, rather than picking, is the moment the switch applies: a
    /// rebuild on the tap itself would tear this screen down before the URL
    /// and key below could be entered.
    ///
    /// `.local` declares no connection flag, so `BackendAvailability` reads it
    /// as available and it never takes the warning branch.
    static func pickerFooter(for kind: BackendKind, isConnected: Bool) -> String {
        let base = "Takes effect as soon as you leave this screen."
        guard !isConnected else { return base }
        let name = BackendCapabilities.for(kind).displayName
        return base + " \(name) isn't connected yet — set it up below, or choose "
            + "\(BackendCapabilities.local.displayName) to keep using the spools on this iPhone."
    }

    /// The switch that is on while the other is off cannot be turned off:
    /// SpoolKid would have nowhere to keep a new link.
    nonisolated static func isLastStoreOn(_ isOn: Bool, other: Bool) -> Bool { isOn && !other }

    // MARK: - Deleting a tag store

    private var canDeleteCardUIDs: Bool {
        store.capabilities.requiresCardUIDsFieldRegistration
            && availability.isAvailable(store.capabilities)
            && store.availableTagStores.contains(.spoolmanTags)
            && !spoolLinkEnabled
            && store.spools.contains { !$0.cardUIDs.isEmpty }
    }

    private var canDeleteNativeTags: Bool {
        store.availableTagStores.contains(.spoolmanTags)
            && availability.isAvailable(store.capabilities)
            && !nativeTagsEnabled
            && store.spools.contains { !$0.nativeTagUIDs.isEmpty }
    }

    private func deleteRow(_ target: TagStore) -> some View {
        Button(role: .destructive) {
            Task { await beginDeletion(target) }
        } label: {
            HStack {
                Text(TagStoreText.deleteRowLabel(target, displayName: store.capabilities.displayName))
                if isCheckingDeletion {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(isCheckingDeletion)
        // On the row, not the form: on iPhone the dialog is a popover, and it
        // should point at the row the user just tapped, within thumb reach,
        // rather than at the top of the screen.
        .confirmationDialog(
            TagStoreText.deleteTitle(target),
            isPresented: Binding(
                get: { showDeleteFinal && deletion == target },
                set: { if !$0 { showDeleteFinal = false } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await performDeletion() }
            }
            Button("Cancel", role: .cancel) { deletion = nil }
        } message: {
            Text("This cannot be undone.")
        }
        .needsServer()
    }

    /// Fresh data first: the decision to delete is made against the server as
    /// it is now, archived spools included (`fetchSpools` asks for them).
    private func beginDeletion(_ target: TagStore) async {
        isCheckingDeletion = true
        await store.fetchSpools()
        await store.fetchFilaments()
        isCheckingDeletion = false
        let check = TagStoreAudit.deletionCheck(
            deleting: target, available: store.availableTagStores,
            spools: store.spools, filaments: store.filaments
        )
        WorkflowTraceStore.log(path: "tags", step: "store-delete.check", details: [
            "store": target.rawValue, "check": String(describing: check)
        ])
        switch check {
        case .nothingToDelete:
            return
        case .blocked(let missing):
            blockedCopy = BlockedCopy(
                deleting: target,
                intro: TagStoreText.blockedIntro(deleting: target, missing: missing),
                canCopy: TagStoreText.copyableCount(deleting: target, missing: missing) > 0
            )
        case .noOtherStore, .ready:
            deletion = target
            deletionCheck = check
            showDeleteAlert = true
        }
    }

    private func recheckAfterCopy() {
        guard let target = recheckTarget else { return }
        recheckTarget = nil
        Task { await beginDeletion(target) }
    }

    private func performDeletion() async {
        guard let target = deletion else { return }
        switch target {
        case .cardUIDs:
            if await store.deleteCardUIDsField() == false {
                deleteFailure = store.errorMessage ?? "card_uids could not be deleted."
            }
        case .spoolmanTags:
            let result = await store.deleteSpoolmanTagLinks()
            if !result.failures.isEmpty {
                deleteFailure = result.failures.joined(separator: "\n")
            }
        case .filamanTags:
            break // Never offered here: FilaMan Tags are not deleted in bulk.
        }
        WorkflowTraceStore.log(path: "tags", step: "store-delete.done", details: [
            "store": target.rawValue, "ok": String(deleteFailure == nil)
        ])
        deletion = nil
        deletionCheck = nil
    }

    private var backendKindSelection: Binding<String> {
        Binding(
            get: { selectedBackendKind },
            set: { newValue in
                selectedBackendKind = newValue
                UserDefaults.standard.set(newValue, forKey: AppConfig.backendKindKey)
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Backend", selection: backendKindSelection) {
                    Text("Library (on device)").tag(BackendKind.local.rawValue)
                    Text("Spoolman").tag(BackendKind.spoolman.rawValue)
                    Text("FilaMan").tag(BackendKind.filaman.rawValue)
                }
            } header: {
                Text("Backend")
            } footer: {
                Text(Self.pickerFooter(
                    for: backendKind,
                    isConnected: availability.isAvailable(BackendCapabilities.for(backendKind))
                ))
            }

            if backendKind == .spoolman {
                Section {
                    SpoolmanConnectionForm(spoolManService: spoolManService)
                } header: {
                    Text("Connection")
                } footer: {
                    if store.capabilities.isOnDeviceStorage {
                        Text("You're using the local Library. Configure a Spoolman server to migrate or sync.")
                    }
                }

                // Only while the ACTIVE backend can report scans: a connected
                // Spoolman 0.27+ (spec 3).
                if store.supportsTagScanReporting {
                    TagReaderSection()
                }
            }

            if backendKind == .filaman {
                Section {
                    FilaManConnectionForm(filaManService: filaManService)
                } header: {
                    Text("Connection")
                } footer: {
                    if store.capabilities.isOnDeviceStorage {
                        Text("You're using the local Library. Configure a FilaMan server to migrate or sync.")
                    }
                }
            }

            Section {
                // Shows the policy's mode — which, before the one-time upgrade
                // decision, is its provisional answer — and stores the pick.
                Picker("Identify spools by", selection: Binding(
                    get: { store.tagIdentity.mode },
                    set: { storedIdentityMode = $0.rawValue }
                )) {
                    ForEach(TagIdentityMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                if store.tagIdentity.mode == .tagLinks {
                    // Gated on the ACTIVE backend being connected and able to store
                    // a mapping. Reading Spoolman's flag here left the toggle
                    // permanently disabled on a FilaMan-only install, which made
                    // SpoolLink — complete and correct on FilaMan since Task 19b —
                    // impossible to ever switch on.
                    let canMap = availability.isAvailable(store.capabilities) && store.capabilities.supportsTagMapping
                    if store.availableTagStores.contains(.spoolmanTags) {
                        // Named like paxx12's `use_spoolman_uid` / `use_spoollink_uid`,
                        // so a user following his firmware docs sees the same two.
                        Toggle(TagStore.spoolmanTags.displayName, isOn: $nativeTagsEnabled)
                            .disabled(!canMap || Self.isLastStoreOn(nativeTagsEnabled, other: spoolLinkEnabled))
                        Toggle(TagStore.cardUIDs.displayName, isOn: $spoolLinkEnabled)
                            .disabled(!canMap || Self.isLastStoreOn(spoolLinkEnabled, other: nativeTagsEnabled))
                    }
                    if store.availableTagStores.contains(.filamanTags) {
                        // Switching refetches: the spool mapping reads the switch,
                        // so cached spools would keep the old Unlink state.
                        Toggle(TagStore.filamanTags.displayName, isOn: $filamanTagsOn)
                            .disabled(!canMap || Self.isLastStoreOn(filamanTagsOn, other: filamanSpoolLinkOn))
                        Toggle(TagStore.cardUIDs.displayName, isOn: $filamanSpoolLinkOn)
                            .disabled(!canMap || Self.isLastStoreOn(filamanSpoolLinkOn, other: filamanTagsOn))
                    }
                    // A store that is switched off but still holds links can be
                    // deleted — only once the other store holds every one of them.
                    if canDeleteCardUIDs {
                        deleteRow(.cardUIDs)
                    }
                    if canDeleteNativeTags {
                        deleteRow(.spoolmanTags)
                    }
                }
            } header: {
                Text("Tag Identity")
            } footer: {
                Text(TagStoreText.identityFooter(
                    store.tagIdentity, available: store.availableTagStores, capabilities: store.capabilities
                ))
            }

            migrationSection
        }
        // Issue #24: links made while SpoolLink was off are only in Spoolman
        // Tags; turning it on offers to copy them into card_uids.
        .onChange(of: spoolLinkEnabled) { _, on in
            guard on, store.availableTagStores.contains(.spoolmanTags) else { return }
            Task {
                await store.fetchSpools()
                if missingCount(.intoCardUIDs) > 0 { migrationCopy = .intoCardUIDs }
            }
        }
        .sheet(item: $migrationCopy) { row in
            NavigationStack { migrationSheet(row) }
        }
        .onChange(of: filamanTagsOn) { _, _ in Task { await store.fetchSpools() } }
        .onChange(of: filamanSpoolLinkOn) { _, _ in Task { await store.fetchSpools() } }
        // The URL, username and key fields belong to the connection forms, so
        // the screen that hosts them is where their way out of the keyboard
        // goes.
        .keyboardDoneBar()
        .alert(deletion.map(TagStoreText.deleteTitle) ?? "", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { deletion = nil }
            Button("Delete…", role: .destructive) { showDeleteFinal = true }
        } message: {
            if let deletion, let deletionCheck {
                Text(TagStoreText.deleteMessage(deletion, check: deletionCheck, displayName: store.capabilities.displayName))
            }
        }
        .sheet(item: $blockedCopy, onDismiss: recheckAfterCopy) { blocked in
            NavigationStack {
                TagStoreCopyView(
                    target: blocked.deleting == .cardUIDs ? .spoolmanTags : .cardUIDs,
                    intro: blocked.intro,
                    canCopy: blocked.canCopy,
                    onCopied: { recheckTarget = blocked.deleting }
                )
            }
        }
        .alert("Not Deleted", isPresented: Binding(
            get: { deleteFailure != nil },
            set: { if !$0 { deleteFailure = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteFailure ?? "")
        }
        .navigationTitle("Backend")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            // Unconditional: `ContentView` compares the stored kind against the
            // running one and rebuilds only on a real change, so the decision
            // stays in one place.
            NotificationCenter.default.post(
                name: AppConfig.backendKindDidChangeNotification, object: nil
            )
        }
        .onAppear {
            selectedBackendKind = SpoolDataStore.seedBackendKindSelection(
                current: selectedBackendKind,
                stored: UserDefaults.standard.string(forKey: AppConfig.backendKindKey),
                spoolmanUrl: spoolmanUrl,
                spoolmanConnectionValid: isConnectionValid
            )
        }
    }
}
