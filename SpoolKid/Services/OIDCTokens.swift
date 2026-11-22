//
//  OIDCTokens.swift
//  SpoolKid
//
//  Purpose: Pure rules for OpenID Connect tokens: the token-endpoint reply,
//  ID-token claim checks, the refresh window, and how a failed token request
//  is classified (signed out versus try again later). No network and no
//  Keychain here; the sign-in service composes these.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// The tokens held for one OpenID Connect sign-in. Stored only in the Keychain.
nonisolated struct OIDCTokenSet: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var idToken: String?
    var displayName: String?
    let issuer: String
    let clientId: String

    /// True once the access token is within 60 seconds of expiry.
    func needsRefresh(now: Date) -> Bool {
        expiresAt.timeIntervalSince(now) < 60
    }

    /// True only for the exact issuer and client ID these tokens were issued for.
    func belongs(to config: OIDCConfiguration) -> Bool {
        issuer == config.issuer && clientId == config.clientId
    }
}

/// The ID-token claims this app reads after validation.
nonisolated struct OIDCIDTokenClaims: Equatable, Sendable {
    let email: String?
    let preferredUsername: String?
    let sub: String?
}

/// ID-token checks from OpenID Connect Core section 3.1.3.7.
nonisolated enum OIDCIDToken {
    /// Clock-skew allowance, in seconds, past the `exp` claim.
    private static let expLeeway: Double = 60

    /// Decodes the payload segment only; the signature is not verified here.
    /// Each failed claim is reported by name.
    static func validate(_ jwt: String, config: OIDCConfiguration, expectedNonce: String?, now: Date) throws(OIDCError) -> OIDCIDTokenClaims {
        let segments = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let data = base64URLDecode(segments[1]),
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any] else {
            throw .invalidTokenResponse
        }

        guard payload["iss"] as? String == config.issuer else { throw .claimRejected("iss") }

        let audience: [String]
        if let single = payload["aud"] as? String {
            audience = [single]
        } else if let many = payload["aud"] as? [String] {
            audience = many
        } else {
            throw .claimRejected("aud")
        }
        guard audience.contains(config.clientId) else { throw .claimRejected("aud") }

        if let azp = payload["azp"] {
            guard azp as? String == config.clientId else { throw .claimRejected("azp") }
        } else if audience.count > 1 {
            throw .claimRejected("azp")
        }

        if let expectedNonce, payload["nonce"] as? String != expectedNonce {
            throw .claimRejected("nonce")
        }

        guard let exp = payload["exp"] as? Double else { throw .claimRejected("exp") }
        guard exp + expLeeway > now.timeIntervalSince1970 else { throw .claimRejected("exp") }

        return OIDCIDTokenClaims(
            email: payload["email"] as? String,
            preferredUsername: payload["preferred_username"] as? String,
            sub: payload["sub"] as? String
        )
    }
}

/// Reads the token-endpoint reply (RFC 6749 section 5.1) into a token set.
nonisolated enum OIDCTokenResponse {
    /// The wire fields this app uses. Every field is optional here so the
    /// rules below report exactly what is missing.
    nonisolated private struct Wire: Decodable {
        let accessToken: String?
        let tokenType: String?
        let expiresIn: Double?
        let refreshToken: String?
        let idToken: String?

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case tokenType = "token_type"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
        }
    }

    /// Requires `access_token` and a `Bearer` token type. A reply without
    /// `expires_in` lasts 300 seconds. A reply without a refresh or ID token
    /// keeps the previous one, since providers omit them on refresh.
    static func tokenSet(from data: Data, config: OIDCConfiguration, previous: OIDCTokenSet?, expectedNonce: String?, now: Date) throws(OIDCError) -> OIDCTokenSet {
        let wire: Wire
        do {
            wire = try JSONDecoder().decode(Wire.self, from: data)
        } catch {
            throw .invalidTokenResponse
        }

        guard let accessToken = wire.accessToken, !accessToken.isEmpty,
              wire.tokenType?.lowercased() == "bearer" else {
            throw .invalidTokenResponse
        }

        var idToken = previous?.idToken
        var displayName = previous?.displayName
        if let rawIDToken = wire.idToken {
            let claims = try OIDCIDToken.validate(rawIDToken, config: config, expectedNonce: expectedNonce, now: now)
            idToken = rawIDToken
            displayName = claims.email ?? claims.preferredUsername ?? claims.sub
        }

        return OIDCTokenSet(
            accessToken: accessToken,
            refreshToken: wire.refreshToken ?? previous?.refreshToken,
            expiresAt: now.addingTimeInterval(wire.expiresIn ?? 300),
            idToken: idToken,
            displayName: displayName,
            issuer: config.issuer,
            clientId: config.clientId
        )
    }
}

/// Whether a failed token request ends the sign-in or can be retried later.
nonisolated enum OIDCTokenFailure: Error, Equatable, Sendable {
    case signedOut
    case transient

    /// A malformed or rejected reply, or any 4xx status other than 408 and 429,
    /// means the sign-in is over. Network errors, a missing status, 408 (timeout),
    /// 429 (rate limit) and 5xx mean try again later.
    static func classify(status: Int?, error: Error?) -> OIDCTokenFailure {
        if let oidc = error as? OIDCError {
            switch oidc {
            case .invalidTokenResponse, .claimRejected:
                return .signedOut
            case .transient:
                return .transient
            default:
                break
            }
        }
        if error is URLError { return .transient }
        guard let status else { return .transient }
        if (400..<500).contains(status), status != 408, status != 429 { return .signedOut }
        return .transient
    }
}

/// Decodes one base64url segment of a JWT, with or without padding.
nonisolated private func base64URLDecode(_ segment: Substring) -> Data? {
    var base64 = String(segment)
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    return Data(base64Encoded: base64)
}
