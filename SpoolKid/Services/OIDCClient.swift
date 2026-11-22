//
//  OIDCClient.swift
//  SpoolKid
//
//  Purpose: The HTTP side of OpenID Connect sign-in against Spoolman's
//  identity provider: discovery, the authorization-code exchange, refresh,
//  and revocation. The pure rules live in OIDCAuthorization and OIDCTokens;
//  this file only sends the requests and maps their results. The token set is
//  kept in the Keychain by OIDCTokenStore, below.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import os.log

/// Talks to the identity provider. Uses the session it is given; the app
/// passes `.shared`, tests pass a stubbed session.
nonisolated struct OIDCClient: Sendable {
    private static let logger = Logger(subsystem: "com.markopraprotnik.SpoolKid", category: "OIDCClient")

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches the discovery document and validates its issuer.
    func discover(_ config: OIDCConfiguration) async throws(OIDCError) -> OIDCDiscovery {
        var request = URLRequest(url: config.discoveryURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let status: Int
        do {
            (data, status) = try await fetch(request)
        } catch {
            Self.logger.error("Discovery request failed: \(error.localizedDescription, privacy: .public)")
            throw .transient(error.localizedDescription)
        }
        guard (200..<300).contains(status) else {
            throw .providerError("HTTP \(status) from the discovery document")
        }
        return try OIDCDiscovery.validated(data, for: config)
    }

    /// Trades the authorization code (with its PKCE verifier) for tokens, and
    /// checks the ID token against the sign-in nonce.
    func exchange(code: String, verifier: String, nonce: String, config: OIDCConfiguration, discovery: OIDCDiscovery, now: Date) async throws(OIDCError) -> OIDCTokenSet {
        let fields = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", OIDCConfiguration.redirectURI),
            ("client_id", config.clientId),
            ("code_verifier", verifier),
        ]

        let data: Data
        let status: Int
        do {
            (data, status) = try await send(fields, to: discovery.tokenEndpoint)
        } catch {
            Self.logger.error("Token exchange request failed: \(error.localizedDescription, privacy: .public)")
            throw .transient(error.localizedDescription)
        }
        guard (200..<300).contains(status) else {
            Self.logger.error("Token exchange returned HTTP \(status, privacy: .public)")
            throw .providerError(Self.providerDescription(data) ?? "HTTP \(status)")
        }
        return try OIDCTokenResponse.tokenSet(from: data, config: config, previous: nil, expectedNonce: nonce, now: now)
    }

    /// Refreshes the access token. Refresh replies carry no nonce, so none is
    /// checked; the previous ID token and refresh token are kept when omitted.
    func refresh(_ tokens: OIDCTokenSet, config: OIDCConfiguration, discovery: OIDCDiscovery, now: Date) async -> Result<OIDCTokenSet, OIDCTokenFailure> {
        guard let refreshToken = tokens.refreshToken else { return .failure(.signedOut) }

        let fields = [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", config.clientId),
        ]

        let data: Data
        let status: Int
        do {
            (data, status) = try await send(fields, to: discovery.tokenEndpoint)
        } catch {
            return .failure(OIDCTokenFailure.classify(status: nil, error: error))
        }
        guard (200..<300).contains(status) else {
            return .failure(OIDCTokenFailure.classify(status: status, error: nil))
        }
        do {
            let refreshed = try OIDCTokenResponse.tokenSet(from: data, config: config, previous: tokens, expectedNonce: nil, now: now)
            return .success(refreshed)
        } catch {
            return .failure(OIDCTokenFailure.classify(status: 200, error: error))
        }
    }

    /// Revokes the refresh token at the provider. False when the provider
    /// publishes no revocation endpoint, or the request fails.
    func revoke(_ refreshToken: String, discovery: OIDCDiscovery, clientId: String) async -> Bool {
        guard let endpoint = discovery.revocationEndpoint else { return false }

        let fields = [
            ("token", refreshToken),
            ("token_type_hint", "refresh_token"),
            ("client_id", clientId),
        ]
        do {
            let (_, status) = try await send(fields, to: endpoint)
            return (200..<300).contains(status)
        } catch {
            return false
        }
    }

    // MARK: - Requests

    private func fetch(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func send(_ fields: [(String, String)], to url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formBody(fields)
        return try await fetch(request)
    }

    /// `application/x-www-form-urlencoded`, with every byte outside the
    /// unreserved set percent-encoded.
    static func formBody(_ fields: [(String, String)]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let pairs = fields.map { name, value in
            let encodedName = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(encodedName)=\(encodedValue)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }

    /// The OAuth error reply's `error_description`, else its `error` code.
    private static func providerDescription(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let description = (object["error_description"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !description.isEmpty { return description }
        return object["error"] as? String
    }
}

/// Keeps the signed-in token set in the Keychain, as one JSON value.
nonisolated enum OIDCTokenStore {
    /// The stored tokens, or nil when none are stored or the stored value
    /// cannot be decoded.
    static func load() -> OIDCTokenSet? {
        guard let json = KeychainStore.read(account: KeychainStore.spoolmanOIDCTokensAccount),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(OIDCTokenSet.self, from: data)
    }

    /// Replaces the stored tokens; nil deletes them. False when encoding or
    /// the Keychain write fails, and the previous value stays in place.
    @discardableResult
    static func save(_ tokens: OIDCTokenSet?) -> Bool {
        guard let tokens else {
            return KeychainStore.delete(account: KeychainStore.spoolmanOIDCTokensAccount)
        }
        guard let data = try? JSONEncoder().encode(tokens),
              let json = String(data: data, encoding: .utf8) else { return false }
        return KeychainStore.save(json, account: KeychainStore.spoolmanOIDCTokensAccount)
    }
}
