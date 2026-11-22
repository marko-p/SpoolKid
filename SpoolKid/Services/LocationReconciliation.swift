//
//  LocationReconciliation.swift
//  SpoolKid
//
//  Purpose: Reconciles the device-local registry against the locations the
//  backend actually lists — including locations created, renamed or removed in
//  Spoolman's or FilaMan's own UI.
//
//  SpoolKid cannot distinguish a server-side rename from a server-side delete,
//  and does not try. It classifies, presents, and lets the user decide. The
//  alternative — inferring a rename from which spool ids used to sit in a
//  location — needs a persisted spool-id snapshot to support what is still a
//  guess, and is deliberately out of scope.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum LocationSyncState: Equatable, Sendable {
    /// The backend lists this name. Nothing to show.
    case inSync
    /// The backend does not list it and no tag carries it — an ordinary
    /// not-yet-filled shelf on a backend that cannot store empty locations.
    case pendingOnDevice
    /// The backend does not list it, but tags point at it. Either it was
    /// renamed on the server or it was removed; the user has to say which.
    case missingFromBackend
}

nonisolated struct LocationSyncBanner: Equatable, Sendable {
    let title: String
    let message: String
}

nonisolated enum LocationReconciliation {
    static func state(for record: LocationRecord, backendLocations: [String]) -> LocationSyncState {
        let key = LocationName.normalizedKey(record.name)
        if backendLocations.contains(where: { LocationName.normalizedKey($0) == key }) {
            return .inSync
        }
        return record.isTagged ? .missingFromBackend : .pendingOnDevice
    }

    /// Whether the BACKEND holds this location name: it lists it, or a spool
    /// sits in it. Asked before a rename, because a name only this device knows
    /// has no server half to rename — Spoolman's `PATCH /location/<name>` fails
    /// for a location no spool references, which is exactly the
    /// pending-on-device case.
    ///
    /// A question about the DATA, deliberately not about which backend is
    /// connected: no capability flag, no identity check.
    static func backendKnows(
        name: String, backendLocations: [String], spoolLocations: [String]
    ) -> Bool {
        let key = LocationName.normalizedKey(name)
        guard !key.isEmpty else { return false }
        return (backendLocations + spoolLocations)
            .contains { LocationName.normalizedKey($0) == key }
    }

    /// Backend locations no registry entry claims — the candidate list behind
    /// "Match to…". Sorted case-insensitively, like every other location list.
    static func unclaimedBackendLocations(
        _ backendLocations: [String], records: [LocationRecord]
    ) -> [String] {
        let claimed = Set(records.map { LocationName.normalizedKey($0.name) })
        let unclaimed = backendLocations
            .filter { !claimed.contains(LocationName.normalizedKey($0)) }
            .map { LocationName.trimmed($0) }
        return Array(Set(unclaimed))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The one home for reconciliation copy. `storageNoun` is
    /// `BackendCapabilities.storageNoun` and always sits mid-sentence, so
    /// "your library" reads as naturally as "Spoolman".
    ///
    /// The missing-state title deliberately does NOT say the location was
    /// deleted: on FilaMan a rename is just as likely, and asserting either
    /// would be reporting a fact the app does not have.
    static func banner(
        state: LocationSyncState, locationName: String, storageNoun: String
    ) -> LocationSyncBanner? {
        switch state {
        case .inSync:
            return nil
        case .pendingOnDevice:
            return LocationSyncBanner(
                title: "Saved on this device",
                message: "\(locationName) appears in \(storageNoun) once you assign a spool to it."
            )
        case .missingFromBackend:
            return LocationSyncBanner(
                title: "No spools are in \(locationName)",
                message: """
                This location isn't listed in \(storageNoun). Its tag still works — but if you renamed it there, \
                match it up now, or your next assignment will create \(locationName) again alongside the new name.
                """
            )
        }
    }
}
