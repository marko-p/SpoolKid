//
//  ContentView.swift
//  SpoolKid
//
//  Purpose: The root view of the application, providing the tab-based navigation structure.
//  Features:
//  - Two-tab layout: Tags and Spoolman.
//  - Shared NFC manager and Spoolman service across tabs.
//  - iOS 26 centered liquid glass tab bar.
//  - Presents welcome guide on first launch.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI
import SwiftData
import TipKit

enum AppTab: Int, Hashable {
    case tags = 0
    case spoolman = 1
    case home = 2
    case printer = 3
}

/// Snapshot of Spoolman connection settings used to detect changes made in iOS Settings.
private struct ConnectionSettingsSnapshot: Equatable {
    let url: String
    let authType: String
    let trustAllCerts: Bool
    let username: String
    let password: String
    let token: String

    static func current() -> ConnectionSettingsSnapshot {
        let defaults = UserDefaults.standard
        return ConnectionSettingsSnapshot(
            url: defaults.string(forKey: AppConfig.spoolmanUrlKey) ?? "",
            authType: defaults.string(forKey: AppConfig.authTypeKey) ?? "none",
            trustAllCerts: defaults.bool(forKey: AppConfig.trustAllCertsKey),
            username: defaults.string(forKey: AppConfig.authUsernameKey) ?? "",
            password: KeychainStore.read(account: KeychainStore.spoolmanPasswordAccount) ?? "",
            token: KeychainStore.read(account: KeychainStore.spoolmanTokenAccount) ?? ""
        )
    }
}

struct ContentView: View {
    private static let uiStartOnSpoolmanArgument = "-ui_start_spoolman_tab"

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var nfcManager: NFCManager
    @StateObject private var spoolManService: SpoolmanService
    @StateObject private var filaManService: FilaManService
    @StateObject private var dataStore: SpoolDataStore
    /// Held at the root so a connected scale survives navigation. Connecting
    /// takes seconds; a service owned by a screen would reconnect every time
    /// that screen appeared, which is unusable on a bench.
    @StateObject private var bleScale = BLEScaleService()
    /// The empty-spool library: one per device, not per backend, so it sits
    /// beside the backend services rather than inside `SpoolDataStore`.
    @StateObject private var emptySpools: EmptySpoolLibrary
    @StateObject private var changelog = ChangelogService()
    @AppStorage(AppConfig.changelogAutoShowKey) private var changelogAutoShow: Bool = true
    @AppStorage(AppConfig.changelogLastShownVersionKey) private var changelogLastShown: String = ""
    @State private var pendingChangelog: [ChangelogEntry] = []
    @StateObject private var messages = MessageService()
    /// Set once this launch's What's New decision is made, so a message read
    /// from the cache at the first render cannot take the screen first.
    @State private var launchDecisionsMade = false
    /// False while the welcome cover is up or leaving: a sheet presented in the
    /// update that dismisses the cover is dropped. Set from its `onDismiss`.
    @State private var welcomeCoverGone: Bool
    /// The message sheet as actually on screen — a presentation SwiftUI dropped
    /// must not hide the first-run tips for the rest of the session.
    @State private var messageSheetOnScreen = false
    @State private var selectedTab: AppTab
    @StateObject private var printerService = PrinterService()
    /// Whether the Printer tab is shown follows the stored address.
    @AppStorage(AppConfig.printerAddressKey) private var printerAddress = ""
    /// Whether the filament server can be reached right now.
    @StateObject private var serverLinkMonitor: ServerLinkMonitor
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = ""
    @AppStorage(AppConfig.hasCompletedWelcomeKey) private var hasCompletedWelcome: Bool = false
    @AppStorage(AppConfig.spoolmanConnectionValidKey) private var isConnectionValid: Bool = false

    // Incremented each time the welcome guide completes to force
    // SwiftUI to recreate tab views and the tabs' popover tips,
    // picking up the freshly-reset TipKit datastore.
    @State private var tipRefreshToken = 0
    /// Bumped to rebuild all three tabs, which pops everything pushed in them
    /// and dismisses the sheets they present, resetting their state.
    @State private var signedOutResetToken = 0
    @State private var isLoadingVocabulary = false

