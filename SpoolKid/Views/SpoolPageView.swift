//
//  SpoolPageView.swift
//  SpoolKid
//
//  Purpose: One spool, read first and led by what you do to it on the bench:
//  Link Tag, Write Tag, Location and Weigh, then its weight card, tags,
//  details, and Archive (Delete once archived). Edit shows the spool form in
//  place. Views render and route; the rules live in SpoolPage, TagLinkService
//  and SpoolTagWrite (conventions A2/A3).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// A pushed destination. It is never wrapped in its own NavigationStack.
struct SpoolPageView: View {
    @ObservedObject var store: SpoolDataStore
    let spoolID: Int
    /// Pushed from another page: cross-links render as plain text, so pages
    /// nest one level only (owner, 2026-11-03).
    var isNested = false
    /// Opens straight in Edit, scrolled to the weight section (the hub weight
    /// card's empty-spool-weight set-up).
    var startsEditingAtWeight = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var supportPrompts: SupportPromptService
    @EnvironmentObject private var printer: PrinterService
    @AppStorage(AppConfig.confirmBeforeDeleteKey) private var confirmBeforeDelete: Bool = true
    @AppStorage(AppConfig.locationSortFieldKey) private var locationSortField: String = LocationSortOption.manual.rawValue
    @AppStorage(AppConfig.locationSortAscendingKey) private var locationSortAscending: Bool = true

    @StateObject private var nfcManager = NFCManager()
    @StateObject private var recentTagManager = RecentTagManager()

    @State private var isEditing = false
    @State private var editsAtWeight = false
    @State private var pendingNFC: SpoolPageNFC?
    /// Which reader Link Tag and Write Tag use. Never stored.
    @State private var tagReader: TagReader = .iPhone
    /// The reader the operation in flight, or the last write, ran on.
    @State private var run = TagReaderRun()
    @State private var didApplyStart = false
    @State private var showingWeigh = false
    @State private var showingLocations = false
    @State private var filamentIDToOpen: Int?
    @State private var tagToUnlink: String?
    @State private var note: String?
    @State private var actionFailure: (title: String, message: String)?
    /// False until the page has looked for its spool once, fetching it when
    /// the store does not hold it, so "Not Found" means a real miss.
    @State private var hasLookedUp = false
    @State private var wasFound = false

    private var spool: Spool? { store.spools.first { $0.id == spoolID } }

    /// A link or write that would replace FilaMan's one tag, awaiting the
    /// person's answer. Shown on the page's list, which is what started it.
    @State private var replaceRequest: TagReplaceRequest?
    /// The person chose Replace Tag before a write; the link after it replaces.
    @State private var replacesOnWriteLink = false

