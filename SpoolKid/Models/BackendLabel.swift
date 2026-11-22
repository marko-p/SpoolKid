//
//  BackendLabel.swift
//  SpoolKid
//
//  Purpose: The QR code on a label printed by Spoolman or FilaMan — which
//  backend printed it, and which record it names. Spoolman prints
//  `WEB+SPOOLMAN:S-<id>` / `F-<id>`, or (its "URL" label option) its own
//  `/spool/show/<id>` and `/filament/show/<id>` pages; FilaMan prints its
//  `/spools/<id>` page. A URL counts only on the host of a configured server,
//  so a shop's web page with a similar path stays a web URL.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct BackendLabel: Equatable, Sendable {
    nonisolated enum Origin: Equatable, Sendable {
        case spoolman
        case filaman

        var displayName: String {
            switch self {
            case .spoolman: "Spoolman"
            case .filaman: "FilaMan"
            }
        }
    }

    nonisolated enum Record: Equatable, Sendable {
        case spool(Int)
        case filament(Int)
    }

    let origin: Origin
    let record: Record

    /// The label `payload` encodes, or nil when it is not a backend label.
    /// `spoolmanURL` / `filamanURL` are the configured server addresses
    /// (empty when not set up).
    static func parse(_ payload: String, spoolmanURL: String, filamanURL: String) -> BackendLabel? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "WEB+SPOOLMAN:"
        if trimmed.uppercased().hasPrefix(prefix) {
            let body = trimmed.dropFirst(prefix.count).uppercased()
            guard let id = Int(body.dropFirst(2)), id > 0 else { return nil }
            if body.hasPrefix("S-") { return BackendLabel(origin: .spoolman, record: .spool(id)) }
            if body.hasPrefix("F-") { return BackendLabel(origin: .spoolman, record: .filament(id)) }
            return nil
        }

        guard let url = URLComponents(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        let path = url.path.split(separator: "/").map(String.init)

        if sameServer(url, spoolmanURL), path.count >= 3, path[path.count - 2] == "show",
           let id = Int(path[path.count - 1]), id > 0 {
            switch path[path.count - 3] {
            case "spool": return BackendLabel(origin: .spoolman, record: .spool(id))
            case "filament": return BackendLabel(origin: .spoolman, record: .filament(id))
            default: break
            }
        }
        if sameServer(url, filamanURL), path.count >= 2, let id = Int(path[path.count - 1]), id > 0 {
            switch path[path.count - 2] {
            case "spools": return BackendLabel(origin: .filaman, record: .spool(id))
            case "filaments": return BackendLabel(origin: .filaman, record: .filament(id))
            default: break
            }
        }
        return nil
    }

    /// Same host (case-insensitive) and port as the configured address. A
    /// configured address without a scheme is read as http, as the
    /// connection form does.
    private static func sameServer(_ url: URLComponents, _ configured: String) -> Bool {
        let raw = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty,
              let server = URLComponents(string: raw.contains("://") ? raw : "http://\(raw)"),
              let host = server.host?.lowercased(), !host.isEmpty,
              url.host?.lowercased() == host
        else { return false }
        return port(of: url) == port(of: server)
    }

    private static func port(of url: URLComponents) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
    }
}
