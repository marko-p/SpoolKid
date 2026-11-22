//
//  OIDCClientTests.swift
//  SpoolKidTests
//
//  Drives the OpenID Connect provider client against StubURLProtocol (host
//  spoolkid-stub.invalid, path /idp) and pins the Keychain-backed token store.
//  Nothing reaches the network.
//
//  The stub-backed tests are an extension of `ServerWebPageWiringTests` so they
//  share that suite's serialization: `StubURLProtocol.handler` is one global.
//  The Keychain and pure form-encoding tests have no stub and live in their own
//  suite.
//

import Foundation
import Testing
@testable import SpoolKid

/// Fixtures and helpers. Nonisolated so the @Sendable stub closures can use them.
nonisolated private enum OIDCFixture {
    static let issuer = "http://spoolkid-stub.invalid/idp"
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let tokenJSON = #"{"access_token":"AT","token_type":"Bearer","expires_in":3600,"refresh_token":"RT"}"#

    static func config() -> OIDCConfiguration {
        OIDCConfiguration(issuer: issuer, clientId: "spoolkid", scopes: "")!
    }

    static func client() -> OIDCClient {
        OIDCClient(session: StubURLProtocol.session())
    }

    static func json(_ body: String, status: Int = 200) -> StubURLProtocol.Reply {
        .init(status: status, contentType: "application/json", body: body)
    }

    /// A discovery document on `host`. The issuer follows the host, so a
    /// document on the default host matches `issuer` exactly.
    static func discoveryJSON(host: String = StubURLProtocol.host, revocation: Bool = true) -> String {
        let base = "http://\(host)/idp"
        var fields = [
            "\"issuer\":\"\(base)\"",
            "\"authorization_endpoint\":\"\(base)/authorize\"",
            "\"token_endpoint\":\"\(base)/token\"",
        ]
        if revocation { fields.append("\"revocation_endpoint\":\"\(base)/revoke\"") }
        return "{" + fields.joined(separator: ",") + "}"
    }

    static func discovery(host: String = StubURLProtocol.host, revocation: Bool = true) -> OIDCDiscovery {
        try! JSONDecoder().decode(OIDCDiscovery.self, from: Data(discoveryJSON(host: host, revocation: revocation).utf8))
    }

    static func sample(refreshToken: String? = "RT") -> OIDCTokenSet {
        OIDCTokenSet(
            accessToken: "OLD", refreshToken: refreshToken, expiresAt: now, idToken: nil,
            displayName: "marko", issuer: issuer, clientId: "spoolkid"
        )
    }

    /// Installs `reply` as the stub handler and records every request it sees.
    static func install(_ reply: @escaping @Sendable (URLRequest) -> StubURLProtocol.Reply) -> RequestRecorder {
        let recorder = RequestRecorder()
        StubURLProtocol.handler = { request in
            recorder.record(request)
            return reply(request)
        }
        return recorder
    }

    /// The OIDCError an operation throws, or nil when it succeeds. Any other
    /// error is recorded as an issue and reported as nil.
    static func failure<T>(_ operation: () async throws -> T) async -> OIDCError? {
        do {
            _ = try await operation()
            return nil
        } catch let error as OIDCError {
            return error
        } catch {
            Issue.record("expected OIDCError, got \(error)")
            return nil
        }
    }
}

