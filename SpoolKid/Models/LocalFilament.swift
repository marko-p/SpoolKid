//
//  LocalFilament.swift
//  SpoolKid
//
//  Purpose: SwiftData model for the on-device local store — a filament
//  definition. Field-for-field faithful to `Filament`. `vendor` is an
//  optional to-one relationship (mirrors Spoolman, where a filament's vendor is
//  optional). `serverId` / `updatedAt` / `isDirty` are sync metadata, dormant
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
final class LocalFilament {
    @Attribute(.unique) var id: UUID
    /// Persistent, monotonic local id (the DTO `id`). Has a default so adding it
    /// is a SwiftData lightweight migration — an existing store opens without a
    /// reset. New rows always get a real allocated id from `LocalIdSequence`.
    var localId: Int = 0
    /// Spoolman server id once this row has been synced; nil for local-only rows.
    var serverId: Int?

    var name: String?
    var material: String?
    var price: Double?
    var colorHex: String?
    var density: Double?
    var diameter: Double?
    var weight: Double?
    var spoolWeight: Double?
    var articleNumber: String?
    var comment: String?
    var settingsExtruderTemp: Int?
    var settingsBedTemp: Int?
    var multiColorHexes: String?
    var multiColorDirection: String?
    var externalId: String?
    var extra: [String: String]?

    var updatedAt: Date
    var isDirty: Bool

    var vendor: LocalVendor?

    // Inverse declared here only. Deleting a filament cascades to its spools —
    // a spool cannot exist without a filament.
    @Relationship(deleteRule: .cascade, inverse: \LocalSpool.filament)
    var spools: [LocalSpool] = []

    init(
        id: UUID = UUID(),
        localId: Int,
        serverId: Int? = nil,
        name: String? = nil,
        material: String? = nil,
        price: Double? = nil,
        colorHex: String? = nil,
        density: Double? = nil,
        diameter: Double? = nil,
        weight: Double? = nil,
        spoolWeight: Double? = nil,
        articleNumber: String? = nil,
        comment: String? = nil,
        settingsExtruderTemp: Int? = nil,
        settingsBedTemp: Int? = nil,
        multiColorHexes: String? = nil,
        multiColorDirection: String? = nil,
        externalId: String? = nil,
        extra: [String: String]? = nil,
        vendor: LocalVendor? = nil,
        updatedAt: Date = .now,
        isDirty: Bool = false
    ) {
        self.id = id
        self.localId = localId
        self.serverId = serverId
        self.name = name
        self.material = material
        self.price = price
        self.colorHex = colorHex
        self.density = density
        self.diameter = diameter
        self.weight = weight
        self.spoolWeight = spoolWeight
        self.articleNumber = articleNumber
        self.comment = comment
        self.settingsExtruderTemp = settingsExtruderTemp
        self.settingsBedTemp = settingsBedTemp
        self.multiColorHexes = multiColorHexes
        self.multiColorDirection = multiColorDirection
        self.externalId = externalId
        self.extra = extra
        self.vendor = vendor
        self.updatedAt = updatedAt
        self.isDirty = isDirty
    }
}
