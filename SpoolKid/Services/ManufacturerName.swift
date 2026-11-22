//
//  ManufacturerName.swift
//  SpoolKid
//
//  Purpose: The one rule for "is this the same manufacturer": trimmed,
//  case-insensitive name equality. Scan resolution, SpoolmanDB import,
//  migration, the filament form and the manufacturer picker all match
//  manufacturers by name through it.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

enum ManufacturerName {
    /// Trimmed and lowercased: two names with the same key are the same
    /// manufacturer.
    nonisolated static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The vendor whose name has `name`'s key; nil for a blank name.
    nonisolated static func vendor(named name: String, in vendors: [Vendor]) -> Vendor? {
        let wanted = key(name)
        guard !wanted.isEmpty else { return nil }
        return vendors.first { key($0.name) == wanted }
    }

    /// One spelling per `ManufacturerName.key` (the first, trimmed), blanks
    /// dropped, A–Z.
    nonisolated static func distinct(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = ManufacturerName.key(trimmed)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The manufacturer a pending name stands for at Save: the backend's own
    /// when one has the name's key (it may have been added meanwhile),
    /// otherwise the one `create` makes from the trimmed name. Nil when the
    /// create fails.
    static func resolve(
        _ name: String,
        in vendors: [Vendor],
        create: (String) async -> Vendor?
    ) async -> Vendor? {
        if let existing = vendor(named: name, in: vendors) { return existing }
        return await create(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
