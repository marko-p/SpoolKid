//
//  ServerAddress.swift
//  SpoolKid
//
//  Purpose: The one rule for a typed server address (Spoolman, FilaMan). It
//  normalises what a person typed to a base URL (adds http://, drops trailing
//  slashes and a trailing /api/v1), refuses what no server could use (other
//  schemes, no host, a query, a fragment, a user name or password), and builds
//  request URLs from it. A clean address (lowercase scheme, no surrounding
//  whitespace, no trailing slash, no /api/v1) builds byte-identical URLs to
//  plain "\(address)\(endpoint)" concatenation. `identity(of:)` equals the tag
//  ledger's old trim/lowercase/strip-slash rule for any address containing
//  "://" except one ending in /api/v1, which never reached a server. Ledger rows
//  can still change scope in two cases, both healed as tags are re-scanned:
//  a scheme-less address gains "http://" (it never reached a server, but a tag
//  write records its spool id without contacting one), and an address with
//  user:pass@ is now refused, so once the credentials are removed its rows sit
//  under the old key. The typed text itself is never rewritten.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum ServerAddressProblem: Error, LocalizedError, Equatable, Sendable {
    case empty
    case unsupportedScheme
    case noHost
    case hasQuery
    case hasFragment
    case hasCredentials
    case invalid

    var message: String {
        switch self {
        case .empty: "No server address is set."
        case .unsupportedScheme: "Use an address that starts with http:// or https://."
        case .noHost: "That address has no server name."
        case .hasQuery: "Remove the part from \"?\" on. A server address has no query."
        case .hasFragment: "Remove the part from \"#\" on."
        case .hasCredentials: "Remove the user name and password from the address. Use the sign-in fields below instead."
        case .invalid: "SpoolKid can't use that address."
        }
    }

    var errorDescription: String? { message }
}

/// What a form shows under an address field while the person types.
nonisolated enum ServerAddressHint: Equatable, Sendable {
    case problem(String)
    case connectsTo(String)
}

nonisolated struct ServerAddress: Equatable, Sendable {
    /// The normalised base, e.g. `http://192.168.1.10:7912`.
    let text: String

    var isSecure: Bool { text.hasPrefix("https://") }

    static func parse(_ typed: String) -> Result<ServerAddress, ServerAddressProblem> {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .failure(.empty) }
        if isSchemeTypo(trimmed.lowercased()) { return .failure(.unsupportedScheme) }
        guard var components = URLComponents(string: normalisedText(typed)) else { return .failure(.invalid) }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .failure(.unsupportedScheme)
        }
        guard let host = components.host, !host.isEmpty else { return .failure(.noHost) }
        if components.query != nil { return .failure(.hasQuery) }
        if components.fragment != nil { return .failure(.hasFragment) }
        if components.user != nil || components.password != nil { return .failure(.hasCredentials) }
        components.scheme = scheme
        guard let text = components.string else { return .failure(.invalid) }
        return .success(ServerAddress(text: text))
    }

    /// Plain concatenation, never a `percentEncodedPath` assignment (it traps on
    /// "?"): that is what keeps a clean address's URLs byte-identical to
    /// `"\(address)\(endpoint)"`. A fragment in the endpoint would be dropped
    /// from the request, so it is refused.
    func url(endpoint: String) -> URL? {
        guard endpoint.hasPrefix("/"), !endpoint.contains("#") else { return nil }
        return URL(string: text + endpoint)
    }

    static func requestURL(_ baseUrl: String, endpoint: String) throws -> URL {
        let address = try parse(baseUrl).get()
        guard let url = address.url(endpoint: endpoint) else { throw ServerAddressProblem.invalid }
        return url
    }

    /// The ledger scope for a server: equivalent typings of one server share it.
    /// For an address containing "://" it is the old trim/lowercase/strip-slash
    /// key, except that a trailing /api/v1 is also dropped.
    static func identity(of typed: String) -> String {
        normalisedText(typed).lowercased()
    }

    /// Quiet while the person is still typing a scheme, so "h" or "http:/"
    /// never flashes a problem or a "connects to" line.
    static func hint(for typed: String) -> ServerAddressHint? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let lowered = trimmed.lowercased()
        if "http://".hasPrefix(lowered) || "https://".hasPrefix(lowered) { return nil }
        switch parse(typed) {
        case .failure(let problem): return .problem(problem.message)
        case .success(let address): return address.text == trimmed ? nil : .connectsTo(address.text)
        }
    }

    static func isUsable(_ typed: String) -> Bool {
        if case .success = parse(typed) { return true }
        return false
    }

    private static func normalisedText(_ typed: String) -> String {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return text }
        if !text.contains("://") { text = "http://" + text }
        stripTrailingSlashes(&text)
        // Only when a host remains: "http://api/v1" is host "api", not a base
        // "http:/" with the API path on it.
        if let suffix = text.range(of: "/api/v1", options: [.caseInsensitive, .backwards, .anchored]) {
            var rest = text
            rest.removeSubrange(suffix)
            stripTrailingSlashes(&rest)
            if let scheme = rest.range(of: "://"), scheme.upperBound < rest.endIndex { text = rest }
        }
        return text
    }

    /// "http:/h", "http//h" or "http:7912" would otherwise gain "http://" and
    /// read as a host named "http". Whether typing a scheme is still in progress
    /// is `hint(for:)`'s question, not this one.
    private static func isSchemeTypo(_ lowered: String) -> Bool {
        !lowered.contains("://") && ["http:", "https:", "http/", "https/"].contains { lowered.hasPrefix($0) }
    }

    private static func stripTrailingSlashes(_ text: inout String) {
        while text.hasSuffix("/") { text.removeLast() }
    }
}
