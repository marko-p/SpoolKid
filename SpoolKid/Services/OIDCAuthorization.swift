//
//  OIDCAuthorization.swift
//  SpoolKid
//
//  Purpose: Pure rules for OpenID Connect sign-in against Spoolman's
//  identity provider: PKCE (RFC 7636), issuer configuration, discovery
//  validation, the authorization request URL and the callback parser. No
//  network and no Keychain here; the sign-in service composes these.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import CryptoKit
import Foundation
import Security

/// The user's identity-provider settings. Built only through `init?`, which
/// rejects anything that cannot start a sign-in.
nonisolated struct OIDCConfiguration: Equatable, Sendable {
    static let defaultScopes = "openid profile email offline_access"
    static let redirectURI = "spoolkid://oauth/callback"
    static let callbackScheme = "spoolkid"

    let issuer: String
    let clientId: String
    let scopes: String

    /// nil when the issuer is not an absolute http(s) URL with a host, or the
    /// client ID is blank. Blank scopes fall back to `defaultScopes`.
    init?(issuer: String, clientId: String, scopes: String) {
        let trimmedIssuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedClientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedScopes = scopes.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: trimmedIssuer),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty else { return nil }
        guard !trimmedClientId.isEmpty else { return nil }

        self.issuer = trimmedIssuer
        self.clientId = trimmedClientId
        self.scopes = trimmedScopes.isEmpty ? Self.defaultScopes : trimmedScopes
    }

    /// The issuer with one trailing slash dropped, plus the well-known path.
    var discoveryURL: URL {
        var base = issuer
        if base.hasSuffix("/") { base.removeLast() }
        // Safe: `init?` already proved the issuer is a parseable absolute URL,
        // and removing a trailing slash keeps it parseable.
        return URL(string: base + "/.well-known/openid-configuration")!
    }

    var issuerHost: String {
        URL(string: issuer)?.host ?? issuer
    }
}

/// The subset of an OpenID Provider metadata document this app uses.
nonisolated struct OIDCDiscovery: Decodable, Equatable, Sendable {
    let issuer: String
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let revocationEndpoint: URL?

    private enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case revocationEndpoint = "revocation_endpoint"
    }

    /// Decodes the discovery document and requires its `issuer` to equal the
    /// configured issuer byte-for-byte (OpenID Connect Discovery section 4.3).
    static func validated(_ data: Data, for config: OIDCConfiguration) throws(OIDCError) -> OIDCDiscovery {
        let discovery: OIDCDiscovery
        do {
            discovery = try JSONDecoder().decode(OIDCDiscovery.self, from: data)
        } catch {
            throw .providerError("the discovery document could not be read")
        }
        guard discovery.issuer == config.issuer else {
            throw .issuerMismatch(expected: config.issuer, found: discovery.issuer)
        }
        return discovery
    }
}

/// PKCE with the S256 method (RFC 7636).
nonisolated enum OIDCPKCE {
    /// BASE64URL(SHA256(verifier)), no padding.
    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// A fresh 43-character verifier from 32 random bytes.
    static func makeVerifier() -> String {
        randomBase64URL(byteCount: 32)
    }
}

/// One authorization request: the URL to open, plus the values that must come
/// back unchanged (`state`) or be presented later (`nonce`, `verifier`).
nonisolated struct OIDCAuthorizationRequest: Sendable {
    let url: URL
    let state: String
    let nonce: String
    let verifier: String

    /// Builds the authorization URL. Query items already on the endpoint are
    /// kept; the eight OIDC/PKCE parameters are appended.
    static func make(config: OIDCConfiguration, discovery: OIDCDiscovery) -> OIDCAuthorizationRequest {
        let state = randomBase64URL(byteCount: 32)
        let nonce = randomBase64URL(byteCount: 32)
        let verifier = OIDCPKCE.makeVerifier()

        // Safe: the endpoint is an absolute URL, so components always build.
        var components = URLComponents(url: discovery.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: OIDCConfiguration.redirectURI),
            URLQueryItem(name: "scope", value: config.scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: OIDCPKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return OIDCAuthorizationRequest(url: components.url!, state: state, nonce: nonce, verifier: verifier)
    }

    /// Extracts the authorization code from the redirect. The state is checked
    /// first, so a reply that is not ours never surfaces its error text.
    static func code(fromCallback url: URL, expectedState: String) throws(OIDCError) -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        guard value("state") == expectedState else { throw .stateMismatch }

        if let error = value("error") {
            let description = value("error_description")?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw .providerError(description.isEmpty ? error : description)
        }

        guard let code = value("code"), !code.isEmpty else { throw .missingCode }
        return code
    }
}

/// Every way an OpenID Connect sign-in can fail, with the user-facing copy.
nonisolated enum OIDCError: Error, Equatable, Sendable {
    case invalidConfiguration
    case issuerMismatch(expected: String, found: String)
    case providerError(String)
    case stateMismatch
    case missingCode
    case invalidTokenResponse
    case claimRejected(String)
    case cancelled
    case transient(String)

    var message: String {
        switch self {
        case .invalidConfiguration:
            return "Enter a valid issuer URL and client ID."
        case let .issuerMismatch(expected, found):
            return "The provider says its issuer is \(found), not \(expected). Copy the issuer URL exactly, including any trailing slash."
        case let .providerError(text):
            return "Sign-in failed: \(text)"
        case .stateMismatch:
            return "Sign-in failed: the reply did not match this sign-in. Try again."
        case .missingCode:
            return "Sign-in failed: the provider sent no authorization code."
        case .invalidTokenResponse:
            return "Sign-in failed: the provider's token reply could not be read."
        case let .claimRejected(claim):
            return "Sign-in failed: the provider's ID token has an unexpected \(claim)."
        case .cancelled:
            return ""
        case let .transient(text):
            return text
        }
    }
}

nonisolated private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

nonisolated private func randomBase64URL(byteCount: Int) -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
    // A failing system RNG cannot be recovered from; never fall back to weak randomness.
    precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
    return base64URL(Data(bytes))
}
