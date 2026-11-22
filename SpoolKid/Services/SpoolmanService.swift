//
//  SpoolmanService.swift
//  SpoolKid
//
//  Purpose: Networking service to interact with the self-hosted Spoolman API.
//  Responsibilities:
//  - Fetching, Creating, Updating, and Deleting Spools, Filaments, and Vendors.
//  - Handling API authentication (Basic Auth, Bearer Token, OpenID Connect) and error handling.
//  - Supporting HTTPS with self-signed certificates when configured.
//  - Managing local state (@Published properties) for UI binding.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Combine
import os

@MainActor
class SpoolmanService: ObservableObject {
    @Published var spools: [Spool] = []
    @Published var filaments: [Filament] = []
    @Published var vendors: [Vendor] = []
    @Published var locations: [String] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SpoolKid",
        category: "SpoolmanService"
    )
    
    private var _cachedInsecureSession: URLSession?
    private var _cachedTrustAll: Bool?

    private struct SpoolmanExtraField: Decodable {
        let key: String
        let fieldType: String?

        enum CodingKeys: String, CodingKey {
            case key
            case fieldType = "field_type"
        }
    }

    private struct SpoolmanCurrencySetting: Decodable {
        let value: String?
    }

    private struct SpoolmanInfo: Decodable {
        let version: String?
    }

    /// What `GET /api/v1/info` last said, and for which server. Kept per server
    /// identity so switching between two Spoolman servers never reuses the other
    /// one's answer, while `h:7912` and `http://h:7912/` are one server.
    nonisolated struct ServerInfo: Equatable, Sendable {
        let server: String
        let version: String

        init(baseUrl: String, version: String) {
            self.server = ServerAddress.identity(of: baseUrl)
            self.version = version
        }

        func describes(_ baseUrl: String) -> Bool {
            server == ServerAddress.identity(of: baseUrl)
        }
    }

    @Published private(set) var serverInfo: ServerInfo?

    /// The test seam: a session whose configuration carries a stub
    /// `URLProtocol`, so tests drive the real request paths without a network.
    /// When set it wins over the trust-all choice, so the host app's settings
    /// can never send a test to the configured server. Nil in the app.
    private let sessionOverride: URLSession?

    /// Every request's reachability, for `ServerLinkMonitor`. Nil in tests
    /// that don't look.
    var transportReport: (@MainActor (TransportReport, URL?) -> Void)?

    /// The OpenID Connect sign-in. Shared with the settings screen.
    let oidc: OIDCSession

    /// The configured auth type. A closure so tests choose it without touching
    /// the host app's defaults.
    private let authType: () -> String

    /// Set when an OpenID Connect sign-in ended mid-use; the UI offers to sign in again.
    @Published var signedOutNotice: SpoolmanSignedOutNotice?

    init(
        session: URLSession? = nil,
        oidc: OIDCSession? = nil,
        authType: @escaping () -> String = { UserDefaults.standard.string(forKey: AppConfig.authTypeKey) ?? "none" }
    ) {
        self.sessionOverride = session
        self.oidc = oidc ?? OIDCSession()
        self.authType = authType
    }

    private var session: URLSession {
        if let sessionOverride { return sessionOverride }
        let trustAll = BackendCapabilities.spoolman.trustsAllCerts
        if trustAll {
            if _cachedTrustAll == true, let existing = _cachedInsecureSession {
                return existing
            }
            _cachedInsecureSession?.invalidateAndCancel()
            let config = URLSessionConfiguration.default
            let newSession = URLSession(configuration: config, delegate: InsecureSessionDelegate(), delegateQueue: nil)
            _cachedInsecureSession = newSession
            _cachedTrustAll = true
            return newSession
        }
        if _cachedTrustAll == true {
            _cachedInsecureSession?.invalidateAndCancel()
            _cachedInsecureSession = nil
        }
        _cachedTrustAll = false
        return URLSession.shared
    }
    
    /// Applies the configured authentication headers to a URLRequest.
    /// Reads the auth type from `UserDefaults` and the credentials from the
    /// Keychain. The secrets lived in `UserDefaults` until 2026-08-25 (016 /
    /// F3.2); `migratingRead` moves each one across the first time it is
    /// asked for after the upgrade. Read per request deliberately — editing
    /// credentials then takes effect on the next call rather than the next
    /// launch.
    ///
    /// Returns the OpenID Connect token outcome, or nil for the other types.
    private func applyAuth(to request: inout URLRequest, type: String, forceRefresh: Bool = false) async -> OIDCSession.AccessToken? {
        switch type {
        case "basic":
            let username = UserDefaults.standard.string(forKey: AppConfig.authUsernameKey) ?? ""
            let password = KeychainStore.migratingRead(
                account: KeychainStore.spoolmanPasswordAccount,
                legacyDefaultsKey: AppConfig.authPasswordKey
            ) ?? ""
            if !username.isEmpty {
                let credentials = "\(username):\(password)"
                if let data = credentials.data(using: .utf8) {
                    let base64 = data.base64EncodedString()
                    request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
                }
            }
        case "bearer":
            let token = KeychainStore.migratingRead(
                account: KeychainStore.spoolmanTokenAccount,
                legacyDefaultsKey: AppConfig.authTokenKey
            ) ?? ""
            if !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        case "oidc":
            let outcome = await oidc.accessToken(forceRefresh: forceRefresh)
            if case let .token(token) = outcome {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            return outcome
        default:
            break
        }
        return nil
    }

    // MARK: - OpenID Connect request rules

    /// Where a request goes: scheme, host and effective port, compared
    /// case-insensitively.
    nonisolated private static func origin(of url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(host):\(port)"
    }

    /// Same origin, or the same host upgraded from http to https on the same
    /// explicit port (or both on their scheme's default): a user who typed
    /// http:// for a proxied https server must not lose the token on the
    /// upgrade redirect. Never https to http, another host or another port.
    nonisolated private static func isSameOrigin(_ url: URL?, baseUrl: String) -> Bool {
        guard let url, let theirs = origin(of: url),
              let base = try? ServerAddress.requestURL(baseUrl, endpoint: "/"),
              let ours = origin(of: base) else { return false }
        if theirs == ours { return true }
        guard base.scheme?.lowercased() == "http", url.scheme?.lowercased() == "https",
              base.host?.lowercased() == url.host?.lowercased() else { return false }
        return base.port == url.port
    }

    /// True when the server refused the credentials: 401/403, or a web page
    /// from another origin (an identity provider's login page the request was
    /// redirected to).
    nonisolated static func isAuthRejection(status: Int, mimeType: String?, responseURL: URL?, baseUrl: String) -> Bool {
        if status == 401 || status == 403 { return true }
        return ServerResponseCheck.isWebPage(mimeType: mimeType) && !isSameOrigin(responseURL, baseUrl: baseUrl)
    }

    /// The request to follow a redirect with: the bearer token never leaves
    /// the Spoolman origin.
    nonisolated static func redirect(_ request: URLRequest, baseUrl: String) -> URLRequest {
        guard !isSameOrigin(request.url, baseUrl: baseUrl) else { return request }
        var stripped = request
        stripped.setValue(nil, forHTTPHeaderField: "Authorization")
        return stripped
    }

    private func send(_ request: URLRequest, baseUrl: String) async throws -> (Data, URLResponse) {
        do {
            let reply = try await session.data(for: request, delegate: SpoolmanRedirectGuard(baseUrl: baseUrl))
            transportReport?(.answered, request.url)
            return reply
        } catch {
            if let failure = ServerFailure.classify(error) { transportReport?(.failed(failure), request.url) }
            throw error
        }
    }

    private static let signedOutMessage = "Signed out of Spoolman. Sign in again in the Spoolman backend settings."

    private func publishSignedOutNotice() {
        guard signedOutNotice == nil else { return }
        signedOutNotice = SpoolmanSignedOutNotice(issuerHost: oidc.issuerHost)
    }

    private static let notSignedInMessage = "Not signed in to Spoolman. Sign in in the Spoolman backend settings."

    /// Never signed in (or signed out on purpose): an error, but no alert.
    private func notSignedInError() -> NSError {
        NSError(domain: "SpoolmanError", code: 401, userInfo: [NSLocalizedDescriptionKey: Self.notSignedInMessage])
    }

    private func signedOutError() -> NSError {
        publishSignedOutNotice()
        return NSError(domain: "SpoolmanError", code: 401, userInfo: [NSLocalizedDescriptionKey: Self.signedOutMessage])
    }

    func fetchSpools(baseUrl: String) async {
        await refreshServerVersion(baseUrl: baseUrl)
        // Spoolman omits archived spools by default; request them so the Manage
        // Spools "Show Archived" toggle has data to reveal. Consumers that must
        // exclude archived filter client-side (DashboardStatsService.activeSpools,
        // ManageSpoolsView.excludingArchived).
        await fetchData(endpoint: "/api/v1/spool?allow_archived=true", baseUrl: baseUrl) { [weak self] (items: [Spool]) in
            self?.spools = items
        }
    }
    
    func fetchFilaments(baseUrl: String) async {
        await fetchData(endpoint: "/api/v1/filament", baseUrl: baseUrl) { [weak self] (items: [Filament]) in
            self?.filaments = items
        }
    }
    
    func fetchVendors(baseUrl: String) async {
        await fetchData(endpoint: "/api/v1/vendor", baseUrl: baseUrl) { [weak self] (items: [Vendor]) in
            self?.vendors = items
        }
    }

    func fetchLocations(baseUrl: String) async {
        await fetchData(endpoint: "/api/v1/location", baseUrl: baseUrl) { [weak self] (items: [String]) in
            self?.locations = items.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }
    
    /// The catalogue Spoolman synced from its `EXTERNAL_DB_URL` (route since
    /// v0.18.0). Throws instead of touching `errorMessage`: a missing
    /// catalogue is not a backend error, and the caller falls back.
    func fetchExternalFilaments(baseUrl: String) async throws -> [SpoolmanDBFilament] {
        try await sendRequest(method: "GET", endpoint: "/api/v1/external/filament", baseUrl: baseUrl)
    }

    func testConnection(baseUrl: String) async -> Bool {
        do {
            let _: [Vendor] = try await sendRequest(method: "GET", endpoint: "/api/v1/vendor", baseUrl: baseUrl)
            await refreshServerVersion(baseUrl: baseUrl)
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    /// Reads the server version. Silent on failure, deliberately: a failed
    /// read keeps the last answer, so a network blip never flips which tag
    /// stores SpoolKid writes to. Re-read on every spool fetch, so upgrading
    /// Spoolman takes effect without restarting the app.
    func refreshServerVersion(baseUrl: String) async {
        guard !baseUrl.isEmpty,
              let data = try? await perform(method: "GET", endpoint: "/api/v1/info", baseUrl: baseUrl),
              let version = (try? JSONDecoder().decode(SpoolmanInfo.self, from: data))?.version
        else { return }
        serverInfo = ServerInfo(baseUrl: baseUrl, version: version)
    }

    /// Native tags arrived in Spoolman 0.27.0. Below that, `GET /spool?tag=`
    /// is silently ignored and answers with EVERY spool (probed on 0.23.1,
    /// 2026-10-08), so no native call may ever reach an older server.
    nonisolated static func supportsNativeTags(version: String?) -> Bool {
        guard let version, let match = version.firstMatch(of: /^v?(\d+)\.(\d+)\.(\d+)/) else { return false }
        let parsed = (Int(match.1) ?? 0, Int(match.2) ?? 0, Int(match.3) ?? 0)
        return parsed >= (0, 27, 0)
    }

    /// Whether the server at `baseUrl` — and not some other one asked
    /// earlier — said it has native tags.
    func supportsNativeTags(at baseUrl: String) -> Bool {
        guard let serverInfo, serverInfo.describes(baseUrl) else { return false }
        return Self.supportsNativeTags(version: serverInfo.version)
    }

    /// Whether the last `/info` answer was for the server at `baseUrl`.
    func knowsServer(at baseUrl: String) -> Bool {
        serverInfo?.describes(baseUrl) == true
    }

    /// Lightweight reachability probe for the status indicator (display only).
    /// Hits the same endpoint as `testConnection` but with a short timeout so an
    /// unreachable server is detected in a few seconds instead of hanging on the
    /// 60s default. Does NOT mutate `errorMessage` or the sticky
    /// `spoolman_connection_valid` flag — those gate SpoolLink/migration and must
    /// only change via an explicit Test Connection.
    func healthCheck(baseUrl: String) async -> Bool {
        guard let url = try? ServerAddress.requestURL(baseUrl, endpoint: "/api/v1/vendor") else {
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        // Display-only: a missing or unrenewable sign-in is just "not reachable",
        // never a notice, and a rejection is not retried.
        switch await applyAuth(to: &request, type: authType()) {
        case .notSignedIn?, .signedOut?, .transient?: return false
        default: break
        }
        do {
            let (_, response) = try await send(request, baseUrl: baseUrl)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               !ServerResponseCheck.isWebPage(mimeType: http.mimeType) {
                return true
            }
            return false
        } catch {
            return false
        }
    }

    /// The `extra` object a filament write should carry for the draft's TD,
    /// or a note saying why TD was not written. A TD problem never fails the
    /// rest of the save. A draft that states its own `extra` is the base;
    /// otherwise `current` (the filament's extra right now; empty on create).
    private func transmissionDistanceExtra(
        for draft: FilamentDraft,
        baseUrl: String,
        current: () async throws -> [String: String]
    ) async -> (extra: [String: String]?, note: String?) {
        if case .ignore = draft.transmissionDistance { return (nil, nil) }
        let registerIfMissing = if case .set = draft.transmissionDistance { true } else { false }
        do {
            // Clearing on a server with no `td` field: nothing to clear.
            guard let fieldType = try await transmissionDistanceFieldType(
                registerIfMissing: registerIfMissing, baseUrl: baseUrl
            ) else { return (nil, nil) }
            let base: [String: String]
            if let stated = draft.extra.valueOnCreate { base = stated } else { base = try await current() }
            switch SpoolmanPayloadBuilder.extraApplyingTransmissionDistance(
                draft.transmissionDistance, to: base, fieldType: fieldType
            ) {
            case .unchanged: return (nil, nil)
            case .extra(let extra): return (extra, nil)
            case .refused(let note): return (nil, note)
            }
        } catch {
            return (nil, "TD was not saved: \(error.localizedDescription)")
        }
    }

    /// The registered `td` filament field's type. When it is missing and
    /// `registerIfMissing`, registers it (`POST /api/v1/field/filament/td`) —
    /// the owner's own definition minus its `default_value`, since a default
    /// would make every filament claim a TD. An existing field is never
    /// altered. Nil when missing and not registered.
    private func transmissionDistanceFieldType(registerIfMissing: Bool, baseUrl: String) async throws -> String? {
        let fields: [SpoolmanExtraField] = try await sendRequest(
            method: "GET", endpoint: "/api/v1/field/filament", baseUrl: baseUrl
        )
        if let existing = fields.first(where: { $0.key == TransmissionDistance.fieldKey }) {
            return existing.fieldType ?? "text"
        }
        guard registerIfMissing else { return nil }
        try await sendRequestWithoutDecoding(
            method: "POST",
            endpoint: "/api/v1/field/filament/\(TransmissionDistance.fieldKey)",
            baseUrl: baseUrl,
            body: [
                "name": TransmissionDistance.fieldName,
                "field_type": "float",
                "unit": "mm",
                "order": 0
            ]
        )
        logger.info("Spoolman td filament field created.")
        return "float"
    }

    func ensureCardUIDsField(baseUrl: String) async throws {
        let fields: [SpoolmanExtraField] = try await sendRequest(
            method: "GET",
            endpoint: "/api/v1/field/spool",
            baseUrl: baseUrl
        )

        guard fields.contains(where: { $0.key == "card_uids" }) == false else {
            logger.info("Spoolman card_uids field already exists; skipping bootstrap.")
            return
        }

        try await sendRequestWithoutDecoding(
            method: "POST",
            endpoint: "/api/v1/field/spool/card_uids",
            baseUrl: baseUrl,
            body: [
                "key": "card_uids",
                "name": "Card UIDs",
                "entity_type": "spool",
                "field_type": "text",
                "order": 1,
                "default_value": "\"\""
            ]
        )
        logger.info("Spoolman card_uids field created.")
    }

    /// Deletes the SpoolLink `card_uids` custom field definition AND every spool's
    /// stored value via `DELETE /api/v1/field/spool/card_uids`.
    /// A 404 Spoolman words itself means the field is already absent, which is
    /// treated as success; an HTML or FastAPI 404 (a proxy, a wrong path) is a
    /// failure. Refreshes the spool cache so the cleared values drop out of `extra`.
    @discardableResult
    func deleteCardUIDsField(baseUrl: String) async -> Bool {
        do {
            let (data, response) = try await performRaw(
                method: "DELETE", endpoint: "/api/v1/field/spool/card_uids", baseUrl: baseUrl
            )
            if (200...299).contains(response.statusCode) {
                logger.info("Spoolman card_uids field deleted.")
            } else if response.statusCode == 404, Self.hasSpoolmanMessage(data) {
                logger.info("Spoolman card_uids field already absent (404); treating delete as success.")
            } else {
                self.errorMessage = Self.errorText(data: data, status: response.statusCode, mimeType: response.mimeType)
                return false
            }
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
        await fetchSpools(baseUrl: baseUrl)
        return true
    }

    /// Spoolman's configured currency code (e.g. "EUR"), or nil on any failure so
    /// the caller can fall back to the device locale. Reads
    /// `GET /api/v1/setting/currency`, whose `value` is a JSON-encoded string.
    func fetchCurrencyCode(baseUrl: String) async -> String? {
        guard !baseUrl.isEmpty else { return nil }
        do {
            let data = try await perform(method: "GET", endpoint: "/api/v1/setting/currency", baseUrl: baseUrl)
            guard let raw = try? JSONDecoder().decode(SpoolmanCurrencySetting.self, from: data).value else {
                return nil
            }
            // `value` is JSON-encoded (e.g. "\"EUR\""); unwrap to the bare code.
            let code: String
            if let unwrapped = try? JSONDecoder().decode(String.self, from: Data(raw.utf8)) {
                code = unwrapped
            } else {
                code = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
            let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }

    // MARK: - CRUD Operations

    /// The response as it came, whatever its status, unless it is a web page.
    /// `perform` throws on anything outside 2xx; the tag endpoints need to read
    /// a 409's body. The web-page throw lives here so no endpoint, tag
    /// endpoints included, can take an HTML 200 for success.
    private func performRaw(
        method: String, endpoint: String, baseUrl: String, body: [String: Any]? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let url = try ServerAddress.requestURL(baseUrl, endpoint: endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = method

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        var data: Data
        var response: URLResponse
        let type = authType()
        switch await applyAuth(to: &request, type: type) {
        case .notSignedIn?:
            throw notSignedInError()
        case .signedOut?:
            throw signedOutError()
        case let .transient(message)?:
            throw NSError(domain: "SpoolmanError", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
        case .token?:
            (data, response) = try await send(request, baseUrl: baseUrl)
            if let http = response as? HTTPURLResponse,
               Self.isAuthRejection(status: http.statusCode, mimeType: http.mimeType, responseURL: http.url, baseUrl: baseUrl) {
                // One refresh and one resend; a second rejection ends the sign-in.
                switch await applyAuth(to: &request, type: type, forceRefresh: true) {
                case .token?:
                    (data, response) = try await send(request, baseUrl: baseUrl)
                    if let retried = response as? HTTPURLResponse,
                       Self.isAuthRejection(status: retried.statusCode, mimeType: retried.mimeType, responseURL: retried.url, baseUrl: baseUrl) {
                        await oidc.signOut()
                        throw signedOutError()
                    }
                case let .transient(message)?:
                    throw NSError(domain: "SpoolmanError", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
                case .notSignedIn?:
                    throw notSignedInError()
                case .signedOut?:
                    throw signedOutError()
                case nil:
                    // Unreachable (the type is read once per request); keep the
                    // first response so the ordinary status handling reports it.
                    break
                }
            }
        case nil:
            (data, response) = try await send(request, baseUrl: baseUrl)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if ServerResponseCheck.isWebPageInsteadOfData(statusCode: httpResponse.statusCode, mimeType: httpResponse.mimeType) {
            let signIn = httpResponse.statusCode == 401 || httpResponse.statusCode == 403
            throw NSError(
                domain: "SpoolmanError",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: signIn
                    ? ServerResponseCheck.signInPageMessage(backendName: "Spoolman", statusCode: httpResponse.statusCode)
                    : ServerResponseCheck.webPageMessage(backendName: "Spoolman")]
            )
        }
        return (data, httpResponse)
    }

    private func perform(method: String, endpoint: String, baseUrl: String, body: [String: Any]? = nil) async throws -> Data {
        let (data, httpResponse) = try await performRaw(method: method, endpoint: endpoint, baseUrl: baseUrl, body: body)
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "SpoolmanError",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: Self.errorText(
                    data: data, status: httpResponse.statusCode, mimeType: httpResponse.mimeType
                )]
            )
        }
        return data
    }

    /// Spoolman's own `{"message": …}`, else the raw body. An HTML body is a
    /// proxy's or the web UI's page, never pasted into a message.
    nonisolated static func errorText(data: Data, status: Int, mimeType: String? = nil) -> String {
        if ServerResponseCheck.isWebPage(mimeType: mimeType) {
            return "Server error \(status)."
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? String {
            return message
        }
        return "Server error \(status): \(String(data: data, encoding: .utf8) ?? "No body")"
    }

    // MARK: - Native tags (Spoolman 0.27+)

    enum TagLinkOutcome: Equatable {
        case linked
        case heldBySpool(Int)
        case heldByFilament(Int)
        case failed(String)
    }

    enum TagUnlinkOutcome: Equatable {
        case unlinked
        case failed(String)
    }

    private struct TagConflictBody: Decodable {
        let message: String?
        let spoolId: Int?
        let filamentId: Int?

        enum CodingKeys: String, CodingKey {
            case message
            case spoolId = "spool_id"
            case filamentId = "filament_id"
        }
    }

    /// `POST /api/v1/tag/scan` (spec 3). Spoolman broadcasts the scan to the
    /// browsers paired with this reader; the matches it answers with are not
    /// used. `.reported` only on a 2xx.
    func reportTagScan(_ report: TagScanReport, baseUrl: String) async -> TagScanReportOutcome {
        do {
            let (data, response) = try await performRaw(
                method: "POST", endpoint: "/api/v1/tag/scan", baseUrl: baseUrl, body: report.body
            )
            guard (200...299).contains(response.statusCode) else {
                return .failed(tagAPIError(data: data, status: response.statusCode, mimeType: response.mimeType))
            }
            return .reported
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// `POST /api/v1/spool/{id}/tag`. Idempotent: relinking a tag the spool
    /// already holds answers 201 and changes nothing (probed 2026-10-08). A
    /// tag something else holds is a 409 naming the holder.
    func linkTag(spoolId: Int, uid: String, baseUrl: String) async -> TagLinkOutcome {
        do {
            let (data, response) = try await performRaw(
                method: "POST", endpoint: "/api/v1/spool/\(spoolId)/tag", baseUrl: baseUrl, body: ["uid": uid]
            )
            switch response.statusCode {
            case 200...299:
                return .linked
            case 409:
                return Self.conflictOutcome(from: data)
            default:
                return .failed(tagAPIError(data: data, status: response.statusCode, mimeType: response.mimeType))
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// A 409's body names whatever holds the tag: a spool or, since filament
    /// tags (spec 4), a filament.
    static func conflictOutcome(from data: Data) -> TagLinkOutcome {
        let conflict = try? JSONDecoder().decode(TagConflictBody.self, from: data)
        if let id = conflict?.spoolId { return .heldBySpool(id) }
        if let id = conflict?.filamentId { return .heldByFilament(id) }
        return .failed(conflict?.message ?? "That tag is already linked elsewhere in Spoolman.")
    }

    /// `POST /api/v1/filament/{id}/tag` (spec 4); answers like a spool's.
    func linkFilamentTag(filamentId: Int, uid: String, baseUrl: String) async -> TagLinkOutcome {
        do {
            let (data, response) = try await performRaw(
                method: "POST", endpoint: "/api/v1/filament/\(filamentId)/tag", baseUrl: baseUrl, body: ["uid": uid]
            )
            switch response.statusCode {
            case 200...299:
                return .linked
            case 409:
                return Self.conflictOutcome(from: data)
            default:
                return .failed(tagAPIError(data: data, status: response.statusCode, mimeType: response.mimeType))
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// `DELETE /api/v1/filament/{id}/tag/{uid}`; Spoolman's own 404 means the
    /// link is already gone.
    func unlinkFilamentTag(filamentId: Int, uid: String, baseUrl: String) async -> TagUnlinkOutcome {
        do {
            let (data, response) = try await performRaw(
                method: "DELETE", endpoint: "/api/v1/filament/\(filamentId)/tag/\(uid)", baseUrl: baseUrl
            )
            if (200...299).contains(response.statusCode) { return .unlinked }
            if response.statusCode == 404, Self.hasSpoolmanMessage(data) { return .unlinked }
            return .failed(tagAPIError(data: data, status: response.statusCode, mimeType: response.mimeType))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// `DELETE /api/v1/spool/{id}/tag/{uid}`. A 404 that Spoolman words
    /// itself means the link is already gone, which is the outcome asked for.
    func unlinkTag(spoolId: Int, uid: String, baseUrl: String) async -> TagUnlinkOutcome {
        do {
            let (data, response) = try await performRaw(
                method: "DELETE", endpoint: "/api/v1/spool/\(spoolId)/tag/\(uid)", baseUrl: baseUrl
            )
            if (200...299).contains(response.statusCode) { return .unlinked }
            if response.statusCode == 404, Self.hasSpoolmanMessage(data) { return .unlinked }
            return .failed(tagAPIError(data: data, status: response.statusCode, mimeType: response.mimeType))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Spoolman answers its own 404s with `{"message": …}`; a missing ROUTE is
    /// FastAPI's `{"detail": "Not Found"}` — a server that claims 0.27 and has
    /// no tag API (a fork). That must never read as success. An HTML 404 is a
    /// proxy's or a wrong path's page, which says nothing about the tag API.
    private func tagAPIError(data: Data, status: Int, mimeType: String?) -> String {
        if status == 404, !ServerResponseCheck.isWebPage(mimeType: mimeType), !Self.hasSpoolmanMessage(data) {
            return "Spoolman reports version \(serverInfo?.version ?? "?") but has no tag API."
        }
        return Self.errorText(data: data, status: status, mimeType: mimeType)
    }

    nonisolated static func hasSpoolmanMessage(_ data: Data) -> Bool {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["message"] is String
    }

    /// Re-reads one spool after a write, so the cache never outlives a change
    /// another writer (the printer) may have made meanwhile. Only Spoolman's
    /// own 404 drops the spool; a proxy's page leaves the cache alone.
    func refetchSpool(id: Int, baseUrl: String) async {
        do {
            let (data, response) = try await performRaw(method: "GET", endpoint: "/api/v1/spool/\(id)", baseUrl: baseUrl)
            if response.statusCode == 404, Self.hasSpoolmanMessage(data) {
                spools.removeAll { $0.id == id }
                return
            }
            guard (200...299).contains(response.statusCode) else { return }
            let spool = try JSONDecoder().decode(Spool.self, from: data)
            if let index = spools.firstIndex(where: { $0.id == id }) {
                spools[index] = spool
            } else {
                spools.append(spool)
            }
        } catch {
            logger.error("Spool \(id, privacy: .public) refetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func sendRequest<T: Decodable>(method: String, endpoint: String, baseUrl: String, body: [String: Any]? = nil) async throws -> T {
        let data = try await perform(method: method, endpoint: endpoint, baseUrl: baseUrl, body: body)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func sendRequestWithoutDecoding(method: String, endpoint: String, baseUrl: String, body: [String: Any]? = nil) async throws {
        _ = try await perform(method: method, endpoint: endpoint, baseUrl: baseUrl, body: body)
    }

    private func sendDeleteRequest(endpoint: String, baseUrl: String) async throws {
        _ = try await perform(method: "DELETE", endpoint: endpoint, baseUrl: baseUrl)
    }

    // Vendors
    func addVendor(
        draft: VendorDraft,
        baseUrl: String
    ) async -> Vendor? {
        self.errorMessage = nil
        do {
            let body = SpoolmanPayloadBuilder.vendorPayload(from: draft)
            let newVendor: Vendor = try await sendRequest(method: "POST", endpoint: "/api/v1/vendor", baseUrl: baseUrl, body: body)
            self.vendors.append(newVendor)
            self.errorMessage = nil
            return newVendor
        } catch {
            self.errorMessage = error.localizedDescription
            return nil
        }
    }

    func addVendor(name: String, baseUrl: String) async -> Vendor? {
        await addVendor(draft: VendorDraft(name: name), baseUrl: baseUrl)
    }

    @discardableResult
    func updateVendor(
        id: Int,
        draft: VendorDraft,
        baseUrl: String
    ) async -> Bool {
        self.errorMessage = nil
        do {
            let body = SpoolmanPayloadBuilder.vendorPayload(from: draft)
            let updatedVendor: Vendor = try await sendRequest(method: "PATCH", endpoint: "/api/v1/vendor/\(id)", baseUrl: baseUrl, body: body)
            if let index = self.vendors.firstIndex(where: { $0.id == id }) {
                self.vendors[index] = updatedVendor
            }
            self.errorMessage = nil
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }
    
    @discardableResult
    func deleteVendor(id: Int, baseUrl: String) async -> Bool {
        do {
            try await sendDeleteRequest(endpoint: "/api/v1/vendor/\(id)", baseUrl: baseUrl)
            self.vendors.removeAll { $0.id == id }
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }
    
    // Filaments
    func addFilament(
        draft: FilamentDraft,
        baseUrl: String
    ) async -> Filament? {
        self.errorMessage = nil

        var body = SpoolmanPayloadBuilder.filamentPayload(from: draft)
        let td = await transmissionDistanceExtra(for: draft, baseUrl: baseUrl) { [:] }
        if let extra = td.extra { body["extra"] = extra }

        do {
            let newFilament: Filament = try await sendRequest(method: "POST", endpoint: "/api/v1/filament", baseUrl: baseUrl, body: body)
            self.filaments.append(newFilament)
            // A half-stated multi-colour pair is refused by the builder rather
            // than 422-ing the whole create. Reported, not dropped.
            self.errorMessage = SaveOutcome.combinedNote([
                SpoolmanPayloadBuilder.droppedMultiColorNote(
                    hexes: draft.multiColorHexes, direction: draft.multiColorDirection
                ),
                td.note
            ])
            return newFilament
        } catch {
            self.errorMessage = error.localizedDescription
            return nil
        }
    }
    
    @discardableResult
    func updateFilament(
        id: Int,
        draft: FilamentDraft,
        baseUrl: String
    ) async -> Bool {
        self.errorMessage = nil

        // No `clearFieldKeys` pass: every clearable `FilamentDraft` field
        // carries its own patch value and the builder emits the `NSNull()`
        // itself. The wire output is unchanged — these were always Spoolman's
        // key names, which is exactly why every OTHER backend had to
        // translate them and FilaMan never did (R21 stage 4).
        var body = SpoolmanPayloadBuilder.filamentPayload(from: draft)
        // Fresh, not the cache: the PATCH replaces `extra`, so a key another
        // client added since the last fetch would otherwise be lost.
        let td = await transmissionDistanceExtra(for: draft, baseUrl: baseUrl) {
            let current: Filament = try await self.sendRequest(method: "GET", endpoint: "/api/v1/filament/\(id)", baseUrl: baseUrl)
            return current.extra ?? [:]
        }
        if let extra = td.extra { body["extra"] = extra }

        do {
            let updatedFilament: Filament = try await sendRequest(method: "PATCH", endpoint: "/api/v1/filament/\(id)", baseUrl: baseUrl, body: body)
            if let index = self.filaments.firstIndex(where: { $0.id == id }) {
                self.filaments[index] = updatedFilament
            }
            self.errorMessage = SaveOutcome.combinedNote([
                SpoolmanPayloadBuilder.droppedMultiColorNote(
                    hexes: draft.multiColorHexes, direction: draft.multiColorDirection
                ),
                td.note
            ])
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }
    
    @discardableResult
    func deleteFilament(id: Int, baseUrl: String) async -> Bool {
        do {
            try await sendDeleteRequest(endpoint: "/api/v1/filament/\(id)", baseUrl: baseUrl)
            self.filaments.removeAll { $0.id == id }
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }
    
    // Spools
    func addSpool(
        draft: SpoolDraft,
        baseUrl: String
    ) async -> Spool? {
        self.errorMessage = nil

        let body = SpoolmanPayloadBuilder.spoolPayload(from: draft)

        do {
            let newSpool: Spool = try await sendRequest(method: "POST", endpoint: "/api/v1/spool", baseUrl: baseUrl, body: body)
            self.spools.append(newSpool)
            self.errorMessage = nil
            return newSpool
        } catch {
            self.errorMessage = error.localizedDescription
            return nil
        }
    }
    
    @discardableResult
    func updateSpool(
        id: Int,
        draft: SpoolDraft,
        baseUrl: String
    ) async -> Bool {
        self.errorMessage = nil

        // No `clearFieldKeys` pass: every clearable `SpoolDraft` field carries
        // its own patch value, and the builder emits the `NSNull()` (R21).
        let body = SpoolmanPayloadBuilder.spoolPayload(from: draft)

        do {
            let updatedSpool: Spool = try await sendRequest(method: "PATCH", endpoint: "/api/v1/spool/\(id)", baseUrl: baseUrl, body: body)
            if let index = self.spools.firstIndex(where: { $0.id == id }) {
                self.spools[index] = updatedSpool
            }
            self.errorMessage = nil
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }
    
    /// The spool the given card UID resolves to: a native tag holder first,
    /// then the first spool whose `card_uids` contains it.
    /// Searches the in-memory `spools` array; call `fetchSpools` first to
    /// ensure it is current.
    func findSpool(byCardUID uid: String) -> Spool? {
        SpoolMappingService.spool(in: spools, claiming: uid)
    }

    /// Replaces the SpoolLink `card_uids` extra field for a spool via a PATCH request.
    /// `uids` is the whole list; callers compute the desired list (append/remove)
    /// from `Spool.writableCardUIDs`, never `mappedCardUIDs`, which carries FilaMan's
    /// `rfid_uid` (FR-2). An empty list encodes as the SpoolLink empty value `"\"\""`.
    @discardableResult
    func setCardUIDs(spoolId: Int, uids: [String], baseUrl: String) async -> Bool {
        do {
            let updated: Spool = try await sendRequest(
                method: "PATCH",
                endpoint: "/api/v1/spool/\(spoolId)",
                baseUrl: baseUrl,
                body: ["extra": ["card_uids": CardUIDsCodec.encode(uids)]]
            )
            if let index = spools.firstIndex(where: { $0.id == spoolId }) {
                spools[index] = updated
            }
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func renameLocation(currentName: String, newName: String, baseUrl: String) async -> Bool {
        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "/")

        guard let encoded = currentName.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
            return false
        }

        do {
            try await sendRequestWithoutDecoding(
                method: "PATCH",
                endpoint: "/api/v1/location/\(encoded)",
                baseUrl: baseUrl,
                body: ["name": newName]
            )
            await fetchSpools(baseUrl: baseUrl)
            await fetchLocations(baseUrl: baseUrl)
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    /// Deletes a location by clearing it from every spool that uses it. Spoolman
    /// has no standalone location entity, so a location disappears once no spool
    /// references it.
    @discardableResult
    func deleteLocation(_ name: String, baseUrl: String) async -> Bool {
        let affected = spools.filter { $0.location == name }
        var allCleared = true
        for spool in affected {
            do {
                let updated: Spool = try await sendRequest(
                    method: "PATCH",
                    endpoint: "/api/v1/spool/\(spool.id)",
                    baseUrl: baseUrl,
                    body: ["location": NSNull()]
                )
                if let index = spools.firstIndex(where: { $0.id == spool.id }) {
                    spools[index] = updated
                }
            } catch {
                self.errorMessage = error.localizedDescription
                allCleared = false
            }
        }
        await fetchLocations(baseUrl: baseUrl)
        return allCleared
    }

    @discardableResult
    func deleteSpool(id: Int, baseUrl: String) async -> Bool {
        do {
            try await sendDeleteRequest(endpoint: "/api/v1/spool/\(id)", baseUrl: baseUrl)
            self.spools.removeAll { $0.id == id }
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func setSpoolArchived(id: Int, archived: Bool, baseUrl: String) async -> Bool {
        self.errorMessage = nil
        let body: [String: Any] = ["archived": archived]
        do {
            let updated: Spool = try await sendRequest(method: "PATCH", endpoint: "/api/v1/spool/\(id)", baseUrl: baseUrl, body: body)
            if let index = self.spools.firstIndex(where: { $0.id == id }) {
                self.spools[index] = updated
            }
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    private func fetchData<T: Decodable>(endpoint: String, baseUrl: String, completion: @escaping ([T]) -> Void) async {
        self.isLoading = true
        self.errorMessage = nil

        do {
            let data = try await perform(method: "GET", endpoint: endpoint, baseUrl: baseUrl)
            let decodedItems = try JSONDecoder().decode([T].self, from: data)
            completion(decodedItems)
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }
}

/// Why Spoolman asked for a new sign-in; the UI shows it as an alert.
nonisolated struct SpoolmanSignedOutNotice: Identifiable, Equatable {
    let id = UUID()
    let issuerHost: String
}

/// Keeps the Authorization header off any request a redirect sends somewhere
/// other than the Spoolman origin.
nonisolated final class SpoolmanRedirectGuard: NSObject, URLSessionTaskDelegate {
    private let baseUrl: String

    init(baseUrl: String) {
        self.baseUrl = baseUrl
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(SpoolmanService.redirect(request, baseUrl: baseUrl))
    }
}
