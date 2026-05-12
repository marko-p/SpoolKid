//
//  WelcomeGuideView.swift
//  SpoolKid
//
//  Purpose: Multi-step welcome guide shown on first launch.
//  Steps:
//  1. Welcome + NFC format selection (full-screen cards with printer brand hints)
//  2. Spoolman connection setup (skippable)
//  3. Completion confirmation
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI
import TipKit

struct WelcomeGuideView: View {
    @Binding var hasCompletedWelcome: Bool
    @ObservedObject var spoolManService: SpoolmanService

    @AppStorage(AppConfig.nfcTagFormatKey) private var nfcTagFormat: String = TagFormat.openSpool.rawValue
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = AppConfig.defaultSpoolmanUrl
    @AppStorage("spoolman_connection_valid") private var isConnectionValid: Bool = false
    @AppStorage(AppConfig.authTypeKey) private var authType: String = "none"
    @AppStorage(AppConfig.trustAllCertsKey) private var trustAllCerts: Bool = false

    @State private var currentStep = 0
    @State private var selectedFormat: TagFormat = .openSpool

    // Spoolman connection state
    @State private var welcomeSpoolmanUrl: String = ""
    @State private var welcomeAuthType: String = "none"
    @State private var welcomeTrustAllCerts: Bool = false
    @State private var authUsername: String = ""
    @State private var authPassword: String = ""
    @State private var authToken: String = ""
    @State private var isTesting = false
    @State private var testResult: String? = nil
    @State private var connectionSucceeded = false
    @State private var connectionFailed = false
    @State private var resultScale: CGFloat = 0.8
    @State private var resultOpacity: Double = 0.0

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            stepIndicator
                .padding(.top, 16)
                .padding(.bottom, 8)

