//
//  AboutView.swift
//  SpoolKid
//
//  Purpose: About page showing app information with links to preferences
//  and the welcome guide restart action.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI
import TipKit

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppConfig.hasCompletedWelcomeKey) private var hasCompletedWelcome: Bool = true

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        Form {
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
                Link(destination: URL(string: "https://github.com/marko-p/SpoolKid")!) {
                    HStack {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // License & Support
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Open-source · MIT License")
                            .font(.subheadline.weight(.medium))
                    }
                    Text("SpoolKid is free to use, modify, and share. If it saves you time, please consider supporting its development — the Apple Developer membership needed to publish on TestFlight and the App Store costs $100/year.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

                Link(destination: URL(string: "https://github.com/sponsors/marko-p")!) {
                    HStack {
                        Spacer()
                        Label("Sponsor on GitHub", systemImage: "heart.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(Color(red: 0.91, green: 0.29, blue: 0.67))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                Link(destination: URL(string: "https://ko-fi.com/spoolkid")!) {
                    HStack {
                        Spacer()
                        Label("Support on Ko-fi", systemImage: "cup.and.saucer.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(Color(red: 0.25, green: 0.55, blue: 0.96))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Support Development")
            }

            Section {
                Button(action: openAppSettings) {
                    HStack {
                        Label("Preferences", systemImage: "gear")
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .foregroundColor(.secondary)
                    }
                }
            } footer: {
                Text("Spoolman connection, NFC tag format, printer compatibility, and other preferences are configured in the iOS Settings app.")
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
        }
        .navigationTitle("About SpoolKid")
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
