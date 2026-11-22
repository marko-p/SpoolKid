//
//  TagOwner.swift
//  SpoolKid
//
//  Purpose: The single answer to "what does this tag belong to?"
//
//  A physical tag UID belongs to at most ONE thing — one spool, or one
//  location, never both and never two of either. A filament type is a third
//  kind of owner (Spoolman 0.27's own filament tags, and the Library's since
//  spec 4). Before this type each claim
//  site re-derived that rule from whatever it happened to have in hand: the
//  spool form checked the scanned PAYLOAD, the location write checked the
//  spool mappings, and the link service checked neither. Three partial answers
//  to one question is how a tag ends up owned twice.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum TagOwner: Equatable, Sendable {
    case none
    case spool(id: Int, label: String)
    /// A tag linked to a filament type rather than a spool: Spoolman 0.27's
    /// own filament tags, or the Library's (spec 4).
    case filament(id: Int, label: String)
    case location(name: String)

    /// What copy calls the holder: a spool's or filament's list title, a
    /// shelf's name; empty for no owner.
    var label: String {
        switch self {
        case .none: ""
        case .spool(_, let label), .filament(_, let label): label
        case .location(let name): name
        }
    }

    /// Whether `other` may claim this tag without the user first releasing it.
    /// A tag already held by the SAME owner is not a conflict — re-scanning a
    /// spool's own tag is an ordinary thing to do.
    func conflicts(with other: TagOwner) -> Bool {
        switch (self, other) {
        case (.none, _), (_, .none): return false
        default: return self != other
        }
    }

    /// What to tell a user whose tag is already spoken for. `nil` for `.none`,
    /// which has nothing to refuse.
    func claimRefusal(attemptedBy other: TagOwner) -> String? {
        guard conflicts(with: other) else { return nil }
        switch self {
        case .none:
            return nil
        case .spool(_, let label):
            return "That tag is linked to \(label). A tag belongs to one spool or one location, never both."
        case .filament(_, let label):
            return "That tag identifies the filament \(label). A tag belongs to one spool, one filament or one location."
        case .location(let name):
            return "That tag labels \(name). A tag belongs to one spool or one location, never both."
        }
    }
}
