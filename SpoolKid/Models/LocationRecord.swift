//
//  LocationRecord.swift
//  SpoolKid
//
//  Purpose: Value snapshot of a `LocationRegistryEntry`, so views and pure
//  logic never hold a SwiftData model — the same Local*→DTO split
//  `LocalRepository` already uses.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct LocationRecord: Equatable, Sendable, Identifiable {
    let uuid: UUID
    let name: String
    let tagUIDs: [String]

    var id: UUID { uuid }
    var isTagged: Bool { !tagUIDs.isEmpty }
}

/// The one place location names are normalized for comparison. The formula is
/// `FilaManRepository.normalizedLocationKey`'s, lifted so both share it rather
/// than each owning a copy.
nonisolated enum LocationName {
    static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedKey(_ name: String) -> String {
        trimmed(name).lowercased()
    }
}
