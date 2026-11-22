//
//  SpoolKidApp.swift
//  SpoolKid
//
//  Purpose: The main entry point of the SwiftUI application.
//  Configures TipKit for contextual tips shown after the welcome guide.
//  Registers Settings.bundle defaults and handles the "Reset All Data" flag.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI
import SwiftData
import TipKit
import os.log

private let logger = Logger(subsystem: "com.spoolkid", category: "SpoolKidApp")

@main
struct SpoolKidApp: App {
    private let modelContainer: ModelContainer

    init() {
        // Register default values for Settings.bundle preferences so they
        // are available before the user ever opens the iOS Settings app.
        UserDefaults.standard.register(defaults: [
            AppConfig.spoolmanUrlKey: "",
            AppConfig.trustAllCertsKey: false,
            AppConfig.authTypeKey: "none",
            AppConfig.authUsernameKey: "",
            AppConfig.nfcTagFormatKey: TagFormat.openSpool.rawValue,
            AppConfig.recentTagsLimitKey: 20,
            AppConfig.writeOpacityToTagsKey: true,
            AppConfig.loadoutMinimumRemainingKey: 10.0,
            AppConfig.recentTagsKeepFormatKey: true,
            AppConfig.confirmBeforeDeleteKey: true,
            AppConfig.selectTextOnFocusKey: true,
            AppConfig.colorMapIslandBaseDiameterKey: 12.0,
            AppConfig.resetAppDataKey: false,
            // Tag Matching & UID Persistence
            AppConfig.spoolmanPersistCardUIDKey: false,
            AppConfig.spoolmanNativeTagsEnabledKey: true,
            AppConfig.tagReaderEnabledKey: true,
            // Diagnostics (one switch for every kind of contributed sample)
            AppConfig.diagnosticsEnabledKey: false,
            // Backend Selection (backendKindKey deliberately unregistered — its
            // absence triggers derivation for existing installs)
            AppConfig.filamanUrlKey: "",
            AppConfig.filamanConnectionValidKey: false,
            AppConfig.filamanTrustAllCertsKey: false,
            // Support prompts
            AppConfig.supportScanCountKey: 0,
            AppConfig.supportEditCountKey: 0,
            AppConfig.supportPromptsShownKey: 0,
            AppConfig.supportOptedOutKey: false,
            AppConfig.supportLastPromptAtKey: 0.0,
            AppConfig.supportLastSeenVersionKey: "",
            // Spool lists
            AppConfig.spoolGroupingKey: SpoolGrouping.filament.rawValue,
            AppConfig.spoolPickerGroupingKey: SpoolGrouping.none.rawValue,
            AppConfig.spoolPickerSortFieldKey: SpoolSortOption.recent.rawValue,
            AppConfig.spoolPickerSortAscendingKey: false,
            AppConfig.libraryShowsWithoutSpoolsKey: false,
            // What's New
            AppConfig.changelogAutoShowKey: true,
            AppConfig.changelogLastShownVersionKey: ""
        ])
        UserDefaults.standard.register(defaults: AppConfig.fieldVisibilityDefaults)

        // Before anything reads the switch. A tester who opted into OCR
        // archive sharing opted into the thing that replaced it.
        DiagnosticsPreference.migrateLegacyOCRArchiveSwitch(in: .standard)

        // Default configuration (auto-creates Application Support). Adding the
        // `localId` field + `LocalIdSequence` model is a SwiftData lightweight
        // migration, so an existing M1 store opens without a reset.
        do {
            modelContainer = try ModelContainer(
                for: LocalVendor.self, LocalFilament.self, LocalSpool.self,
                     LocalIdSequence.self, LocationRegistryEntry.self, EmptySpoolEntry.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Handle the "Reset All Data on Next Launch" flag from Settings.bundle.
        // The container must exist first so we can wipe the Library via the
        // SwiftData context API (no store-file deletion).
        if UserDefaults.standard.bool(forKey: AppConfig.resetAppDataKey) {
            Self.wipeLocalStore(modelContainer.mainContext)
            Self.wipeLocationRegistry(modelContainer.mainContext)
            Self.wipeEmptySpoolLibrary(modelContainer.mainContext)
            Self.resetAllAppData()
        }

        // Before any view, and after the reset, which leaves a new install:
        // a new install starts on Tag Links; an upgrade is decided later,
        // once the active backend's tag stores are known.
        TagIdentityMigration.persistFreshInstallIfNeeded()

        try? Tips.configure([
            .displayFrequency(.immediate)
        ])
    }

    /// Bumped to rebuild `ContentView` from scratch, which is the only way to
    /// re-resolve the backend: `ContentView.init` picks the repository and
    /// hands it to `@StateObject`s that outlive every other update.
    ///
    /// Lives HERE rather than in `ContentView` because a view cannot `.id()`
    /// itself. Its callers are the first-run guide's dismissal and the Backend
    /// screen's — see `ContentView.needsBackendRebuild`.
    @State private var contentRebuildToken = 0
    /// The tab on screen when the last rebuild was asked for, so the rebuilt
    /// `ContentView` opens there — a backend switched from Library stays in
    /// Library.
    @State private var tabBeforeRebuild: AppTab?

    /// Owned here rather than in `ContentView` because `ContentView` is
    /// discarded and rebuilt by `contentRebuildToken`; a `@StateObject` there
    /// would be recreated mid-flight and drop a visible prompt.
    @StateObject private var supportPrompts = SupportPromptService()

    var body: some Scene {
        WindowGroup {
            ContentView(
                modelContext: modelContainer.mainContext,
                restoredTab: tabBeforeRebuild,
                onBackendChanged: { tab in
                    tabBeforeRebuild = tab
                    contentRebuildToken += 1
                }
            )
            .id(contentRebuildToken)
            .environmentObject(supportPrompts)
            .tint(.accentColor)
        }
        .modelContainer(modelContainer)
    }
    
    /// Deletes the on-device Library — spools, filaments, vendors, the
    /// Library's own location-registry entries, and the `LocalIdSequence`
    /// counters. Wiping `LocalIdSequence` resets the monotonic id counters so
    /// new rows start from 1 again, matching a true first-launch state.
    ///
    /// Registry entries of the other backends are kept: this also runs after a
    /// Library → server migration (`MigrationService`), and those entries are
    /// the servers' empty locations and location tags. Reset clears them
    /// through `wipeLocationRegistry`.
    static func wipeLocalStore(_ context: ModelContext) {
        do {
            let spools = try context.fetch(FetchDescriptor<LocalSpool>())
            let filaments = try context.fetch(FetchDescriptor<LocalFilament>())
            let vendors = try context.fetch(FetchDescriptor<LocalVendor>())
            let sequences = try context.fetch(FetchDescriptor<LocalIdSequence>())
            let registryEntries = try context.fetch(FetchDescriptor<LocationRegistryEntry>())
                .filter { $0.backendKind == BackendKind.local.rawValue }

            spools.forEach { context.delete($0) }
            filaments.forEach { context.delete($0) }
            vendors.forEach { context.delete($0) }
            sequences.forEach { context.delete($0) }
            registryEntries.forEach { context.delete($0) }

            try context.save()
        } catch {
            logger.error("Failed to wipe local store: \(error.localizedDescription)")
        }
    }

    /// Deletes every backend's location-registry entries. Reset-only, like
    /// `wipeEmptySpoolLibrary`: a migration must not touch the registry of the
    /// server it migrates to, or of any other server.
    static func wipeLocationRegistry(_ context: ModelContext) {
        do {
            try context.fetch(FetchDescriptor<LocationRegistryEntry>()).forEach { context.delete($0) }
            try context.save()
        } catch {
            logger.error("Failed to wipe the location registry: \(error.localizedDescription)")
        }
    }

    /// Deletes the empty-spool library. Reset-only, and deliberately not part
    /// of `wipeLocalStore`: that also runs after a Library → server migration
    /// (`MigrationService`), and the library belongs to the device, not to the
    /// backend being left.
    static func wipeEmptySpoolLibrary(_ context: ModelContext) {
        do {
            try context.fetch(FetchDescriptor<EmptySpoolEntry>()).forEach { context.delete($0) }
            try context.save()
        } catch {
            logger.error("Failed to wipe the empty-spool library: \(error.localizedDescription)")
        }
    }

    /// Clears all UserDefaults entries for this app, resets TipKit data,
    /// and turns the reset flag back off.
    private static func resetAllAppData() {
        // Clear all UserDefaults for this app's bundle
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
            UserDefaults.standard.synchronize()
        }
        
        // Credentials live in the Keychain, which is NOT part of the
        // UserDefaults domain cleared above and survives app deletion. Until
        // 2026-08-25 FilaMan's API key outlived a reset that claims to clear
        // everything; Spoolman's password and token joined it there in the
        // same change that added this line (016 / F3.2). Scoped to SpoolKid's
        // own three accounts — see the method's doc comment.
        KeychainStore.deleteSpoolKidSecrets()

        // Reset TipKit datastore
        try? Tips.resetDatastore()

        // Ensure the reset toggle is turned back off so it doesn't
        // fire again on the next launch.
        UserDefaults.standard.set(false, forKey: AppConfig.resetAppDataKey)
    }
}
