//
//  SpoolmanConnectionForm.swift
//  SpoolKid
//
//  Purpose: Shared Spoolman connection form (URL, auth type — None, Basic,
//  Bearer or OpenID Connect — credentials or sign-in, Trust All, Test Connection). Used by the Welcome wizard and SpoolmanSettingsView.
//  Writes the same AppStorage / UserDefaults keys the old Settings.bundle did.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct SpoolmanConnectionForm: View {
    @ObservedObject var spoolManService: SpoolmanService

    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = AppConfig.defaultSpoolmanUrl
    @AppStorage(AppConfig.authTypeKey) private var authType: String = "none"
    @AppStorage(AppConfig.trustAllCertsKey) private var trustAllCerts: Bool = false
    @AppStorage(AppConfig.spoolmanConnectionValidKey) private var isConnectionValid: Bool = false
    @AppStorage(AppConfig.oidcIssuerKey) private var oidcIssuer: String = ""
    @AppStorage(AppConfig.oidcClientIdKey) private var oidcClientId: String = ""
    @AppStorage(AppConfig.oidcScopesKey) private var oidcScopes: String = ""

    // Credentials use UserDefaults directly (SecureField / non-@AppStorage pattern
    // matches the prior WelcomeGuideView implementation).
    @State private var authUsername: String = ""
    @State private var authPassword: String = ""
    @State private var authToken: String = ""
    /// Set while the typed password or token is not the stored one.
    @State private var credentialSaveError: String?

    // Editable mirror of the persisted values so the user can type before testing.
    @State private var editUrl: String = ""
    @State private var editAuthType: String = "none"
    @State private var editTrustAllCerts: Bool = false

    /// Set by the signed-out alert's Sign In; the sign-in section consumes it.
    @State private var signInRequested = false
    /// Drives the signed-out alert. Not bound to the notice directly: an alert
    /// whose condition is already true while the page is still being pushed is dropped.
    @State private var showSignedOutAlert = false
    @State private var signedOutAlertTask: Task<Void, Never>?
    /// Set once the alert's content appeared, which ends the retry loop.
    @State private var signedOutAlertShown = false
    @State private var isTesting = false
    @State private var testResult: String? = nil
    @State private var connectionSucceeded = false
    @State private var resultScale: CGFloat = 0.8
    @State private var resultOpacity: Double = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ServerAddressField(placeholder: "http://192.168.1.100:7912", text: $editUrl)
                .onChange(of: editUrl) { _, _ in invalidateConnection() }

            VStack(alignment: .leading, spacing: 6) {
                Text("Authentication")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Auth Type", selection: $editAuthType) {
                    Text("None").tag("none")
                    Text("Basic").tag("basic")
                    Text("Bearer").tag("bearer")
                    Text("OpenID").tag("oidc")
                }
                .pickerStyle(.segmented)
                .onChange(of: editAuthType) { _, _ in invalidateConnection() }
            }

            if editAuthType == "basic" {
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

            if editAuthType == "bearer" {
                SecureField("API Key / Token", text: $authToken)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: authToken) { _, _ in invalidateConnection() }
            }

            if editAuthType == "oidc" {
                OIDCSignInSection(
                    oidc: spoolManService.oidc,
                    issuer: $oidcIssuer,
                    clientId: $oidcClientId,
                    scopes: $oidcScopes,
                    startSignIn: $signInRequested,
                    onEdited: invalidateConnection,
                    onSignedIn: runTestConnection
                )
            }

            if let credentialSaveError {
                Text(credentialSaveError)
                    .foregroundColor(.statusError)
            }

            Toggle("Trust All Certificates", isOn: $editTrustAllCerts)
                .onChange(of: editTrustAllCerts) { _, _ in invalidateConnection() }

            Text("Enable only if your Spoolman uses a self-signed certificate on a trusted network.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !editUrl.isEmpty {
                VStack(spacing: 12) {
                    Button {
                        runTestConnection()
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
                    .disabled(connectionSucceeded || isTesting || !ServerAddress.isUsable(editUrl))

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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            editUrl = spoolmanUrl
            editAuthType = authType
            editTrustAllCerts = trustAllCerts
            loadCredentials()
            presentSignedOutAlertWhenSettled()
        }
        .onChange(of: spoolManService.signedOutNotice?.id) { _, id in
            if id != nil {
                presentSignedOutAlertWhenSettled()
            } else {
                showSignedOutAlert = false
            }
        }
        .onDisappear { signedOutAlertTask?.cancel() }
        .onChange(of: editUrl) { _, _ in commitFields() }
        .onChange(of: editAuthType) { _, _ in commitFields() }
        .onChange(of: editTrustAllCerts) { _, _ in commitFields() }
        .onChange(of: authUsername) { _, _ in saveCredentials() }
        .onChange(of: authPassword) { _, _ in saveCredentials() }
        .onChange(of: authToken) { _, _ in saveCredentials() }
        .alert(
            "Signed Out of Spoolman",
            isPresented: Binding(
                get: { showSignedOutAlert },
                // Only the buttons clear the notice: SwiftUI also calls this with
                // false when another presentation (a TipKit popover) blocks the alert.
                set: { showSignedOutAlert = $0 }
            ),
            presenting: spoolManService.signedOutNotice
        ) { _ in
            Button("Sign In") {
                spoolManService.signedOutNotice = nil
                editAuthType = "oidc"
                signInRequested = true
            }
            Button("Not Now", role: .cancel) {
                spoolManService.signedOutNotice = nil
            }
        } message: { notice in
            Text("Your sign-in with \(notice.issuerHost) expired and couldn't be renewed. Sign in again to keep using Spoolman. Anything you hadn't saved was not sent.")
                .onAppear { signedOutAlertShown = true }
        }
    }

    /// Waits out the push animation, then shows the alert while the notice
    /// stands. A failed presentation (another presentation was in the way)
    /// leaves the flag true, so each attempt re-arms it: false, one pause, true.
    /// Stops once the alert's content appeared or the notice is gone. One loop
    /// at a time.
    private func presentSignedOutAlertWhenSettled() {
        signedOutAlertTask?.cancel()
        guard spoolManService.signedOutNotice != nil else { return }
        signedOutAlertShown = false
        signedOutAlertTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            for attempt in 0..<3 {
                if Task.isCancelled || spoolManService.signedOutNotice == nil || signedOutAlertShown { return }
                if showSignedOutAlert {
                    showSignedOutAlert = false
                    try? await Task.sleep(for: .milliseconds(50))
                    if Task.isCancelled || spoolManService.signedOutNotice == nil { return }
                }
                showSignedOutAlert = true
                if attempt < 2 { try? await Task.sleep(for: .milliseconds(900)) }
            }
        }
    }

    private func invalidateConnection() {
        connectionSucceeded = false
        testResult = nil
        resultScale = 0.8
        resultOpacity = 0.0
    }

    private func loadCredentials() {
        authUsername = UserDefaults.standard.string(forKey: AppConfig.authUsernameKey) ?? ""
        // Keychain, not UserDefaults (016 / F3.2). `migratingRead` so a form
        // opened before any request has been made still finds a pre-upgrade
        // credential and moves it across.
        authPassword = KeychainStore.migratingRead(
            account: KeychainStore.spoolmanPasswordAccount,
            legacyDefaultsKey: AppConfig.authPasswordKey
        ) ?? ""
        authToken = KeychainStore.migratingRead(
            account: KeychainStore.spoolmanTokenAccount,
            legacyDefaultsKey: AppConfig.authTokenKey
        ) ?? ""
    }

    private func saveCredentials() {
        UserDefaults.standard.set(authUsername, forKey: AppConfig.authUsernameKey)
        let passwordSaved = KeychainStore.save(authPassword, account: KeychainStore.spoolmanPasswordAccount)
        let tokenSaved = KeychainStore.save(authToken, account: KeychainStore.spoolmanTokenAccount)
        credentialSaveError = passwordSaved && tokenSaved
            ? nil
            : "Your password or token could not be saved to the Keychain."
    }

    private func commitFields() {
        spoolmanUrl = editUrl
        authType = editAuthType
        trustAllCerts = editTrustAllCerts
    }

    private func runTestConnection() {
        commitFields()
        saveCredentials()

        isTesting = true
        testResult = nil
        connectionSucceeded = false
        resultScale = 0.8
        resultOpacity = 0.0

        Task {
            let success = await spoolManService.testConnection(baseUrl: editUrl)
            isTesting = false
            connectionSucceeded = success

            if success {
                testResult = "Connection Successful"
                isConnectionValid = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                testResult = spoolManService.errorMessage ?? "Connection Failed"
                isConnectionValid = false
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }

            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                resultScale = 1.0
                resultOpacity = 1.0
            }
        }
    }
}

