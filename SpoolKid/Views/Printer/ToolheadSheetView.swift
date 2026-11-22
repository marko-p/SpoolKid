//
//  ToolheadSheetView.swift
//  SpoolKid
//
//  Purpose: One toolhead's detail and actions, and the confirmation an
//  assignment goes through. Every printer write is disabled during a print.
//  A tag the printer read that no spool claims can be added to the Library
//  or linked to a spool, then assigned here (`ToolheadTagImport`).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct ToolheadSheetView: View {
    let index: Int
    @EnvironmentObject private var printer: PrinterService
    @EnvironmentObject private var store: SpoolDataStore
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var picked: PendingAssignment?
    @State private var settingByHand = false
    @State private var rewriting: Spool?
    /// Write Tag: the Library spool, written through this toolhead.
    @State private var writingThroughToolhead: Spool?
    /// Read Tag has its own scan, so the Printer tab's scan routing never sees it.
    @StateObject private var scanner = NFCManager()
    @State private var readRun = TagReaderRun()
    @State private var readResult: ScanResult?
    @State private var showReadHub = false
    @State private var correcting: CorrectingFilament?
    @State private var confirmingClear = false
    @State private var working = false
    @State private var problem: String?
    /// What an import left to say: it waits for the print, or it saved but
    /// didn't assign.
    @State private var notice: String?
    @State private var importRoute: ImportRoute?
    /// A spool saved or linked in a pushed screen, assigned once it pops.
    @State private var imported: Spool?
    /// What a link that only partly landed said; kept beside the assignment's text.
    @State private var linkCaveat: String?
    @State private var linking = false
    @State private var pendingSpoolForm: ImportRoute?
    @Environment(\.serverLink) private var serverLink
    @AppStorage(AppConfig.printerNameKey) private var savedPrinterName = ""

    private enum ImportRoute: Hashable {
        case filament(uid: String)
        case search(uid: String)
        case spool(uid: String, filamentID: Int)
    }

    private var toolhead: ToolheadState? { printer.toolheads.first { $0.index == index } }
    private var writesBlocked: Bool { printer.activity.blocksWrites || printer.connection != .online || working }
    /// Saving and linking go ahead during a print; only the assignment waits.
    private var importBlocked: Bool { printer.connection != .online || working || serverLink.isDown }
    private var offer: ToolheadTagImport.Offer {
        toolhead.map { ToolheadTagImport.offer(for: $0, printer: printer, store: store) } ?? .none
    }

    var body: some View {
        NavigationStack {
            Form {
                if let toolhead {
                    if let note = printer.notes[index] {
                        Section {
                            Label(note.message, systemImage: "info.circle").foregroundStyle(.orange)
                        }
                    }
                    Section("On the Printer") {
                        if toolhead.hasData {
                            HStack(spacing: 12) {
                                FilamentSwatch(colors: toolhead.colors, size: 44)
                                VStack(alignment: .leading) {
                                    Text([toolhead.vendor, toolhead.material, toolhead.subtype].compactMap { $0 }.joined(separator: " "))
                                    if let optics = FilamentOpacity.toolheadText(
                                        alpha: toolhead.alpha, libraryTD: librarySpool?.filament.transmissionDistance
                                    ) {
                                        Text(optics).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } else {
                            Text("Nothing set").foregroundStyle(.secondary)
                        }
                        LabeledContent("Filament", value: toolhead.isLoaded ? "Loaded" : "Not loaded")
                        if let id = toolhead.spoolID { LabeledContent("Spoolman Spool", value: "#\(id)") }
                        if let uid = toolhead.tagUID { LabeledContent("Tag", value: uid) }
                    }

                    if let spool = ToolheadSpoolMatch.spool(for: toolhead, printer: printer, store: store) {
                        Section("In the Library") {
                            Text(spool.listTitle)
                            if let left = spool.remainingWeightText { LabeledContent("Left", value: left) }
                        }
                    }

                    if let mismatch = ToolheadMismatch.of(toolhead, spool: librarySpool) {
                        mismatchSection(mismatch, toolhead: toolhead)
                    }

                    if case .unlinked = offer {
                        Section {
                            Label("This tag isn't linked to a spool yet.", systemImage: "tag")
                                .foregroundStyle(.orange)
                        }
                    }

                    Section {
                        ToolheadTileGrid(rows: tileRows)
                            .disabled(writesBlocked || scanner.isScanning)
                    } footer: {
                        if printer.activity.blocksWrites {
                            Text("Toolheads can't be changed during a print.").font(.body)
                        } else if case .disabled(let reason) = tagActions.write {
                            Text(reason).font(.body)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    Section {
                        bigActions
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    if scanner.isScanning, let progress = readRun.progressText {
                        Text(progress).font(.body).foregroundStyle(.secondary)
                    }
                    if let notice {
                        Label(notice, systemImage: "info.circle").font(.body).foregroundStyle(.orange)
                    }
                    if let problem {
                        Text(problem).font(.body).foregroundStyle(.red)
                    }
                }
            }
            .onDisappear { printer.acknowledgeNote(toolhead: index) }
            .navigationTitle("Toolhead \(index + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(readRun.holdsScreen(isScanning: scanner.isScanning))
            .interactiveDismissDisabled(readRun.holdsScreen(isScanning: scanner.isScanning))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .disabled(readRun.holdsScreen(isScanning: scanner.isScanning))
                }
            }
            .navigationDestination(isPresented: $picking) {
                SpoolSelectionView { spool in
                    picking = false
                    picked = PendingAssignment(
                        spool: spool,
                        tag: ToolheadAssignmentWarning.pickedTag(for: spool),
                        toolhead: index
                    )
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { rewriting != nil }, set: { if !$0 { rewriting = nil } }
            )) {
                if let rewriting { WriteTagView(initialData: FilamentTagData.from(spool: rewriting)) }
            }
            .navigationDestination(isPresented: Binding(
                get: { writingThroughToolhead != nil }, set: { if !$0 { writingThroughToolhead = nil } }
            )) {
                if let writingThroughToolhead {
                    WriteTagView(initialData: FilamentTagData.from(spool: writingThroughToolhead),
                                 initialReader: .toolhead(index))
                }
            }
            .navigationDestination(isPresented: $showReadHub) {
                if let readResult { ScanResultHubView(result: readResult) }
            }
            .onChange(of: scanner.isScanning) { _, isScanning in
                guard !isScanning, let result = scanner.scanResult else { return }
                readResult = result
                showReadHub = true
            }
            .onChange(of: showReadHub) { _, isShowing in
                guard !isShowing else { return }
                readResult = nil
                scanner.scanResult = nil
            }
            .alert("NFC Error", isPresented: Binding(
                get: { !scanner.alertMessage.isEmpty }, set: { _ in scanner.alertMessage = "" }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scanner.alertMessage)
            }
            .navigationDestination(item: $importRoute) { route in
                importDestination(route)
            }
            .onChange(of: importRoute) { _, route in
                guard route == nil else { return }
                assignImported()
            }
            .navigationDestination(isPresented: $linking) {
                linkPicker
            }
            .onChange(of: linking) { _, isLinking in
                guard !isLinking else { return }
                assignImported()
            }
            .sheet(item: $picked) { AssignSpoolView(pending: $0) }
            .sheet(item: $correcting) { item in
                NavigationStack {
                    FilamentFormView(store: store, filamentToEdit: item.filament, correction: item.correction)
                }
            }
            .sheet(isPresented: $settingByHand) {
                if let toolhead { ToolheadManualView(toolhead: toolhead) }
            }
            .confirmationDialog("Clear this toolhead?", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { run { await printer.clear(toolhead: index) } }
            } message: {
                Text("The printer forgets what is in it until a tag is read or a spool is assigned.")
            }
        }
    }

    // MARK: Actions

    private var tileRows: [[ToolheadTile]] {
        var first: [ToolheadTile] = []
        if printer.capabilities?.canClear == true {
            first.append(ToolheadTile(title: "Clear", systemImage: "trash", destructive: true) { confirmingClear = true })
        }
        if printer.capabilities?.canReRead == true {
            first.append(ToolheadTile(title: "Read Tag Again", systemImage: "arrow.clockwise") {
                run { await printer.reRead(toolhead: index) }
            })
        }
        var second = [ToolheadTile(title: "Set by Hand", systemImage: "pencil") { settingByHand = true }]
        if case .unlinked = offer {
            second.append(ToolheadTile(title: "Assign Spool", systemImage: "arrow.left.arrow.right") { picking = true })
        }
        var third: [ToolheadTile] = []
        if tagActions.read {
            third.append(ToolheadTile(title: "Read Tag", systemImage: "wave.3.right") { readTag() })
        }
        switch tagActions.write {
        case .hidden: break
        case .enabled, .disabled:
            third.append(ToolheadTile(
                title: "Write Tag", systemImage: "square.and.pencil", isEnabled: tagActions.write == .enabled
            ) { writingThroughToolhead = librarySpool })
        }
        return [first, second, third]
    }

    private var tagActions: (read: Bool, write: ToolheadTagActions.Write) {
        guard let toolhead else { return (false, .hidden) }
        return ToolheadTagActions.available(
            connection: printer.connection, plugin: printer.tagPlugin, toolhead: toolhead, hasLibrarySpool: librarySpool != nil,
            isPrinterBusy: printer.activity.blocksWrites)
    }

    /// Reads through this toolhead and opens the Scan Result hub. If the toolhead
    /// stopped being usable it says so; it never falls back to the iPhone's NFC.
    private func readTag() {
        problem = nil
        let run = TagReaderRun.start(.toolhead(index), purpose: .read, printer: printer, store: store)
        guard run.reader == .toolhead(index) else {
            let options = TagReaderOption.options(printer: printer, store: store, purpose: .read)
            problem = options.first { $0.reader == .toolhead(index) }?.disabledReason ?? TagReaderOption.goneReason
            return
        }
        readRun = run
        scanner.startScanning(reader: run.reader)
    }

    /// Add Spool sits at the bottom, closest to the thumb (owner).
    @ViewBuilder
    private var bigActions: some View {
        VStack(spacing: 8) {
            if case .unlinked(let uid) = offer {
                ToolheadBigButton(title: "Link to Spool", systemImage: "link") { linking = true }
                    .disabled(importBlocked)
                ToolheadBigButton(title: "Add Spool", systemImage: "plus", prominent: true) { addSpool(uid: uid) }
                    .disabled(importBlocked)
            } else {
                ToolheadBigButton(title: "Assign Spool", systemImage: "arrow.left.arrow.right", prominent: true) { picking = true }
                    .disabled(writesBlocked)
            }
        }
    }

    private var printerName: String { savedPrinterName.isEmpty ? printer.profile.name : savedPrinterName }

    private func addSpool(uid: String) {
        notice = nil
        problem = nil
        linkCaveat = nil
        let tagData = toolhead.flatMap { ToolheadTagImport.tagData(from: $0) }
        switch ToolheadTagImport.addStart(tagData: tagData, filaments: store.filaments) {
        case .newFilament: importRoute = .filament(uid: uid)
        case .filamentSearch: importRoute = .search(uid: uid)
        case .spool(let filamentID): importRoute = .spool(uid: uid, filamentID: filamentID)
        }
    }

    @ViewBuilder
    private func importDestination(_ route: ImportRoute) -> some View {
        let tagData = toolhead.flatMap { ToolheadTagImport.tagData(from: $0) }
        switch route {
        case .filament(let uid):
            if let tagData {
                FilamentFormView(store: store, initialData: tagData, onSaveFilament: { created in
                    // Opened once the filament form has gone.
                    pendingSpoolForm = .spool(uid: uid, filamentID: created.id)
                })
            }
        case .search(let uid):
            FilamentSelectionView(
                selectedFilamentID: Binding(get: { nil }, set: { picked in
                    guard let picked else { return }
                    // Opened once the search has gone.
                    pendingSpoolForm = .spool(uid: uid, filamentID: picked)
                    importRoute = nil
                }),
                store: store, dismissesOnSelect: false
            )
        case .spool(let uid, let filamentID):
            SpoolFormView(
                store: store,
                initialFilamentId: filamentID,
                initialCardUIDs: [uid],
                initialLocation: PrinterLocationMatch.location(
                    in: ManageLocationsView.mergedLocations(
                        observed: store.spools.compactMap(\.location),
                        known: store.locations,
                        registered: store.registeredLocations.map(\.name)
                    ),
                    printerName: printerName
                ),
                tagWeights: tagData.map { TagSpoolWeights(tagData: $0, format: nil) },
                onSaveSpool: { spool, _ in imported = spool }
            )
        }
    }

    private var linkPicker: some View {
        let tagData = toolhead.flatMap { ToolheadTagImport.tagData(from: $0) }
        return TagTargetPicker(
            matches: tagData.map { ToolheadTagImport.linkMatches(for: $0, in: store.activeSpools) } ?? [],
            allowAllSpools: true
        ) { target, _ in
            guard case .spool(let spool) = target, case .unlinked(let uid) = offer else { return }
            working = true
            notice = nil
            problem = nil
            linkCaveat = nil
            Task {
                let outcome = await TagLinkService.assign(uid, to: spool, in: store)
                working = false
                if outcome.didWrite {
                    linkCaveat = outcome.caveat
                    imported = spool
                    if !linking { assignImported() }
                } else if case .notSaved(let reason) = outcome {
                    notice = reason
                }
            }
        }
    }

    /// After an import: assign it, ask first, or say it waits for the print.
    private func assignImported() {
        if let next = pendingSpoolForm {
            pendingSpoolForm = nil
            importRoute = next
            return
        }
        guard let spool = imported, let toolhead else { return }
        imported = nil
        let linkedSpoolID: Int? = toolhead.tagUID.flatMap {
            if case .spool(let id, _) = store.owner(ofTagUID: $0) { return id }
            return nil
        }
        let tagNote = SaveOutcome.combinedNote([
            linkCaveat, ToolheadImportAssignment.tagNote(linkedSpoolID: linkedSpoolID, savedSpoolID: spool.id)
        ])
        linkCaveat = nil
        let step = ToolheadImportAssignment.step(
            spool: spool, toolhead: toolhead,
            route: printer.usageRoute(connectionTarget: store.connectionTarget),
            printing: printer.activity.blocksWrites,
            assignsSpoolID: printer.capabilities?.assignsSpoolID == true
        )
        switch step {
        case .confirmFirst:
            notice = tagNote
            picked = PendingAssignment(spool: spool, tag: ToolheadAssignmentWarning.pickedTag(for: spool), toolhead: index)
        case .waitForPrint:
            notice = ToolheadImportAssignment.message(saved: true, outcome: nil, step: step, toolhead: toolhead.name, tagNote: tagNote)
        case .send:
            working = true
            Task {
                let outcome = await ToolheadImportAssignment.perform(step, toolhead: index, force: false, printer: printer)
                working = false
                notice = ToolheadImportAssignment.message(saved: true, outcome: outcome, step: step, toolhead: toolhead.name, tagNote: tagNote)
            }
        }
    }

    private var librarySpool: Spool? {
        toolhead.flatMap { ToolheadSpoolMatch.spool(for: $0, printer: printer, store: store) }
    }

    private func describe(_ material: String?, _ vendor: String?, _ hexes: [String]) -> String {
        ([vendor, material].compactMap { $0 } + hexes).joined(separator: " ")
    }

    /// A source row, marked when the printer is using it.
    /// One source with its "on the printer" checkbox. Tapping a source the
    /// printer isn't using sends it there.
    private func sourceRow(_ label: String, _ value: String, onPrinter: Bool, select: @escaping () -> Void) -> some View {
        Button {
            if !onPrinter { select() }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                    Text(value).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: onPrinter ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(onPrinter ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(writesBlocked && !onPrinter)
        .accessibilityAddTraits(onPrinter ? .isSelected : [])
        .accessibilityHint(onPrinter ? "" : "Sends it to the printer")
    }

    @ViewBuilder
    private func mismatchSection(_ mismatch: ToolheadMismatch, toolhead: ToolheadState) -> some View {
        Section {
            if let tag = toolhead.tag {
                sourceRow("Tag", describe(tag.material, tag.vendor, tag.colorHexes), onPrinter: mismatch.printerMatchesTag) {
                    let assignment = ToolheadAssignment(tag: tag, keepingSpoolID: toolhead.spoolID)
                    run {
                        await printer.assign(
                            assignment, toolhead: index, force: PrinterCommands.needsForce(toolhead)
                        )
                    }
                }
            }
            if let spool = librarySpool, let matches = mismatch.printerMatchesLibrary {
                let library = FilamentTagData.from(spool: spool)
                sourceRow("Library", describe(
                    library.material, library.brand, library.trimmedColors(max: PrinterCommands.maxColors)
                ), onPrinter: matches) {
                    picked = PendingAssignment(
                        spool: spool, tag: ToolheadAssignmentWarning.pickedTag(for: spool), toolhead: index
                    )
                }
            }
            if mismatch.printerUsesNeither {
                LabeledContent("Printer", value: describe(toolhead.material, toolhead.vendor, toolhead.colorHexes))
            }
        } header: {
            HStack {
                Text(mismatch.title)
                Spacer()
                Text("U1")
            }
        } footer: {
            Text(mismatch.message).font(.body)
        }

        let tiles = mismatchTiles(mismatch, toolhead: toolhead)
        if !tiles.isEmpty {
            Section {
                ToolheadTileGrid(rows: [tiles])
            } footer: {
                if tiles.contains(where: { $0.id == Self.writeTagTitle }) {
                    Text("The iPhone can't reach the tag on the printer. Take the spool off first.")
                        .font(.body)
                        .padding(.horizontal, 16)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private static let writeTagTitle = "Write Tag with iPhone"

    /// The fixes that change the Library or the tag, not the printer.
    private func mismatchTiles(_ mismatch: ToolheadMismatch, toolhead: ToolheadState) -> [ToolheadTile] {
        guard mismatch.libraryMatchesTag == false, let spool = librarySpool, let tag = toolhead.tag else { return [] }
        var tiles = [ToolheadTile(title: "Update Library from Tag", systemImage: "square.and.arrow.down") {
            correcting = CorrectingFilament(
                filament: spool.filament,
                correction: FilamentCorrection.from(tag: tag, spool: spool, spools: store.spools)
            )
        }]
        if ToolheadMismatch.phoneWritesTag(tagType: toolhead.tagType) {
            tiles.append(ToolheadTile(title: Self.writeTagTitle, systemImage: "iphone.radiowaves.left.and.right") {
                rewriting = spool
            })
        }
        return tiles
    }

    private func run(_ write: @escaping () async -> ToolheadWriteOutcome) {
        working = true
        problem = nil
        Task {
            problem = await write().message
            working = false
        }
    }
}

/// Update Library from Tag's editor: the filament, with the tag's values.
private struct CorrectingFilament: Identifiable {
    let id = UUID()
    let filament: Filament
    let correction: FilamentCorrection
}

/// Says what will happen, then sends the spool. Stays open on any outcome but
/// a confirmed one.
struct AssignSpoolView: View {
    let pending: PendingAssignment
    @EnvironmentObject private var printer: PrinterService
    @EnvironmentObject private var store: SpoolDataStore
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var problem: String?

    private var toolhead: ToolheadState? { printer.toolheads.first { $0.index == pending.toolhead } }
    private var sharesSpoolman: Bool {
        PrinterService.sharesSpoolman(printerServer: printer.spoolmanServer, connectionTarget: store.connectionTarget)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let toolhead, let capabilities = printer.capabilities {
                    let warning = ToolheadAssignmentWarning.lines(
                        toolhead: toolhead, tag: pending.tag, capabilities: capabilities,
                        spoolLinkResolves: sharesSpoolman && capabilities.assignsSpoolID
                            && !pending.spool.cardUIDs.isEmpty
                    )
                    Section {
                        HStack(spacing: 12) {
                            FilamentSwatch(colors: pending.spool.filament.colors, size: 44)
                            Text(pending.spool.listTitle)
                        }
                    }
                    Section("What Happens Next") {
                        ForEach(warning.lines, id: \.self) { Text($0) }
                        if !sharesSpoolman, capabilities.assignsSpoolID {
                            Text("The printer uses a different Spoolman, so it gets the color and material but won't track this spool.")
                        }
                    }
                    Section {
                        Button("Assign to \(toolhead.name)") { assign(to: toolhead, force: warning.needsForce) }
                            .disabled(working || printer.activity.blocksWrites)
                    }
                    if let problem {
                        Text(problem).font(.body).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Assign Spool")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func assign(to toolhead: ToolheadState, force: Bool) {
        working = true
        problem = nil
        // This button is the confirmation, so a forced write is sent as is.
        let step = ToolheadImportAssignment.send(
            spool: pending.spool, route: printer.usageRoute(connectionTarget: store.connectionTarget),
            assignsSpoolID: printer.capabilities?.assignsSpoolID == true
        )
        Task {
            let outcome = await ToolheadImportAssignment.perform(step, toolhead: toolhead.index, force: force, printer: printer)
            working = false
            if outcome == .confirmed { dismiss() } else { problem = outcome?.message }
        }
    }
}
