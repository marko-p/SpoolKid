//
//  BackendFieldSupport.swift
//  SpoolKid
//
//  Purpose: Which fields a backend actually HAS, as data — separate from
//  whether the user wants to see them.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// One entity's worth of support: the IDs this backend has.
///
/// A per-backend label/section override (`FieldOverride`) lived here until
/// 2026-09-28. Its last entry, FilaMan's "Manufacturer" for `vendor_id`, went
/// when every backend's base label became "Manufacturer", and an override no
/// backend sets is a declaration with no consumer — the rule that governs
/// `BackendCapabilities` — so the mechanism went with it. Every field renders
/// under its `FieldCatalog` label on every backend.
nonisolated struct EntitySupport: Equatable, Sendable {
    var supportedIDs: Set<String>
}

/// What a backend's field set actually is.
///
/// `FieldCatalog` describes every field SpoolKid knows how to render.
/// Until 2026-08-28 that list was shown on all three backends, so a FilaMan
/// user was offered First Used — a field FilaMan's PATCH accepts, stores
/// nowhere, and does not render in its own UI. This narrows the catalogue to
/// what is really there.
///
/// Reached through `BackendCapabilities.fieldSupport`, never by asking which
/// backend is running.
nonisolated struct BackendFieldSupport: Equatable, Sendable {
    var entities: [LibraryEntity: EntitySupport]

    func supportedIDs(in entity: LibraryEntity) -> Set<String> {
        entities[entity]?.supportedIDs ?? []
    }

    func supports(_ fieldID: String, in entity: LibraryEntity) -> Bool {
        supportedIDs(in: entity).contains(fieldID)
    }

    /// Every field the catalogue holds, for a backend that has them all.
    /// Both tables start here; Tasks 4 and 6 take fields away from `.filaman`.
    private static func wholeCatalog() -> [LibraryEntity: EntitySupport] {
        var entities: [LibraryEntity: EntitySupport] = [:]
        for entity in LibraryEntity.allCases {
            entities[entity] = EntitySupport(
                supportedIDs: Set(FieldCatalog.fields(for: entity).map(\.id))
            )
        }
        return entities
    }

    /// Local AND Spoolman. `LocalSpool`, `LocalFilament` and `LocalVendor`
    /// mirror Spoolman's model field for field, so one table serves both —
    /// and sharing it is the assertion that this stays true.
    static let spoolmanShaped: BackendFieldSupport = {
        var entities = wholeCatalog()
        // Native to FilaMan only. Spoolman has an archived boolean instead of
        // a status, and no external id or purchase date on a spool.
        entities[.spool]?.supportedIDs.subtract(["status", "external_id", "purchase_date"])
        return BackendFieldSupport(entities: entities)
    }()

    /// Measured against a live FilaMan instance on 2026-08-28 rather than read
    /// off a schema — a route inventory tells you a key is accepted, not that
    /// it is kept. `first_used` / `last_used` are the case in point: PATCH
    /// answers 200 and stores neither.
    ///
    /// The four fields SpoolKid used to emulate inside `custom_fields`
    /// (`comment`, `article_number`, the two temperatures) leave with the
    /// rest. Owner decision, 2026-08-28, taken with the counts stated: 46 of
    /// 50 filaments carry an emulated comment that FilaMan's own Admin Panel
    /// does not render either. Those rows stay in FilaMan's database and
    /// become unreachable from any UI. Nothing here deletes them.
    static let filaman: BackendFieldSupport = {
        var entities = wholeCatalog()

        entities[.spool]?.supportedIDs.subtract([
            "used_weight", "comment", "first_used", "last_used",
            // Archived is a VALUE of Status on FilaMan, not a field of its own.
            // The picker replaces the toggle; exactly one reaches the form.
            "archived"
        ])

        entities[.filament]?.supportedIDs.subtract([
            "comment", "article_number", "settings_extruder_temp", "settings_bed_temp",
            "external_id"
        ])

        entities[.vendor]?.supportedIDs.subtract(["comment", "external_id"])

        return BackendFieldSupport(entities: entities)
    }()
}
