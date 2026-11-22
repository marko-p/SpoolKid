//
//  LocationRegistryEntry.swift
//  SpoolKid
//
//  Purpose: A location SpoolKid knows about that the backend cannot hold on its
//  own — one with no spools yet, and the stable uuid its NFC tags carry.
//  Device-local by necessity: Spoolman has no location entity, FilaMan's has
//  only `id` and `name`, and the on-device Library has none at all.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import SwiftData

@Model
final class LocationRegistryEntry {
    /// Stable identity written onto tags. Survives every rename, which is what
    /// lets an already-written tag keep resolving.
    var uuid: UUID = UUID()
    /// Last known name. The backend, not this, decides what a location is
    /// called — this is a cache plus the only home for a not-yet-created one.
    var name: String = ""
    /// `BackendKind.rawValue`. Scoped by kind rather than by connection target
    /// so changing a server's address does not orphan the registry.
    var backendKind: String = ""
    /// Hardware UIDs of the tags carrying this location, normalized uppercase
    /// via `SpoolMappingService.normalizeUID`.
    var tagUIDs: [String] = []

    init(uuid: UUID = UUID(), name: String, backendKind: String, tagUIDs: [String] = []) {
        self.uuid = uuid
        self.name = name
        self.backendKind = backendKind
        self.tagUIDs = tagUIDs
    }
}
