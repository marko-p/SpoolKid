//
//  FilaManService.swift
//  SpoolKid
//
//  Purpose: Networking service to interact with FilaMan's native /api/v1/ REST
//  API. Responsibilities:
//  - Sending authenticated requests using FilaMan's own `ApiKey` auth scheme
//    (not Bearer).
//  - Extracting FastAPI-shaped error bodies (`{"detail": …}`) into user-facing
//    messages.
//  - Probing a server address to distinguish FilaMan from Spoolman, and a
//    valid API key from a rejected one, before the user commits to it.
//  - Supporting HTTPS with self-signed certificates when configured.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Combine
import os.log

/// Outcome of probing a server address against `/api/v1/me` (FilaMan-only).
/// Kept as five distinct cases rather than a `Bool` because 401/403 ("this IS
/// FilaMan, but the key is wrong") and 404 ("this is not FilaMan") demand
/// different user-facing messages in the backend picker — collapsing them
/// would tell a user with a typo'd key that their server "does not look like
/// FilaMan," a confidently wrong diagnosis pointing at the wrong fix.
nonisolated enum FilaManProbeResult: Equatable, Sendable {
    case confirmed           // 200 — FilaMan, key valid
    case credentialsRejected // 401/403 — IS FilaMan, key is wrong
    case notFilaMan          // 404 or other conclusive non-FilaMan response
    case unreachable         // transport failure, no HTTP response
    case webPage             // an HTML answer: a sign-in page or a page that is not the API
}

