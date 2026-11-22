//
//  SpoolmanTabView.swift
//  SpoolKid
//
//  Purpose: The Library tab content — resource management for whichever backend
//  is active (Spoolman, FilaMan, or the on-device Library). The name is history:
//  this tab predates the other two backends and is shared by all three.
//  Features:
//  - The spool list is the tab's root (ManageSpoolsView in Library mode, grouped
//    by filament by default). Above it: the backend connection row with the
//    spool count (and, under Tag Links, the tagged count) under it, the
//    migrate / copy-tags offers, then the search field.
//  - A bottom toolbar: Locations, Empty Spools, Weigh Spools and Add Spool
//    (the Add Spool sheet).
//  - ContentUnavailableView when the active backend has no valid connection.
//  - Settings (and Diagnostics, when enabled) in the toolbar.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI
import SwiftData
import TipKit

struct SpoolmanTabView: View {
    /// Held only to hand to the Diagnostics hub, whose Tag Explorer needs a
    /// live NFC session. This tab does not scan anything itself.
    @ObservedObject var nfcManager: NFCManager

    /// Spelled out because the synthesized memberwise initializer would inherit
    /// the `private` of the stored properties below and stop `ContentView` from
    /// constructing this view.
    init(nfcManager: NFCManager) {
        _nfcManager = ObservedObject(wrappedValue: nfcManager)
    }

    @EnvironmentObject private var store: SpoolDataStore
    @EnvironmentObject private var spoolManService: SpoolmanService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    /// True while the root shows a launch-time sheet, which the tips'
    /// popovers would otherwise cover.
    @Environment(\.hidesFirstRunTips) private var hidesFirstRunTips

    /// The bar's four icons left to right, then the grouping tip, one at a
    /// time — the Tags tab's pattern, so two popovers never compete.
    @State private var tips = TipGroup(.ordered) {
        LocationsTip()
        EmptySpoolsTip()
        WeighSpoolsTip()
        AddSpoolTip()
        SpoolmanManageTip()
    }

    /// False while a screen is pushed over the list, or the tab is off
    /// screen: a popover anchored on this root would present over it.
    @State private var isRootOnScreen = false

    private var showsFirstRunTips: Bool {
        isRootOnScreen && !hidesFirstRunTips
    }

    /// Read for the grouping tip only; the list owns the setting.
    @AppStorage(AppConfig.spoolGroupingKey) private var groupingRaw: String = SpoolGrouping.filament.rawValue
    /// The system's row height. The spool list lowers its own for the compact
    /// spool rows; the rows above it get this back.
    @Environment(\.defaultMinListRowHeight) private var systemMinRowHeight
    /// The ACTIVE backend's validated-connection flag. Reading Spoolman's here
    /// is what made this whole tab render "No Spoolman Connection" on a
    /// FilaMan-only install (F34).
    private var availability = BackendAvailability()
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl = ""

    /// Bumped by pull-to-refresh so the backend row re-probes along with it.
    @State private var reachabilityProbeToken = 0

    @State private var showSettings = false
    @AppStorage(AppConfig.diagnosticsEnabledKey) private var diagnosticsEnabled = false
    @State private var showDiagnostics = false
    @State private var showSpoolmanSettings = false
    @State private var showingAddSpoolFlow = false
    @State private var showLocations = false
    @State private var showEmptySpools = false
    @State private var showWeigh = false
    /// Select mode for the root list. A stack's root gets no edit mode of its
    /// own (a pushed list does), so without this the list's Select reached the
    /// List but not `ManageSpoolsView`: no selection circles, no Archive bar.
    @State private var listEditMode: EditMode = .inactive
    @State private var unsyncedLocalRows: UnsyncedLocalRowCount = .counted(0)
    @State private var showMigrationSheet = false
    @State private var showNativeCopySheet = false
    @State private var showFilamanCopySheet = false

    /// Whether the backend's library is usable right now. `isOnDeviceStorage`
    /// no longer needs a special case: the local backend declares no connection
    /// flag, which `BackendAvailability` already answers as available.
    private var isBackendAvailable: Bool {
        availability.isAvailable(store.capabilities)
            && ServerDownPresentation.decide(isDown: serverLink.isDown, hasLoadedRows: !store.spools.isEmpty) != .notConnected
    }

    @Environment(\.serverLink) private var serverLink

