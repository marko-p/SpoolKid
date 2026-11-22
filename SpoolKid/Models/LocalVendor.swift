//
//  LocalVendor.swift
//  SpoolKid
//
//  Purpose: SwiftData model for the on-device local store — a vendor
//  (manufacturer/brand). Field-for-field faithful to `Vendor` so the
//  later offline-sync milestone and the Spoolman-compatible SaaS need no
//  remapping. `serverId` / `updatedAt` / `isDirty` are sync metadata, dormant
//  until the sync milestone (M3).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import SwiftData

@Model
final class LocalVendor {
    @Attribute(.unique) var id: UUID
    /// Persistent, monotonic local id (the DTO `id`). Has a default so adding it
    /// is a SwiftData lightweight migration — an existing store opens without a
    /// reset. New rows always get a real allocated id from `LocalIdSequence`.
    var localId: Int = 0
    /// Spoolman server id once this row has been synced; nil for local-only rows.
    var serverId: Int?

    var name: String
    var comment: String?
    var emptySpoolWeight: Double?
    var externalId: String?
    var extra: [String: String]?

    var updatedAt: Date
    var isDirty: Bool

    // Inverse declared on the to-many side only. Deleting a vendor leaves its
    // filaments (vendor becomes nil) — Spoolman filament.vendor is optional.
    @Relationship(deleteRule: .nullify, inverse: \LocalFilament.vendor)
    var filaments: [LocalFilament] = []

    init(
        id: UUID = UUID(),
        localId: Int,
        serverId: Int? = nil,
        name: String,
        comment: String? = nil,
        emptySpoolWeight: Double? = nil,
        externalId: String? = nil,
        extra: [String: String]? = nil,
        updatedAt: Date = .now,
        isDirty: Bool = false
    ) {
        self.id = id
        self.localId = localId
        self.serverId = serverId
        self.name = name
        self.comment = comment
        self.emptySpoolWeight = emptySpoolWeight
        self.externalId = externalId
        self.extra = extra
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}
