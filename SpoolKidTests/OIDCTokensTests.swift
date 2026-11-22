//
//  OIDCTokensTests.swift
//  SpoolKidTests
//
//  Pins the pure OpenID Connect token rules: token-response parsing, ID-token
//  claim checks, the refresh window and failure classification. No network,
//  no Keychain.
//

import Foundation
import Testing
@testable import SpoolKid

@Suite
struct OIDCTokensTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeConfig() -> OIDCConfiguration {
        OIDCConfiguration(issuer: "https://auth.example", clientId: "spoolkid", scopes: "")!
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// A JWT with a placeholder signature; only the payload is read by the app.
    private func jwt(_ claims: [String: Any]) -> String {
        let payload = try! JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys])
        let header = base64URL(Data(#"{"alg":"none"}"#.utf8))
        return "\(header).\(base64URL(payload)).c2ln"
    }

    /// Claims of a well-formed ID token for `makeConfig()` at `now`; `overrides` replace keys.
    private func idClaims(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var claims: [String: Any] = [
            "iss": "https://auth.example",
            "aud": "spoolkid",
            "exp": Int(now.timeIntervalSince1970) + 300,
            "nonce": "N1",
            "email": "marko@example.test",
            "preferred_username": "marko",
            "sub": "user-1",
        ]
        claims.merge(overrides) { _, new in new }
        return claims
    }

    private func body(_ fields: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: fields)
    }

    private func claimError(_ token: String) -> OIDCError? {
        do {
            _ = try OIDCIDToken.validate(token, config: makeConfig(), expectedNonce: "N1", now: now)
            return nil
        } catch {
            return error
        }
    }

    private func responseError(_ data: Data, previous: OIDCTokenSet? = nil) -> OIDCError? {
        do {
            _ = try OIDCTokenResponse.tokenSet(from: data, config: makeConfig(), previous: previous, expectedNonce: "N1", now: now)
            return nil
        } catch {
            return error
        }
    }

    private func previousSet(refresh: String? = "R1", idToken: String? = nil, displayName: String? = nil) -> OIDCTokenSet {
        OIDCTokenSet(
            accessToken: "old",
            refreshToken: refresh,
            expiresAt: now,
            idToken: idToken,
            displayName: displayName,
            issuer: "https://auth.example",
            clientId: "spoolkid"
        )
    }

    // MARK: - Token response

    @Test func parsesFullResponse() throws {
        let data = body([
            "access_token": "A",
            "token_type": "Bearer",
            "expires_in": 120,
            "refresh_token": "R",
            "id_token": jwt(idClaims()),
        ])
        let set = try OIDCTokenResponse.tokenSet(from: data, config: makeConfig(), previous: nil, expectedNonce: "N1", now: now)
        #expect(set.accessToken == "A")
        #expect(set.expiresAt == now.addingTimeInterval(120))
        #expect(set.refreshToken == "R")
        #expect(set.displayName == "marko@example.test")
        #expect(set.issuer == "https://auth.example")
        #expect(set.clientId == "spoolkid")
    }

    @Test func defaultsExpiresInToFiveMinutes() throws {
        let set = try OIDCTokenResponse.tokenSet(
            from: body(["access_token": "A", "token_type": "bearer"]),
            config: makeConfig(), previous: nil, expectedNonce: nil, now: now
        )
        #expect(set.expiresAt == now.addingTimeInterval(300))
    }

    @Test func keepsPreviousRefreshTokenAndIDTokenWhenOmitted() throws {
        let set = try OIDCTokenResponse.tokenSet(
            from: body(["access_token": "A2", "token_type": "Bearer", "expires_in": 120]),
            config: makeConfig(),
            previous: previousSet(refresh: "R1", idToken: "old-id", displayName: "old name"),
            expectedNonce: nil,
            now: now
        )
        #expect(set.refreshToken == "R1")
        #expect(set.idToken == "old-id")
        #expect(set.displayName == "old name")
    }

    @Test func rejectsNonBearerAndMissingAccessToken() {
        #expect(responseError(body(["access_token": "A", "token_type": "mac"])) == OIDCError.invalidTokenResponse)
        #expect(responseError(body(["token_type": "Bearer"])) == OIDCError.invalidTokenResponse)
        #expect(responseError(Data("not json".utf8)) == OIDCError.invalidTokenResponse)
    }

    // MARK: - ID-token claims

    @Test func idTokenClaimsAreChecked() {
        #expect(claimError(jwt(idClaims(["iss": "https://evil.example"]))) == OIDCError.claimRejected("iss"))
        #expect(claimError(jwt(idClaims(["aud": ["other"]]))) == OIDCError.claimRejected("aud"))
        #expect(claimError(jwt(idClaims(["aud": ["spoolkid", "x"]]))) == OIDCError.claimRejected("azp"))
        #expect(claimError(jwt(idClaims(["aud": ["spoolkid", "x"], "azp": "spoolkid"]))) == nil)
        #expect(claimError(jwt(idClaims(["nonce": "other"]))) == OIDCError.claimRejected("nonce"))
        #expect(claimError(jwt(idClaims(["exp": Int(now.timeIntervalSince1970) - 61]))) == OIDCError.claimRejected("exp"))
        #expect(claimError(jwt(idClaims(["exp": Int(now.timeIntervalSince1970) - 30]))) == nil)

        var noExp = idClaims()
        noExp["exp"] = nil
        #expect(claimError(jwt(noExp)) == OIDCError.claimRejected("exp"))

        #expect(claimError("not-a-jwt") == OIDCError.invalidTokenResponse)
    }

    @Test func displayNameFallsBackToPreferredUsernameThenSub() throws {
        var noEmail = idClaims()
        noEmail["email"] = nil
        let byUsername = try OIDCTokenResponse.tokenSet(
            from: body(["access_token": "A", "token_type": "Bearer", "id_token": jwt(noEmail)]),
            config: makeConfig(), previous: nil, expectedNonce: "N1", now: now
        )
        #expect(byUsername.displayName == "marko")

        var bare = noEmail
        bare["preferred_username"] = nil
        let bySub = try OIDCTokenResponse.tokenSet(
            from: body(["access_token": "A", "token_type": "Bearer", "id_token": jwt(bare)]),
            config: makeConfig(), previous: nil, expectedNonce: "N1", now: now
        )
        #expect(bySub.displayName == "user-1")
    }

    // MARK: - Refresh window and ownership

    @Test func needsRefreshInsideSixtySeconds() {
        func set(expiresIn seconds: TimeInterval) -> OIDCTokenSet {
            OIDCTokenSet(accessToken: "A", refreshToken: nil, expiresAt: now.addingTimeInterval(seconds),
                         idToken: nil, displayName: nil, issuer: "https://auth.example", clientId: "spoolkid")
        }
        #expect(set(expiresIn: 61).needsRefresh(now: now) == false)
        #expect(set(expiresIn: 59).needsRefresh(now: now) == true)
    }

    @Test func belongsOnlyToIssuerAndClient() {
        let tokens = previousSet()
        #expect(tokens.belongs(to: makeConfig()))
        #expect(tokens.belongs(to: OIDCConfiguration(issuer: "https://auth.example", clientId: "other", scopes: "")!) == false)
        #expect(tokens.belongs(to: OIDCConfiguration(issuer: "https://elsewhere.example", clientId: "spoolkid", scopes: "")!) == false)
    }

    // MARK: - Failure classification

    @Test func classifiesFailures() {
        #expect(OIDCTokenFailure.classify(status: nil, error: URLError(.notConnectedToInternet)) == .transient)
        #expect(OIDCTokenFailure.classify(status: 503, error: nil) == .transient)
        #expect(OIDCTokenFailure.classify(status: 400, error: nil) == .signedOut)
        #expect(OIDCTokenFailure.classify(status: 401, error: nil) == .signedOut)
        #expect(OIDCTokenFailure.classify(status: 408, error: nil) == .transient)
        #expect(OIDCTokenFailure.classify(status: 429, error: nil) == .transient)
        #expect(OIDCTokenFailure.classify(status: 200, error: OIDCError.claimRejected("iss")) == .signedOut)
        #expect(OIDCTokenFailure.classify(status: 200, error: OIDCError.invalidTokenResponse) == .signedOut)
        #expect(OIDCTokenFailure.classify(status: nil, error: OIDCError.transient("offline")) == .transient)
    }
}