/// The OpenID Connect part of the form. Observes the session directly so
/// "Signed in as" follows it (the form only observes SpoolmanService).
private struct OIDCSignInSection: View {
    @ObservedObject var oidc: OIDCSession
    @Binding var issuer: String
    @Binding var clientId: String
    @Binding var scopes: String
    @Binding var startSignIn: Bool
    let onEdited: () -> Void
    let onSignedIn: () -> Void

    @State private var isSigningIn = false
    @State private var signInError: String?

    private var canSignIn: Bool {
        !isSigningIn && OIDCConfiguration(issuer: issuer, clientId: clientId, scopes: scopes) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Issuer URL", text: $issuer, prompt: Text(verbatim: "https://auth.example.com/application/o/spoolman/"))
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .textFieldStyle(.roundedBorder)
                .onChange(of: issuer) { _, _ in edited(changesIdentity: true) }
            TextField("Client ID", text: $clientId)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .textFieldStyle(.roundedBorder)
                .onChange(of: clientId) { _, _ in edited(changesIdentity: true) }
            TextField("Scopes", text: $scopes, prompt: Text(verbatim: OIDCConfiguration.defaultScopes))
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .textFieldStyle(.roundedBorder)
                .onChange(of: scopes) { _, _ in edited(changesIdentity: false) }

            Text("Register this redirect URI with your provider: \(OIDCConfiguration.redirectURI)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let name = oidc.displayName {
                Label("Signed in as \(name)", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.statusSuccess)
                    .font(.subheadline)
                    .accessibilityIdentifier("oidcSignedInAs")
                Button(role: .destructive) {
                    Task { await oidc.signOut() }
                } label: {
                    Text("Sign Out")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("oidcSignOut")
            } else {
                Button {
                    signIn()
                } label: {
                    HStack {
                        if isSigningIn { ProgressView().padding(.trailing, 5) }
                        Text("Sign In")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSignIn)
                .accessibilityIdentifier("oidcSignIn")

                if let signInError, !signInError.isEmpty {
                    Text(signInError)
                        .font(.caption)
                        .foregroundColor(.statusError)
                }
            }
        }
        .onAppear(perform: consumeSignInRequest)
        .onChange(of: startSignIn) { _, _ in consumeSignInRequest() }
    }

    private func edited(changesIdentity: Bool) {
        onEdited()
        // Tokens belong to one issuer and client; scopes edits keep them.
        if changesIdentity, oidc.displayName != nil {
            Task { await oidc.signOut() }
        }
    }

    private func consumeSignInRequest() {
        guard startSignIn else { return }
        startSignIn = false
        signIn()
    }

    private func signIn() {
        guard canSignIn else { return }
        isSigningIn = true
        signInError = nil
        Task {
            let result = await oidc.signIn(using: OIDCWebSignIn.present)
            isSigningIn = false
            switch result {
            case .success: onSignedIn()
            case let .failure(error): signInError = error.message
            }
        }
    }
}
