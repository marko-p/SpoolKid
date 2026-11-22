//
//  PrinterTabView.swift
//  SpoolKid
//
//  Purpose: The Printer tab: what is in each toolhead, live, and the way to put
//  a Library spool into one. The scan has its own `NFCManager`, so Tags' scan
//  routing never sees it.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// A spool on its way to a toolhead.
struct PendingAssignment: Identifiable {
    let id = UUID()
    let spool: Spool
    let tag: ToolheadAssignmentWarning.SpoolTag
    var toolhead: Int?
}

struct PrinterTabView: View {
    @EnvironmentObject private var printer: PrinterService
    @EnvironmentObject private var store: SpoolDataStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var scanner = NFCManager()
    @State private var openToolhead: ToolheadState?
    @State private var showSettings = false
    @State private var scanned: PendingAssignment?
    @State private var toConfirm: PendingAssignment?
    @State private var scanProblem: String?
    @State private var refreshProblem: String?

    private var isOnline: Bool { printer.connection == .online }

    var body: some View {
        NavigationStack {
            Group {
                if printer.connection == .notConfigured {
                    PrinterSettingsView()
                } else if printer.connection == .needsSignIn {
                    PrinterSignInView()
                } else {
                    toolheadGrid
                        // The drawn printer names the page; a title only
                        // pushed the cards off screen (owner, 2026-11-09).
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            .navigationTitle("Printer")
            .navigationDestination(isPresented: $showSettings) { PrinterSettingsView() }
        }
        // The app can open on this tab, and then Tags, which otherwise loads
        // the spools, has not appeared.
        .onAppear { Task { await store.fetchSpools() } }
        .task { if !isOnline { await printer.connect() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !isOnline { Task { await printer.connect() } }
        }
        .onChange(of: scanner.isScanning) { _, isScanning in
            if !isScanning { finishScan() }
        }
        .sheet(item: $openToolhead) { toolhead in
            ToolheadSheetView(index: toolhead.index)
        }
        .sheet(item: $toConfirm) { pending in
            AssignSpoolView(pending: pending)
        }
        .confirmationDialog(
            "Which toolhead?",
            isPresented: Binding(get: { scanned != nil }, set: { if !$0 { scanned = nil } }),
            presenting: scanned
        ) { pending in
            ForEach(printer.toolheads) { toolhead in
                Button(toolhead.name) {
                    var chosen = pending
                    chosen.toolhead = toolhead.index
                    toConfirm = chosen
                }
            }
        } message: { pending in
            Text(pending.spool.listTitle)
        }
        .alert("Can't Read Tags", isPresented: Binding(get: { refreshProblem != nil }, set: { if !$0 { refreshProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(refreshProblem ?? "")
        }
        .alert("Can't Use This Tag", isPresented: Binding(get: { scanProblem != nil }, set: { if !$0 { scanProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(scanProblem ?? "")
        }
    }

    private var toolheadGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(printer.profile.arranged(printer.toolheads)) { toolhead in
                        Button { openToolhead = toolhead } label: {
                            ToolheadCard(toolhead: toolhead)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .opacity(isOnline ? 1 : 0.5)
            }
            .padding()
        }
        .refreshable { await refresh() }
        .floatingBottomBar(alignedToTabBar: false) {
            HStack(spacing: 24) {
                BottomBarButton(title: "Refresh", systemImage: "arrow.clockwise", large: true) {
                    Task { await refresh() }
                }
                BottomBarButton(title: "Scan Tag", systemImage: "wave.3.right", prominent: true, large: true) {
                    scanner.startScanning(rejectingLocationTags: true)
                }
                .disabled(!isOnline || printer.activity.blocksWrites)
            }
            // The same gap above the tab bar as Library's and Tags' bars.
            .padding(.vertical)
        }
    }

    private func refresh() async {
        if let problem = await printer.refresh() { refreshProblem = problem }
        await store.fetchSpools()
    }

    private var header: some View {
        Button { showSettings = true } label: {
            PrinterOutlineHeader(name: printerName, detail: printer.capabilities?.stack.label, status: stateLabel)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var printerName: String {
        let saved = UserDefaults.standard.string(forKey: AppConfig.printerNameKey) ?? ""
        return saved.isEmpty ? printer.profile.name : saved
    }

    private var stateLabel: String {
        switch printer.connection {
        case .online: printer.activity.label
        case .connecting: "Connecting…"
        case .needsSignIn: "Sign In"
        case .offline, .notConfigured: "Offline"
        }
    }

    private func finishScan() {
        guard let result = scanner.scanResult else { return }
        scanner.scanResult = nil
        let spool = result.cardUID.flatMap { SpoolMappingService.spool(in: store.spools, claiming: $0) }
            ?? result.tagData?.spoolmanId.flatMap { id in store.spools.first { $0.id == id } }
        guard let spool else {
            scanProblem = "No Library spool is linked to this tag."
            return
        }
        scanned = PendingAssignment(
            spool: spool,
            tag: ToolheadScanTag.classify(result: result, spool: spool)
        )
    }
}

/// What a scan says about the spool's tag, for the warning.
enum ToolheadScanTag {
    static func classify(result: ScanResult, spool: Spool) -> ToolheadAssignmentWarning.SpoolTag {
        guard let format = result.format.flatMap({ tagFormat($0) }), let data = result.tagData else { return .unknownFormat }
        let library = FilamentTagData.from(spool: spool)
        let same = data.material.caseInsensitiveCompare(library.material) == .orderedSame
            && data.colorHex.caseInsensitiveCompare(library.colorHex) == .orderedSame
        return .scanned(format: format, differsAs: same ? nil : "\(data.material) \(data.colorHex)")
    }

    private static func tagFormat(_ detected: ScanResult.DetectedFormat) -> TagFormat? {
        switch detected {
        case .openSpool: .openSpool
        case .openPrintTag: .openPrintTag
        case .openTag3D: .openTag3D
        case .anycubicACE: .anycubicACE
        case .elegoo: .elegoo
        case .tigerTag: .tigerTag
        case .webUrl, .backendLabel, .ocr: nil
        }
    }
}

/// One toolhead at a glance. The Library spool is named when it can be told.
struct ToolheadCard: View {
    let toolhead: ToolheadState
    @EnvironmentObject private var printer: PrinterService
    @EnvironmentObject private var store: SpoolDataStore

    private var spool: Spool? { ToolheadSpoolMatch.spool(for: toolhead, printer: printer, store: store) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(toolhead.name).font(.headline)
                Spacer()
                if let source = toolhead.source.label {
                    Text(source).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let note = printer.notes[toolhead.index] {
                Label(note.message, systemImage: "info.circle")
                    .font(.subheadline).foregroundStyle(.orange)
            }
            if toolhead.hasData {
                // Swatch beside the filament, so four cards fit on one screen
                // under the printer drawing (owner, 2026-11-09).
                HStack(spacing: 10) {
                    FilamentSwatch(colors: toolhead.colors, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text([toolhead.material, toolhead.subtype].compactMap { $0 }.joined(separator: " "))
                            .font(.body).lineLimit(1)
                        if let vendor = toolhead.vendor {
                            Text(vendor).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                if let spool {
                    Text([spool.listTitle, spool.remainingWeightText].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).lineLimit(2)
                }
                if !toolhead.isLoaded {
                    Text("Not loaded").font(.subheadline).foregroundStyle(.secondary)
                }
                if case .unlinked = ToolheadTagImport.offer(for: toolhead, printer: printer, store: store) {
                    Label("Tag not in Library", systemImage: "tag")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let mismatch = ToolheadMismatch.of(toolhead, spool: spool) {
                    Label(mismatch.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline).foregroundStyle(.orange)
                }
            } else {
                Spacer(minLength: 0)
                Text(toolhead.isLoaded ? "Unknown filament" : "Empty")
                    .font(.body).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

@MainActor
enum ToolheadSpoolMatch {
    /// The spool id first, where it names a spool of this Library, then the tag.
    static func spool(for toolhead: ToolheadState, printer: PrinterService, store: SpoolDataStore) -> Spool? {
        let shared = PrinterService.sharesSpoolman(printerServer: printer.spoolmanServer, connectionTarget: store.connectionTarget)
        if shared, let id = toolhead.spoolID, let spool = store.spools.first(where: { $0.id == id }) { return spool }
        return toolhead.tagUID.flatMap { SpoolMappingService.spool(in: store.spools, claiming: $0) }
    }
}
