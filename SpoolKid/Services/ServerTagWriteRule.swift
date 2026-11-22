//
//  ServerTagWriteRule.swift
//  SpoolKid
//
//  Purpose: Which tag writes still work while the filament server can't be
//  reached. A write that links needs the server; a write that doesn't is
//  fine, unless the server still links that tag to something — releasing
//  that link is a server write, and one tag keeps one owner.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum ServerTagWriteRule {
    enum Gate: Equatable {
        case allowed
        /// Greyed out with the rest of the server's actions.
        case locked
        /// Not written, with this message.
        case refused(String)
    }

    static func gate(isDown: Bool, links: Bool, isOwned: Bool, ownerName: String?) -> Gate {
        guard isDown else { return .allowed }
        if links { return .locked }
        guard isOwned else { return .allowed }
        return .refused("This tag is linked to \(ownerName ?? "a spool"). Try again when the server is back.")
    }

    /// The scan hub's line when the spool behind a tag can't be fetched.
    static func lookupNote(backendName: String) -> String {
        "\(backendName) can't be reached, so this spool can't be looked up right now."
    }
}
