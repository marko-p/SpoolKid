//
//  OIDCSession.swift
//  SpoolKid
//
//  Purpose: The signed-in state for Spoolman's OpenID Connect sign-in. Hands
//  out a fresh access token (one refresh at a time, however many requests are
//  waiting), signs in through an injected presenter, and signs out. The wire
//  work is OIDCClient's; this type owns when to use it and what the tokens'
//  fate is.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Combine
import Foundation
import os.log

/// Where the token set is kept. The app uses the Keychain; tests pass memory.
nonisolated struct OIDCTokenStoring: Sendable {
    let load: @Sendable () -> OIDCTokenSet?
    /// nil deletes. False when the write failed and the old value stays.
    let save: @Sendable (OIDCTokenSet?) -> Bool

    static let keychain = OIDCTokenStoring(load: OIDCTokenStore.load, save: OIDCTokenStore.save)
}

@MainActor
final class OIDCSession: ObservableObject {
    enum AccessToken: Equatable {
        case token(String)
        /// No usable tokens were ever stored for this configuration.
        case notSignedIn
        /// A sign-in that ended: the provider rejected the refresh.
        case signedOut
        case transient(String)
    }

    private static let logger = Logger(subsystem: "com.markopraprotnik.SpoolKid", category: "OIDCSession")

    /// The signed-in account's label; nil means signed out.
    @Published private(set) var displayName: String?

    private let client: OIDCClient
    private let configuration: () -> OIDCConfiguration?
    private let store: OIDCTokenStoring
    private let now: () -> Date

    private var refreshTask: Task<AccessToken, Never>?
    private var cachedDiscovery: (config: OIDCConfiguration, discovery: OIDCDiscovery)?

    init(
        client: OIDCClient = OIDCClient(),
        configuration: @escaping () -> OIDCConfiguration? = OIDCSession.storedConfiguration,
        store: OIDCTokenStoring = .keychain,
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.configuration = configuration
        self.store = store
        self.now = now
        if let config = configuration(), let tokens = store.load(), tokens.belongs(to: config) {
            displayName = Self.label(for: tokens, config: config)
        }
    }

    /// The issuer, client ID and scopes the user entered; nil until they form
    /// a valid configuration.
    nonisolated static func storedConfiguration() -> OIDCConfiguration? {
        let defaults = UserDefaults.standard
        return OIDCConfiguration(
            issuer: defaults.string(forKey: AppConfig.oidcIssuerKey) ?? "",
            clientId: defaults.string(forKey: AppConfig.oidcClientIdKey) ?? "",
            scopes: defaults.string(forKey: AppConfig.oidcScopesKey) ?? ""
        )
    }

    /// The provider's host for user-facing copy: the configured issuer, else
    /// the stored tokens' issuer.
    var issuerHost: String {
        if let config = configuration() { return config.issuerHost }
        if let issuer = store.load()?.issuer, let host = URL(string: issuer)?.host { return host }
        return "your provider"
    }

    // MARK: - Access token

    /// A token to send now. Refreshes when it is within the refresh margin (or
    /// `forceRefresh`); concurrent callers share one refresh. A refresh the
    /// provider rejects deletes the tokens; one that merely failed keeps them.
    func accessToken(forceRefresh: Bool) async -> AccessToken {
        guard let config = configuration(), let tokens = store.load(), tokens.belongs(to: config) else {
            return .notSignedIn
        }
        if !forceRefresh && !tokens.needsRefresh(now: now()) {
            return .token(tokens.accessToken)
        }
        if let refreshTask { return await refreshTask.value }

        let task = Task { [self] in
            let result = await refresh(tokens, config: config)
            refreshTask = nil
            return result
        }
        refreshTask = task
        return await task.value
    }