@MainActor
class FilaManService: ObservableObject {
    @Published var errorMessage: String?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SpoolKid",
        category: "FilaManService"
    )

    private var _cachedInsecureSession: URLSession?
    private var _cachedTrustAll: Bool?

    /// The test seam: a session whose configuration carries a stub
    /// `URLProtocol`, so tests drive the real request paths without a network.
    /// When set it wins over the trust-all choice, so the host app's settings
    /// can never send a test to the configured server. Nil in the app.
    private let sessionOverride: URLSession?

    init(session: URLSession? = nil) {
        self.sessionOverride = session
    }

    /// Every request's reachability, for `ServerLinkMonitor`. Nil in tests
    /// that don't look.
    var transportReport: (@MainActor (TransportReport, URL?) -> Void)?

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            let reply = try await session.data(for: request)
            transportReport?(.answered, request.url)
            return reply
        } catch {
            if let failure = ServerFailure.classify(error) { transportReport?(.failed(failure), request.url) }
            throw error
        }
    }

    private var session: URLSession {
        if let sessionOverride { return sessionOverride }
        // FilaMan's OWN flag. This read `AppConfig.trustAllCertsKey` —
        // Spoolman's — until 2026-08-25, a flag no FilaMan user could set (I2).
        let trustAll = BackendCapabilities.filaman.trustsAllCerts
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

    /// Pure precedence rule for FilaMan's `Authorization` header: an explicit
    /// candidate key (typed during setup, not yet saved) always wins over the
    /// stored Keychain key; an empty explicit key is treated as "no candidate"
    /// and falls back to the stored key; no key at all yields no header.
    /// Extracted so this precedence — the entire reason `probeIsFilaMan` takes
    /// an `apiKey` parameter at all (F9) — is unit-testable and cannot silently
    /// invert. FilaMan authenticates with a user API key using its OWN scheme —
    /// NOT Bearer. Verified 2026-08-18: `Bearer` returns 401, `ApiKey` returns 200.
    nonisolated static func authHeader(explicitKey: String?, storedKey: String?) -> String? {
        if let explicitKey, !explicitKey.isEmpty {
            return "ApiKey \(explicitKey)"
        }
        if let storedKey, !storedKey.isEmpty {
            return "ApiKey \(storedKey)"
        }
        return nil
    }

    private func applyAuth(to request: inout URLRequest) {
        let storedKey = KeychainStore.read(account: KeychainStore.filaManAPIKeyAccount)
        if let header = Self.authHeader(explicitKey: nil, storedKey: storedKey) {
            request.setValue(header, forHTTPHeaderField: "Authorization")
        }
    }

    // MARK: - Transport core

    private func perform(method: String, endpoint: String, baseUrl: String, body: [String: Any]? = nil) async throws -> Data {
        let url = try ServerAddress.requestURL(baseUrl, endpoint: endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = method
        applyAuth(to: &request)

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await send(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if ServerResponseCheck.isWebPageInsteadOfData(statusCode: httpResponse.statusCode, mimeType: httpResponse.mimeType) {
            throw NSError(
                domain: "FilaManError",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: ServerResponseCheck.webPageMessage(backendName: "FilaMan")]
            )
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let message = Self.extractErrorMessage(
                from: data, statusCode: httpResponse.statusCode, mimeType: httpResponse.mimeType
            )
            throw NSError(domain: "FilaManError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        return data
    }

    private func sendRequest<T: Decodable>(method: String, endpoint: String, baseUrl: String, body: [String: Any]? = nil) async throws -> T {
        let data = try await perform(method: method, endpoint: endpoint, baseUrl: baseUrl, body: body)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// For endpoints that return no body worth decoding (FilaMan's DELETE
    /// routes all return 204 per its OpenAPI schema, verified live 2026-08-20).
    private func sendRequestWithoutDecoding(method: String, endpoint: String, baseUrl: String, body: [String: Any]? = nil) async throws {
        _ = try await perform(method: method, endpoint: endpoint, baseUrl: baseUrl, body: body)
    }

    // MARK: - Error extraction

    /// FastAPI error shape: `{"detail": …}`, where detail is a string, an
    /// object `{"code", "message"}` (FilaMan's own HTTPExceptions — the 409
    /// refusing a delete is one), or, on 422, a list of `{"msg": …}` objects.
    /// Spoolman uses `message` instead. An HTML body is a proxy's or a web
    /// UI's page, never pasted into a message.
    nonisolated static func extractErrorMessage(from data: Data, statusCode: Int, mimeType: String? = nil) -> String {
        if statusCode == 401 {
            return "FilaMan rejected the API key. Check the key in Library → FilaMan — "
                + "you may need to issue a new one."
        }
        if ServerResponseCheck.isWebPage(mimeType: mimeType) {
            return "Server error \(statusCode)."
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = json["detail"] as? String {
                return detail
            }
            if let message = (json["detail"] as? [String: Any])?["message"] as? String {
                return message
            }
            if let items = json["detail"] as? [[String: Any]] {
                let messages = items.compactMap { $0["msg"] as? String }
                if !messages.isEmpty { return messages.joined(separator: ", ") }
            }
        }
        let body = String(data: data, encoding: .utf8) ?? "No body"
        return "Server error \(statusCode): \(body)"
    }

    // MARK: - Probe

    /// Pure mapping from an HTTP status code returned by `/api/v1/me` to a
    /// `FilaManProbeResult`. Extracted from `probeIsFilaMan` so this decision —
    /// the most consequential logic in this file — is unit-testable without a
    /// live server. `.unreachable` is never produced here: it represents "no
    /// HTTP response was received at all," which by definition carries no
    /// status code to switch on. An HTML answer is `.webPage` whatever its
    /// status: FilaMan's `/me` answers in JSON, so a page proves neither
    /// "FilaMan" nor "not FilaMan".
    nonisolated static func probeResult(statusCode: Int, mimeType: String? = nil) -> FilaManProbeResult {
        if ServerResponseCheck.isWebPage(mimeType: mimeType) { return .webPage }
        switch statusCode {
        case 200: return .confirmed
        case 401, 403: return .credentialsRejected
        default: return .notFilaMan
        }
    }

    /// Distinguishes FilaMan from Spoolman. `/api/v1/me` exists only on FilaMan;
    /// its `/spoolman/api/v1/info` deliberately impersonates Spoolman's info
    /// shape, so that endpoint must NOT be used for identification.
    ///
    /// `apiKey` is an explicit candidate key — during setup the user is typing
    /// a key that has NOT been saved to the Keychain yet, so the probe cannot
    /// rely on `applyAuth`. Pass `nil` to use the stored key.
    ///
    /// An address `ServerAddress` refuses never reaches a server, so it is
    /// `.unreachable`, not `.notFilaMan` — `.notFilaMan` is reserved for a
    /// conclusive response actually received from a server (see the enum's
    /// doc comment); reporting it here would misdiagnose a bad address as "not
    /// FilaMan," exactly what the F10 amendment eliminated for bad credentials.
    func probeIsFilaMan(baseUrl: String, apiKey: String?) async -> FilaManProbeResult {
        let url: URL
        do {
            url = try ServerAddress.requestURL(baseUrl, endpoint: "/api/v1/me")
        } catch {
            errorMessage = error.localizedDescription
            return .unreachable
        }
        var request = URLRequest(url: url)
        let storedKey = KeychainStore.read(account: KeychainStore.filaManAPIKeyAccount)
        if let header = Self.authHeader(explicitKey: apiKey, storedKey: storedKey) {
            request.setValue(header, forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, response) = try await send(request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "The server did not return a valid response."
                return .unreachable
            }
            errorMessage = nil
            return Self.probeResult(statusCode: http.statusCode, mimeType: http.mimeType)
        } catch {
            errorMessage = error.localizedDescription
            return .unreachable
        }
    }

    /// Reachability + credential check, required by `SpoolDataRepository`.
    /// Delegates to `probeIsFilaMan` rather than decoding a typed body: this is
    /// a status-code question (200 vs. anything else), not a response-shape
    /// question, and every FilaMan list endpoint (including `/manufacturers`,
    /// which an earlier version of this method decoded directly) returns a
    /// paginated `{"items": […], ...}` envelope rather than a bare array —
    /// verified against a live 1.2.19 instance 2026-08-19. Decoding here would
    /// have thrown on every real server and surfaced as "connection failed,"
    /// misdirecting the user. `errorMessage` still ends up populated on
    /// failure because `probeIsFilaMan` sets it in its unreachable paths.
    func testConnection(baseUrl: String) async -> Bool {
        await probeIsFilaMan(baseUrl: baseUrl, apiKey: nil) == .confirmed
    }

    /// Lightweight reachability probe for the Library tab's status dot (display
    /// only), mirroring `SpoolmanService.healthCheck`.
    ///
    /// Hits the same `/api/v1/me` as `probeIsFilaMan` but with a short timeout,
    /// and — the reason it exists rather than reusing `probeIsFilaMan` or
    /// `testConnection` — it does NOT mutate `errorMessage`. This runs
    /// unprompted on every appearance and foreground; overwriting the banner
    /// from here would destroy a message the user has not read yet, and
    /// clearing it would hide one.
    ///
    /// Returns the full `FilaManProbeResult` rather than a `Bool` so that
    /// "the key was rejected" is not laundered into "the server is down" here;
    /// callers that only need reachability collapse it themselves.
    func healthCheck(baseUrl: String) async -> FilaManProbeResult {
        guard let url = try? ServerAddress.requestURL(baseUrl, endpoint: "/api/v1/me") else {
            return .unreachable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        applyAuth(to: &request)
        do {
            let (_, response) = try await send(request)
            guard let http = response as? HTTPURLResponse else { return .unreachable }
            return Self.probeResult(statusCode: http.statusCode, mimeType: http.mimeType)
        } catch {
            return .unreachable
        }
    }

    // MARK: - Reads

    /// FilaMan's paginated list shape — every
    /// `/api/v1/{spools,filaments,manufacturers,locations}` GET returns
    /// `{"items": […], "page": Int, "page_size": Int, "total": Int}`, never a
    /// bare array (verified live 2026-08-19).
    ///
    /// `/api/v1/colors` goes through the same `fetchAllPages` (F27) and is the
    /// one endpoint here whose envelope is INFERRED rather than separately
    /// confirmed: its `page`/`page_size` query was verified live 2026-08-21,
    /// and the shape is assumed to match its siblings. If colour resolution
    /// ever fails to decode while the other lists are fine, this assumption is
    /// the first thing to check (review finding M2).
    ///
    /// `total` drives `fetchAllPages`'s loop; `page`/`pageSize` are decoded
    /// for completeness but the loop tracks its own request cursor rather than
    /// trusting the server to echo it back faithfully.
    private struct FilaManListEnvelope<Item: Decodable>: Decodable {
        let items: [Item]
        let page: Int
        let pageSize: Int
        let total: Int

        enum CodingKeys: String, CodingKey {
            case items, page, total
            case pageSize = "page_size"
        }
    }

    /// Highest `page_size` FilaMan's OpenAPI schema allows (verified live
    /// 2026-08-19: `default: 50, maximum: 200`). The server's own default of
    /// 50 is well within reach of a real filament collection — F22 was found
    /// against a 38-spool instance one page short of that default — so every
    /// fetch below requests the maximum up front to minimize round trips, and
    /// still loops for anything larger.
    nonisolated static let maxPageSize = 200

    /// Hard ceiling on how many pages one `fetchAllPages` call will request.
    ///
    /// `fetchAllPages` loops on `while true`, so every termination condition
    /// below is derived from what the server says. A server that keeps
    /// answering with full pages and a `total` that stays ahead of them would
    /// page forever, on the main app's data path. This turns that into a
    /// bounded — if incomplete — fetch.
    ///
    /// 100 × 200 = 20,000 records, orders of magnitude past any real filament
    /// collection (the instance F22 was found against had 38 spools). A cap
    /// within reach of real data would be the truncation it exists to prevent.
    nonisolated static let maxPages = 100

    /// Pure pagination-termination decision: given how many items have been
    /// accumulated so far, the server's reported `total`, how many items the
    /// most recently fetched page actually contained, how many were asked
    /// for, and how many pages have been fetched, should another page be
    /// requested?
    ///
    /// Three ways to stop, in order:
    ///
    /// 1. **An empty page.** Even if `accumulatedCount` has not reached
    ///    `total`, a page with nothing in it ends the loop — the guard against
    ///    a server that OVERSTATES `total`. What was observed beats what was
    ///    claimed.
    /// 2. **The hard cap** (`maxPages`), which no server response can talk
    ///    past.
    /// 3. **Everything accounted for**: `accumulatedCount` has reached `total`
    ///    *and* the last page came back partial.
    ///
    /// That last conjunct is the fix for the opposite error to (1) — a server
    /// that UNDERSTATES `total`. A page that came back FULL is evidence in its
    /// own right: the server handed over every record it was asked for, so
    /// there is no reason to treat it as the last. Believing an understated
    /// `total` truncates the list silently, which is F22's failure mode
    /// exactly — a tag on a record past the cut reports "unmapped" while its
    /// mapping sits on the server.
    ///
    /// The cost is one extra, empty request whenever a collection happens to
    /// be an exact multiple of `pageSize`; (1) then ends it. A spare round
    /// trip is the cheaper error.
    nonisolated static func hasMorePages(
        accumulatedCount: Int,
        total: Int,
        lastPageCount: Int,
        pageSize: Int = maxPageSize,
        pagesFetched: Int = 1
    ) -> Bool {
        guard lastPageCount > 0 else { return false }
        guard pagesFetched < maxPages else { return false }
        if accumulatedCount < total { return true }
        return lastPageCount >= pageSize
    }

    /// One page's path for a list endpoint, with `page`/`page_size` and any
    /// endpoint-specific filters. Sorted by key so the result is stable and
    /// testable.
    nonisolated static func listPath(
        endpoint: String,
        page: Int,
        pageSize: Int = maxPageSize,
        query: [String: String] = [:]
    ) -> String {
        var items = ["page=\(page)", "page_size=\(pageSize)"]
        items += query.keys.sorted().map { "\($0)=\(query[$0]!)" }
        return "\(endpoint)?\(items.joined(separator: "&"))"
    }

    /// Pages through a FilaMan list endpoint until every record is
    /// collected. Without this, `fetchSpools` et al. silently returned only
    /// the first `page_size` (default 50) records — invisible on a small
    /// collection, but a scanned tag on spool #51 would report "unmapped"
    /// even though the mapping exists on the server (F22).
    private func fetchAllPages<Item: Decodable>(
        endpoint: String,
        baseUrl: String,
        query: [String: String] = [:]
    ) async throws -> [Item] {
        var page = 1
        var accumulated: [Item] = []
        while true {
            let envelope: FilaManListEnvelope<Item> = try await sendRequest(
                method: "GET",
                endpoint: Self.listPath(
                    endpoint: endpoint, page: page, pageSize: Self.maxPageSize, query: query
                ),
                baseUrl: baseUrl
            )
            accumulated.append(contentsOf: envelope.items)
            guard Self.hasMorePages(
                accumulatedCount: accumulated.count,
                total: envelope.total,
                lastPageCount: envelope.items.count,
                pageSize: Self.maxPageSize,
                pagesFetched: page
            ) else {
                if page >= Self.maxPages {
                    logger.error(
                        "\(endpoint) hit the \(Self.maxPages)-page fetch cap with \(accumulated.count) records; the list may be truncated."
                    )
                }
                break
            }
            page += 1
        }
        return accumulated
    }

    /// `include_archived=true` is NOT optional polish. FilaMan's spool list
    /// defaults it to `false`, so without it an archived spool leaves the app
    /// entirely: Manage Spools' "Show Archived" toggle filters the fetched
    /// list (`ManageSpoolsView.excludingArchived`), and a row that was never
    /// fetched cannot be shown, opened, or un-archived — the spool could only
    /// be recovered in FilaMan's own web UI (device finding, 2026-08-29).
    /// Spoolman's equivalent (`allow_archived=true`) has always been sent.
    /// Archived spools stay out of the dashboard's numbers because
    /// `DashboardStatsService` filters them itself.
    func fetchSpools(baseUrl: String) async throws -> [FilaManSpool] {
        try await fetchAllPages(
            endpoint: "/api/v1/spools", baseUrl: baseUrl, query: ["include_archived": "true"]
        )
    }

    func fetchFilaments(baseUrl: String) async throws -> [FilaManFilament] {
        try await fetchAllPages(endpoint: "/api/v1/filaments", baseUrl: baseUrl)
    }

    func fetchManufacturers(baseUrl: String) async throws -> [FilaManManufacturer] {
        try await fetchAllPages(endpoint: "/api/v1/manufacturers", baseUrl: baseUrl)
    }

    func fetchLocations(baseUrl: String) async throws -> [FilaManLocation] {
        try await fetchAllPages(endpoint: "/api/v1/locations", baseUrl: baseUrl)
    }

    /// Every colour row, paged. `GET /api/v1/colors` takes `page`/`page_size`
    /// and **no hex filter** (verified live 2026-08-21), so a caller resolving
    /// a hex to a `color_id` has to fetch the whole set and match locally —
    /// which makes the F22 pagination rule load-bearing here, not optional.
    func fetchColors(baseUrl: String) async throws -> [FilaManColor] {
        try await fetchAllPages(endpoint: "/api/v1/colors", baseUrl: baseUrl)
    }

    /// FilaMan's seeded spool states, for the Status picker's labels.
    ///
    /// Not `fetchAllPages`: this endpoint returns a bare JSON array, not the
    /// `{"items": …}` envelope the list endpoints use.
    func fetchSpoolStatuses(baseUrl: String) async throws -> [FilaManSpoolStatus.Option] {
        try await sendRequest(method: "GET", endpoint: "/api/v1/spools/statuses", baseUrl: baseUrl)
    }

    // MARK: - custom_fields read-modify-write

    /// Pure merge: `new` keys are layered onto `existing`, overwriting on
    /// collision, with every other pre-existing key left untouched.
    ///
    /// This is the single guard against a real data-loss bug. Verified live
    /// 2026-08-19: `PATCH /api/v1/spools/{id}` with a `custom_fields` body
    /// REPLACES the object server-side rather than merging —
    ///
    ///     before : {"probe_a":"AAA","probe_b":"BBB"}
    ///     PATCH  : {"custom_fields":{"card_uids":"AABBCCDD"}}
    ///     after  : {"card_uids":"AABBCCDD"}      <-- both prior keys destroyed
    ///
    /// Every spool on a migrated FilaMan instance carries
    /// `custom_fields: {"spoolman_id": N}` linking it back to Spoolman. Any
    /// caller that PATCHes `custom_fields` without first merging destroys that
    /// linkage the first time it writes — silently, one spool per write. This
    /// function is what `patchSpoolCustomFields` uses to avoid that; it is
    /// pure so the guarantee is unit-testable without a network.
    ///
    /// `existing` keeps each value's original JSON type (`spoolman_id` is an
    /// Int on every migrated record), so a merge cannot quietly restring it on
    /// the way back out. `new` is SpoolKid's own keys, which are always strings
    /// — and that asymmetry is why the echo rule below exists.
    ///
    /// **A new value that merely echoes the existing one is not an edit.**
    /// `custom_fields` is the app's `extra` passthrough bucket: the spool form
    /// loads `extra` (a flat `[String: String]`, rendered from this object by
    /// `displayStrings`) and hands the same strings back on save, so every
    /// untouched non-string value arrives here as its own decimal rendering —
    /// `43` leaves as `.int(43)` and comes back as `"43"`. Taking that
    /// literally rewrites the type of every passthrough key on every save,
    /// which is the whole-object-replace data loss this merge exists to
    /// prevent, arriving one type-coercion at a time instead of all at once.
    /// So a `new` string equal to the existing value's `displayString` keeps
    /// the existing value; anything else is a real edit and wins.
    ///
    /// Observed on the owner's instance 2026-08-23: spool 39's
    /// `spoolman_id` came back as `"43"` after a form save. FilaMan itself
    /// preserves types exactly — probed live the same day, ints, strings and
    /// bools all round-trip — so the restring was SpoolKid's.
    ///
    /// The merge is additive: leaving a key out means "keep whatever is
    /// there", so it cannot delete one. It had a `removing:` parameter for
    /// that (R21); its only caller went with the emulated custom fields on
    /// 2026-08-28 and the parameter was removed on 2026-09-24. A future
    /// clearable `custom_fields` key needs a delete path of its own again.
    nonisolated static func mergedCustomFields(
        existing: [String: FilaManJSONValue]?,
        new: [String: String]
    ) -> [String: FilaManJSONValue] {
        var merged = existing ?? [:]
        for (key, value) in new {
            if let current = merged[key], current.displayString == value { continue }
            merged[key] = .string(value)
        }
        return merged
    }

    /// Records a scale reading against a spool:
    /// `POST /api/v1/spools/{id}/measurements`. FilaMan files this as a
    /// `measurement` event, distinct from the `manual_adjust` its adjustment
    /// endpoint produces — the same distinction its own "Record Weight
    /// Measurement" action makes.
    ///
    /// FilaMan sets the remaining weight from the reading itself
    /// (`measured − tara`), so this needs no current-value read and no delta
    /// arithmetic, and it supersedes any re-base a basis change in the same
    /// save caused (F32).
    ///
    /// One caveat the endpoint does not report: if the spool has no
    /// `empty_spool_weight_g` and its filament no `default_spool_weight_g`,
    /// FilaMan records the event with `meta.tara_missing`, returns 200, and
    /// leaves the weight alone. The caller re-reads the spool, so nothing
    /// false is shown — but a `true` here does not prove the weight moved.
    @discardableResult
    /// Returns the event FilaMan wrote, because its `meta` is the only place
    /// that says whether the measurement was APPLIED or merely RECORDED.
    ///
    /// This used `sendRequestWithoutDecoding` and answered `Bool` until
    /// 2026-08-25, which threw away the one signal distinguishing the two —
    /// see `FilaManMeasurementEvent.taraMissing`.
    func recordMeasurement(
        spoolId: Int, measuredWeight: Double, baseUrl: String
    ) async -> FilaManMeasurementEvent? {
        do {
            let event: FilaManMeasurementEvent = try await sendRequest(
                method: "POST",
                endpoint: "/api/v1/spools/\(spoolId)/measurements",
                baseUrl: baseUrl,
                body: FilaManPayloadBuilder.measurementPayload(measuredWeight: measuredWeight)
            )
            return event
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// A spool's weighing history: `GET /api/v1/spools/{id}/events`, filtered
    /// to the events that are actually measurements.
    ///
    /// `GET /api/v1/spools/{id}/measurements` answers **404** — that route only
    /// accepts POST (probed 2026-09-04). The events route is the read side.
    ///
    /// Returns `[]` rather than throwing on failure: history is decoration on
    /// the weigh loop, and a screen that refuses to weigh because it could not
    /// draw the last reading would be worse than one that draws nothing.
    func fetchMeasurementEvents(spoolId: Int, baseUrl: String) async -> [FilaManSpoolEvent] {
        do {
            let events: [FilaManSpoolEvent] = try await fetchAllPages(
                endpoint: "/api/v1/spools/\(spoolId)/events", baseUrl: baseUrl
            )
            return events.filter { $0.eventType == FilaManSpoolEvent.measurementType }
        } catch {
            logger.error(
                "Failed to read spool \(spoolId, privacy: .public) events: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    // MARK: - System extra fields

    /// The registry key SpoolLink declares, and the label FilaMan's UI shows
    /// for it. The key must match `CardUIDsCodec.fieldKey` byte for byte —
    /// registering `cardUids` would declare a field nothing reads.
    nonisolated static let cardUIDsFieldLabel = "Card UIDs"

    /// Whether `card_uids` still has to be created, given the registry as it
    /// stands. Split out so the decision is testable without a server: the
    /// whole value of this call is that it does nothing the second time.
    ///
    /// Matches on `target_type` as well as `key`, because the registry is
    /// shared by spools and filaments and a `card_uids` on filaments would
    /// otherwise be mistaken for the spool one.
    nonisolated static func needsCardUIDsFieldCreation(
        existing: [FilaManSystemExtraField]
    ) -> Bool {
        !existing.contains { $0.key == CardUIDsCodec.fieldKey && $0.targetType == "spool" }
    }

    /// Declares `card_uids` as a system-wide spool field, so it exists on every
    /// spool rather than only on the ones SpoolKid has mapped, and so a
    /// Spoolman-compatible client reading `GET /spoolman/api/v1/field/spool`
    /// sees it declared.
    ///
    /// Idempotent: reads the registry first and returns without writing when
    /// the field is already there. `POST` is the native route, not the compat
    /// one — the compat plugin serves this path unauthenticated (see the
    /// security note in `filaman-api.md`), and the native registry is what the
    /// Admin Panel lists.
    ///
    /// A FilaMan `custom_fields` write does NOT need this: the object is
    /// free-form and a PATCH creates whatever key it names. Registration is
    /// about visibility and interop, so a failure here must never be reported
    /// as a failure to map a tag.
    func ensureCardUIDsField(baseUrl: String) async throws {
        let existing: [FilaManSystemExtraField] = try await sendRequest(
            method: "GET",
            endpoint: "/api/v1/system-extra-fields?target_type=spool",
            baseUrl: baseUrl
        )

        guard Self.needsCardUIDsFieldCreation(existing: existing) else {
            logger.info("FilaMan card_uids system extra field already exists; skipping bootstrap.")
            return
        }

        try await sendRequestWithoutDecoding(
            method: "POST",
            endpoint: "/api/v1/system-extra-fields",
            baseUrl: baseUrl,
            body: FilaManPayloadBuilder.systemExtraFieldPayload(
                targetType: "spool",
                key: CardUIDsCodec.fieldKey,
                label: Self.cardUIDsFieldLabel
            )
        )
        logger.info("FilaMan card_uids system extra field created.")
    }

    /// Declares `td` as a system-wide numeric filament field, so FilaMan's own
    /// UI shows it. The value itself needs no registration (`custom_fields` is
    /// free-form). Needs `admin:system`; a refusal throws, and the caller
    /// reports it as a caveat.
    func ensureTransmissionDistanceField(baseUrl: String) async throws {
        let existing: [FilaManSystemExtraField] = try await sendRequest(
            method: "GET",
            endpoint: "/api/v1/system-extra-fields?target_type=filament",
            baseUrl: baseUrl
        )
        guard !existing.contains(where: { $0.key == TransmissionDistance.fieldKey && $0.targetType == "filament" })
        else { return }
        try await sendRequestWithoutDecoding(
            method: "POST",
            endpoint: "/api/v1/system-extra-fields",
            baseUrl: baseUrl,
            body: FilaManPayloadBuilder.systemExtraFieldPayload(
                targetType: "filament",
                key: TransmissionDistance.fieldKey,
                label: TransmissionDistance.fieldName,
                fieldType: "number",
                config: ["unit": "mm", "decimal_places": 1]
            )
        )
        logger.info("FilaMan td system extra field created.")
    }

    /// Removes `card_uids` from the system registry AND from every spool that
    /// carries it, mirroring what Spoolman's `DELETE /field/spool/card_uids`
    /// does in one call. FilaMan needs both halves done explicitly: deleting
    /// the registry row leaves the per-record values in `custom_fields`, where
    /// they would keep resolving scans for a feature the user just turned off.
    ///
    /// Returns false if ANY part failed, with `errorMessage` naming what is
    /// left — the caller keeps the teardown pending so it re-offers, which is
    /// only correct if a partial teardown reports itself as unfinished.
    @discardableResult
    func deleteCardUIDsField(baseUrl: String, spoolIds: [Int]) async -> Bool {
        var failures: [String] = []

        do {
            let existing: [FilaManSystemExtraField] = try await sendRequest(
                method: "GET",
                endpoint: "/api/v1/system-extra-fields?target_type=spool",
                baseUrl: baseUrl
            )
            if let row = existing.first(where: {
                $0.key == CardUIDsCodec.fieldKey && $0.targetType == "spool"
            }) {
                try await sendRequestWithoutDecoding(
                    method: "DELETE",
                    endpoint: "/api/v1/system-extra-fields/\(row.id)",
                    baseUrl: baseUrl
                )
            }
        } catch {
            failures.append("the field definition")
        }

        var failedSpools = 0
        for id in spoolIds {
            if await !removeSpoolCustomField(spoolId: id, key: CardUIDsCodec.fieldKey, baseUrl: baseUrl) {
                failedSpools += 1
            }
        }
        if failedSpools > 0 {
            failures.append("\(failedSpools) spool\(failedSpools == 1 ? "" : "s")")
        }

        guard failures.isEmpty else {
            errorMessage = "SpoolLink could not be fully removed: \(failures.joined(separator: " and ")) "
                + "still hold the mapping."
            return false
        }
        errorMessage = nil
        return true
    }

    /// Drops one key from a spool's `custom_fields`, preserving every other
    /// key. Same GET → modify → PATCH shape as `patchSpoolCustomFields`, and
    /// for the same reason: a PATCH replaces the whole object, so anything not
    /// sent back is destroyed.
    @discardableResult
    func removeSpoolCustomField(spoolId: Int, key: String, baseUrl: String) async -> Bool {
        do {
            let current = try await fetchSpool(id: spoolId, baseUrl: baseUrl)
            guard var fields = current.customFields, fields[key] != nil else { return true }
            fields[key] = nil
            let _: FilaManSpool = try await sendRequest(
                method: "PATCH",
                endpoint: "/api/v1/spools/\(spoolId)",
                baseUrl: baseUrl,
                body: FilaManPayloadBuilder.customFieldsPayload(fields)
            )
            return true
        } catch {
            return false
        }
    }

    /// Sets `fields` on a spool's `custom_fields` without disturbing any other
    /// key already there. Reads the spool fresh (never trusts a cached copy,
    /// which could be stale relative to the value on the server), merges
    /// locally via `mergedCustomFields`, then PATCHes the complete object —
    /// GET → merge → PATCH, never a partial PATCH. See `mergedCustomFields`'s
    /// doc comment for why a partial PATCH is a data-loss bug here.
    @discardableResult
    func patchSpoolCustomFields(spoolId: Int, fields: [String: String], baseUrl: String) async -> Bool {
        do {
            let current = try await fetchSpool(id: spoolId, baseUrl: baseUrl)
            let merged = Self.mergedCustomFields(existing: current.customFields, new: fields)
            let body = FilaManPayloadBuilder.customFieldsPayload(merged)
            let _: FilaManSpool = try await sendRequest(
                method: "PATCH", endpoint: "/api/v1/spools/\(spoolId)", baseUrl: baseUrl, body: body
            )
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Writes a spool's tag fields as ONE PATCH: `card_uids` merged into a
    /// freshly read `custom_fields` (only when `cardUIDs` is non-nil, via the
    /// repository's single encoder) and `rfid_uid` per `rfid`. Nothing to
    /// write sends nothing and reports success.
    @discardableResult
    func patchSpoolTags(
        spoolId: Int, cardUIDs: [String]?, rfid: FilaManTagPlan.RFIDChange, baseUrl: String
    ) async -> Bool {
        if cardUIDs == nil, rfid == .keep { return true }
        do {
            var merged: [String: FilaManJSONValue]?
            if let cardUIDs {
                let current = try await fetchSpool(id: spoolId, baseUrl: baseUrl)
                merged = Self.mergedCustomFields(
                    existing: current.customFields, new: FilaManRepository.cardUIDsField(cardUIDs)
                )
            }
            let body = FilaManPayloadBuilder.spoolTagPayload(customFields: merged, rfid: rfid)
            let _: FilaManSpool = try await sendRequest(
                method: "PATCH", endpoint: "/api/v1/spools/\(spoolId)", baseUrl: baseUrl, body: body
            )
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Single-item reads
    //
    // Used by FilaManRepository both to re-read a fresh `custom_fields` object
    // before a merge-protected write (see `mergedCustomFields`'s doc comment —
    // manufacturers and filaments carry the same migration-linkage risk as
    // spools, verified live 2026-08-20: every manufacturer/filament on this
    // instance carries `custom_fields: {"spoolman_id": N, ...}`) and to re-read
    // a spool after a status change, whose response is an event log entry
    // rather than the updated spool (see `setSpoolStatus`).

    func fetchManufacturer(id: Int, baseUrl: String) async throws -> FilaManManufacturer {
        try await sendRequest(method: "GET", endpoint: "/api/v1/manufacturers/\(id)", baseUrl: baseUrl)
    }

    func fetchFilament(id: Int, baseUrl: String) async throws -> FilaManFilament {
        try await sendRequest(method: "GET", endpoint: "/api/v1/filaments/\(id)", baseUrl: baseUrl)
    }

    func fetchSpool(id: Int, baseUrl: String) async throws -> FilaManSpool {
        try await sendRequest(method: "GET", endpoint: "/api/v1/spools/\(id)", baseUrl: baseUrl)
    }

    // MARK: - Manufacturers (vendors) writes

    func createManufacturer(payload: [String: Any], baseUrl: String) async throws -> FilaManManufacturer {
        try await sendRequest(method: "POST", endpoint: "/api/v1/manufacturers", baseUrl: baseUrl, body: payload)
    }

    func updateManufacturer(id: Int, payload: [String: Any], baseUrl: String) async throws -> FilaManManufacturer {
        try await sendRequest(method: "PATCH", endpoint: "/api/v1/manufacturers/\(id)", baseUrl: baseUrl, body: payload)
    }

    /// Without `force`, a manufacturer with filaments is refused with a 409.
    /// With it, FilaMan deletes the manufacturer, its filaments and their
    /// spools — archived ones included — in one commit (measured live
    /// 2026-09-15).
    func deleteManufacturer(id: Int, force: Bool, baseUrl: String) async throws {
        try await sendRequestWithoutDecoding(
            method: "DELETE", endpoint: Self.deleteEndpoint(collection: "manufacturers", id: id, force: force), baseUrl: baseUrl
        )
    }

    nonisolated static func deleteEndpoint(collection: String, id: Int, force: Bool) -> String {
        "/api/v1/\(collection)/\(id)" + (force ? "?force=true" : "")
    }

    // MARK: - Filaments writes

    func createFilament(payload: [String: Any], baseUrl: String) async throws -> FilaManFilament {
        try await sendRequest(method: "POST", endpoint: "/api/v1/filaments", baseUrl: baseUrl, body: payload)
    }

    func updateFilament(id: Int, payload: [String: Any], baseUrl: String) async throws -> FilaManFilament {
        try await sendRequest(method: "PATCH", endpoint: "/api/v1/filaments/\(id)", baseUrl: baseUrl, body: payload)
    }

    /// See `deleteManufacturer`: without `force` a filament with spools is a
    /// 409; with it, the spools go too.
    func deleteFilament(id: Int, force: Bool, baseUrl: String) async throws {
        try await sendRequestWithoutDecoding(
            method: "DELETE", endpoint: Self.deleteEndpoint(collection: "filaments", id: id, force: force), baseUrl: baseUrl
        )
    }

    /// Full REPLACE of a filament's colour list — the only way to write colours
    /// on an EXISTING filament, since `FilamentUpdate` has no `colors` property
    /// (F27/R18). An empty `colors: []` wipes every colour, so callers must skip
    /// this call rather than send an empty body; see `colorsPayload`.
    /// The response echoes the filament, which callers re-read via
    /// `fetchFilament` anyway, so it is discarded here.
    func replaceFilamentColors(id: Int, payload: [String: Any], baseUrl: String) async throws {
        try await sendRequestWithoutDecoding(
            method: "PUT", endpoint: "/api/v1/filaments/\(id)/colors", baseUrl: baseUrl, body: payload
        )
    }

    // MARK: - Colours writes

    /// `POST /api/v1/colors`. Uniqueness is on the (name, hex_code) pair and an
    /// exact-pair duplicate returns 500, so callers must resolve against
    /// `fetchColors` first — resolve-before-create is mandatory here, not an
    /// optimisation.
    func createColor(payload: [String: Any], baseUrl: String) async throws -> FilaManColor {
        try await sendRequest(method: "POST", endpoint: "/api/v1/colors", baseUrl: baseUrl, body: payload)
    }

    // MARK: - Spools writes

    func createSpool(payload: [String: Any], baseUrl: String) async throws -> FilaManSpool {
        try await sendRequest(method: "POST", endpoint: "/api/v1/spools", baseUrl: baseUrl, body: payload)
    }

    func updateSpool(id: Int, payload: [String: Any], baseUrl: String) async throws -> FilaManSpool {
        try await sendRequest(method: "PATCH", endpoint: "/api/v1/spools/\(id)", baseUrl: baseUrl, body: payload)
    }

    /// `/permanent`, not the plain `DELETE /spools/{id}` route — verified live
    /// 2026-08-19/20: the plain route soft-deletes (sets `status_id = 6`,
    /// identical to archiving) and still returns 204, while a GET afterward
    /// still returns 200. `/permanent` actually removes the row (later GET
    /// returns 404).
    func deleteSpoolPermanent(id: Int, baseUrl: String) async throws {
        try await sendRequestWithoutDecoding(method: "DELETE", endpoint: "/api/v1/spools/\(id)/permanent", baseUrl: baseUrl)
    }

    /// Archiving is a status transition, not a field PATCH (`FilaManPayloadBuilder.statusPayload`).
    /// The response body is `SpoolEventResponse` (an event-log entry), not the
    /// updated spool, so this discards it — callers that need the fresh spool
    /// follow up with `fetchSpool`.
    func setSpoolStatus(id: Int, payload: [String: Any], baseUrl: String) async throws {
        try await sendRequestWithoutDecoding(method: "POST", endpoint: "/api/v1/spools/\(id)/status", baseUrl: baseUrl, body: payload)
    }

    /// Remaining weight is event-sourced (`FilaManPayloadBuilder.adjustmentPayload`).
    /// The response is the adjustment event, not the updated spool, and posting
    /// one also flips `status_id` (1 "new" → 2 "opened") — so callers re-read
    /// the spool with `fetchSpool` rather than patching their copy locally.
    func createSpoolAdjustment(spoolId: Int, payload: [String: Any], baseUrl: String) async throws {
        try await sendRequestWithoutDecoding(
            method: "POST", endpoint: "/api/v1/spools/\(spoolId)/adjustments", baseUrl: baseUrl, body: payload
        )
    }

    // MARK: - Locations writes
    //
    // FilaMan locations are first-class entities (full CRUD verified live via
    // its OpenAPI schema 2026-08-20), unlike Spoolman/Local where a location
    // is a free string derived from spools.

    /// `POST /api/v1/locations`. The shared, backend-agnostic spool form treats
    /// a typed location name as a create ("locations are spool-derived"), which
    /// is true on Spoolman and the local store; on FilaMan nothing is derived,
    /// so the entity has to be created explicitly for that promise to hold here
    /// too (plan defect F25/R15).
    func createLocation(payload: [String: Any], baseUrl: String) async throws -> FilaManLocation {
        try await sendRequest(method: "POST", endpoint: "/api/v1/locations", baseUrl: baseUrl, body: payload)
    }

    func updateLocation(id: Int, payload: [String: Any], baseUrl: String) async throws -> FilaManLocation {
        try await sendRequest(method: "PATCH", endpoint: "/api/v1/locations/\(id)", baseUrl: baseUrl, body: payload)
    }

    func deleteLocation(id: Int, baseUrl: String) async throws {
        try await sendRequestWithoutDecoding(method: "DELETE", endpoint: "/api/v1/locations/\(id)", baseUrl: baseUrl)
    }
}
