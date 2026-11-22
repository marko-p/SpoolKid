//
//  MigrationPlanner.swift
//  SpoolKid
//
//  Purpose: Pure, testable migration planning. Given a snapshot of the local
//  Library and the current Spoolman server state, decides for each local row
//  whether it matches something already on the server (conflict → user chooses
//  reuse/create) or is new (auto-create). No network, no UI, no store access.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// Match-relevant snapshot of a local vendor.
nonisolated struct MigrationLocalVendor {
    let localId: Int
    let name: String
}

/// Match-relevant snapshot of a local filament.
nonisolated struct MigrationLocalFilament {
    let localId: Int
    let vendorLocalId: Int?
    let name: String?
    let material: String?
    let diameter: Double?
    let weight: Double?
}

/// Match-relevant snapshot of a local spool. The filament key is carried along
/// so spool matching needs no cross-lookup.
nonisolated struct MigrationLocalSpool {
    let localId: Int
    let filamentLocalId: Int
    let filamentKey: FilamentMatchKey
}

/// Normalized comparison key for filaments. Strings are trimmed + lowercased;
/// numbers are bucketed to display precision (diameter %.2f, weight %.0f);
/// nil and empty string both normalize to empty.
nonisolated struct FilamentMatchKey: Hashable {
    let manufacturer: String
    let name: String
    let material: String
    let diameterBucket: String
    let weightBucket: String

    init(manufacturer: String?, name: String?, material: String?, diameter: Double?, weight: Double?) {
        self.manufacturer = Self.normalize(manufacturer)
        self.name = Self.normalize(name)
        self.material = Self.normalize(material)
        self.diameterBucket = Self.bucket(diameter, format: "%.2f")
        self.weightBucket = Self.bucket(weight, format: "%.0f")
    }

    init(_ filament: Filament) {
        self.init(
            manufacturer: filament.vendor?.name,
            name: filament.name,
            material: filament.material,
            diameter: filament.diameter,
            weight: filament.weight
        )
    }

    init(_ filament: MigrationLocalFilament, localVendors: [MigrationLocalVendor]) {
        let manufacturer = filament.vendorLocalId.flatMap { id in
            localVendors.first { $0.localId == id }?.name
        }
        self.init(
            manufacturer: manufacturer,
            name: filament.name,
            material: filament.material,
            diameter: filament.diameter,
            weight: filament.weight
        )
    }

    /// Display label derived from the normalized components.
    var label: String {
        [manufacturer, name, material, diameterBucket, weightBucket]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private static func normalize(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func bucket(_ value: Double?, format: String) -> String {
        guard let value else { return "" }
        return String(format: format, value)
    }
}

nonisolated enum MigrationResolution: Equatable, Hashable {
    case create
    case reuse(serverId: Int)
}

nonisolated struct MigrationItem<Candidate: Identifiable> where Candidate.ID == Int {
    let localId: Int
    let label: String
    let candidates: [Candidate]
    var resolution: MigrationResolution
}

nonisolated struct MigrationPlan {
    var vendors: [MigrationItem<Vendor>]
    var filaments: [MigrationItem<Filament>]
    var spools: [MigrationItem<Spool>]

    /// What a filament's create requirements depend on: its own resolution
    /// (only a create is checked) and its manufacturer's (a planned create
    /// stands in for an id). The review screen re-runs the pre-flight when
    /// this changes — the plan itself is not `Equatable`.
    @MainActor
    var resolutions: [MigrationResolution] {
        vendors.map(\.resolution) + filaments.map(\.resolution)
    }

    @MainActor
    var conflictCount: Int {
        vendors.filter { !$0.candidates.isEmpty }.count
        + filaments.filter { !$0.candidates.isEmpty }.count
        + spools.filter { !$0.candidates.isEmpty }.count
    }

    /// Counted by RESOLUTION, not by whether a match exists: a conflict the
    /// user flipped to Create is a create, and deriving this from
    /// `conflictCount` counted it as a reuse.
    @MainActor
    var createCount: Int {
        [vendors.map(\.resolution), filaments.map(\.resolution), spools.map(\.resolution)]
            .joined()
            .filter { $0 == .create }
            .count
    }

    /// The rest — rows that will be linked to a record the server already has,
    /// not uploaded. The Upload button counts creates alone, so this is what
    /// says the linked rows are going somewhere too.
    @MainActor
    var reuseCount: Int {
        vendors.count + filaments.count + spools.count - createCount
    }
}

enum MigrationPlanner {
    static func plan(
        localVendors: [MigrationLocalVendor],
        localFilaments: [MigrationLocalFilament],
        localSpools: [MigrationLocalSpool],
        serverVendors: [Vendor],
        serverFilaments: [Filament],
        serverSpools: [Spool]
    ) -> MigrationPlan {
        MigrationPlan(
            vendors: planVendors(localVendors, against: serverVendors),
            filaments: planFilaments(localFilaments, localVendors: localVendors, against: serverFilaments),
            spools: planSpools(localSpools, against: serverSpools)
        )
    }

    /// The rule that decides whether a local manufacturer IS a server one:
    /// trimmed, case-insensitive name equality. Exposed because the migration
    /// fix sheet resolves a chosen manufacturer name to a local row by the same
    /// rule — a fix that used a different one could create a local vendor this
    /// planner then fails to match, duplicating the manufacturer on the server.
    nonisolated static func vendorMatchKey(_ name: String) -> String {
        ManufacturerName.key(name)
    }

    private static func planVendors(
        _ locals: [MigrationLocalVendor],
        against servers: [Vendor]
    ) -> [MigrationItem<Vendor>] {
        locals.map { local in
            let localName = vendorMatchKey(local.name)
            let candidates = servers.filter { vendorMatchKey($0.name) == localName }
            return MigrationItem(
                localId: local.localId,
                label: local.name,
                candidates: candidates,
                resolution: candidates.isEmpty ? .create : .reuse(serverId: candidates[0].id)
            )
        }
    }

    private static func planFilaments(
        _ locals: [MigrationLocalFilament],
        localVendors: [MigrationLocalVendor],
        against servers: [Filament]
    ) -> [MigrationItem<Filament>] {
        locals.map { local in
            let key = FilamentMatchKey(local, localVendors: localVendors)
            let candidates = servers.filter { FilamentMatchKey($0) == key }
            return MigrationItem(
                localId: local.localId,
                label: filamentLabel(for: local, localVendors: localVendors),
                candidates: candidates,
                resolution: candidates.isEmpty ? .create : .reuse(serverId: candidates[0].id)
            )
        }
    }

    private static func planSpools(
        _ locals: [MigrationLocalSpool],
        against servers: [Spool]
    ) -> [MigrationItem<Spool>] {
        locals.map { local in
            let candidates = servers.filter { FilamentMatchKey($0.filament) == local.filamentKey }
            return MigrationItem(
                localId: local.localId,
                label: local.filamentKey.label,
                candidates: candidates,
                resolution: candidates.isEmpty ? .create : .reuse(serverId: candidates[0].id)
            )
        }
    }

    private static func filamentLabel(
        for local: MigrationLocalFilament,
        localVendors: [MigrationLocalVendor]
    ) -> String {
        let manufacturer = local.vendorLocalId.flatMap { id in
            localVendors.first { $0.localId == id }?.name
        }
        let parts: [String] = [
            manufacturer,
            local.name,
            local.material,
            local.diameter.map { String(format: "%.2f mm", $0) },
            local.weight.map { String(format: "%.0f g", $0) }
        ].compactMap { value in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? "Filament #\(local.localId)" : parts.joined(separator: " · ")
    }
}