    private func refresh(_ tokens: OIDCTokenSet, config: OIDCConfiguration) async -> AccessToken {
        let transient = AccessToken.transient("Couldn't renew your sign-in with \(config.issuerHost). Try again in a moment.")

        let found: OIDCDiscovery
        do {
            found = try await discovery(for: config)
        } catch {
            Self.logger.error("Discovery failed during refresh: \(error.message, privacy: .public)")
            return transient
        }

        switch await client.refresh(tokens, config: config, discovery: found, now: now()) {
        case let .success(refreshed):
            // A sign-out or newer sign-in while the refresh was in flight wins.
            if let newer = supersedingTokens(than: tokens, config: config) { return newer }
            if !store.save(refreshed) {
                Self.logger.error("Refreshed tokens could not be saved to the Keychain")
            }
            displayName = Self.label(for: refreshed, config: config)
            return .token(refreshed.accessToken)
        case .failure(.signedOut):
            if let newer = supersedingTokens(than: tokens, config: config) { return newer }
            Self.logger.error("Refresh rejected by the provider; signing out")
            _ = store.save(nil)
            displayName = nil
            return .signedOut
        case .failure(.transient):
            return transient
        }
    }

    /// Whether `stored` is still the token set that was being refreshed: the
    /// same refresh token, or both without one and the same access token.
    nonisolated static func isStillCurrent(_ stored: OIDCTokenSet?, comparedTo refreshing: OIDCTokenSet) -> Bool {
        guard let stored else { return false }
        if let refreshToken = refreshing.refreshToken { return stored.refreshToken == refreshToken }
        return stored.refreshToken == nil && stored.accessToken == refreshing.accessToken
    }

    /// nil when the tokens being refreshed are still the stored ones. Otherwise
    /// the outcome of the newer state: its access token, or not signed in
    /// (a deliberate sign-out or identity edit mid-refresh, which is no notice).
    private func supersedingTokens(than refreshing: OIDCTokenSet, config: OIDCConfiguration) -> AccessToken? {
        let stored = store.load()
        if Self.isStillCurrent(stored, comparedTo: refreshing) { return nil }
        if let stored, stored.belongs(to: config) { return .token(stored.accessToken) }
        return .notSignedIn
    }

    /// The discovery document, fetched again only when the configuration changed.
    private func discovery(for config: OIDCConfiguration) async throws(OIDCError) -> OIDCDiscovery {
        if let cachedDiscovery, cachedDiscovery.config == config { return cachedDiscovery.discovery }
        let discovery = try await client.discover(config)
        cachedDiscovery = (config, discovery)
        return discovery
    }

    // MARK: - Sign in / out

    /// Runs the authorization-code flow. `present` shows the provider's page
    /// and returns the callback URL it redirected to.
    func signIn(using present: (URL) async throws(OIDCError) -> URL) async -> Result<Void, OIDCError> {
        guard let config = configuration() else { return .failure(.invalidConfiguration) }
        do {
            let discovery = try await discovery(for: config)
            let request = OIDCAuthorizationRequest.make(config: config, discovery: discovery)
            let callback = try await present(request.url)
            let code = try OIDCAuthorizationRequest.code(fromCallback: callback, expectedState: request.state)
            let tokens = try await client.exchange(
                code: code, verifier: request.verifier, nonce: request.nonce,
                config: config, discovery: discovery, now: now()
            )
            guard store.save(tokens) else {
                return .failure(.providerError("Your sign-in could not be saved to the Keychain."))
            }
            displayName = Self.label(for: tokens, config: config)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Deletes the tokens first, so the app is signed out whatever the
    /// provider does, then revokes the refresh token on a best-effort basis.
    func signOut() async {
        let tokens = store.load()
        _ = store.save(nil)
        displayName = nil
        // The provider that issued the token, not the live configuration: an
        // identity edit writes the new issuer before it signs out, and the old
        // refresh token must never reach the new provider.
        guard let tokens, let refreshToken = tokens.refreshToken,
              let issuing = OIDCConfiguration(issuer: tokens.issuer, clientId: tokens.clientId, scopes: ""),
              let discovery = try? await discovery(for: issuing) else { return }
        _ = await client.revoke(refreshToken, discovery: discovery, clientId: tokens.clientId)
    }

    private static func label(for tokens: OIDCTokenSet, config: OIDCConfiguration) -> String {
        tokens.displayName ?? config.issuerHost
    }
}
