//
//  SettingsView.swift
//  SpoolKid
//
//  Purpose: Settings — the active backend's row (the same one that tops the
//  Library tab), app-wide preferences (tag writing, deleting, the Bluetooth
//  scale, release notes, the welcome guide), then an About section with the app's
//  identity, storage notes, links and support.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI
import TipKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SpoolDataStore
    @EnvironmentObject private var changelog: ChangelogService
    @EnvironmentObject private var scale: BLEScaleService
    @AppStorage(AppConfig.changelogAutoShowKey) private var changelogAutoShow: Bool = true
    @AppStorage(AppConfig.hasCompletedWelcomeKey) private var hasCompletedWelcome: Bool = true
    @AppStorage(AppConfig.nfcTagFormatKey) private var nfcTagFormat: String = TagFormat.openSpool.rawValue
    @AppStorage(AppConfig.recentTagsKeepFormatKey) private var recentTagsKeepFormat: Bool = true
    @AppStorage(AppConfig.writeOpacityToTagsKey) private var writeOpacityToTags: Bool = true
    @AppStorage(AppConfig.printerAddressKey) private var printerAddress = ""
    @AppStorage(AppConfig.printerNameKey) private var printerName = PrinterProfile.snapmakerU1.name
    @AppStorage(AppConfig.confirmBeforeDeleteKey) private var confirmBeforeDelete: Bool = true
    @AppStorage(AppConfig.selectTextOnFocusKey) private var selectTextOnFocus: Bool = true
    @AppStorage(AppConfig.colorMapIslandBaseDiameterKey) private var colorMapIslandBaseDiameter: Double = 12

    private var appVersion: String {
        Bundle.main.appVersion ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        Form {
            // Shown whatever the connection state, unlike the Library tab's
            // copy: a backend that cannot connect is when this row is needed.
            Section {
                BackendConnectionRow()
            } header: {
                Text("Library")
            }

            // The printer is set up here or in the welcome guide; the Printer
            // tab appears once it is.
            Section {
                NavigationLink {
                    PrinterSettingsView()
                } label: {
                    HStack {
                        Label("Snapmaker U1", systemImage: "printer")
                        Spacer()
                        Text(PrinterService.isConfigured(address: printerAddress) ? printerName : "Not set up")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Printer")
            } footer: {
                Text("Connect your Snapmaker U1 to see what each toolhead holds in the Printer tab.")
            }

            // Tag Writing
            Section {
                Picker("Write Format", selection: $nfcTagFormat) {
                    ForEach(TagFormat.allCases) { format in
                        Text(format.displayName).tag(format.rawValue)
                    }
                }
                Toggle("Open Recent Tags in Their Format", isOn: $recentTagsKeepFormat)
                Toggle("Write Opacity to Tags", isOn: $writeOpacityToTags)
            } header: {
                Text("Tag Writing")
            } footer: {
                Text("Choose the NFC tag format for writing. Reading auto-detects the format. Open Recent Tags in Their Format opens a Recent Tag in the format it was written in instead of this one. Write Opacity to Tags works out a translucent filament's opacity from its TD, on formats that carry it.")
            }

            // Management
            Section {
                Toggle("Confirm Before Deleting", isOn: $confirmBeforeDelete)
                Toggle("Select Field Text on Tap", isOn: $selectTextOnFocus)
                Stepper(value: $colorMapIslandBaseDiameter, in: ColorFilterService.islandBaseDiameterBounds, step: 1) {
                    HStack {
                        Text("Color Map Dot Size")
                        Spacer()
                        Text("\(Int(colorMapIslandBaseDiameter)) pt")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Management")
            } footer: {
                Text("Select Field Text on Tap selects a form field's value when you tap it, so typing replaces it. Dot size is for inventory colors on the color filter map (Manage Spools).")
            }

            // Weighing
            Section {
                NavigationLink {
                    ScaleSetupView()
                } label: {
                    HStack {
                        Label("Bluetooth Scale", systemImage: "scalemass")
                        Spacer()
                        Text(scale.paired?.name ?? "Not set up")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Weighing")
            } footer: {
                Text("Set your scale up once. Weigh Spools and every spool's Measured Weight then take the number straight off the pan.")
            }

            Section {
                Button(action: openAppSettings) {
                    HStack {
                        Label("iOS Settings App", systemImage: "iphone")
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .foregroundColor(.secondary)
                    }
                }
            } footer: {
                Text("Reset All Data, Share OCR Scans to Improve Recognition, and Recent Tags to Remember are configured in the iOS Settings app.")
            }

            Section {
                NavigationLink {
                    WhatsNewView(entries: changelog.entries, presentation: .history)
                } label: {
                    Label("What's New", systemImage: "sparkles")
                }
                Toggle("Show After Each Update", isOn: $changelogAutoShow)
            } header: {
                Text("Release Notes")
            } footer: {
                Text("Release notes appear once after each update. This row stays here either way.")
            }

            Section {
                Button(action: restartWelcomeGuide) {
                    Label("Restart Welcome Guide", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("App Guide")
            } footer: {
                Text("Show the welcome guide again and reset all contextual tips.")
            }

            // App identity
            Section {
                VStack(spacing: 12) {
                    Image("SpoolKidLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Text("SpoolKid")
                        .font(.title2.bold())

                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            } header: {
                Text("About")
            }

            if store.capabilities.isOnDeviceStorage {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(LocalModeCopy.storageExplanation)
                        Text(LocalModeCopy.capSummary)
                        Text(LocalModeCopy.notAReplacement)
                        Text(LocalModeCopy.dataLossDisclaimer)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                } header: {
                    Text("How your Library is stored")
                }
            }

            // Links
            Section {
                Link(destination: URL(string: "https://www.spoolkid.com")!) {
                    HStack {
                        Label("Website", systemImage: "globe")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                    }
                }
                Link(destination: URL(string: "https://github.com/marko-p/SpoolKid/issues")!) {
                    HStack {
                        Label("Report an Issue or Idea", systemImage: "exclamationmark.bubble")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Support
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                        Text("Free to Use")
                            .font(.subheadline.weight(.medium))
                    }
                    Text("SpoolKid is free. If it saves you time, support for its development is welcome.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

                SupportLinksView()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Support Development")
            }

        }
        .navigationTitle("Settings")
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - Actions

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func restartWelcomeGuide() {
        dismiss()
        try? Tips.resetDatastore()
        hasCompletedWelcome = false
    }
}
