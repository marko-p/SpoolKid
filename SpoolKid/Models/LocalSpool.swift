//
//  LocalSpool.swift
//  SpoolKid
//
//  Purpose: SwiftData model for the on-device local store — a physical spool
//  instance. Field-for-field faithful to `Spool`. `filament` is an
//  optional to-one relationship at the storage level; the repository guarantees
//  every created spool has a filament, and deleting a filament cascades to its
//  spools. `serverId` / `updatedAt` / `isDirty` are sync metadata, dormant until
//  the sync milestone (M3).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import SwiftData

@Model
final class LocalSpool {
    @Attribute(.unique) var id: UUID
    /// Persistent, monotonic local id (the DTO `id`). Has a default so adding it
    /// is a SwiftData lightweight migration — an existing store opens without a
    /// reset. New rows always get a real allocated id from `LocalIdSequence`.
    var localId: Int = 0
    /// Spoolman server id once this row has been synced; nil for local-only rows.
    var serverId: Int?

    /// When the row was created (Spoolman's `registered`). Optional, so adding
    /// it is a lightweight migration; rows created before it existed stay nil
    /// and never read as recently added.
    var registered: Date?
    var firstUsed: Date?
    var lastUsed: Date?
    var remainingWeight: Double?
    var initialWeight: Double?
    var spoolWeight: Double?
    var usedWeight: Double?
    var price: Double?
    var location: String?
    /// The Lot/Batch field (mirrors Spoolman `lot_nr`). Plain text; tag links
    /// live in `extra["card_uids"]`.
    var lotNr: String?
    var comment: String?
    var archived: Bool?
    var extra: [String: String]?

    var updatedAt: Date
    var isDirty: Bool

    var filament: LocalFilament?

    init(
        id: UUID = UUID(),
        localId: Int,
        serverId: Int? = nil,
        registered: Date? = nil,
        firstUsed: Date? = nil,
        lastUsed: Date? = nil,
        remainingWeight: Double? = nil,
        initialWeight: Double? = nil,
        spoolWeight: Double? = nil,
        usedWeight: Double? = nil,
        price: Double? = nil,
        location: String? = nil,
        lotNr: String? = nil,
        comment: String? = nil,
        archived: Bool? = nil,
        extra: [String: String]? = nil,
        filament: LocalFilament? = nil,
        updatedAt: Date = .now,
        isDirty: Bool = false
    ) {
        self.id = id
        self.localId = localId
        self.serverId = serverId
        self.registered = registered
        self.firstUsed = firstUsed
        self.lastUsed = lastUsed
        self.remainingWeight = remainingWeight
        self.initialWeight = initialWeight
        self.spoolWeight = spoolWeight
        self.usedWeight = usedWeight
        self.price = price
        self.location = location
        self.lotNr = lotNr
        self.comment = comment
        self.archived = archived
        self.extra = extra
        self.filament = filament
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}
