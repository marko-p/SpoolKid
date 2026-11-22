//
//  OIDCAuthorizationTests.swift
//  SpoolKidTests
//
//  Pins the pure OpenID Connect sign-in rules: PKCE (RFC 7636), issuer
//  configuration, discovery validation, the authorization request URL and
//  the callback parser. No network, no Keychain.
//

import Foundation
import Testing
@testable import SpoolKid

@Suite
struct OIDCAuthorizationTests {

    // MARK: - PKCE

    @Test func pkceMatchesRFC7636AppendixB() {
        #expect(OIDCPKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func verifierIsUnreservedAndLongEnough() {
        let verifiers = (0..<100).map { _ in OIDCPKCE.makeVerifier() }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        for verifier in verifiers {
            #expect((43...128).contains(verifier.count))
            #expect(Set(verifier).isSubset(of: allowed))
        }
        #expect(Set(verifiers).count == verifiers.count)
    }

    // MARK: - Configuration

    @Test func configRejectsBadInput() {
        #expect(OIDCConfiguration(issuer: "", clientId: "spoolkid", scopes: "") == nil)
        #expect(OIDCConfiguration(issuer: "auth.example", clientId: "spoolkid", scopes: "") == nil)
        #expect(OIDCConfiguration(issuer: "ftp://x", clientId: "spoolkid", scopes: "") == nil)
        #expect(OIDCConfiguration(issuer: "https://auth.example", clientId: "  ", scopes: "") == nil)
    }

    @Test func blankScopesFallBackToDefaults() {
        let config = OIDCConfiguration(issuer: "https://auth.example", clientId: "spoolkid", scopes: "   ")
        #expect(config?.scopes == OIDCConfiguration.defaultScopes)
        #expect(OIDCConfiguration.defaultScopes == "openid profile email offline_access")
    }

    @Test func discoveryURLHandlesTrailingSlash() throws {
        let withSlash = try #require(OIDCConfiguration(issuer: "https://auth.example/application/o/spoolman/", clientId: "c", scopes: ""))
        #expect(withSlash.discoveryURL.absoluteString == "https://auth.example/application/o/spoolman/.well-known/openid-configuration")

        let dex = try #require(OIDCConfiguration(issuer: "http://localhost:5556/dex", clientId: "c", scopes: ""))
        #expect(dex.discoveryURL.absoluteString == "http://localhost:5556/dex/.well-known/openid-configuration")
    }

    // MARK: - Discovery

    private func discoveryJSON(issuer: String, revocation: Bool) -> Data {
        let revocationPart = revocation ? #","revocation_endpoint":"https://auth.example/revoke""# : ""
        let json = #"{"issuer":"\#(issuer)","authorization_endpoint":"https://auth.example/authorize","token_endpoint":"https://auth.example/token""# + revocationPart + "}"
        return Data(json.utf8)
    }

    @Test func discoveryIssuerMustMatchExactly() throws {
        let config = try #require(OIDCConfiguration(issuer: "https://auth.example/", clientId: "c", scopes: ""))

        do {
            _ = try OIDCDiscovery.validated(discoveryJSON(issuer: "https://auth.example", revocation: true), for: config)
            Issue.record("Expected issuerMismatch")
        } catch {
            #expect(error == .issuerMismatch(expected: "https://auth.example/", found: "https://auth.example"))
        }

        let discovery = try OIDCDiscovery.validated(discoveryJSON(issuer: "https://auth.example/", revocation: true), for: config)
        #expect(discovery.authorizationEndpoint == URL(string: "https://auth.example/authorize"))
        #expect(discovery.tokenEndpoint == URL(string: "https://auth.example/token"))
        #expect(discovery.revocationEndpoint == URL(string: "https://auth.example/revoke"))

        let noRevocation = try OIDCDiscovery.validated(discoveryJSON(issuer: "https://auth.example/", revocation: false), for: config)
        #expect(noRevocation.revocationEndpoint == nil)
    }

    // MARK: - Authorization request

    private func makeRequest() throws -> OIDCAuthorizationRequest {
        let config = try #require(OIDCConfiguration(issuer: "https://auth.example", clientId: "spoolkid-app", scopes: ""))
        let discovery = try OIDCDiscovery.validated(discoveryJSON(issuer: "https://auth.example", revocation: false), for: config)
        return OIDCAuthorizationRequest.make(config: config, discovery: discovery)
    }

    @Test func authorizationURLCarriesPKCEAndState() throws {
        let request = try makeRequest()
        let components = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "auth.example")
        #expect(components.path == "/authorize")

        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items.count == 8)
        #expect(items["response_type"] == "code")
        #expect(items["client_id"] == "spoolkid-app")
        #expect(items["redirect_uri"] == "spoolkid://oauth/callback")
        #expect(items["scope"] == OIDCConfiguration.defaultScopes)
        #expect(items["state"] == request.state)
        #expect(items["nonce"] == request.nonce)
        #expect(items["code_challenge"] == OIDCPKCE.challenge(for: request.verifier))
        #expect(items["code_challenge_method"] == "S256")
    }

    @Test func authorizationURLKeepsExistingEndpointQuery() throws {
        let config = try #require(OIDCConfiguration(issuer: "https://auth.example", clientId: "c", scopes: ""))
        let discovery = OIDCDiscovery(
            issuer: "https://auth.example",
            authorizationEndpoint: try #require(URL(string: "https://auth.example/authorize?tenant=home")),
            tokenEndpoint: try #require(URL(string: "https://auth.example/token")),
            revocationEndpoint: nil
        )
        let request = OIDCAuthorizationRequest.make(config: config, discovery: discovery)
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains { $0.name == "tenant" && $0.value == "home" })
        #expect(items.contains { $0.name == "response_type" && $0.value == "code" })
    }

    // MARK: - Callback

    @Test func callbackParsing() throws {
        let request = try makeRequest()

        let ok = try #require(URL(string: "spoolkid://oauth/callback?code=abc&state=\(request.state)"))
        #expect(try OIDCAuthorizationRequest.code(fromCallback: ok, expectedState: request.state) == "abc")

        let wrongState = try #require(URL(string: "spoolkid://oauth/callback?code=abc&state=other"))
        do {
            _ = try OIDCAuthorizationRequest.code(fromCallback: wrongState, expectedState: request.state)
            Issue.record("Expected stateMismatch")
        } catch {
            #expect(error == .stateMismatch)
        }

        let denied = try #require(URL(string: "spoolkid://oauth/callback?error=access_denied&error_description=User%20denied&state=\(request.state)"))
        do {
            _ = try OIDCAuthorizationRequest.code(fromCallback: denied, expectedState: request.state)
            Issue.record("Expected providerError")
        } catch {
            #expect(error == .providerError("User denied"))
        }

        let noCode = try #require(URL(string: "spoolkid://oauth/callback?state=\(request.state)"))
        do {
            _ = try OIDCAuthorizationRequest.code(fromCallback: noCode, expectedState: request.state)
            Issue.record("Expected missingCode")
        } catch {
            #expect(error == .missingCode)
        }
    }
}
