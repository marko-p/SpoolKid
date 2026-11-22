//
//  HomeDashboardView.swift
//  SpoolKid
//
//  Purpose: The "Home" tab — a read-only inventory dashboard over the active
//  backend (Spoolman or local Library). All numbers come from the pure
//  `DashboardStatsService`; this view only fetches, renders, and routes.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct HomeDashboardView: View {
    @EnvironmentObject private var store: SpoolDataStore
    @EnvironmentObject private var spoolManService: SpoolmanService
    /// The ACTIVE backend's validated-connection flag — reading Spoolman's here
    /// is what left FilaMan users staring at "No Spoolman Connection" instead of
    /// their dashboard (F34). `spoolmanUrl` below stays Spoolman's on purpose:
    /// it is only ever read behind `supportsCurrencySetting`, which no other
    /// backend declares.
    private var availability = BackendAvailability()
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl = ""

    @State private var layout = DashboardLayoutStore()
    @State private var showCustomize = false
    @State private var currencyCode: String?

    @State private var showArchiveEmptiesConfirm = false
    @State private var archiveResultMessage: String?
    @State private var showArchiveResult = false
    @State private var showBackendSettings = false
    @EnvironmentObject private var messages: MessageService
    @State private var reopenedMessage: AppMessage?

    /// True while the root shows a launch-time sheet: popovers present above
    /// sheets, so the (i) intro tip is withheld until it is gone.
    @Environment(\.hidesFirstRunTips) private var hidesFirstRunTips
    /// False while a screen is pushed over the dashboard or the tab is off
    /// screen. `InfoButtonTip` is shared with the spool form and Weigh, both
    /// reachable from here — anchored on this root, it would present over them.
    @State private var isRootOnScreen = false

    private var emptySpools: [Spool] {
        DashboardStatsService.spools(in: store.spools, bucket: .empty)
    }

    private var totalValueText: String {
        DashboardStatsService.formatCurrency(DashboardStatsService.totalValue(of: store.spools), code: currencyCode)
    }

    @Environment(\.serverLink) private var serverLink

    private var presentation: ServerDownPresentation {
        .decide(isDown: serverLink.isDown, hasLoadedRows: !store.spools.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Group {
                if availability.isAvailable(store.capabilities), presentation != .notConnected {
                    dashboard
                        .staleWhileServerDown()
                } else {
                    notConnected
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { ServerDownBanner(showsStaleNote: presentation == .staleList) }
            .navigationTitle("Home")
            .navigationDestination(for: SpoolFilter.self) { filter in
                ManageSpoolsView(filter: filter)
            }
            .navigationDestination(isPresented: $showBackendSettings) {
                SpoolmanSettingsView()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCustomize = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Customize dashboard")
                }
            }
            .sheet(item: $reopenedMessage) { message in
                MessageView(
                    message: message,
                    image: messages.image(for: message),
                    onAction: { messages.markActed(message.id) },
                    onClose: {}
                )
            }
            .sheet(isPresented: $showCustomize, onDismiss: {
                layout = DashboardLayoutStore()
                Task { await load() }
            }) {
                DashboardCustomizeView(store: layout, onDone: { showCustomize = false })
            }
        }
        .task { await load() }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(spacing: 16) {
                reminderCards
                SpoolStatusCard(
                    counts: statusCounts,
                    introTip: isRootOnScreen && !hidesFirstRunTips ? InfoButtonTip() : nil
                )
                if layout.isVisible(.tagCoverage) { TagCoverageCard(coverage: coverage) }
                if layout.isVisible(.reorderSoon) { ReorderSoonCard(items: reorder) }
                if layout.isVisible(.colors) { ColorsCard(stats: colorStats, distinctCount: colorStats.count) }
                if layout.isVisible(.materialStats) { MaterialStatisticsCard(stats: filamentStats) }
                if layout.isVisible(.totalValue) {
                    TotalValueCard(value: totalValueText, info: DashboardInfo.totalValue(store.capabilities))
                }
                if layout.isVisible(.locations) {
                    NavigationLink {
                        ManageLocationsView()
                    } label: {
                        LocationsCard(summary: LocationSummary.make(
                            locations: ManageLocationsView.mergedLocations(
                                observed: store.spools.compactMap(\.location),
                                known: store.locations,
                                registered: store.registeredLocations.map(\.name)
                            ),
                            spools: store.activeSpools
                        ))
                    }
                    .buttonStyle(.plain)
                }
                if !emptySpools.isEmpty {
                    Button(role: .destructive) {
                        showArchiveEmptiesConfirm = true
                    } label: {
                        Label("Archive \(emptySpools.count) empty spool\(emptySpools.count == 1 ? "" : "s")", systemImage: "archivebox")
                            .frame(maxWidth: .infinity)
                    }
                    .needsServer()
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .onAppear { isRootOnScreen = true }
        .onDisappear { isRootOnScreen = false }
        .refreshable { await load() }
        .overlay {
            if store.isLoading && store.spools.isEmpty {
                ProgressView()
            }
        }
        .confirmationDialog(
            "Archive \(emptySpools.count) empty spool\(emptySpools.count == 1 ? "" : "s")?",
            isPresented: $showArchiveEmptiesConfirm,
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) { Task { await archiveEmpties() } }
                .needsServer()
            Button("Cancel", role: .cancel) {}
        }
        .alert("Archive complete", isPresented: $showArchiveResult) {
            Button("OK", role: .cancel) {}
        } message: { Text(archiveResultMessage ?? "") }
    }

    /// Only a server backend reaches this — on-device storage is always
    /// available — so `displayName` always names a server here.
    ///
    /// The action used to open **iOS** Settings, where `Settings.bundle` carries
    /// no server configuration at all: the only route offered out of this screen
    /// went nowhere useful (F37). It now pushes the in-app backend settings,
    /// where both the connection form and the Backend picker live.
    private var notConnected: some View {
        VStack(spacing: 0) {
            // A message is unrelated to the backend, so it shows here too.
            if !messages.reminders.isEmpty {
                VStack(spacing: 16) { reminderCards }
                    .padding()
            }
            BackendNotConnectedView(
                capabilities: store.capabilities,
                symbol: "chart.bar.xaxis",
                onOpenBackendSettings: { showBackendSettings = true }
            )
        }
    }

    /// Messages closed without their action, until each one ends.
    private var reminderCards: some View {
        ForEach(messages.reminders) { message in
            MessageReminderCard(message: message, image: messages.image(for: message)) {
                reopenedMessage = message
            }
        }
    }

    // MARK: Derived stats (computation lives in DashboardStatsService)

    private var statusCounts: [SpoolFillBucket: Int] {
        DashboardStatsService.statusCounts(in: store.spools)
    }
    private var coverage: TagCoverage {
        DashboardStatsService.tagCoverage(in: store.spools, ledger: TagAssociationStore.shared.snapshot())
    }
    private var reorder: [FilamentRunway] {
        DashboardStatsService.reorderSoon(in: store.spools, now: Date())
    }
    private var colorStats: [ColorStat] {
        DashboardStatsService.colorStats(in: store.spools)
    }
    private var filamentStats: [MaterialStat] {
        DashboardStatsService.filamentStatistics(for: store.spools)
    }

    private func archiveEmpties() async {
        let ids = Set(emptySpools.map(\.id))
        let result = await store.archiveSpools(ids: ids)
        archiveResultMessage = result.failed == 0
            ? "Archived \(result.succeeded) empty spool\(result.succeeded == 1 ? "" : "s")."
            : "Archived \(result.succeeded); \(result.failed) failed."
        showArchiveResult = true
        await load()
    }

    private func load() async {
        await store.fetchSpools()
        await store.fetchFilaments()
        if layout.isVisible(.totalValue), store.capabilities.supportsCurrencySetting, !spoolmanUrl.isEmpty {
            currencyCode = await spoolManService.fetchCurrencyCode(baseUrl: spoolmanUrl)
        }
    }
}
