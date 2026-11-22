//
//  DeletionImpact.swift
//  SpoolKid
//
//  Purpose: What deleting a set of vendors or filaments would take with it —
//  the dependents a delete has to be told about before it may remove them.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// The filaments and spools that depend on a vendor or filament selection.
///
/// Every backend has a different answer to deleting a record something still
/// references — the on-device Library cascaded spools and orphaned filaments
/// silently, Spoolman refuses a filament but orphans a vendor's filaments,
/// FilaMan refuses both — so the app asks this question itself, from a fresh
/// fetch, before any delete runs. Archived spools count: all three backends
/// refuse (or cascade) over them just the same.
nonisolated struct DeletionImpact: Equatable, Sendable {
    /// Filaments that go with a vendor selection; always empty for filaments.
    let filamentIDs: Set<Int>
    let spoolIDs: Set<Int>
    let archivedSpoolCount: Int

    var isEmpty: Bool { filamentIDs.isEmpty && spoolIDs.isEmpty }

    static func forFilaments(_ selected: Set<Int>, spools: [Spool]) -> DeletionImpact {
        let dependents = spools.filter { selected.contains($0.filament.id) }
        return DeletionImpact(
            filamentIDs: [],
            spoolIDs: Set(dependents.map(\.id)),
            archivedSpoolCount: dependents.filter { $0.archived == true }.count
        )
    }

    static func forVendors(_ selected: Set<Int>, filaments: [Filament], spools: [Spool]) -> DeletionImpact {
        let filamentIDs = Set(filaments.filter { $0.vendor.map { selected.contains($0.id) } ?? false }.map(\.id))
        let spoolImpact = forFilaments(filamentIDs, spools: spools)
        return DeletionImpact(
            filamentIDs: filamentIDs,
            spoolIDs: spoolImpact.spoolIDs,
            archivedSpoolCount: spoolImpact.archivedSpoolCount
        )
    }

    /// "4 filaments and 11 spools (2 archived)" — the dependents notice's
    /// middle, after "*X* is used by". Unset halves are omitted.
    var dependentsPhrase: String {
        var parts: [String] = []
        if !filamentIDs.isEmpty { parts.append(Self.counted(filamentIDs.count, "filament")) }
        if !spoolIDs.isEmpty { parts.append(Self.counted(spoolIDs.count, "spool")) }
        let phrase = parts.joined(separator: " and ")
        return archivedSpoolCount > 0 ? "\(phrase) (\(archivedSpoolCount) archived)" : phrase
    }

    /// Why a plain delete refused — on the backends where the app, not the
    /// server, is what refuses (the on-device Library; Spoolman's vendors).
    func refusalMessage(for noun: String) -> String {
        "This \(noun) still has \(dependentsPhrase), so it was not deleted."
    }

    /// Everything the final warning says will go: the selection plus its dependents.
    func totalItemCount(selected: Int) -> Int {
        selected + filamentIDs.count + spoolIDs.count
    }

    private static func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}
