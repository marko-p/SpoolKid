//
//  AppConfig.swift
//  SpoolKid
//
//  Created by Marko on 12/30/25.
//
//  Purpose: Central configuration file for the application.
//  Contains:
//  - Storage keys for UserDefaults/AppStorage
//  - Default values for new tags/spools
//  - Predefined lists of Materials and Brands
//  - Temperature presets for different materials
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct AppConfig {
    static let spoolmanUrlKey = "spoolman_url"
    static let defaultSpoolmanUrl = ""
    
    // Authentication & Security
    static let authTypeKey = "spoolman_auth_type"            // "none", "basic", "bearer", "oidc"
    static let oidcIssuerKey = "spoolman_oidc_issuer"        // String
    static let oidcClientIdKey = "spoolman_oidc_client_id"   // String
    static let oidcScopesKey = "spoolman_oidc_scopes"        // String, blank = OIDCConfiguration.defaultScopes
    static let trustAllCertsKey = "spoolman_trust_all_certs" // Bool
    static let authUsernameKey = "spoolman_auth_username"    // String
    /// LEGACY. Spoolman's password and bearer token moved to the Keychain on
    /// 2026-08-25 (016 / F3.2); these two keys survive only as
    /// `KeychainStore.migratingRead` sources for installs that predate the
    /// move, and are removed from `UserDefaults` once copied. Nothing may
    /// write them again.
    static let authPasswordKey = "spoolman_auth_password"    // String, legacy
    static let authTokenKey    = "spoolman_auth_token"       // String, legacy
    
    // NFC Tag Format
    static let nfcTagFormatKey = "nfc_tag_format"            // TagFormat.rawValue
    
    // Onboarding
    static let hasCompletedWelcomeKey = "has_completed_welcome" // Bool
    
    // Reset
    static let resetAppDataKey = "reset_app_data"              // Bool

    // MARK: - Tag Matching & UID Persistence

    /// Master switch for the SpoolLink integration (Snapmaker U1 `card_uids` mapping).
    /// Repurposed from the old "persist UID to lot_nr" toggle; the key string is
    /// unchanged so existing users keep their saved value.
    static let spoolmanPersistCardUIDKey = "spoolman_persist_card_uid"      // Bool, default false

    /// Whether new tag links go to Spoolman's own Tags (Spoolman 0.27+ only).
    /// Mirrors paxx12's `use_spoolman_uid`; on by default, like his.
    static let spoolmanNativeTagsEnabledKey = "spoolman_native_tags_enabled" // Bool, default true

    /// Whether new tag links go to FilaMan's `rfid_uid` (FilaMan Tags). Absent
    /// means off: an upgrader keeps today's behaviour. A fresh install writes
    /// true (`TagIdentityMigration.persistFreshInstallIfNeeded`).
    static let filamanTagsEnabledKey = "filaman_tags_enabled"               // Bool, absent = false
    /// Whether new tag links also go to SpoolLink's `card_uids` on FilaMan.
    static let filamanSpoolLinkEnabledKey = "filaman_spoollink_enabled"     // Bool, absent = true

    /// How SpoolKid identifies a spool from a tag (`TagIdentityMode` raw
    /// value). Deliberately NOT registered: unset means the one-time upgrade
    /// decision has not been taken (`TagIdentityMigration`).
    static let tagIdentityModeKey = "tag_identity_mode"                       // String, unregistered

    /// The upgrade decision found both Write Spool ID and linking on; the
    /// explanation sheet is owed until it is dismissed.
    static let tagIdentityExplanationPendingKey = "tag_identity_explanation_pending" // Bool, default false

    // MARK: - Spoolman Tag Reader (spec 3)

    /// Whether SpoolKid reports each scanned tag to Spoolman 0.27+
    /// (`POST /tag/scan`), so a paired browser opens its spool.
    static let tagReaderEnabledKey = "spoolman_tag_reader_enabled"           // Bool, default true
    /// The reader name Spoolman shows; blank means "SpoolKid on ‹device›".
    static let tagReaderNameKey = "spoolman_tag_reader_name"                 // String, unregistered
    /// `spoolkid-` + 8 hex, generated once (`TagReaderIdentity.readerID`).
    static let tagReaderIdKey = "spoolman_tag_reader_id"                     // String, unregistered


    // MARK: - NFC Write

    /// The old "Write Spool ID to Tag" switch. Read ONLY by
    /// `TagIdentityPolicy.current` and `TagIdentityMigration` for the upgrade
    /// decision; never written.
    static let legacyWriteSpoolIdKey = "write_spool_id"                      // Bool, unregistered (missing = true)

    // MARK: - Recent Tags

    static let recentTagsKey = "recent_tags"                                 // Data (encoded [RecentTag])
    static let recentTagsLimitKey = "recent_tags_limit"                      // Int, default 20
    /// Off: every tag format writes opaque. Toolheads ignore it (`FilamentOpacity`).
    static let writeOpacityToTagsKey = "write_opacity_to_tags"               // Bool, default true
    /// The tab the app reopens on (`AppTab.rawValue`).
    static let lastSelectedTabKey = "last_selected_tab"                      // Int, unregistered
    static let printerAddressKey = "printer_address"                         // String, unregistered
    static let printerNameKey = "printer_name"                               // String, unregistered
    static let printerAssignmentWatchKey = "printer_assignment_watch"        // Data, unregistered
    static let loadoutMinimumRemainingKey = "loadout_minimum_remaining"      // Double, default 10 (grams)
    /// Whether the planner may use multi-colour spools, matched on any colour.
    static let loadoutIncludesMultiColorKey = "loadout_includes_multi_color" // Bool, unregistered (default false)
    static let recentTagsKeepFormatKey = "recent_tags_keep_format"           // Bool, default true
    /// Whether the weigh session takes its weights off a Bluetooth scale
    /// instead of the keyboard. A mode, not a preference about one spool —
    /// a bench session is all one way or all the other.
    static let weighWithScaleKey = "weigh_with_scale"                        // Bool, default false

    /// Per-scale zero masks, keyed by peripheral identifier. Learned by
    /// watching the scale rest (`AiLinkScaleZero`), never typed by anyone, and
    /// kept so a scale is only ever learned once.
    static let bleScaleZeroMasksKey = "ble_scale_zero_masks"                // Data (encoded [String: UInt16] peripheral UUID -> mask)
    /// The one scale this phone weighs with. Set up once, in Settings; every
    /// weighing screen then uses it without asking. Absent means "no scale",
    /// which is also what keeps the Bluetooth permission prompt away from
    /// people who do not own one.
    static let bleScalePairedKey = "ble_scale_paired"                       // Data (encoded BLEScaleService.Paired)
    static let tagLedgerKey = "tag_ledger"                                  // Data (legacy global [String: Int] UID→spoolId; adopted into the first active backend's scope, then removed)
    static let tagLedgerScopedKey = "tag_ledger_scoped"                     // Data (encoded [String: [String: Int]] backend scope → UID→spoolId)
    static let dashboardHiddenCardsKey = "dashboard_hidden_cards"           // Data (encoded [String: Bool] per-DashboardCardKind visibility override)

    // MARK: - Spool Form "Remember Last"

    static let lastSpoolPriceKey = "last_spool_price"                        // String, default ""
    static let lastSpoolEmptyWeightKey = "last_spool_empty_weight"           // String, default "0"
    static let lastSpoolFilamentIdKey = "last_spool_filament_id"             // Int, default -1

    // MARK: - Filament Form "Remember Last"

    static let lastFilamentMaterialKey = "last_filament_material"            // String, default ""
    static let lastFilamentVendorIdKey = "last_filament_vendor_id"           // Int, default -1
    static let lastFilamentColorHexKey = "last_filament_color_hex"           // String, default "000000"
    static let lastFilamentDensityKey = "last_filament_density"              // Double, default 1.24
    static let lastFilamentDiameterKey = "last_filament_diameter"            // Double, default 1.75
    static let lastFilamentExtruderTempKey = "last_filament_extruder_temp"   // Int, default 205
    static let lastFilamentBedTempKey = "last_filament_bed_temp"             // Int, default 60

    // MARK: - Connection & UI State

    static let spoolmanConnectionValidKey = "spoolman_connection_valid"      // Bool, default false
    static let confirmBeforeDeleteKey = "confirm_before_delete"              // Bool, default true
    static let selectTextOnFocusKey = "select_text_on_focus"                // Bool, default true (form fields select their value when focused)
    static let colorMapIslandBaseDiameterKey = "color_map_island_base_diameter" // Double, default 12, bounds 8–20 pt (color filter map dot size)
    static let colorCaptureGuideSeenKey = "color_capture_guide_seen"            // Bool, unregistered (missing = false)
    static let colorCaptureCircleRadiusKey = "color_capture_circle_radius"      // Double, view-width fraction, unregistered (missing = 0.12)

    // MARK: - Backend Selection

    static let backendKindKey = "backend_kind"                              // String, BackendKind.rawValue; absent = derive
    /// The `BackendKind.rawValue` the automatic migration sheet was closed for.
    /// Empty until the first close. The Library tab's Migrate row ignores it.
    static let migrationOfferDismissedBackendKey = "migration_offer_dismissed_backend"  // String

    /// Posted when the Backend screen is left, so `ContentView` can re-resolve
    /// the repository against whatever `backendKindKey` now says. Nothing else
    /// swaps it: the repository is chosen in `ContentView.init` and handed to
    /// `@StateObject`s that outlive every other update, so before this the
    /// picker's choice only took effect at the next launch — and the app kept
    /// reading and writing the OLD backend in the meantime, with only the tab's
    /// name to say so (device finding, 2026-08-29).
    static let backendKindDidChangeNotification = Notification.Name("SpoolKid.backendKindDidChange")
    static let filamanUrlKey = "filaman_url"                                // String, default ""
    static let filamanConnectionValidKey = "filaman_connection_valid"       // Bool, default false
    /// FilaMan's OWN trust-all-certs flag. `trustAllCertsKey` above is
    /// Spoolman's, and `FilaManService` read it until 2026-08-25 (I2) — a flag
    /// only `SpoolmanConnectionForm` can write, and that form renders solely
    /// when the backend is Spoolman. A FilaMan user over HTTPS with a
    /// self-signed certificate therefore could not connect, and nothing said
    /// why. Read through `BackendCapabilities.trustsAllCerts`, never directly
    /// by a shared view.
    static let filamanTrustAllCertsKey = "filaman_trust_all_certs"           // Bool, default false

    // MARK: - Sort State

    static let spoolSortFieldKey = "spool_sort_field"                        // String, default SpoolSortOption.id.rawValue
    static let spoolSortAscendingKey = "spool_sort_ascending"                // Bool, default false
    static let locationSortFieldKey = "location_sort_field"                  // String, default LocationSortOption.manual.rawValue
    static let locationSortAscendingKey = "location_sort_ascending"          // Bool, default true
    /// The spool sort INSIDE a location group. Deliberately not
    /// `spoolSortFieldKey`: Manage Spools defaults to Spool ID, which is a
    /// library index, while a shelf wants Name, which is how you find a reel in
    /// your hand. One shared key would make each screen re-sort the other.
    static let locationSpoolSortFieldKey = "location_spool_sort_field"       // String, default SpoolSortOption.name.rawValue
    static let locationSpoolSortAscendingKey = "location_spool_sort_ascending" // Bool, default true
    /// Manage Spools' own grouping. Select Spool has its own, `spoolPickerGroupingKey`.
    static let spoolGroupingKey = "spool_grouping"                         // String, default SpoolGrouping.filament.rawValue
    /// Select Spool's own Group choice: you hold the spool when writing a tag or weighing, so a flat list by number is the quicker default (owner, 2026-10-24).
    static let spoolPickerGroupingKey = "spool_picker_grouping"            // String, default SpoolGrouping.none.rawValue
    /// Select Spool's own sort, so it stops sharing Manage Spools' sort. The most recent spool (last used, else added) comes first by default.
    static let spoolPickerSortFieldKey = "spool_picker_sort_field"         // String, default SpoolSortOption.recent.rawValue
    static let spoolPickerSortAscendingKey = "spool_picker_sort_ascending" // Bool, default false

    // MARK: - Location Arrangement

    /// The order the user dragged their shelves into, per backend.
    /// `Data`, JSON `[String: [String]]` — `BackendKind.rawValue` → ordered
    /// `LocationName.normalizedKey` values. Scoped by kind to match
    /// `LocationRegistryEntry.backendKind`, so switching backends does not
    /// shuffle the other one's shelves.
    static let locationManualOrderKey = "location_manual_order"

    // MARK: - Spoolman Field Visibility

    static let visibilityVendorNameKey = "visibility_vendor_name"
    static let visibilityVendorCommentKey = "visibility_vendor_comment"
    static let visibilityVendorEmptySpoolWeightKey = "visibility_vendor_empty_spool_weight"
    static let visibilityVendorExternalIdKey = "visibility_vendor_external_id"

    static let visibilityFilamentPriceKey = "visibility_filament_price"
    static let visibilityFilamentWeightKey = "visibility_filament_weight"
    static let visibilityFilamentSpoolWeightKey = "visibility_filament_spool_weight"
    static let visibilityFilamentArticleNumberKey = "visibility_filament_article_number"
    static let visibilityFilamentCommentKey = "visibility_filament_comment"
    static let visibilityFilamentExternalIdKey = "visibility_filament_external_id"

    static let visibilitySpoolUsedWeightKey = "visibility_spool_used_weight"
    static let visibilitySpoolCommentKey = "visibility_spool_comment"
    static let visibilitySpoolArchivedKey = "visibility_spool_archived"
    static let visibilitySpoolFirstUsedKey = "visibility_spool_first_used"
    static let visibilitySpoolLastUsedKey = "visibility_spool_last_used"
    static let visibilitySpoolStatusKey = "visibility_spool_status"
    static let visibilitySpoolExternalIdKey = "visibility_spool_external_id"
    static let visibilitySpoolPurchaseDateKey = "visibility_spool_purchase_date"

    static let visibilityNFCOpenSpoolNameKey = "visibility_nfc_opensp_name"
    static let visibilityNFCOpenSpoolSubtypeKey = "visibility_nfc_opensp_subtype"
    static let visibilityNFCOpenSpoolSpoolIDKey = "visibility_nfc_opensp_spool_id"
    static let visibilityNFCOpenTag3DSubtypeKey = "visibility_nfc_ot3d_subtype"
    static let visibilityNFCOpenTag3DNameKey = "visibility_nfc_ot3d_name"
    static let visibilityNFCOpenTag3DDiameterKey = "visibility_nfc_ot3d_diameter"
    static let visibilityNFCOpenTag3DNominalWeightKey = "visibility_nfc_ot3d_nominal_weight"
    static let visibilityNFCOpenTag3DEmptyWeightKey = "visibility_nfc_ot3d_empty_weight"
    static let visibilityNFCOpenTag3DDryingTempKey = "visibility_nfc_ot3d_drying_temp"
    static let visibilityNFCOpenTag3DDryingTimeKey = "visibility_nfc_ot3d_drying_time"
    static let visibilityNFCOpenTag3DManufacturedKey = "visibility_nfc_ot3d_manufactured"
    static let visibilityNFCAnycubicDiameterKey = "visibility_nfc_ace_diameter"
    static let visibilityNFCAnycubicNominalWeightKey = "visibility_nfc_ace_nominal_weight"
    static let visibilityNFCOpenPrintTagNameKey = "visibility_nfc_opt_name"
    static let visibilityNFCOpenPrintTagDensityKey = "visibility_nfc_opt_density"
    static let visibilityNFCOpenPrintTagPreheatKey = "visibility_nfc_opt_preheat"
    static let visibilityNFCOpenPrintTagNominalWeightKey = "visibility_nfc_opt_nominal_weight"
    static let visibilityNFCOpenPrintTagEmptyWeightKey = "visibility_nfc_opt_empty_weight"
    static let visibilityNFCOpenPrintTagDryingTempKey = "visibility_nfc_opt_drying_temp"
    static let visibilityNFCOpenPrintTagDryingTimeKey = "visibility_nfc_opt_drying_time"
    static let visibilityNFCOpenPrintTagGTINKey = "visibility_nfc_opt_gtin"
    static let visibilityNFCOpenPrintTagCountryKey = "visibility_nfc_opt_country"
    static let visibilityNFCOpenPrintTagManufacturedKey = "visibility_nfc_opt_manufactured"
    static let visibilityNFCOpenPrintTagURLKey = "visibility_nfc_opt_url"
    static let visibilityNFCOpenPrintTagDiameterKey = "visibility_nfc_opt_diameter"
    static let visibilityNFCOpenPrintTagRemainingKey = "visibility_nfc_opt_remaining"
    static let visibilityNFCTigerTagNameKey = "visibility_nfc_tt_name"
    static let visibilityNFCTigerTagSubtypeKey = "visibility_nfc_tt_subtype"
    static let visibilityNFCTigerTagDiameterKey = "visibility_nfc_tt_diameter"
    static let visibilityNFCTigerTagNominalWeightKey = "visibility_nfc_tt_nominal_weight"

    // MARK: - Manage Spools View State

    static let manageSpoolsShowArchivedKey = "manage_spools_show_archived"     // Bool, default false (in-screen view state)
    static let libraryShowsWithoutSpoolsKey = "library_shows_without_spools" // Bool, default false (in-screen view state)

    // MARK: - Weigh Session

    /// Bool, default true. Whether "Scan"/"Choose" in the batch weigh loop also
    /// commit the reading on screen. In-app, not Settings.bundle: it is part of
    /// the loop's own workflow and lives on the screen it governs (C2).
    static let weighAutoSaveOnAdvanceKey = "weigh_auto_save_on_advance"

    /// Data, JSON `[MeasurementRecord]`. This device's log of weighings it
    /// performed — history for backends that keep none of their own.
    static let weighHistoryKey = "weigh_history"

    // MARK: - OCR Vocabulary

    /// When the online OCR vocabulary was last refreshed from SpoolmanDB. Written only after
    /// the delta files land, so a failed refresh leaves it unset or old and retries.
    static let vocabularyLastRefreshKey = "ocr_vocabulary_last_refresh"          // Date, unregistered
    /// Launch argument the UI tests pass so the app does not download SpoolmanDB mid-run.
    static let disableVocabularyRefreshArgument = "-disableVocabularyRefresh"

    // MARK: - OCR Archive

    /// LEGACY. Superseded on 2026-09-06 by `diagnosticsEnabledKey`, which is
    /// one switch for every kind of sample a test user can contribute rather
    /// than one per feature. Survives only as a migration source — read once
    /// at launch by `DiagnosticsPreference.migrateLegacyOCRArchiveSwitch` and
    /// removed. Nothing may write it again, and it is no longer registered.
    static let saveOCRArchivesKey = "save_ocr_archives"                       // Bool, legacy

    /// The single "I am a test user" switch: gates every diagnostic capture
    /// SpoolKid can offer to share, and reveals the Diagnostics screen behind
    /// the toolbar's bug button. One switch rather than one per feature —
    /// a tester who is helping is helping with whatever is being worked on,
    /// and per-feature switches would be a settings screen that grows a row
    /// per experiment. Settings.bundle rather than in-app: rarely touched, no
    /// rich UI, and deliberately not on a path an ordinary user walks.
    ///
    /// Nothing is ever sent automatically. This only lets SpoolKid *keep*
    /// captures and offer them to a Share sheet the user drives.
    static let diagnosticsEnabledKey = "diagnostics_enabled"                  // Bool, default false

    // MARK: - Support Prompts
    //
    // In-app behaviour, not user configuration — nothing here belongs in
    // Settings.bundle (C2). The only user-facing controls are the banner's own
    // "Don't ask again" and the existing Settings screen.

    static let supportScanCountKey = "support_scan_count"                     // Int, default 0
    static let supportEditCountKey = "support_edit_count"                     // Int, default 0
    static let supportPromptsShownKey = "support_prompts_shown"               // Int, default 0
    /// Bool, default false. Also a Settings.bundle toggle — the only way back
    /// off once the sheet or a support tap sets it.
    static let supportOptedOutKey = "support_opted_out"
    static let supportLastPromptAtKey = "support_last_prompt_at"              // Double epoch, default 0 (= never)
    static let supportLastSeenVersionKey = "support_last_seen_version"        // String, default "" (= not yet seeded)

    /// The two support destinations, previously inline literals in `SettingsView`.
    /// Force-unwrapped: both are compile-time literals that cannot fail to parse.
    static let sponsorsURL = URL(string: "https://github.com/sponsors/marko-p")!
    static let kofiURL = URL(string: "https://ko-fi.com/spoolkid")!

    // MARK: - What's New
    //
    // In-app rather than Settings.bundle (C1): the moment a user wants these
    // notes turned off is the moment the sheet is in front of them, which is
    // the "contextual to a screen" case the placement rule names. The Settings
    // screen mirrors the same toggle so the choice is reversible.

    /// String, default "" (= no version has ever been shown, so show nothing
    /// and seed it). Same sentinel convention as `supportLastSeenVersionKey`.
    static let changelogLastShownVersionKey = "changelog_last_shown_version"

    /// Bool, default true. The sheet's own footer toggle and the Settings screen
    /// write the same key.
    static let changelogAutoShowKey = "changelog_auto_show"

    /// The public repo's mirror of the bundled `Changelog.json`. `raw.` rather
    /// than `api.github.com`: raw URLs are not rate-limited per IP the way the
    /// API is. Force-unwrapped — a compile-time literal that cannot fail.
    static let changelogURL = URL(
        string: "https://raw.githubusercontent.com/marko-p/SpoolKid/main/changelog.json"
    )!

    // MARK: - Messages

    /// The public repo's root on the raw host; message image paths resolve
    /// against it.
    static let publicRawBaseURL = URL(
        string: "https://raw.githubusercontent.com/marko-p/SpoolKid/main/"
    )!
    static let messagesURL = URL(
        string: "https://raw.githubusercontent.com/marko-p/SpoolKid/main/messages/messages.json"
    )!
    static let messagesSeenIDsKey = "messages_seen_ids"      // [String], default []
    static let messagesActedIDsKey = "messages_acted_ids"    // [String], default []
    /// Passed by the UI tests, like `disableVocabularyRefreshArgument`.
    static let disableMessagesArgument = "-disableMessages"

    /// Short version and build, as a dump records the app that made it.
    static var versionString: String {
        let short = Bundle.main.appVersion ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    static let fieldVisibilityDefaults: [String: Any] = [
        visibilityVendorNameKey: true,
        visibilityVendorCommentKey: false,
        visibilityVendorEmptySpoolWeightKey: false,
        visibilityVendorExternalIdKey: false,
        visibilityFilamentPriceKey: false,
        visibilityFilamentWeightKey: false,
        visibilityFilamentSpoolWeightKey: false,
        visibilityFilamentArticleNumberKey: false,
        visibilityFilamentCommentKey: false,
        visibilityFilamentExternalIdKey: false,
        visibilitySpoolUsedWeightKey: false,
        visibilitySpoolCommentKey: false,
        visibilitySpoolArchivedKey: false,
        visibilitySpoolFirstUsedKey: false,
        visibilitySpoolLastUsedKey: false,
        visibilitySpoolStatusKey: true,
        visibilitySpoolExternalIdKey: false,
        visibilitySpoolPurchaseDateKey: false,
        visibilityNFCOpenSpoolNameKey: true,
        visibilityNFCOpenSpoolSubtypeKey: true,
        visibilityNFCOpenSpoolSpoolIDKey: true,
        visibilityNFCOpenTag3DSubtypeKey: true,
        visibilityNFCOpenTag3DNameKey: true,
        visibilityNFCOpenTag3DDiameterKey: true,
        visibilityNFCOpenTag3DNominalWeightKey: true,
        visibilityNFCOpenTag3DEmptyWeightKey: true,
        visibilityNFCOpenTag3DDryingTempKey: true,
        visibilityNFCOpenTag3DDryingTimeKey: true,
        visibilityNFCOpenTag3DManufacturedKey: false,
        visibilityNFCAnycubicDiameterKey: true,
        visibilityNFCAnycubicNominalWeightKey: true,
        visibilityNFCOpenPrintTagNameKey: true,
        visibilityNFCOpenPrintTagDensityKey: true,
        visibilityNFCOpenPrintTagPreheatKey: true,
        visibilityNFCOpenPrintTagNominalWeightKey: true,
        visibilityNFCOpenPrintTagEmptyWeightKey: true,
        visibilityNFCOpenPrintTagDryingTempKey: true,
        visibilityNFCOpenPrintTagDryingTimeKey: true,
        visibilityNFCOpenPrintTagGTINKey: true,
        visibilityNFCOpenPrintTagCountryKey: true,
        visibilityNFCOpenPrintTagManufacturedKey: true,
        visibilityNFCOpenPrintTagURLKey: true,
        visibilityNFCOpenPrintTagDiameterKey: true,
        visibilityNFCOpenPrintTagRemainingKey: true,
        visibilityNFCTigerTagNameKey: true,
        visibilityNFCTigerTagSubtypeKey: true,
        visibilityNFCTigerTagDiameterKey: true,
        visibilityNFCTigerTagNominalWeightKey: true
    ]

    static let materialPresets: [String: (extruder: Int, bed: Int)] = [
        "PLA": (210, 50),
        "PLA+": (215, 60),
        "ABS": (250, 100),
        "ABS+": (245, 90),
        "ABS-T": (245, 95),
        "PETG": (235, 80),
        "PCTG": (240, 85),
        "Nylon": (250, 80),
        "Flexible (TPU)": (220, 50),
        "Flexible (TPE 32D)": (230, 50),
        "Flexible (TPE 88A)": (230, 50),
        "Polycarbonate (PC)": (270, 110),
        "PC/ABS": (270, 100),
        "PC/PBT": (270, 110),
        "HIPS": (240, 110),
        "ASA": (250, 100),
        "Polypropylene (PP)": (240, 100),
        "PVA": (200, 60),
        "PVB": (215, 75),
        "Wood": (205, 60),
        "Carbon Fiber": (240, 70),
        "Acetal (POM)": (220, 110),
        "PMMA": (245, 100),
        "Semi flexible (FPE)": (235, 80),
        "PVDF": (250, 100),
        "PEI (Ultem)": (375, 150),
        "PEKK": (370, 130),
        "PEEK": (390, 140),
        "PPSU": (380, 140),
        "BIOFUSION": (218, 65),
        "GREENTEC": (220, 60),
        "FLAX": (210, 60),
        "PEARL": (215, 60)
    ]
    
    /// Preset materials plus the refreshed vocabulary, one entry per name
    /// ignoring case; the preset's spelling wins a clash.
    static var materials: [String] {
        var seen = Set<String>()
        let presets = materialPresets.keys.sorted()
        let names = (presets + OCRVocabularyLoader.shared.materialNames())
            .filter { seen.insert($0.lowercased()).inserted }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    static let subtypes = ["Basic", "Rapid", "HF", "Silk", "Matte", "Glossy", "Translucent", "Transparent", "Glitter", "Glow", "Carbon Fiber", "Wood", "Flexible", "Semi Flexible", "Support", "PVA"]
    
    struct Defaults {
        static let colorHex = "000000"
        static let density = 1.24
        static let diameter = 1.75
        /// Target net weight written to a tag when nothing supplies one (grams).
        static let nominalNetWeight = 1000.0
        static let extruderTemp = 205
        static let bedTemp = 60
        static let material = "PLA"
        static let brand = "Generic"
        static let subtype = ""
        static let minNozzleTemp = 190
        static let maxNozzleTemp = 220
        static let minBedTemp = 50
        static let maxBedTemp = 70
        
        // Offsets applied when deriving min/max temps from a single Spoolman temp value
        static let nozzleTempOffset = 10
        static let bedTempOffset = 5
    }
}