    /// Snapshot of connection-related settings at the time the connection was last valid.
    /// Used to detect changes made in iOS Settings while the app was backgrounded.
    @State private var lastValidatedSettings: ConnectionSettingsSnapshot?

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var supportPrompts: SupportPromptService
    @State private var isPresentingSupportSheet = false
    @State private var unsyncedLocalRows: UnsyncedLocalRowCount = .counted(0)
    @AppStorage(AppConfig.migrationOfferDismissedBackendKey) private var migrationOfferDismissedBackend: String = ""
    @AppStorage(AppConfig.tagIdentityExplanationPendingKey) private var tagIdentityExplanationPending = false
    /// `tag_identity_mode` is unregistered (absent = the one-time upgrade
    /// decision), so it is bound as an optional and written only on a pick.
    @AppStorage(AppConfig.tagIdentityModeKey) private var storedIdentityMode: String?
    /// The answer, held in memory too. The pending key alone cannot be the
    /// whole gate: a launch argument shadows it in the argument domain, and a
    /// defaults write that fails would otherwise trap the user in the sheet.
    @State private var tagIdentityExplanationAnswered = false
    /// Once-per-session guard for the SpoolLink field bootstrap, released again
    /// if the call fails so the next foreground retries.
    @State private var didEnsureCardUIDsField = false

    /// Declares the `card_uids` field on whichever backend is active, whenever
    /// SpoolLink is on and that backend has a registry. Idempotent — the
    /// repository reads the registry before writing — and safe to call on every
    /// foreground event.
    ///
    /// Two things it deliberately does NOT do any more. It no longer reads
    /// Spoolman's URL and calls `SpoolmanService` directly: that is why the
    /// bootstrap stayed Spoolman-only, and with FilaMan now declaring a
    /// registry it would have provisioned the wrong server. And it no longer
    /// gates on the old SpoolLink shadow flag (removed 2026-10-08 along with
    /// the Library-tab teardown alert it armed), which was written *before*
    /// the call and never cleared — so one failure (a server not yet reachable
    /// at launch) meant the field was never created and never retried. The
    /// once-per-session guard is in memory and is released on failure.
    private func reconcileSpoolLink() {
        // The welcome guide asks how to identify spools; registering `card_uids`
        // before that answer would register it for a user about to choose
        // otherwise (owner, 2026-10-09).
        guard hasCompletedWelcome else { return }
        guard dataStore.needsCardUIDsFieldProvisioning else { return }
        guard !didEnsureCardUIDsField else { return }
        didEnsureCardUIDsField = true
        Task {
            if await dataStore.ensureCardUIDsField() == false {
                didEnsureCardUIDsField = false
            }
        }
    }

    /// Called when the stored backend no longer matches the running one —
    /// either because the first-run guide picked one `init` did not resolve, or
    /// because the Backend screen's picker was changed. `SpoolKidApp` rebuilds
    /// this view in response, which re-runs `init` against the newly stored
    /// `backend_kind`. It is handed the tab on screen, so the rebuilt view
    /// opens there rather than on Tags.
    private let onBackendChanged: (AppTab) -> Void

    /// The tab a new `ContentView` opens on: the UI-test launch argument, else
    /// the tab a backend rebuild left, else the tab last used, else Tags.
    nonisolated static func startTab(
        uiStartOnSpoolman: Bool, restored: AppTab?, saved: AppTab? = nil, printerConfigured: Bool
    ) -> AppTab {
        if uiStartOnSpoolman { return .spoolman }
        let tab = restored ?? saved ?? .tags
        // The Printer tab is shown only once a printer is set up.
        return tab == .printer && !printerConfigured ? .home : tab
    }

    /// Whether the stored backend differs from the one now running.
    ///
    /// Pure so the decision is testable without a `fullScreenCover`. An
    /// unparseable or absent stored kind means nothing worth rebuilding for
    /// was written.
    nonisolated static func needsBackendRebuild(stored: String?, active: BackendKind) -> Bool {
        guard let stored, let chosen = BackendKind(rawValue: stored) else { return false }
        return chosen != active
    }

