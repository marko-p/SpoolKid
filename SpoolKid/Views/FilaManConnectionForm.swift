//
//  FilaManConnectionForm.swift
//  SpoolKid
//
//  Purpose: FilaMan connection form (URL, API key, Test Connection). Mirrors
//  SpoolmanConnectionForm's structure and control idioms; used by
//  SpoolmanSettingsView when the FilaMan backend is selected. The probe
//  (`FilaManService.probeIsFilaMan`) is switched exhaustively (no `default:`)
//  so a message is written for every case and a future case is a compile
//  error, not a silently unhandled state. Each message describes only what
//  the probe actually established — see the case-by-case doc comments below.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct FilaManConnectionForm: View {
    @ObservedObject var filaManService: FilaManService

    @AppStorage(AppConfig.filamanUrlKey) private var filamanUrl: String = ""
    @AppStorage(AppConfig.filamanConnectionValidKey) private var isConnectionValid: Bool = false
    /// FilaMan's own flag, not Spoolman's. `FilaManService` read
    /// `spoolman_trust_all_certs` — writable only from `SpoolmanConnectionForm`,
    /// which renders solely when the backend is Spoolman — so this control had
    /// no writer at all and a self-signed FilaMan was unreachable with no
    /// explanation (I2).
    @AppStorage(AppConfig.filamanTrustAllCertsKey) private var trustAllCerts: Bool = false

    // API key never touches @AppStorage/UserDefaults — Keychain only.
    @State private var apiKey: String = ""
    /// Set while the typed key is not the stored one. Test Connection probes
    /// the typed key, so a pass does not show it was saved; this does.
    @State private var apiKeySaveError: String?

    @State private var isTesting = false
    @State private var connectionMessage: String? = nil
    @State private var connectionSucceeded = false
    @State private var resultScale: CGFloat = 0.8
    @State private var resultOpacity: Double = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ServerAddressField(placeholder: "http://192.168.1.100:8000", text: $filamanUrl)
                .onChange(of: filamanUrl) { _, _ in invalidateConnection() }

            VStack(alignment: .leading, spacing: 6) {
                Text("API Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("API Key", text: $apiKey)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiKey) { _, _ in
                        apiKeySaveError = KeychainStore.save(apiKey, account: KeychainStore.filaManAPIKeyAccount)
                            ? nil
                            : "This API key could not be saved to the Keychain, so SpoolKid will not use it."
                        invalidateConnection()
                    }
                if let apiKeySaveError {
                    Text(apiKeySaveError)
                        .foregroundColor(.statusError)
                }
            }

            if (try? ServerAddress.parse(filamanUrl).get())?.isSecure == true {
                Toggle("Trust All Certificates", isOn: $trustAllCerts)
                    .onChange(of: trustAllCerts) { _, _ in invalidateConnection() }
                Text("Only for a self-signed certificate on a server you control.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !filamanUrl.isEmpty {
                VStack(spacing: 12) {
                    Button {
                        testFilaManConnection()
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
                    .disabled(connectionSucceeded || isTesting || !ServerAddress.isUsable(filamanUrl))

                    if let connectionMessage {
                        HStack(spacing: 8) {
                            Image(systemName: connectionSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(connectionSucceeded ? .statusSuccess : .statusError)
                            Text(connectionMessage)
                                .foregroundColor(connectionSucceeded ? .statusSuccess : .statusError)
                                .font(.subheadline)
                        }
                        .scaleEffect(resultScale)
                        .opacity(resultOpacity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            apiKey = KeychainStore.read(account: KeychainStore.filaManAPIKeyAccount) ?? ""
        }
    }

    private func invalidateConnection() {
        connectionSucceeded = false
        connectionMessage = nil
        resultScale = 0.8
        resultOpacity = 0.0
    }

    /// Runs the single probe and renders its result. No `default:` — a future
    /// `FilaManProbeResult` case must fail to compile here, not fall through
    /// silently. Each message states only what that case established:
    /// `.notFilaMan` never implies a bad address, `.unreachable` never implies
    /// "not FilaMan", `.webPage` never claims either, and `.credentialsRejected`
    /// is never hedged into a URL suggestion — see FilaManService's doc comments
    /// for the reasoning.
    private func testFilaManConnection() {
        isTesting = true
        connectionMessage = nil
        connectionSucceeded = false
        resultScale = 0.8
        resultOpacity = 0.0

        Task {
            let result = await filaManService.probeIsFilaMan(baseUrl: filamanUrl, apiKey: apiKey)
            isTesting = false

            switch result {
            case .confirmed:
                connectionSucceeded = true
                isConnectionValid = true
                connectionMessage = "Connected."
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .credentialsRejected:
                connectionSucceeded = false
                isConnectionValid = false
                connectionMessage = "This is a FilaMan server, but it rejected the API key. "
                    + "Check the key, or issue a new one in FilaMan."
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            case .notFilaMan:
                connectionSucceeded = false
                isConnectionValid = false
                connectionMessage = "Reached the server, but it does not look like FilaMan. "
                    + "If it is Spoolman, choose Spoolman above."
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            case .webPage:
                connectionSucceeded = false
                isConnectionValid = false
                connectionMessage = ServerResponseCheck.webPageMessage(backendName: "FilaMan")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            case .unreachable:
                connectionSucceeded = false
                isConnectionValid = false
                connectionMessage = filaManService.errorMessage
                    ?? "Could not reach that address. Check the URL and that the server is running."
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }

            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                resultScale = 1.0
                resultOpacity = 1.0
            }
        }
    }
}
