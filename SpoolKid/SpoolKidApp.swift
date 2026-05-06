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
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI
import TipKit

@main
struct SpoolKidApp: App {
    init() {
        // Register default values for Settings.bundle preferences so they
        // are available before the user ever opens the iOS Settings app.
        UserDefaults.standard.register(defaults: [
            AppConfig.spoolmanUrlKey: "",
            AppConfig.trustAllCertsKey: false,
            AppConfig.authTypeKey: "none",
            AppConfig.authUsernameKey: "",
            AppConfig.authPasswordKey: "",
            AppConfig.authTokenKey: "",
            AppConfig.nfcTagFormatKey: TagFormat.openSpool.rawValue,
            "write_spool_id": true,
            "snapmaker_u1_compat": false,
            "recent_tags_limit": 20,
            "remember_spool_data": false,
            "remember_filament_data": false,
            "confirm_before_delete": true,
            AppConfig.resetAppDataKey: false,
            // Tag Matching & UID Persistence
            AppConfig.spoolmanPersistCardUIDKey: false
        ])
        
        // Handle the "Reset All Data on Next Launch" flag from Settings.bundle
        if UserDefaults.standard.bool(forKey: AppConfig.resetAppDataKey) {
            Self.resetAllAppData()
        }
        
        try? Tips.configure([
            .displayFrequency(.immediate)
        ])
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(.accentColor)
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
        
        // Reset TipKit datastore
        try? Tips.resetDatastore()
        
        // Ensure the reset toggle is turned back off so it doesn't
        // fire again on the next launch.
        UserDefaults.standard.set(false, forKey: AppConfig.resetAppDataKey)
    }
}