    /// The migration sheet opens by itself once per backend (audit L2): after
    /// it is closed, the Library tab's Migrate row — which stays until the
    /// library is migrated or discarded — is the way back.
    nonisolated static func autoOffersMigration(shouldOffer: Bool, dismissedFor: String, active: BackendKind) -> Bool {
        shouldOffer && dismissedFor != active.rawValue
    }

    nonisolated enum LaunchMigrationOffer: Equatable {
        case none
        /// Wanted, but the server has not answered yet.
        case waitingForServer
        case shown
    }

    /// The offer is shown only once the server has answered: one that cannot
    /// be reached would only fail in the sheet, and closing it there would
    /// count as declining. Unreachable means no offer this launch, not never.
    nonisolated static func migrationOffer(wanted: Bool, serverAnswered: Bool?) -> LaunchMigrationOffer {
        guard wanted else { return .none }
        switch serverAnswered {
        case nil: return .waitingForServer
        case true?: return .shown
        case false?: return .none
        }
    }

    private var migrationOfferWanted: Bool {
        Self.autoOffersMigration(
            shouldOffer: MigrationService.shouldOfferMigration(
                capabilities: dataStore.capabilities,
                localRows: unsyncedLocalRows
            ),
            dismissedFor: migrationOfferDismissedBackend,
            active: dataStore.capabilities.kind
        )
    }

    private struct ReprobeKey: Equatable {
        var link: ServerLink
        var isActive: Bool
    }

    /// The on-device Library is never down, whatever a stale probe said.
    private var serverLinkState: ServerLinkState {
        ServerLinkState(
            isDown: serverLinkMonitor.link.isDown && !dataStore.capabilities.isOnDeviceStorage,
            backendName: dataStore.capabilities.displayName,
            retry: { [serverLinkMonitor] in Task { await serverLinkMonitor.probeNow() } },
            outcome: { [serverLinkMonitor] write in await serverLinkMonitor.outcome(of: write) }
        )
    }

    private var migrationOffer: LaunchMigrationOffer {
        Self.migrationOffer(wanted: migrationOfferWanted, serverAnswered: serverLinkMonitor.launchAnswer)
    }

    /// Whether the migration offer is on screen. Read by its own sheet and by
    /// the What's New sheet, which must not compete with it: two launch-time
    /// sheets on one view resolve to whichever went true first, and the other
    /// is dropped rather than queued. The other launch sheets also wait while
    /// the server is asked, so the offer never takes the screen from them.
    private var isOfferingMigration: Bool {
        migrationOffer != .none
    }

    /// Whether the What's New sheet is on screen. Read by that sheet's binding
    /// and by `isPresentingLaunchSheet`.
    private var isShowingWhatsNew: Bool {
        !pendingChangelog.isEmpty && hasCompletedWelcome && !isOfferingMigration
    }

    /// After every other launch sheet (spec §5): never over the welcome cover,
    /// the migration offer or What's New.
    private var isShowingTagIdentityExplanation: Bool {
        tagIdentityExplanationPending && !tagIdentityExplanationAnswered
            && hasCompletedWelcome && !isOfferingMigration && !isShowingWhatsNew
    }

    /// The owner's messages come last of all: never over the welcome cover or
    /// any other launch sheet.
    private var launchMessage: AppMessage? {
        messages.launchSheetMessage(settled: launchDecisionsMade && welcomeCoverGone && hasCompletedWelcome
            && !isOfferingMigration && !isShowingWhatsNew && !isShowingTagIdentityExplanation
            && !isPresentingSupportSheet)
    }

    /// Either answer clears the debt, in memory and in defaults.
    private func answerTagIdentityExplanation() {
        tagIdentityExplanationAnswered = true
        tagIdentityExplanationPending = false
    }

    /// Any sheet the root raises over the tabs. The tabs' first-run popovers
    /// would present on top of it, so they are hidden meanwhile.
    private var isPresentingLaunchSheet: Bool {
        isOfferingMigration || isPresentingSupportSheet || isShowingWhatsNew || isShowingTagIdentityExplanation
            || messageSheetOnScreen
    }