    var body: some View {
        Group {
            if let spool {
                if isEditing {
                    SpoolFormView(
                        store: store, spoolToEdit: spool,
                        onFinish: { isEditing = false; editsAtWeight = false },
                        opensAtWeight: editsAtWeight
                    )
                    .navigationBarBackButtonHidden(true)
                } else {
                    readList(spool)
                        .tagReplacePrompt($replaceRequest) { request in replace(request) }
                        .pageTitle("Spool")
                        .navigationBarBackButtonHidden(run.holdsScreen(isScanning: nfcManager.isScanning))
                        .interactiveDismissDisabled(run.holdsScreen(isScanning: nfcManager.isScanning))
                }
            } else if !hasLookedUp {
                ProgressView().pageTitle("Spool")
            } else {
                ContentUnavailableView("Spool Not Found", systemImage: "questionmark.circle")
                    .pageTitle("Spool")
            }
        }
        .environmentObject(store)
        .task {
            if spool == nil { await store.fetchSpools() }
            hasLookedUp = true
            wasFound = spool != nil
            if SpoolPage.appliesOnce(requested: startsEditingAtWeight, applied: didApplyStart), spool != nil {
                didApplyStart = true
                editsAtWeight = true
                isEditing = true
            }
        }
        .onChange(of: spool == nil) { _, isGone in
            if !isGone { wasFound = true }
            if SpoolPage.shouldDismiss(wasFound: wasFound, spool: spool) { dismiss() }
        }
        .onChange(of: nfcManager.isScanning) { _, isScanning in
            guard !isScanning, let result = nfcManager.scanResult else { return }
            nfcManager.scanResult = nil
            Task { await handleScan(result) }
        }
        .onChange(of: nfcManager.lastWriteSucceeded) { _, succeeded in
            let routed = SpoolPage.writeResult(pending: pendingNFC, succeeded: succeeded)
            pendingNFC = routed.pendingAfter
            if routed.handles { Task { await writeFinished() } }
        }
        .onChange(of: nfcManager.alertMessage) { _, message in
            guard let failure = SpoolPage.nfcFailure(message) else { return }
            nfcManager.alertMessage = ""
            pendingNFC = nil
            actionFailure = ("NFC Error", failure)
        }
        .navigationDestination(isPresented: $showingWeigh) {
            WeighSessionView(initialSpool: spool)
        }
        .navigationDestination(item: $filamentIDToOpen) { id in
            FilamentPageView(store: store, filamentID: id, isNested: true)
        }
        .sheet(isPresented: $showingLocations) {
            NavigationStack {
                LocationPickerSheet(
                    title: "Move \(spool?.listTitle ?? "Spool") to…",
                    locations: ManageLocationsView.orderedLocationNames(
                        store: store, sortField: locationSortField, ascending: locationSortAscending
                    ),
                    onScanTag: { startNFC(.location) }
                ) { patch in
                    Task { await setLocation(patch) }
                }
            }
        }
        .alert(
            "Unlink Tag?",
            isPresented: Binding(get: { tagToUnlink != nil }, set: { if !$0 { tagToUnlink = nil } }),
            presenting: tagToUnlink
        ) { uid in
            Button("Unlink", role: .destructive) { Task { await unlink(uid) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Removes this tag from \(spool?.listTitle ?? "this spool") in \(store.capabilities.displayName). The tag itself is not erased.")
        }
        .alert(
            actionFailure?.title ?? "",
            isPresented: Binding(get: { actionFailure != nil }, set: { if !$0 { actionFailure = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionFailure?.message ?? "")
        }
    }

    // MARK: - Read list

    private func readList(_ spool: Spool) -> some View {
        List {
            Section {
                header(spool)
                TagReaderPicker(selection: $tagReader, purpose: .write(format: TagFormatService.shared.currentFormat))
                    .needsServer()
                if nfcManager.isScanning, let progress = run.progressText {
                    Text(progress).font(.subheadline).foregroundStyle(.secondary)
                }
                if nfcManager.lastWriteSucceeded, pendingNFC == nil, run.offersOtherSide {
                    WriteOtherSideButton { beginWrite(spool, replacing: false, reader: .iPhone) }
                        .buttonStyle(.borderless)
                        .needsServer()
                }
                tiles.needsServer()
                if let note {
                    Text(note).font(.body).foregroundStyle(.red)
                }
            }
            Section {
                HubSpoolWeightCard(spool: spool, onEditSpool: {
                    editsAtWeight = true
                    isEditing = true
                }, onSaved: { _ in })
                .id(spool.id)
                .needsServer()
            }
            tagsSection(spool).needsServer()
            detailsSection(spool)
            Section {
                SpoolArchiveControls(
                    spool: spool, store: store, confirmBeforeDelete: confirmBeforeDelete,
                    run: runSpoolAction
                )
            }
        }
        .listStyle(.insetGrouped)
        .staleWhileServerDown()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
                    .accessibilityIdentifier("spoolPage.edit")
            }
        }
    }

    private func header(_ spool: Spool) -> some View {
        HStack(spacing: 12) {
            FilamentSwatch(colors: spool.filament.colors, size: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(spool.listTitle)
                        .font(.title3.bold())
                    Text("#\(spool.id)")
                        .foregroundStyle(.secondary)
                }
                if isNested {
                    Text(SpoolPage.headerSubtitle(spool))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        filamentIDToOpen = spool.filament.id
                    } label: {
                        Text(SpoolPage.headerSubtitle(spool))
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("spoolPage.filament")
                }
                if spool.archived == true {
                    Text("Archived")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .foregroundStyle(.orange)
                        .overlay(Capsule().stroke(Color.orange, lineWidth: 1))
                        .accessibilityIdentifier("spoolPage.archived")
                }
            }
        }
    }

    private var tiles: some View {
        let tiles = SpoolPage.tiles(
            writesLinks: store.tagIdentity.writesLinks,
            isLinkScanning: pendingNFC == .link && nfcManager.isScanning
        )
        return LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 8),
                count: HubTileGrid.columnCount(forTileCount: tiles.count)
            ),
            spacing: 8
        ) {
            ForEach(tiles, id: \.id) { tile in
                HubTile(action: tile) { perform(tile.id) }
                    .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func tagsSection(_ spool: Spool) -> some View {
        let rows = SpoolPage.tagRows(for: spool)
        Section {
            if rows.isEmpty {
                Text("No tags").foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.uid) { row in
                HStack {
                    Text(row.uid).font(.body.monospaced())
                    Spacer()
                    if row.canUnlink {
                        Button("Unlink", role: .destructive) { tagToUnlink = row.uid }
                            .buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            Text("Tags")
        }
    }

    @ViewBuilder
    private func detailsSection(_ spool: Spool) -> some View {
        let statusName = spool.statusId.flatMap { id in store.spoolStatusOptions.first { $0.id == id }?.label }
        let rows = SpoolPage.detailRows(
            for: spool, visibleFieldIDs: SpoolFormView.visibleFieldIDs(for: store.capabilities), statusName: statusName
        )
        if !rows.isEmpty {
            Section {
                ForEach(rows, id: \.label) { row in
                    LabeledContent(row.label, value: row.value)
                }
            }
        }
    }

    // MARK: - Actions

    private func perform(_ id: HubTileID) {
        note = nil
        switch id {
        case .weigh:
            showingWeigh = true
        case .writeTag:
            guard let spool else { return }
            // Asked before the write, not after: the new tag's ID is unknown
            // until it has been written, and Cancel must leave the tag blank.
            if store.tagIdentity.writesLinks,
               let request = TagReplaceRequest.writing(
                   spool: spool, knownUID: nil, targets: store.tagIdentity.linkTargets
               ) {
                replaceRequest = request
                return
            }
            beginWrite(spool, replacing: false)
        case .linkTag:
            startNFC(.link)
        case .setLocation:
            showingLocations = true
        default:
            break
        }
    }

    private func beginWrite(_ spool: Spool, replacing: Bool, reader: TagReader? = nil) {
        replacesOnWriteLink = replacing
        pendingNFC = .write
        let write = SpoolTagWrite.spoolWrite(for: spool, store: store)
        run = reader.map { TagReaderRun(reader: $0, isWriting: true) }
            ?? .start(tagReader, purpose: .write(format: write.format), printer: printer, store: store)
        nfcManager.writeTag(data: write.data, format: write.format, reader: run.reader)
    }

    /// Replace Tag: a scan-link continues with `replacing`; a write starts.
    private func replace(_ request: TagReplaceRequest) {
        guard let target = request.spool else { return }
        if request.uid.isEmpty {
            guard let spool = store.spools.first(where: { $0.id == target.id }) else { return }
            beginWrite(spool, replacing: true)
        } else {
            Task {
                note = await TagLinkService.assign(
                    request.uid, to: target, in: store, replacing: true
                ).followUpNote
            }
        }
    }

    private func startNFC(_ purpose: SpoolPageNFC) {
        pendingNFC = purpose
        // A location tag is never on a spool holder: only Link Tag may use a toolhead.
        run = purpose == .link
            ? .start(tagReader, purpose: .read, printer: printer, store: store)
            : .iPhone
        nfcManager.startScanning(reader: run.reader)
    }

    private func handleScan(_ result: ScanResult) async {
        guard let spool else { return }
        defer { pendingNFC = nil }
        switch pendingNFC {
        case .link:
            if result.locationTag == nil, let uid = result.cardUID,
               let request = TagReplaceRequest.linking(
                   uid: uid, to: spool, targets: store.tagIdentity.linkTargets
               ) {
                replaceRequest = request
                return
            }
            note = await TagLinkService.linkScanned(result, to: spool, in: store)
        case .location:
            guard let name = SpoolPage.locationFromScan(result, registry: store.locationRegistry) else {
                note = "That isn't a location tag."
                return
            }
            await setLocation(.set(name))
        case .write, nil:
            break
        }
    }

    /// The spool form's write follow-up: record the tag, count the success,
    /// and in Tag Links link the tag just written to this spool.
    private func writeFinished() async {
        guard var data = nfcManager.tagDataToWrite, let spool else { return }
        if data.name == nil { data.name = spool.filament.name }
        recentTagManager.addTag(data, format: nfcManager.writeFormatToUse)
        supportPrompts.record(.tagWriteSucceeded)
        guard store.tagIdentity.writesLinks, let uid = nfcManager.lastWrittenTagUID else { return }
        let replacing = replacesOnWriteLink
        replacesOnWriteLink = false
        note = await TagLinkService.assign(uid, to: spool, in: store, replacing: replacing).followUpNote
    }

    private func setLocation(_ patch: SpoolmanPatchValue<String>) async {
        let result = await store.assignLocation(spoolIDs: [spoolID], to: patch)
        if !result.isCompleteSuccess {
            note = store.errorMessage ?? "The spool could not be moved."
        }
    }

    private func unlink(_ uid: String) async {
        guard let spool else { return }
        note = await TagLinkService.unlink(uid, from: spool, in: store)
    }

    /// Archive, Unarchive and Delete. A failure shows as an alert; Delete's
    /// success closes the page (`SpoolPage.shouldDismiss`).
    private func runSpoolAction(failureTitle: String, fallback: String, _ write: @escaping () async -> Bool) {
        Task {
            let didWrite = await write()
            let outcome = SaveOutcome.classify(didSave: didWrite, message: store.errorMessage, failureFallback: fallback)
            if let failure = outcome.failure {
                actionFailure = (failureTitle, failure)
            }
        }
    }
}
