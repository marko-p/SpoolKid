//
//  LocationOrder.swift
//  SpoolKid
//
//  Purpose: The order the user dragged their shelves into. Advisory by
//  design — it may name shelves the backend has since dropped and omit ones
//  created in the backend's own web UI, and it renders sensibly either way.
//
//  Deliberately NOT stored on `LocationRegistryEntry`: an entry exists only
//  for a location SpoolKid created or tagged, and `SpoolDataStore.syncState`
//  reads "no entry" as "the backend says so". Minting entries to hang an index
//  on would reclassify every server-side delete as `.pendingOnDevice` and
//  resurrect deleted shelves forever.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct LocationOrder: Equatable, Sendable, Codable {
    /// `LocationName.normalizedKey` values, in the order the user chose.
    private(set) var keys: [String]

    init(keys: [String] = []) {
        self.keys = LocationOrder.deduplicated(keys)
    }

    /// The order currently on screen, frozen. This is what makes a drag while
    /// sorted by Name not jump: the visible order becomes the manual one, with
    /// the move applied on top.
    static func seed(from visible: [String]) -> LocationOrder {
        LocationOrder(keys: visible.map(LocationName.normalizedKey))
    }

    /// Known names first, in stored order; everything else appended in
    /// case-insensitive name order. Never drops a name.
    func arranged(_ names: [String]) -> [String] {
        let position = Dictionary(
            keys.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )

        var known: [(String, Int)] = []
        var unknown: [String] = []
        for name in names {
            if let index = position[LocationName.normalizedKey(name)] {
                known.append((name, index))
            } else {
                unknown.append(name)
            }
        }

        return known.sorted { $0.1 < $1.1 }.map(\.0)
            + unknown.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Re-seats `name` at `index` within `visible`, taking `visible` as the new
    /// truth. Silently does nothing when `name` is not in `visible` — there is
    /// no position to move it from.
    mutating func move(_ name: String, to index: Int, within visible: [String]) {
        var next = visible.map(LocationName.normalizedKey).filter { !$0.isEmpty }
        let key = LocationName.normalizedKey(name)
        guard let from = next.firstIndex(of: key) else { return }

        next.remove(at: from)
        next.insert(key, at: min(max(index, 0), next.count))
        keys = LocationOrder.deduplicated(next)
    }

    /// Keeps a renamed shelf where the user put it. A rename onto a name the
    /// order already holds collapses to one position rather than listing the
    /// shelf twice.
    mutating func rename(from currentName: String, to newName: String) {
        let old = LocationName.normalizedKey(currentName)
        let new = LocationName.normalizedKey(newName)
        guard !new.isEmpty, let index = keys.firstIndex(of: old) else { return }

        keys[index] = new
        keys = LocationOrder.deduplicated(keys)
    }

    /// Forgets every key no longer among `names`. Called on read, so a shelf
    /// deleted in Spoolman's own web UI drops out without a migration.
    mutating func prune(keeping names: [String]) {
        let live = Set(names.map(LocationName.normalizedKey))
        keys.removeAll { !live.contains($0) }
    }

    private static func deduplicated(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.filter { key in
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}