    init(
        modelContext: ModelContext,
        restoredTab: AppTab? = nil,
        onBackendChanged: @escaping (AppTab) -> Void = { _ in }
    ) {
        self.onBackendChanged = onBackendChanged
        let shouldStartOnSpoolman = ProcessInfo.processInfo.arguments.contains(Self.uiStartOnSpoolmanArgument)
        let savedTab = UserDefaults.standard.object(forKey: AppConfig.lastSelectedTabKey) == nil
            ? nil : AppTab(rawValue: UserDefaults.standard.integer(forKey: AppConfig.lastSelectedTabKey))
        _welcomeCoverGone = State(initialValue: UserDefaults.standard.bool(forKey: AppConfig.hasCompletedWelcomeKey))
        _selectedTab = State(initialValue: Self.startTab(
            uiStartOnSpoolman: shouldStartOnSpoolman, restored: restoredTab, saved: savedTab,
            printerConfigured: PrinterService.isConfigured(
                address: UserDefaults.standard.string(forKey: AppConfig.printerAddressKey) ?? "")
        ))

        let service = SpoolmanService()
        let filaManSvc = FilaManService()
        _nfcManager = StateObject(wrappedValue: NFCManager())
        _spoolManService = StateObject(wrappedValue: service)
        _filaManService = StateObject(wrappedValue: filaManSvc)
        _emptySpools = StateObject(wrappedValue: EmptySpoolLibrary(context: modelContext))

        let defaults = UserDefaults.standard
        // Routed through the same seed helper the Backend picker uses
        // (SpoolDataStore.seedBackendKindSelection), rather than reassembling
        // resolveBackendKind's three arguments independently — see the F15
        // blank-picker history in that function's doc comment. `current: ""`
        // always takes the derive branch: init has no prior selection to
        // preserve.
        let seededKind = SpoolDataStore.seedBackendKindSelection(
            current: "",
            stored: defaults.string(forKey: AppConfig.backendKindKey),
            spoolmanUrl: defaults.string(forKey: AppConfig.spoolmanUrlKey) ?? AppConfig.defaultSpoolmanUrl,
            spoolmanConnectionValid: defaults.bool(forKey: AppConfig.spoolmanConnectionValidKey)
        )
        let kind = BackendKind(rawValue: seededKind) ?? .local
        // P-3: ledger rows belong to the backend that recorded them.
        TagAssociationStore.shared.activeBackend = kind

        let repository = SpoolDataStore.selectRepository(
            kind: kind,
            spoolmanService: service,
            filaManService: filaManSvc,
            context: modelContext
        )
        let registry = LocationRegistry(context: modelContext, backendKind: kind)
        let locationOrder = LocationOrderStore(backendKind: kind)
        let store = SpoolDataStore(repository: repository, registry: registry, order: locationOrder)
        _dataStore = StateObject(wrappedValue: store)
        let monitor = ServerLinkMonitor(probe: { [weak store] in await store?.checkReachability() ?? .notConfigured })
        monitor.onRecovered = { [weak store] in
            guard let store else { return }
            Task {
                await store.fetchSpools()
                await store.fetchFilaments()
                await store.fetchVendors()
                await store.fetchLocations()
            }
        }
        ServerLinkMonitor.connect(monitor, spoolman: service, filaMan: filaManSvc) { [weak store] in
            store?.connectionTarget ?? ""
        }
        _serverLinkMonitor = StateObject(wrappedValue: monitor)

        // Counted only when a server is active — the on-device Library has
        // nowhere to migrate to, and `shouldOfferMigration` says so anyway.
        let localRows = repository.capabilities.isOnDeviceStorage
            ? UnsyncedLocalRowCount.counted(0)
            : MigrationService.unsyncedLocalRowCount(in: modelContext)
        _unsyncedLocalRows = State(initialValue: localRows)
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeDashboardView()
                    .id("\(tipRefreshToken)-\(signedOutResetToken)")
            }

            // Hidden until a printer is set up (in Settings or the welcome
            // guide): without one the tab had nothing to show.
            if PrinterService.isConfigured(address: printerAddress) {
                Tab("Printer", systemImage: "printer", value: .printer) {
                    PrinterTabView()
                        .id("\(tipRefreshToken)-\(signedOutResetToken)")
                }
            }

