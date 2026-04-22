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
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI
import TipKit

enum AppTab: Int, Hashable {
    case tags = 0
    case spoolman = 1
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
            password: defaults.string(forKey: AppConfig.authPasswordKey) ?? "",
            token: defaults.string(forKey: AppConfig.authTokenKey) ?? ""
        )
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var nfcManager = NFCManager()
    @StateObject private var spoolManService = SpoolmanService()
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = ""
    @AppStorage(AppConfig.hasCompletedWelcomeKey) private var hasCompletedWelcome: Bool = false
    @AppStorage("spoolman_connection_valid") private var isConnectionValid: Bool = false

    // Incremented each time the welcome guide completes to force
    // SwiftUI to recreate tab views and their TipView instances,
    // picking up the freshly-reset TipKit datastore.
    @State private var tipRefreshToken = 0

    /// Snapshot of connection-related settings at the time the connection was last valid.
    /// Used to detect changes made in iOS Settings while the app was backgrounded.
    @State private var lastValidatedSettings: ConnectionSettingsSnapshot?

    var body: some View {
        TabView {
            Tab("Tags", systemImage: "dot.radiowaves.left.and.right") {
                TagsTabView(nfcManager: nfcManager)
                    .id(tipRefreshToken)
            }

            Tab("Spoolman", systemImage: "server.rack") {
                SpoolmanTabView(
                    spoolManService: spoolManService,
                    spoolmanUrl: spoolmanUrl
                )
                .id(tipRefreshToken)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedWelcome },
            set: { if $0 == false { hasCompletedWelcome = true } }
        ), onDismiss: {
            // Donate the event and refresh tips only after the cover's
            // dismissal animation finishes, so the AboutTip popover
            // doesn't flash behind the departing welcome guide.
            Task { await WelcomeGuideCompleted.event.donate() }
            tipRefreshToken += 1
        }) {
            WelcomeGuideView(
                hasCompletedWelcome: $hasCompletedWelcome,
                spoolManService: spoolManService
            )
        }
        .task {
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
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // When returning from iOS Settings (or any background),
                // invalidate the Spoolman connection if settings changed.
                if isConnectionValid, let snapshot = lastValidatedSettings {
                    let current = ConnectionSettingsSnapshot.current()
                    if current != snapshot {
                        isConnectionValid = false
                        lastValidatedSettings = nil
                    }
                }
            }
        }
        .onAppear {
            // Capture initial snapshot if connection is already valid on launch
            if isConnectionValid {
                lastValidatedSettings = ConnectionSettingsSnapshot.current()
            }
        }
    }
}

#Preview {
    ContentView()
}