            // Step content
            TabView(selection: $currentStep) {
                welcomeStep.tag(0)
                spoolmanStep.tag(1)
                completionStep.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentStep)
        }
        .interactiveDismissDisabled()
        .onAppear {
            // Initialize local state from persisted values
            welcomeSpoolmanUrl = spoolmanUrl
            welcomeAuthType = authType
            welcomeTrustAllCerts = trustAllCerts
            if let format = TagFormat(rawValue: nfcTagFormat) {
                selectedFormat = format
            }
            loadCredentials()
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep ? Color.accentColor : Color(.systemGray4))
                    .frame(width: index == currentStep ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentStep)
            }
        }
    }

    // MARK: - Step 1: Welcome + NFC Format

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image("SpoolKidLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .padding(.bottom, 4)
                        Text("Welcome to SpoolKid")
                            .font(.largeTitle.bold())
                        Text("Your NFC filament tag companion. Choose the tag format that matches your printer.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.top, 16)

                    // Format cards
                    VStack(spacing: 12) {
                        ForEach(TagFormat.allCases) { format in
                            FormatCard(
                                format: format,
                                isSelected: selectedFormat == format
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedFormat = format
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }

            // Continue button
            Button {
                nfcTagFormat = selectedFormat.rawValue
                withAnimation { currentStep = 1 }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Step 2: Spoolman Connection

    private var spoolmanStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)
                            .padding(.bottom, 4)
                        Text("Connect to Spoolman")
                            .font(.largeTitle.bold())
                        Text("Optionally connect to your Spoolman instance to manage your filament library and write tags from your existing spools.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.top, 16)

                    // Connection form
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Server URL")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("http://192.168.1.100:7912", text: $welcomeSpoolmanUrl)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: welcomeSpoolmanUrl) { _, _ in
                                    invalidateConnection()
                                }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Authentication")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Auth Type", selection: $welcomeAuthType) {
                                Text("None").tag("none")
                                Text("Basic Auth").tag("basic")
                                Text("API Key / Bearer").tag("bearer")
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: welcomeAuthType) { _, _ in
                                invalidateConnection()
                            }
                        }

                        if welcomeAuthType == "basic" {
                            VStack(spacing: 10) {
                                TextField("Username", text: $authUsername)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: authUsername) { _, _ in invalidateConnection() }
                                SecureField("Password", text: $authPassword)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: authPassword) { _, _ in invalidateConnection() }
                            }
                        }

                        if welcomeAuthType == "bearer" {
                            SecureField("API Key / Token", text: $authToken)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: authToken) { _, _ in invalidateConnection() }
                        }

                        Toggle("Trust All Certificates", isOn: $welcomeTrustAllCerts)
                            .onChange(of: welcomeTrustAllCerts) { _, _ in invalidateConnection() }

                        Text("Enable only if your Spoolman uses a self-signed certificate on a trusted network.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)

                    // Test connection
                    if !welcomeSpoolmanUrl.isEmpty {
                        VStack(spacing: 12) {
                            Button {
                                testConnection()
                            } label: {
                                HStack {
                                    if isTesting {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .padding(.trailing, 5)
                                    }
                                    Text("Test Connection")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.bordered)
                            .disabled(connectionSucceeded || isTesting || welcomeSpoolmanUrl.isEmpty)

                            if let result = testResult {
                                HStack(spacing: 8) {
                                    Image(systemName: connectionSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(connectionSucceeded ? .statusSuccess : .statusError)
                                    Text(result)
                                        .foregroundColor(connectionSucceeded ? .statusSuccess : .statusError)
                                        .font(.subheadline)
                                }
                                .scaleEffect(resultScale)
                                .opacity(resultOpacity)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            // Bottom buttons
            VStack(spacing: 10) {
                Button {
                    commitSpoolmanSettings()
                    withAnimation { currentStep = 2 }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!connectionSucceeded && !welcomeSpoolmanUrl.isEmpty)

                Button {
                    // Skip without saving Spoolman settings
                    withAnimation { currentStep = 2 }
                } label: {
                    Text("Skip for Now")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Step 3: Completion

    private var completionStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)

                Text("You're All Set!")
                    .font(.largeTitle.bold())

                VStack(spacing: 12) {
                    summaryRow(
                        icon: "dot.radiowaves.left.and.right",
                        label: "Tag Format",
                        value: selectedFormat.displayName
                    )
                    summaryRow(
                        icon: "server.rack",
                        label: "Spoolman",
                        value: connectionSucceeded ? "Connected" : "Not configured"
                    )
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)

                    Text("You can change these anytime in the iOS Settings app. Contextual tips will help you discover features as you explore.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button {
                hasCompletedWelcome = true
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Helpers

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .padding(.vertical, 6)
    }

    private func invalidateConnection() {
        connectionSucceeded = false
        connectionFailed = false
        testResult = nil
        resultScale = 0.8
        resultOpacity = 0.0
    }

    private func loadCredentials() {
        authUsername = UserDefaults.standard.string(forKey: AppConfig.authUsernameKey) ?? ""
        authPassword = UserDefaults.standard.string(forKey: AppConfig.authPasswordKey) ?? ""
        authToken = UserDefaults.standard.string(forKey: AppConfig.authTokenKey) ?? ""
    }

    private func commitSpoolmanSettings() {
        // Persist Spoolman configuration to AppStorage / UserDefaults
        spoolmanUrl = welcomeSpoolmanUrl
        authType = welcomeAuthType
        trustAllCerts = welcomeTrustAllCerts
        isConnectionValid = connectionSucceeded

        // Save credentials to UserDefaults (read by SpoolmanService and visible in Settings.bundle)
        UserDefaults.standard.set(authUsername, forKey: AppConfig.authUsernameKey)
        UserDefaults.standard.set(authPassword, forKey: AppConfig.authPasswordKey)
        UserDefaults.standard.set(authToken, forKey: AppConfig.authTokenKey)
    }

    private func testConnection() {
        // Temporarily apply settings so SpoolmanService can test
        spoolmanUrl = welcomeSpoolmanUrl
        authType = welcomeAuthType
        trustAllCerts = welcomeTrustAllCerts
        UserDefaults.standard.set(authUsername, forKey: AppConfig.authUsernameKey)
        UserDefaults.standard.set(authPassword, forKey: AppConfig.authPasswordKey)
        UserDefaults.standard.set(authToken, forKey: AppConfig.authTokenKey)

        isTesting = true
        testResult = nil
        connectionFailed = false
        connectionSucceeded = false
        resultScale = 0.8
        resultOpacity = 0.0

        Task {
            let success = await spoolManService.testConnection(baseUrl: welcomeSpoolmanUrl)
            isTesting = false
            connectionSucceeded = success
            connectionFailed = !success

            if success {
                testResult = "Connection Successful"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                testResult = spoolManService.errorMessage ?? "Connection Failed"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }

            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                resultScale = 1.0
                resultOpacity = 1.0
            }
        }
    }
}

// MARK: - Format Card

private struct FormatCard: View {
    let format: TagFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Format logo
                formatLogo
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Color.accentColor.opacity(0.12) : Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Text content
                VStack(alignment: .leading, spacing: 3) {
                    Text(format.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(printerHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.systemGray3))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color(.systemGray4), lineWidth: isSelected ? 2 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var formatLogo: some View {
        switch format {
        case .elegoo:
            AsyncImage(url: URL(string: "https://www.elegoo.com/cdn/shop/files/Logo_e6b0d316-e2b8-4362-9112-a9b185ebbf9b.png?v=1691652260")) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                } else {
                    Image(systemName: "tag")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(10)
                        .foregroundStyle(.secondary)
                }
            }
        default:
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(6)
        }
    }

    private var assetName: String {
        switch format {
        case .openSpool:    return "OpenSpoolLogo"
        case .openTag3D:    return "OpenTag3DLogo"
        case .anycubicACE:  return "AnycubicLogo"
        case .elegoo:       return "ElegooLogo"
        }
    }

    private var printerHint: String {
        switch format {
        case .openSpool:
            return "Snapmaker U1 with community firmware and other OpenSpool-compatible printers"
        case .openTag3D:
            return "Community standard for 3D printing NFC tags"
        case .anycubicACE:
            return "Anycubic ACE Pro spool holder"
        case .elegoo:
            return "ELEGOO FDM 3D printers with RFID spool recognition"
        }
    }
}