            // Always "Library" (audit L1): the tab is where the library lives
            // whichever backend holds it, and its connection row names the
            // backend. The symbol still follows the backend.
            Tab("Library",
                systemImage: dataStore.capabilities.tabSymbol,
                value: .spoolman) {
                SpoolmanTabView(nfcManager: nfcManager)
                    .id("\(tipRefreshToken)-\(signedOutResetToken)")
            }

            Tab("Tags", systemImage: "dot.radiowaves.left.and.right", value: .tags) {
                TagsTabView(nfcManager: nfcManager)
                    .id("\(tipRefreshToken)-\(signedOutResetToken)")
            }
        }
        .onChange(of: selectedTab) { _, tab in
            UserDefaults.standard.set(tab.rawValue, forKey: AppConfig.lastSelectedTabKey)
        }
        .onChange(of: printerAddress) { _, address in
            if selectedTab == .printer, !PrinterService.isConfigured(address: address) { selectedTab = .home }
        }
    }

    var body: some View {
        tabs
        // A pending signed-out notice also hides the tips: a popover on the
        // rebuilt tabs would block the alert the Backend form is about to show.
        .environment(\.hidesFirstRunTips, isPresentingLaunchSheet || spoolManService.signedOutNotice != nil)
        // An expired OpenID sign-in is repaired in the Spoolman form, wherever
        // the user was: go to the Library and rebuild all three tabs, which
        // tears down the sheets they present and resets their state. (A UIKit
        // dismissal would leave SwiftUI's presentation bindings set, so those
        // sheets could refuse to reopen.) Launch sheets owned here stay.
        .onChange(of: spoolManService.signedOutNotice?.id) { _, id in
            guard id != nil else { return }
            selectedTab = .spoolman
            signedOutResetToken += 1
        }
        // A partial success dismisses its form (the record WAS written) but
        // still has something to tell the user, so the note is rendered here
        // at the root, where it outlives the sheet — see `SaveNoticeBanner`
        // and `SpoolDataStore.saveNotice` (plan defect I1).
        //
        // The support ask shares the slot and always loses it: a report that a
        // write half-failed outranks an optional request for money. Because the
        // ask can be withheld this way, it is counted from the banner's own
        // `onAppear` (`markShown`) rather than when the policy decided it —
        // a prompt nobody saw must not spend the user's cooldown.
        .overlay(alignment: .bottom) {
            if let notice = dataStore.saveNotice {
                SaveNoticeBanner(notice: notice) {
                    withAnimation { dataStore.clearSaveNotice() }
                }
            } else if let content = supportPrompts.visibleBanner {
                SupportPromptBanner(
                    content: content,
                    onSupport: { isPresentingSupportSheet = true },
                    onDismiss: { withAnimation { supportPrompts.dismissed() } },
                    onAutoHide: { withAnimation { supportPrompts.autoHidden() } }
                )
                .onAppear { supportPrompts.markShown() }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: dataStore.saveNotice)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: supportPrompts.visibleBanner)
        .environment(\.serverLink, serverLinkState)
        .environmentObject(spoolManService)
        .environmentObject(filaManService)
        .environmentObject(dataStore)
        .environmentObject(bleScale)
        .environmentObject(emptySpools)
        .environmentObject(printerService)
        .environmentObject(changelog)
        .environmentObject(messages)
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedWelcome },
            set: { if $0 == false { hasCompletedWelcome = true } }
        ), onDismiss: {
            welcomeCoverGone = true
            // Donate the event and refresh tips only after the cover's
            // dismissal animation finishes, so the first-run popovers
            // don't flash behind the departing welcome guide.
            Task { await WelcomeGuideCompleted.event.donate() }
            tipRefreshToken += 1
            // AFTER the donation, deliberately. The rebuild discards this
            // view, and the debt note that filed this feared exactly that
            // race — but the donation is an unstructured `Task`, which is not
            // tied to the view's lifetime, and the bump below only takes
            // effect on the next update. Doing it from `onDismiss` rather
            // than from `hasCompletedWelcome` is what keeps the two apart:
            // that flag is what dismisses the cover in the first place.
            if Self.needsBackendRebuild(
                stored: UserDefaults.standard.string(forKey: AppConfig.backendKindKey),
                active: dataStore.capabilities.kind
            ) {
                onBackendChanged(selectedTab)
            }
        }) {
            WelcomeGuideView(
                hasCompletedWelcome: $hasCompletedWelcome,
                spoolManService: spoolManService,
                filaManService: filaManService,
                activeKind: dataStore.capabilities.kind
            )
            // The environment objects above are applied before this modifier,
            // so they do not reach the cover's content. The printer step reads
            // `PrinterService`; without it a fresh install traps on launch.
            .environmentObject(printerService)
        }
        .sheet(isPresented: Binding(
            get: { migrationOffer == .shown },
            set: { if !$0 { migrationOfferDismissedBackend = dataStore.capabilities.kind.rawValue } }
        ), onDismiss: {
            unsyncedLocalRows = MigrationService.unsyncedLocalRowCount(in: modelContext)
        }) {
            MigrationReviewView(
                service: MigrationService(
                    context: modelContext,
                    // Migration writes through the shared store, whose repository
                    // is whichever server backend is active.
                    writer: dataStore
                )
            )
        }
        .sheet(isPresented: $isPresentingSupportSheet) {
            SupportChoiceSheet(
                onOpen: { supportPrompts.openedSupport() },
                onOptOut: { supportPrompts.optOut() }
            )
        }
        // Gated on `hasCompletedWelcome` so it can never stack on the welcome
        // `fullScreenCover`, and against the migration offer, which is decided
        // synchronously at first render while this one is decided in `.task`
        // — the notes would otherwise be dropped, and their marker never
        // advanced, on every launch until the migration is resolved.
        // Dismissing migration gives this sheet the clean false-to-true edge
        // it needs. `changelogLastShown` is advanced on dismissal rather than
        // on presentation, so a user who kills the app mid-sheet sees it once
        // more rather than never.
        .sheet(isPresented: Binding(
            get: { isShowingWhatsNew },
            set: { if !$0 { pendingChangelog = [] } }
        ), onDismiss: {
            changelogLastShown = Bundle.main.appVersion ?? changelogLastShown
        }) {
            WhatsNewView(entries: pendingChangelog, presentation: .sheet)
        }
        // Swiping it away means Keep; either answer clears the debt.
        .sheet(isPresented: Binding(
            get: { isShowingTagIdentityExplanation },
            set: { if !$0 { answerTagIdentityExplanation() } }
        )) {
            TagIdentityExplanationView(
                lines: TagStoreText.explanationLines(
                    storeNames: TagStoreText.explanationStoreNames(
                        targets: dataStore.tagIdentity.linkTargets, available: dataStore.availableTagStores,
                        capabilities: dataStore.capabilities
                    ),
                    connectionRowLabel: dataStore.capabilities.connectionRowLabel
                ),
                onKeep: { answerTagIdentityExplanation() },
                onUseSpoolID: {
                    storedIdentityMode = TagIdentityMode.spoolID.rawValue
                    answerTagIdentityExplanation()
                }
            )
        }
        // Seen is recorded only by the sheet's own buttons, never by this
        // binding: a presentation SwiftUI drops because another sheet is up
        // must leave the message owed for a later launch, and a feed change
        // mid-sheet must not mark a different message seen. One message per
        // launch: `launchSheetMessage` goes nil, not to the next owed one.
        .sheet(item: Binding(
            get: { launchMessage },
            set: { _ in }
        )) { message in
            MessageView(
                message: message,
                image: messages.image(for: message),
                onAction: { messages.markActed(message.id) },
                onClose: { messages.markSeen(message.id) }
            )
            .onAppear {
                messages.didPresent(message.id)
                messageSheetOnScreen = true
            }
            .onDisappear { messageSheetOnScreen = false }
        }
        // The Backend screen posts on dismissal; the repository is resolved in
        // `init`, so re-running it is the only way to make the pick live.
        .onReceive(NotificationCenter.default.publisher(
            for: AppConfig.backendKindDidChangeNotification
        )) { _ in
            if Self.needsBackendRebuild(
                stored: UserDefaults.standard.string(forKey: AppConfig.backendKindKey),
                active: dataStore.capabilities.kind
            ) {
                onBackendChanged(selectedTab)
            }
        }
        .task { await serverLinkMonitor.probeNow() }
        // Only in the foreground; restarted on every change of the link.
        .task(id: ReprobeKey(link: serverLinkMonitor.link, isActive: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await serverLinkMonitor.reprobeWhileDown()
        }
        .task {
            // Preload OCR vocabulary in the background so the first scan opens instantly
            isLoadingVocabulary = true
            await Task.detached(priority: .background) {
                OCRVocabularyLoader.shared.preload()
            }.value
            isLoadingVocabulary = false
            // Not awaited: the weekly SpoolmanDB refresh must not hold up the rest of this task.
            if VocabularyRefreshService.shouldRun(
                environment: ProcessInfo.processInfo.environment,
                arguments: ProcessInfo.processInfo.arguments
            ) {
                Task.detached(priority: .background) { await VocabularyRefreshService().refreshIfDue() }
            }
            supportPrompts.record(.appBecameActive(version: Bundle.main.appVersion ?? ""))
            let installed = Bundle.main.appVersion ?? ""
            let owed = ChangelogService.entriesToPresent(
                installed: installed,
                lastShown: changelogLastShown,
                autoShow: changelogAutoShow,
                entries: changelog.entries
            )
            if owed.isEmpty {
                // Nothing to show — seed or advance the marker so a user who
                // was opted out, or who is new, does not accumulate a backlog.
                changelogLastShown = installed
            } else {
                pendingChangelog = owed
            }
            launchDecisionsMade = true
            // Refreshed after the decision, deliberately: the bundled copy
            // already describes the version just installed, so the sheet never
            // waits on the network. A newer remote file lands for next time.
            await changelog.refresh()
            await messages.refresh()
            // Ensure tips are eligible for users who already completed the welcome
            // (e.g. after an app update that introduced TipKit)
            if hasCompletedWelcome {
                await WelcomeGuideCompleted.event.donate()
            }
        }
        .onChange(of: isConnectionValid) { _, valid in
            if valid {
                // Snapshot settings at the moment the connection is validated
                lastValidatedSettings = ConnectionSettingsSnapshot.current()
                reconcileSpoolLink()
            }
        }
        .onChange(of: hasCompletedWelcome) { _, done in
            if done { reconcileSpoolLink() }
        }
        // Provisioning settles after launch: once a server's version is read
        // (it waits for that), and whenever the mode or a store switch
        // changes — Tag Links picked on a server without the field would
        // otherwise fail its link writes until the next foreground. Watched
        // as the gate itself rather than `tagIdentity`: below 0.27 reading
        // the version leaves the policy unchanged.
        .onChange(of: dataStore.needsCardUIDsFieldProvisioning) { _, needed in
            if needed { reconcileSpoolLink() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await serverLinkMonitor.probeNow() }
                Task { await messages.refreshIfDue() }
                // When returning from iOS Settings (or any background),
                // invalidate the Spoolman connection if settings changed.
                if isConnectionValid, let snapshot = lastValidatedSettings {
                    let current = ConnectionSettingsSnapshot.current()
                    if current != snapshot {
                        isConnectionValid = false
                        lastValidatedSettings = nil
                    }
                }
                reconcileSpoolLink()
            }
        }
        .onChange(of: dataStore.writeCount) { oldValue, newValue in
            let delta = newValue - oldValue
            if delta > 0 { supportPrompts.record(.backendWriteSucceeded(count: delta)) }
        }
        .overlay(alignment: .topTrailing) {
            if isLoadingVocabulary {
                ProgressView()
                    .controlSize(.mini)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .padding(8)
            }
        }
        .onAppear {
            // The toolhead readers of every NFCManager reach the printer through this.
            NFCManager.printerTagGateway = printerService
            // Capture initial snapshot if connection is already valid on launch
            if isConnectionValid {
                lastValidatedSettings = ConnectionSettingsSnapshot.current()
            }
            reconcileSpoolLink()
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ContentView(modelContext: container.mainContext)
        .environmentObject(SupportPromptService())
}

extension EnvironmentValues {
    /// Popovers present above sheets, so a screen hides its first-run tips
    /// while the root shows a launch-time sheet (migration offer, support
    /// choice, What's New). Set by `ContentView` on its `TabView`.
    @Entry var hidesFirstRunTips: Bool = false
}
