//
//  PrinterCredentials.swift
//  SpoolKid
//
//  Purpose: How the app signs in to a printer's Moonraker, kept in the
//  Keychain. Scoped to one address, so a token never reaches another printer.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct PrinterCredentials: Codable, Equatable, Sendable {
    var address: String
    var token: String?
    var refreshToken: String?
    var apiKey: String?

    /// What `server.connection.identify` carries. Moonraker reads the token
    /// first, so only one is sent.
    var identifyFields: [String: String] {
        if let token { return ["access_token": token] }
        if let apiKey { return ["api_key": apiKey] }
        return [:]
    }

    /// For the plain HTTP read of the firmware's config.
    var httpHeaders: [String: String] {
        if let token { return ["Authorization": "Bearer \(token)"] }
        if let apiKey { return ["X-Api-Key": apiKey] }
        return [:]
    }

    /// Nil unless stored for this address.
    static func decode(_ json: String?, address: String) -> PrinterCredentials? {
        guard let json, let stored = try? JSONDecoder().decode(PrinterCredentials.self, from: Data(json.utf8)),
              ServerAddress.identity(of: stored.address) == ServerAddress.identity(of: address) else { return nil }
        return stored
    }

    var encoded: String? {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) }
    }
}
