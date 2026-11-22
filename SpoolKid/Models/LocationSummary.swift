//
//  LocationSummary.swift
//  SpoolKid
//
//  Purpose: The two numbers the Locations dashboard card shows. Pure, so the
//  card renders a value rather than computing one.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct LocationSummary: Equatable, Sendable {
    let locationCount: Int
    let unassignedSpoolCount: Int

    static func make(locations: [String], spools: [Spool]) -> LocationSummary {
        LocationSummary(
            locationCount: locations.count,
            unassignedSpoolCount: spools.filter { LocationName.trimmed($0.location ?? "").isEmpty }.count
        )
    }
}
