//
//  LocationGroup.swift
//  SpoolKid
//
//  Purpose: One group as the arrangement list renders it — which location,
//  which spools, and why it is on screen.
//
//  Carries spool IDs rather than spools because `Spool` is not `Equatable`;
//  a group holding `[Spool]` could only be `Equatable` through a hand-written
//  `==` that compares ids while claiming to compare spools.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct LocationGroup: Equatable, Identifiable, Sendable {
    /// The location's name. An empty string is the Unassigned pseudo-group —
    /// the one group that is not a location, and whose drop clears the field
    /// rather than writing a name.
    let name: String
    let spoolIDs: [Int]
    /// The search matched the group's NAME, so every spool in it is shown.
    let matchedByName: Bool
    /// The search matched spools INSIDE this group, so it opens regardless of
    /// what the user had collapsed.
    let forcedOpen: Bool

    var id: String { name }
    var isUnassigned: Bool { name.isEmpty }
}