    var body: some View {
        let caps = store.capabilities
        NavigationStack {
            Group {
                if isBackendAvailable {
                    ManageSpoolsView(
                        libraryRows: AnyView(
                            libraryRows
                                .environment(\.defaultMinListRowHeight, systemMinRowHeight)
                                .staleWhileServerDown()
                        ),
                        // Spools are already fetched by the list's own refresh.
                        onRefresh: {
                            await store.fetchFilaments()
                            await store.fetchVendors()
                            reachabilityProbeToken += 1
                        },
                        onShowSettings: { showSettings = true }
                    )
                    .environment(\.editMode, $listEditMode)
                    .safeAreaInset(edge: .top, spacing: 0) { ServerDownBanner(showsStaleNote: true) }
                    .onAppear {
                        isRootOnScreen = true
                        // A sign-out that cannot be repaired from here is repaired in the form.
                        if spoolManService.signedOutNotice != nil { showSpoolmanSettings = true }
                    }
                    .onDisappear { isRootOnScreen = false }
                    // The tab's actions, in thumb reach and off the list. On the
                    // root only — a pushed screen has its own controls — and not
                    // while selecting, when the list floats its selection
                    // actions here instead.
                    .floatingBottomBar(alignedToTabBar: false) {
                        if !listEditMode.isEditing {
                            libraryActions
                        }
                    }
                } else {
                    // Only a server backend can land here — on-device storage is
                    // always available — so `displayName` always names a server.
                    // Shared with the Home dashboard: it is one screen, and the
                    // recovery copy F37 added has to be on both (the picker that
                    // strands a user is reachable from either).
                    BackendNotConnectedView(
                        capabilities: caps,
                        symbol: caps.tabSymbol,
                        onOpenBackendSettings: { showSpoolmanSettings = true }
                    )
                    .safeAreaInset(edge: .top, spacing: 0) { ServerDownBanner() }
                    // The list takes its title from ManageSpoolsView.
                    .navigationTitle("Library")
                }
            }
            .toolbar {
                // Settings sits in the list's own trailing group, after Select and
                // Sort & Filter (`onShowSettings`), where the other tabs keep it.
                // Off the list, the tab supplies it itself.
                if !isBackendAvailable {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                // The bug is the way IN to the experiments, the cog the way in to
                // SpoolKid's settings. Absent entirely unless the user has opted
                // in — an ordinary user has nothing to do behind it.
                if diagnosticsEnabled {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: { showDiagnostics = true }) {
                            Image(systemName: "ladybug")
                        }
                        .accessibilityLabel("Help Improve SpoolKid")
                    }
                }
            }
            .navigationDestination(isPresented: $showDiagnostics) {
                DiagnosticsHubView(nfcManager: nfcManager)
            }
            .navigationDestination(isPresented: $showLocations) {
                ManageLocationsView()
            }
            .navigationDestination(isPresented: $showEmptySpools) {
                EmptySpoolListView(mode: .manage)
            }
            .navigationDestination(isPresented: $showWeigh) {
                WeighSessionView(initialSpool: nil)
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(isPresented: $showSpoolmanSettings) {
                SpoolmanSettingsView()
            }
            .sheet(isPresented: $showingAddSpoolFlow) {
                AddSpoolFlowView(store: store)
            }
            .sheet(isPresented: $showMigrationSheet, onDismiss: {
                unsyncedLocalRows = MigrationService.unsyncedLocalRowCount(in: modelContext)
            }) {
                NavigationStack {
                    MigrationReviewView(
                        service: MigrationService(
                            context: modelContext,
                            writer: store
                        )
                    )
                }
            }
            .sheet(isPresented: $showNativeCopySheet) {
                NavigationStack {
                    TagStoreCopyView(
                        target: .spoolmanTags,
                        intro: TagStoreText.copyIntoNativeIntro(count: nativeCopyCount)
                    )
                }
            }
            .sheet(isPresented: $showFilamanCopySheet) {
                NavigationStack {
                    TagStoreCopyView(
                        target: .filamanTags,
                        intro: TagStoreText.copyIntoFilamanIntro(count: filamanCopyCount)
                    )
                }
            }
            .task {
                unsyncedLocalRows = MigrationService.unsyncedLocalRowCount(in: modelContext)
                await store.fetchFilaments()
                await store.fetchVendors()
            }
            // Spools refetch on every return, not once: Sort: Recent follows the
            // backend's `last_used`, which a print moves while SpoolKid is in the
            // background. The list's own `.onAppear` covers tab switches and pops.
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await store.fetchSpools() }
                }
            }
        }
    }

    /// What sits above the spool groups. Sections, so they scroll with the list
    /// and empty when a search narrows it to spools.
    @ViewBuilder
    private var libraryRows: some View {
        let caps = store.capabilities
        let copyCount = nativeCopyCount
        let filamanCount = filamanCopyCount

        LeadingSection {
            BackendConnectionRow(probeToken: reachabilityProbeToken)
        } footer: {
            let atCapacity = caps.spoolCapacity.map { store.activeSpools.count >= $0 } == true
            Text(Self.countsLine(count: store.activeSpools.count, capacity: caps.spoolCapacity, tagged: taggedCount))
                .foregroundStyle(atCapacity ? .orange : .secondary)
                .accessibilityIdentifier("library.counts")
                // The grouping tip points here: the line is there whenever the
                // list is, while group headers are not (Group By None).
                .popoverTip(
                    showsFirstRunTips && Self.showsGroupingTip(
                        grouping: SpoolGrouping(rawValue: groupingRaw) ?? .filament,
                        activeSpoolCount: store.activeSpools.count
                    ) ? tips.currentTip as? SpoolmanManageTip : nil,
                    arrowEdge: .top
                )
            if caps.isOnDeviceStorage {
                Text(LocalModeCopy.storageExplanation + " " + LocalModeCopy.spoolmanBenefit)
            }
        }

        if offersLocalLibraryMigration {
            LeadingSection {
                Button {
                    showMigrationSheet = true
                } label: {
                    HStack {
                        Label("Migrate local library to \(caps.displayName)", systemImage: "arrow.up.square")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .needsServer()
            }
        }

        if copyCount > 0 {
            LeadingSection {
                Button {
                    showNativeCopySheet = true
                } label: {
                    HStack {
                        Label(TagStoreText.copyRowLabel(count: copyCount), systemImage: "tag")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .needsServer()
            }
        }

        if filamanCount > 0 {
            LeadingSection {
                Button {
                    showFilamanCopySheet = true
                } label: {
                    HStack {
                        Label(TagStoreText.copyRowLabel(count: filamanCount, target: .filamanTags), systemImage: "tag")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .needsServer()
            }
        }
    }

    /// Left to right: Locations, Empty Spools, Weigh Spools, then Add Spool as
    /// the screen's one prominent action (owner, 2026-10-29), large and
    /// centred (owner, 2026-11-04).
    private var libraryActions: some View {
        // Glass buttons add about 12 pt of their own between them on iOS
        // 26.5 and none on the owner's device, so the spacing alone keeps
        // them apart; four large ones still fit a 390-pt-wide iPhone 17e.
        HStack(spacing: 8) {
            BottomBarButton(title: "Locations", systemImage: "mappin.and.ellipse", large: true) {
                LocationsTip().invalidate(reason: .actionPerformed)
                showLocations = true
            }
            .accessibilityIdentifier("spoolman.manageLocations")
            .popoverTip(showsFirstRunTips ? tips.currentTip as? LocationsTip : nil, arrowEdge: .bottom)
            BottomBarButton(title: "Empty Spools", systemImage: "circle.circle", large: true) {
                EmptySpoolsTip().invalidate(reason: .actionPerformed)
                showEmptySpools = true
            }
            .accessibilityIdentifier("spoolman.manageEmptySpools")
            .popoverTip(showsFirstRunTips ? tips.currentTip as? EmptySpoolsTip : nil, arrowEdge: .bottom)
            BottomBarButton(title: "Weigh Spools", systemImage: "scalemass", large: true) {
                WeighSpoolsTip().invalidate(reason: .actionPerformed)
                showWeigh = true
            }
            .needsServer()
            .popoverTip(showsFirstRunTips ? tips.currentTip as? WeighSpoolsTip : nil, arrowEdge: .bottom)
            BottomBarButton(title: "Add Spool", systemImage: "plus", prominent: true, large: true) {
                AddSpoolTip().invalidate(reason: .actionPerformed)
                showingAddSpoolFlow = true
            }
            .needsServer()
            .accessibilityIdentifier("library.addSpool")
            // On a transparent stand-in: anchored on the prominent glass
            // button itself, the popover opened beside it, not above. Hit
            // testing goes off outside popoverTip: inside it, the tip's
            // anchor still caught every tap meant for the button.
            .overlay {
                Color.clear
                    .popoverTip(showsFirstRunTips ? tips.currentTip as? AddSpoolTip : nil, arrowEdge: .bottom)
                    .allowsHitTesting(false)
            }
        }
        .padding(.vertical)
    }

    /// Spools that hold a tag, counted only while Tag Links is in effect —
    /// the same number as Home's Tag coverage card.
    private var taggedCount: Int? {
        guard store.tagIdentity.effectiveMode == .tagLinks else { return nil }
        return DashboardStatsService.tagCoverage(
            in: store.spools, ledger: TagAssociationStore.shared.snapshot()
        ).tagged
    }

    /// The grouping tip talks about group headers, so it waits while the
    /// list shows none: Group By None, or no spools at all.
    nonisolated static func showsGroupingTip(grouping: SpoolGrouping, activeSpoolCount: Int) -> Bool {
        SpoolListGrouping.layout(grouping: grouping, isFilamentDrillDown: false).showsHeaders
            && activeSpoolCount > 0
    }

    /// "48 / 100 spools · 31 tagged". `tagged` is nil unless Tag Links is in
    /// effect, and then the tagged part is left off.
    nonisolated static func countsLine(count: Int, capacity: Int?, tagged: Int?) -> String {
        let spools = usageLabel(count: count, capacity: capacity)
            + (capacity == nil && count == 1 ? " spool" : " spools")
        guard let tagged else { return spools }
        return spools + " · \(tagged) tagged"
    }

    /// Whether to offer uploading the on-device Library. Reads the active
    /// backend's capability, not the Spoolman URL plus Spoolman's connection
    /// flag — that pairing is what made this row dead on FilaMan.
    private var offersLocalLibraryMigration: Bool {
        MigrationService.shouldOfferMigration(
            capabilities: store.capabilities,
            localRows: unsyncedLocalRows
        )
    }

    /// Links SpoolKid resolves that Spoolman Tags does not hold yet — zero
    /// unless the identity mode links tags and Spoolman Tags is one of its stores.
    private var nativeCopyCount: Int {
        guard store.tagIdentity.linkTargets.contains(.spoolmanTags) else { return 0 }
        return TagStoreAudit.missingLinks(
            into: .spoolmanTags, spools: store.spools, filaments: store.filaments
        ).copyable.count
    }

    /// Spools FilaMan Tags could take a tag for — zero unless it is a link target.
    private var filamanCopyCount: Int {
        guard store.tagIdentity.linkTargets.contains(.filamanTags) else { return 0 }
        return TagStoreAudit.missingLinks(
            into: .filamanTags, spools: store.spools, filaments: store.filaments
        ).copyable.count
    }

    /// Capacity `nil` means unlimited — show the bare count. Capping is a
    /// capability of the backend, not a property of "being local".
    nonisolated static func usageLabel(count: Int, capacity: Int?) -> String {
        guard let capacity else { return "\(count)" }
        return "\(count.formatted()) / \(capacity.formatted())"
    }
}

/// How a `BackendReachability` reads on the status menu item.
///
/// Presentation lives here rather than on the enum itself, which is declared in
/// the service layer alongside `SpoolDataRepository` and has no business
/// knowing about `Color`.
///
/// This is display-only state, kept separate from the sticky
/// `<backend>_connection_valid` flag (which gates SpoolLink provisioning,
/// migration offers, and backend selection). It is driven by a lightweight live
/// probe so the indicator reflects actual reachability rather than "validated at
/// least once." `nil` is a probe still in flight — the repository never returns
/// that, because it never has that answer to give.
extension BackendReachability {
    static func statusColor(for reachability: BackendReachability?) -> Color {
        switch reachability {
        case .none, .alwaysAvailable, .notConfigured:
            return .secondary
        case .reachable:
            return .statusSuccess
        case .unreachable:
            return .statusError
        }
    }

    static func statusText(for reachability: BackendReachability?) -> String {
        switch reachability {
        case .none:
            return "Checking…"
        case .alwaysAvailable:
            return "Local"
        case .notConfigured:
            return "Not configured"
        case .reachable:
            return "Connected"
        case .unreachable:
            return "Unreachable"
        }
    }
}