/// Keeps a copy of each request the stub saw. URLProtocol delivers form bodies
/// as a stream, so the body is read here.
nonisolated private final class RequestRecorder: @unchecked Sendable {
    struct Entry: Sendable {
        let path: String
        let contentType: String?
        let body: String
    }

    private let lock = NSLock()
    private var stored: [Entry] = []

    func record(_ request: URLRequest) {
        let entry = Entry(
            path: request.url?.path ?? "",
            contentType: request.value(forHTTPHeaderField: "Content-Type"),
            body: Self.body(of: request)
        )
        lock.withLock { stored.append(entry) }
    }

    var entries: [Entry] { lock.withLock { stored } }

    private static func body(of request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Stub-backed provider tests. Shares `ServerWebPageWiringTests`' serialization.
extension ServerWebPageWiringTests {

    // MARK: - Discovery

    @Test func oidcClientDiscoveryDecodesTheEndpointsWhenTheIssuerMatches() async throws {
        _ = OIDCFixture.install { _ in OIDCFixture.json(OIDCFixture.discoveryJSON()) }
        let found = try await OIDCFixture.client().discover(OIDCFixture.config())
        #expect(found.tokenEndpoint.absoluteString == "http://spoolkid-stub.invalid/idp/token")
    }

    @Test func oidcClientDiscoveryRejectsAnIssuerThatDiffersByATrailingSlash() async {
        _ = OIDCFixture.install { _ in OIDCFixture.json(OIDCFixture.discoveryJSON()) }
        let slashed = OIDCConfiguration(issuer: OIDCFixture.issuer + "/", clientId: "spoolkid", scopes: "")!
        let error = await OIDCFixture.failure { try await OIDCFixture.client().discover(slashed) }
        #expect(error == OIDCError.issuerMismatch(expected: OIDCFixture.issuer + "/", found: OIDCFixture.issuer))
    }

    @Test func oidcClientDiscoveryWithAnHTTPErrorIsAProviderError() async {
        _ = OIDCFixture.install { _ in OIDCFixture.json("{}", status: 500) }
        let error = await OIDCFixture.failure { try await OIDCFixture.client().discover(OIDCFixture.config()) }
        #expect(error == OIDCError.providerError("HTTP 500 from the discovery document"))
    }

    @Test func oidcClientDiscoveryWithoutANetworkIsTransient() async {
        let unreachable = OIDCConfiguration(issuer: "http://spoolkid-unreachable.invalid/idp", clientId: "spoolkid", scopes: "")!
        _ = OIDCFixture.install { _ in OIDCFixture.json("{}") }
        let error = await OIDCFixture.failure { try await OIDCFixture.client().discover(unreachable) }
        guard case .transient = error else {
            Issue.record("expected .transient, got \(String(describing: error))")
            return
        }
    }

    // MARK: - Code exchange

    @Test func oidcClientExchangePostsThePKCEFormAndReadsTheTokens() async throws {
        let recorder = OIDCFixture.install { request in
            request.url?.path == "/idp/token" ? OIDCFixture.json(OIDCFixture.tokenJSON) : OIDCFixture.json("{}", status: 404)
        }
        let tokens = try await OIDCFixture.client().exchange(
            code: "CODE", verifier: "VERIFIER", nonce: "N",
            config: OIDCFixture.config(), discovery: OIDCFixture.discovery(), now: OIDCFixture.now
        )

        #expect(tokens.accessToken == "AT")
        #expect(tokens.refreshToken == "RT")
        let post = try #require(recorder.entries.first)
        #expect(post.contentType == "application/x-www-form-urlencoded")
        #expect(post.body.contains("grant_type=authorization_code"))
        #expect(post.body.contains("code=CODE"))
        #expect(post.body.contains("code_verifier=VERIFIER"))
        #expect(post.body.contains("client_id=spoolkid"))
        #expect(post.body.contains("redirect_uri=spoolkid%3A%2F%2Foauth%2Fcallback"))
    }

    @Test func oidcClientExchangeReportsTheProvidersOwnDescription() async {
        _ = OIDCFixture.install { _ in
            OIDCFixture.json(#"{"error":"invalid_grant","error_description":"code expired"}"#, status: 400)
        }
        let error = await OIDCFixture.failure {
            try await OIDCFixture.client().exchange(
                code: "CODE", verifier: "V", nonce: "N",
                config: OIDCFixture.config(), discovery: OIDCFixture.discovery(), now: OIDCFixture.now
            )
        }
        #expect(error == OIDCError.providerError("code expired"))
    }

    // MARK: - Refresh

    @Test func oidcClientRefreshWithoutARefreshTokenFailsWithoutARequest() async {
        let recorder = OIDCFixture.install { _ in OIDCFixture.json(OIDCFixture.tokenJSON) }
        let result = await OIDCFixture.client().refresh(
            OIDCFixture.sample(refreshToken: nil),
            config: OIDCFixture.config(), discovery: OIDCFixture.discovery(), now: OIDCFixture.now
        )
        #expect(result == .failure(.signedOut))
        #expect(recorder.entries.isEmpty)
    }

    @Test func oidcClientRefreshPostsTheRefreshTokenGrant() async throws {
        let recorder = OIDCFixture.install { _ in OIDCFixture.json(OIDCFixture.tokenJSON) }
        let result = await OIDCFixture.client().refresh(
            OIDCFixture.sample(),
            config: OIDCFixture.config(), discovery: OIDCFixture.discovery(), now: OIDCFixture.now
        )
        let tokens = try result.get()
        #expect(tokens.accessToken == "AT")
        let post = try #require(recorder.entries.first)
        #expect(post.body.contains("grant_type=refresh_token"))
        #expect(post.body.contains("refresh_token=RT"))
    }

    @Test func oidcClientRefreshInvalidGrantIsSignedOut() async {
        _ = OIDCFixture.install { _ in OIDCFixture.json(#"{"error":"invalid_grant"}"#, status: 400) }
        let result = await OIDCFixture.client().refresh(
            OIDCFixture.sample(),
            config: OIDCFixture.config(), discovery: OIDCFixture.discovery(), now: OIDCFixture.now
        )
        #expect(result == .failure(.signedOut))
    }

    @Test func oidcClientRefreshServerErrorIsTransient() async {
        _ = OIDCFixture.install { _ in OIDCFixture.json("{}", status: 503) }
        let result = await OIDCFixture.client().refresh(
            OIDCFixture.sample(),
            config: OIDCFixture.config(), discovery: OIDCFixture.discovery(), now: OIDCFixture.now
        )
        #expect(result == .failure(.transient))
    }

    @Test func oidcClientRefreshWithAnUnreachableProviderIsTransient() async {
        _ = OIDCFixture.install { _ in OIDCFixture.json(OIDCFixture.tokenJSON) }
        let result = await OIDCFixture.client().refresh(
            OIDCFixture.sample(),
            config: OIDCFixture.config(), discovery: OIDCFixture.discovery(host: "spoolkid-unreachable.invalid"),
            now: OIDCFixture.now
        )
        #expect(result == .failure(.transient))
    }

    @Test func oidcClientRefreshWithAMalformedBodyIsSignedOut() async {
        _ = OIDCFixture.install { _ in OIDCFixture.json("{}") }
        let result = await OIDCFixture.client().refresh(
            OIDCFixture.sample(),
            config: OIDCFixture.config(), discovery: OIDCFixture.discovery(), now: OIDCFixture.now
        )
        #expect(result == .failure(.signedOut))
    }

    // MARK: - Revocation

    @Test func oidcClientRevokeNeedsARevocationEndpoint() async {
        let recorder = OIDCFixture.install { _ in OIDCFixture.json("{}") }
        let revoked = await OIDCFixture.client().revoke(
            "RT", discovery: OIDCFixture.discovery(revocation: false), clientId: "spoolkid"
        )
        #expect(revoked == false)
        #expect(recorder.entries.isEmpty)
    }

    @Test func oidcClientRevokePostsTheRefreshTokenHint() async throws {
        let recorder = OIDCFixture.install { _ in OIDCFixture.json("{}") }
        let revoked = await OIDCFixture.client().revoke(
            "RT", discovery: OIDCFixture.discovery(), clientId: "spoolkid"
        )
        #expect(revoked)
        let post = try #require(recorder.entries.first)
        #expect(post.path == "/idp/revoke")
        #expect(post.body.contains("token=RT"))
        #expect(post.body.contains("token_type_hint=refresh_token"))
    }

    @Test func oidcClientRevokeServerErrorIsFalse() async {
        _ = OIDCFixture.install { _ in OIDCFixture.json("{}", status: 500) }
        let revoked = await OIDCFixture.client().revoke(
            "RT", discovery: OIDCFixture.discovery(), clientId: "spoolkid"
        )
        #expect(revoked == false)
    }
}

/// Keychain-backed token store and form encoding. No network stub, so this
/// suite does not share the stub's serialization.
@Suite(.serialized)
struct OIDCTokenStoreTests {

    @Test func tokenStoreRoundTripsAndDeletes() {
        let previous = KeychainStore.read(account: KeychainStore.spoolmanOIDCTokensAccount)
        defer { KeychainStore.save(previous ?? "", account: KeychainStore.spoolmanOIDCTokensAccount) }

        let tokens = OIDCFixture.sample()
        #expect(OIDCTokenStore.save(tokens))
        #expect(OIDCTokenStore.load() == tokens)

        #expect(OIDCTokenStore.save(nil))
        #expect(OIDCTokenStore.load() == nil)
    }

    @Test func anUndecodableStoredValueLoadsAsNil() {
        let previous = KeychainStore.read(account: KeychainStore.spoolmanOIDCTokensAccount)
        defer { KeychainStore.save(previous ?? "", account: KeychainStore.spoolmanOIDCTokensAccount) }

        #expect(KeychainStore.save("{not json", account: KeychainStore.spoolmanOIDCTokensAccount))
        #expect(OIDCTokenStore.load() == nil)
    }

    @Test func theTokenAccountIsResetWithTheOtherSecrets() {
        #expect(KeychainStore.spoolKidAccounts.contains(KeychainStore.spoolmanOIDCTokensAccount))
        #expect(KeychainStore.spoolmanOIDCTokensAccount == "spoolman_oidc_tokens")
    }

    @Test func formBodyPercentEncodesNonASCIIAndSpaces() {
        let body = String(decoding: OIDCClient.formBody([("name", "é x")]), as: UTF8.self)
        #expect(body == "name=%C3%A9%20x")
    }
}
