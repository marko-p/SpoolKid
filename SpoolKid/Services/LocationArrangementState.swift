//
//  LocationArrangementState.swift
//  SpoolKid
//
//  Purpose: What a released drag means. The view caches header geometry and
//  applies the answer; every rule about what a drop DOES lives here, so it is
//  tested without a device.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import CoreGraphics
import Foundation

/// One group header's position, in the arrangement list's own coordinate
/// space. An empty `name` is the Unassigned pseudo-group.
nonisolated struct HeaderFrame: Equatable, Sendable {
    let name: String
    let rect: CGRect

    init(name: String, rect: CGRect) {
        self.name = name
        self.rect = rect
    }
}

nonisolated enum LocationArrangementState {
    enum Grabbed: Equatable, Sendable {
        case location(String)
        /// The spool's id, and the location it came from — without the origin
        /// there is no way to tell a deliberate move from a drop back home.
        case spool(Int, from: String)
    }

    enum Drop: Equatable, Sendable {
        case reorder(Int)
        case assign(String)
        case unassign
        case cancel
    }

    /// A location drag CLAMPS rather than cancels: every vertical position maps
    /// to some index, which is how native reorder behaves, and inventing a dead
    /// zone would mean a drag that travelled too far silently did nothing.
    /// Only a spool drag can miss, because only a spool drag needs to hit a
    /// specific target.
    static func drop(for point: CGPoint, grabbed: Grabbed, headers: [HeaderFrame]) -> Drop {
        let sorted = headers.sorted { $0.rect.minY < $1.rect.minY }

        switch grabbed {
        case .location(let name):
            // Unassigned is pinned and never reorderable, so it neither moves
            // nor consumes an index.
            let reorderable = sorted.filter { !$0.name.isEmpty }
            guard !reorderable.isEmpty else { return .cancel }

            let key = LocationName.normalizedKey(name)
            let others = reorderable.filter { LocationName.normalizedKey($0.name) != key }
            return .reorder(others.filter { $0.rect.midY < point.y }.count)

        case .spool(_, let origin):
            guard let hit = sorted.first(where: { $0.rect.contains(point) }) else { return .cancel }

            let originKey = LocationName.normalizedKey(origin)
            if hit.name.isEmpty {
                return originKey.isEmpty ? .cancel : .unassign
            }
            if LocationName.normalizedKey(hit.name) == originKey { return .cancel }
            return .assign(hit.name)
        }
    }
}
