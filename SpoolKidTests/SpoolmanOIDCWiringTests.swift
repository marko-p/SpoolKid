//
//  SpoolmanOIDCWiringTests.swift
//  SpoolKidTests
//
//  Drives SpoolmanService + OIDCSession against StubURLProtocol: the bearer
//  token on each request, refresh before expiry (one refresh for concurrent
//  callers), one retry after an auth rejection, the signed-out notice, and the
//  Authorization header being dropped on a cross-origin redirect. Spoolman is
//  /api/v1 and the fake provider is /idp, both on the stub host.
//
//  These are an extension of `ServerWebPageWiringTests` so they share that
//  suite's serialization: `StubURLProtocol.handler` is one global.
//

import Foundation
import Testing
@testable import SpoolKid

/// Fixtures. Nonisolated so the @Sendable stub closures can use them.
nonisolated private enum OIDCWiringFixture {
    static let issuer = "http://spoolkid-stub.invalid/idp"
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func config() -> OIDCConfiguration {
        OIDCConfiguration(issuer: issuer, clientId: "spoolkid", scopes: "")!
    }

    static func tokens(access: String = "A", expiresIn: TimeInterval = 3600, refresh: String? = "RT") -> OIDCTokenSet {
        OIDCTokenSet(
            accessToken: access, refreshToken: refresh, expiresAt: now.addingTimeInterval(expiresIn),
            idToken: nil, displayName: "marko", issuer: issuer, clientId: "spoolkid"
        )
    }

    static func json(_ body: String, status: Int = 200) -> StubURLProtocol.Reply {
        .init(status: status, contentType: "application/json", body: body)
    }

    static func tokenReply(_ access: String) -> StubURLProtocol.Reply {
        json(#"{"access_token":"\#(access)","token_type":"Bearer","expires_in":3600}"#)
    }

    static func discoveryReply(issuer: String = OIDCWiringFixture.issuer) -> StubURLProtocol.Reply {
        json(#"{"issuer":"\#(issuer)","authorization_endpoint":"\#(issuer)/authorize","token_endpoint":"\#(issuer)/token","revocation_endpoint":"\#(issuer)/revoke"}"#)
    }

    static func jwt(_ claims: [String: Any]) -> String {
        func b64(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let payload = try! JSONSerialization.data(withJSONObject: claims)
        return "\(b64(Data(#"{"alg":"none"}"#.utf8))).\(b64(payload)).c2ln"
    }
}

/// An in-memory token store and a request log, both lock-protected so the
/// @Sendable closures can share them.
nonisolated private final class WiringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: OIDCTokenSet?
    private var saveSucceeds = true
    private var requests: [(path: String, authorization: String?)] = []
    private var nonce: String?

    init(tokens: OIDCTokenSet?) { self.tokens = tokens }

    var stored: OIDCTokenSet? { lock.withLock { tokens } }
    var store: OIDCTokenStoring {
        OIDCTokenStoring(
            load: { [self] in lock.withLock { tokens } },
            save: { [self] new in
                lock.withLock {
                    guard saveSucceeds else { return false }
                    tokens = new
                    return true
                }
            }
        )
    }

    func replace(_ new: OIDCTokenSet?) { lock.withLock { tokens = new } }
    func failSaves() { lock.withLock { saveSucceeds = false } }

    func record(_ request: URLRequest) {
        lock.withLock { requests.append((request.url?.path ?? "", request.value(forHTTPHeaderField: "Authorization"))) }
    }
    func count(prefix: String) -> Int { lock.withLock { requests.filter { $0.path.hasPrefix(prefix) }.count } }
    func authorizations(prefix: String) -> [String?] { lock.withLock { requests.filter { $0.path.hasPrefix(prefix) }.map(\.authorization) } }

    func setNonce(_ value: String) { lock.withLock { nonce = value } }
    var recordedNonce: String? { lock.withLock { nonce } }
}

/// A mutable string the @Sendable configuration closures can read.
nonisolated private final class LiveIssuer: @unchecked Sendable {
    private let lock = NSLock()
    private var current: String
    init(_ value: String) { current = value }
    var value: String {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

extension ServerWebPageWiringTests {

    // MARK: - Harness

    /// Installs a handler: Spoolman answers through `api`, the provider answers
    /// discovery and `token`. Every request is logged on the returned box.
    private func oidcWiringInstall(
        _ box: WiringBox,
        api: @escaping @Sendable (String?) -> StubURLProtocol.Reply = { _ in OIDCWiringFixture.json("[]") },
        token: @escaping @Sendable (URLRequest) -> StubURLProtocol.Reply = { _ in OIDCWiringFixture.tokenReply("B") }
    ) {
        StubURLProtocol.handler = { request in
            box.record(request)
            let path = request.url?.path ?? ""
            if path.hasSuffix("/.well-known/openid-configuration") { return OIDCWiringFixture.discoveryReply() }
            if path == "/idp/token" { return token(request) }
            return api(request.value(forHTTPHeaderField: "Authorization"))
        }
    }

    private func oidcWiringService(_ box: WiringBox, authType: String = "oidc") -> SpoolmanService {
        let session = OIDCSession(
            client: OIDCClient(session: StubURLProtocol.session()),
            configuration: { OIDCWiringFixture.config() },
            store: box.store,
            now: { OIDCWiringFixture.now }
        )
        return SpoolmanService(session: StubURLProtocol.session(), oidc: session, authType: { authType })
    }

    // MARK: - Bearer token

    @Test func oidcWiringSendsBearerToSpoolman() async {
        let box = WiringBox(tokens: OIDCWiringFixture.tokens(access: "A"))
        oidcWiringInstall(box)
        let service = oidcWiringService(box)
        await service.fetchVendors(baseUrl: StubURLProtocol.baseUrl)
        #expect(box.authorizations(prefix: "/api/v1/vendor") == ["Bearer A"])
        #expect(service.errorMessage == nil)
    }

    @Test func oidcWiringRefreshesBeforeExpiry() async {
        let box = WiringBox(tokens: OIDCWiringFixture.tokens(access: "A", expiresIn: 30))
        oidcWiringInstall(box)
        let service = oidcWiringService(box)
        await service.fetchVendors(baseUrl: StubURLProtocol.baseUrl)
        #expect(box.count(prefix: "/idp/token") == 1)
        #expect(box.authorizations(prefix: "/api/v1/vendor") == ["Bearer B"])
        #expect(box.stored?.accessToken == "B")
        #expect(box.stored?.refreshToken == "RT")
    }

    @Test func oidcWiringConcurrentRequestsShareOneRefresh() async {
        let box = WiringBox(tokens: OIDCWiringFixture.tokens(access: "A", expiresIn: -10))
        oidcWiringInstall(box)
        let service = oidcWiringService(box)
        async let spools: Void = service.fetchSpools(baseUrl: StubURLProtocol.baseUrl)
        async let filaments: Void = service.fetchFilaments(baseUrl: StubURLProtocol.baseUrl)
        async let vendors: Void = service.fetchVendors(baseUrl: StubURLProtocol.baseUrl)
        async let locations: Void = service.fetchLocations(baseUrl: StubURLProtocol.baseUrl)
        _ = await (spools, filaments, vendors, locations)
        #expect(box.count(prefix: "/idp/token") == 1)
        #expect(box.count(prefix: "/api/v1/") >= 4)
        #expect(Set(box.authorizations(prefix: "/api/v1/").compactMap { $0 }) == ["Bearer B"])
    }

    // MARK: - Retry and sign-out

    @Test func oidcWiringRetriesOnceAfter401() async {
        let box = WiringBox(tokens: OIDCWiringFixture.tokens(access: "A"))
        oidcWiringInstall(box, api: { auth in
            auth == "Bearer B" ? OIDCWiringFixture.json("[]") : OIDCWiringFixture.json(#"{"message":"no"}"#, status: 401)
        })
        let service = oidcWiringService(box)
        await service.fetchVendors(baseUrl: StubURLProtocol.baseUrl)
        #expect(service.errorMessage == nil)
        #expect(box.count(prefix: "/api/v1/") == 2)
        #expect(service.signedOutNotice == nil)
    }

    @Test func oidcWiringSignsOutAfterARejectedRefresh() async {
        let box = WiringBox(tokens: OIDCWiringFixture.tokens(access: "A"))
        oidcWiringInstall(
            box,
            api: { _ in OIDCWiringFixture.json("{}", status: 401) },
            token: { _ in OIDCWiringFixture.json(#"{"error":"invalid_grant"}"#, status: 400) }
        )
        let service = oidcWiringService(box)
        await service.fetchVendors(baseUrl: StubURLProtocol.baseUrl)
        #expect(service.signedOutNotice?.issuerHost == "spoolkid-stub.invalid")
        #expect(box.stored == nil)
        #expect(service.oidc.displayName == nil)
        #expect(service.errorMessage == "Signed out of Spoolman. Sign in again in the Spoolman backend settings.")
    }

    @Test func oidcWiringKeepsTokensOnATransientRefreshFailure() async {
        let box = WiringBox(tokens: OIDCWiringFixture.tokens(access: "A"))
        oidcWiringInstall(
            box,
            api: { _ in OIDCWiringFixture.json("{}", status: 401) },
            token: { _ in OIDCWiringFixture.json("{}", status: 503) }
        )
        let service = oidcWiringService(box)
        await service.fetchVendors(baseUrl: StubURLProtocol.baseUrl)
        #expect(service.signedOutNotice == nil)
        #expect(box.stored?.accessToken == "A")
        #expect(service.errorMessage?.isEmpty == false)
        #expect(box.count(prefix: "/api/v1/") == 1)
    }

    @Test func oidcWiringStillRejectedAfterRefreshSignsOut() async {
        let box = WiringBox(tokens: OIDCWiringFixture.tokens(access: "A"))
        oidcWiringInstall(box, api: { _ in OIDCWiringFixture.json("{}", status: 401) })
        let service = oidcWiringService(box)
        await service.fetchVendors(baseUrl: StubURLProtocol.baseUrl)
        #expect(box.count(prefix: "/api/v1/") == 2)
        #expect(service.signedOutNotice != nil)
        #expect(box.stored == nil)
    }

    @Test func oidcWiringNeverSignedInPublishesNoNotice() async {
        let box = WiringBox(tokens: nil)
        oidcWiringInstall(box)
        let service = oidcWiringService(box)
        await service.fetchVendors(baseUrl: StubURLProtocol.baseUrl)
        #expect(service.errorMessage == "Not signed in to Spoolman. Sign in in the Spoolman backend settings.")
        #expect(service.signedOutNotice == nil)
        #expect(box.count(prefix: "/api/v1/") == 0)
    }

    @Test func oidcWiringNoticeDoesNotRepopAfterSignOut() async {
        let box = WiringBox(tokens: OIDCWiringFixture.tokens(access: "A"))
        oidcWiringInstall(
            box,
            api: { _ in OIDCWiringFixture.json("{}", status: 401) },
            token: { _ in OIDCWiringFixture.json(#"{"error":"invalid_grant"}"#, status: 400) }
        )
        let service = oidcWiringService(box)
        await service.fetchVendors(baseUrl: StubURLProtocol.baseUrl)
        #expect(service.signedOutNotice != nil)

        service.signedOutNotice = nil  // "Not Now"
        await service.fetchVendors(baseUrl: StubURLProtocol.baseUrl)
        #expect(service.signedOutNotice == nil)
        #expect(service.errorMessage == "Not signed in to Spoolman. Sign in in the Spoolman backend settings.")
    }

    @Test func oidcWiringHealthCheckNeverPublishesANotice() async {
        let box = WiringBox(tokens: nil)
        oidcWiringInstall(box)
        let service = oidcWiringService(box)
        #expect(await service.healthCheck(baseUrl: StubURLProtocol.baseUrl) == false)
        #expect(service.signedOutNotice == nil)

        let rejected = WiringBox(tokens: OIDCWiringFixture.tokens(access: "A"))
        oidcWiringInstall(rejected, api: { _ in OIDCWiringFixture.json("{}", status: 401) })
        let second = oidcWiringService(rejected)
        #expect(await second.healthCheck(baseUrl: StubURLProtocol.baseUrl) == false)
        #expect(second.signedOutNotice == nil)
        #expect(rejected.count(prefix: "/api/v1/") == 1)
    }

    @Test func oidcWiringBearerTypeIsUnchanged() async {
        let box = WiringBox(tokens: OIDCWiringFixture.tokens(access: "A"))
        oidcWiringInstall(box, api: { _ in OIDCWiringFixture.json("{}", status: 401) })
        let service = oidcWiringService(box, authType: "bearer")
        await service.fetchVendors(baseUrl: StubURLProtocol.baseUrl)
        #expect(box.count(prefix: "/api/v1/") == 1)
        #expect(box.count(prefix: "/idp/") == 0)
        #expect(service.signedOutNotice == nil)
    }

    // MARK: - Sign in

    @Test func oidcWiringSignInStoresTokens() async {
        let box = WiringBox(tokens: nil)
        oidcWiringInstall(box, token: { _ in
            let idToken = OIDCWiringFixture.jwt([
                "iss": OIDCWiringFixture.issuer, "aud": "spoolkid", "nonce": box.recordedNonce ?? "",
                "exp": OIDCWiringFixture.now.timeIntervalSince1970 + 3600, "email": "marko@example.com",
            ])
            return OIDCWiringFixture.json(#"{"access_token":"AT","token_type":"Bearer","expires_in":3600,"refresh_token":"RT","id_token":"\#(idToken)"}"#)
        })
        let service = oidcWiringService(box)
        let result = await service.oidc.signIn { url in
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let state = items.first { $0.name == "state" }?.value ?? ""
            box.setNonce(items.first { $0.name == "nonce" }?.value ?? "")
            return URL(string: "spoolkid://oauth/callback?code=c1&state=\(state)")!
        }
        if case .failure(let error) = result { Issue.record("sign-in failed: \(error)") }
        #expect(service.oidc.displayName == "marko@example.com")
        #expect(box.stored?.accessToken == "AT")
        #expect(box.stored?.refreshToken == "RT")
    }

    @Test func oidcWiringSignInFailsWhenTheKeychainWriteFails() async {
        let box = WiringBox(tokens: nil)
        box.failSaves()
        oidcWiringInstall(box)
        let service = oidcWiringService(box)
        let result = await service.oidc.signIn { url in
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value ?? ""
            return URL(string: "spoolkid://oauth/callback?code=c1&state=\(state)")!
        }
        if case .failure(let error) = result {
            #expect(error == .providerError("Your sign-in could not be saved to the Keychain."))
        } else {
            Issue.record("expected a failure")
        }
        #expect(service.oidc.displayName == nil)
    }

    @Test func oidcWiringSignOutDeletesTokensAndRevokes() async {
        let box = WiringBox(tokens: OIDCWiringFixture.tokens(access: "A"))
        oidcWiringInstall(box)
        let service = oidcWiringService(box)
        #expect(service.oidc.displayName == "marko")
        await service.oidc.signOut()
        #expect(box.stored == nil)
        #expect(service.oidc.displayName == nil)
        #expect(box.count(prefix: "/idp/revoke") == 1)
    }

    @Test func oidcWiringSignOutRevokesAtTheIssuingProvider() async {
        let box = WiringBox(tokens: OIDCWiringFixture.tokens(access: "A"))
        let issuerB = "http://spoolkid-stub.invalid/idp2"
        StubURLProtocol.handler = { request in
            box.record(request)
            let path = request.url?.path ?? ""
            if path == "/idp2/.well-known/openid-configuration" { return OIDCWiringFixture.discoveryReply(issuer: issuerB) }
            if path.hasSuffix("/.well-known/openid-configuration") { return OIDCWiringFixture.discoveryReply() }
            return OIDCWiringFixture.json("{}")
        }
        let live = LiveIssuer(OIDCWiringFixture.issuer)
        let session = OIDCSession(
            client: OIDCClient(session: StubURLProtocol.session()),
            configuration: { OIDCConfiguration(issuer: live.value, clientId: "spoolkid", scopes: "") },
            store: box.store,
            now: { OIDCWiringFixture.now }
        )
        // The identity edit: the new issuer is stored before sign-out runs.
        live.value = issuerB
        await session.signOut()
        #expect(box.count(prefix: "/idp2/") == 0)
        #expect(box.count(prefix: "/idp/revoke") == 1)
        #expect(box.stored == nil)
    }

    @Test func oidcWiringARefreshSupersededBySignOutPublishesNoNotice() async {
        let box = WiringBox(tokens: OIDCWiringFixture.tokens(access: "A", expiresIn: -10, refresh: "OLD-RT"))
        oidcWiringInstall(box, token: { _ in
            box.replace(nil)  // signed out while the refresh is answered
            return OIDCWiringFixture.json(#"{"error":"invalid_grant"}"#, status: 400)
        })
        let service = oidcWiringService(box)
        #expect(await service.oidc.accessToken(forceRefresh: false) == .notSignedIn)
    }

    // MARK: - Pure rules

    @Test func oidcWiringAuthRejectionRule() {
        let base = StubURLProtocol.baseUrl
        let same = URL(string: "http://spoolkid-stub.invalid/api/v1/vendor")
        #expect(SpoolmanService.isAuthRejection(status: 401, mimeType: "application/json", responseURL: same, baseUrl: base))
        #expect(SpoolmanService.isAuthRejection(status: 403, mimeType: "application/json", responseURL: same, baseUrl: base))
        #expect(!SpoolmanService.isAuthRejection(status: 200, mimeType: "text/html", responseURL: same, baseUrl: base))
        let foreign = URL(string: "http://idp.other/login")
        #expect(SpoolmanService.isAuthRejection(status: 200, mimeType: "text/html", responseURL: foreign, baseUrl: base))
        #expect(!SpoolmanService.isAuthRejection(status: 200, mimeType: "application/json", responseURL: foreign, baseUrl: base))
    }

    @Test func oidcWiringRedirectStripsAuthorizationCrossOrigin() {
        let base = StubURLProtocol.baseUrl
        func redirected(_ target: String) -> String? {
            var request = URLRequest(url: URL(string: target)!)
            request.setValue("Bearer A", forHTTPHeaderField: "Authorization")
            return SpoolmanService.redirect(request, baseUrl: base).value(forHTTPHeaderField: "Authorization")
        }
        #expect(redirected("http://spoolkid-stub.invalid/api/v1/other") == "Bearer A")
        #expect(redirected("http://SPOOLKID-STUB.invalid:80/x") == "Bearer A")
        #expect(redirected("http://other.invalid/x") == nil)
        #expect(redirected("http://spoolkid-stub.invalid:8080/x") == nil)
        #expect(redirected("https://spoolkid-stub.invalid/x") == "Bearer A")
        #expect(redirected("https://spoolkid-stub.invalid:8443/x") == nil)
    }

    @Test func oidcWiringRedirectKeepsTheTokenOnlyOnAnHTTPSUpgrade() {
        func redirected(from base: String, to target: String) -> String? {
            var request = URLRequest(url: URL(string: target)!)
            request.setValue("Bearer A", forHTTPHeaderField: "Authorization")
            return SpoolmanService.redirect(request, baseUrl: base).value(forHTTPHeaderField: "Authorization")
        }
        #expect(redirected(from: "http://h.invalid", to: "https://h.invalid/x") == "Bearer A")
        #expect(redirected(from: "http://h.invalid:8080", to: "https://h.invalid:8080/x") == "Bearer A")
        #expect(redirected(from: "https://h.invalid", to: "http://h.invalid/x") == nil)
        #expect(redirected(from: "http://h.invalid", to: "https://h.invalid:8443/x") == nil)
        #expect(redirected(from: "http://h.invalid:8080", to: "https://h.invalid/x") == nil)
        #expect(redirected(from: "http://h.invalid", to: "https://other.invalid/x") == nil)
        let upgraded = URL(string: "https://h.invalid/login")
        #expect(!SpoolmanService.isAuthRejection(status: 200, mimeType: "text/html", responseURL: upgraded, baseUrl: "http://h.invalid"))
    }

    @Test func oidcWiringARefreshRejectedAfterANewSignInKeepsTheNewTokens() async {
        let box = WiringBox(tokens: OIDCWiringFixture.tokens(access: "A", expiresIn: -10, refresh: "OLD-RT"))
        let newer = OIDCWiringFixture.tokens(access: "NEW", expiresIn: 3600, refresh: "NEW-RT")
        oidcWiringInstall(box, token: { _ in
            // Mid-flight: the user signs in again while this refresh is answered.
            box.replace(newer)
            return OIDCWiringFixture.json(#"{"error":"invalid_grant"}"#, status: 400)
        })
        let service = oidcWiringService(box)
        let result = await service.oidc.accessToken(forceRefresh: false)
        #expect(result == .token("NEW"))
        #expect(box.stored == newer)
        #expect(service.oidc.displayName == "marko")
    }

    @Test func oidcWiringASuccessfulRefreshNeverOverwritesNewerTokens() async {
        let box = WiringBox(tokens: OIDCWiringFixture.tokens(access: "A", expiresIn: -10, refresh: "OLD-RT"))
        let newer = OIDCWiringFixture.tokens(access: "NEW", expiresIn: 3600, refresh: "NEW-RT")
        oidcWiringInstall(box, token: { _ in
            box.replace(newer)
            return OIDCWiringFixture.tokenReply("STALE")
        })
        let service = oidcWiringService(box)
        #expect(await service.oidc.accessToken(forceRefresh: false) == .token("NEW"))
        #expect(box.stored == newer)
    }

    @Test func oidcWiringStillCurrentRule() {
        let a = OIDCWiringFixture.tokens(access: "A", refresh: "R")
        #expect(OIDCSession.isStillCurrent(a, comparedTo: a))
        #expect(!OIDCSession.isStillCurrent(nil, comparedTo: a))
        #expect(!OIDCSession.isStillCurrent(OIDCWiringFixture.tokens(access: "A", refresh: "R2"), comparedTo: a))
        let bare = OIDCWiringFixture.tokens(access: "A", refresh: nil)
        #expect(OIDCSession.isStillCurrent(bare, comparedTo: bare))
        #expect(!OIDCSession.isStillCurrent(OIDCWiringFixture.tokens(access: "B", refresh: nil), comparedTo: bare))
    }
}
