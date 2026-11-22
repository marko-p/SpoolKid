//
//  LocationSortOption.swift
//  SpoolKid
//
//  Purpose: How the shelves order. One entry point — `arrange` — so `.manual`
//  and the automatic sorts cannot disagree about what the list is.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// A location and how many spools sit in it. The only facts any location sort
/// needs, so the sort never reaches for a `Spool`.
nonisolated struct LocationTally: Equatable, Sendable {
    let name: String
    let spoolCount: Int

    init(name: String, spoolCount: Int) {
        self.name = name
        self.spoolCount = spoolCount
    }
}

nonisolated enum LocationSortOption: String, SortOption, CaseIterable, Identifiable {
    case manual
    case name
    case spoolCount

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .name: return "Name"
        case .spoolCount: return "Spool Count"
        }
    }

    var systemImage: String {
        switch self {
        case .manual: return "hand.draw"
        case .name: return "textformat"
        case .spoolCount: return "number"
        }
    }

    var isDirectional: Bool { self != .manual }

    /// The one place the shelf list is ordered.
    ///
    /// `.manual` ignores `ascending`: a hand-arranged list has no direction to
    /// reverse, and reversing it would silently undo the arrangement.
    static func arrange(
        _ tallies: [LocationTally],
        by option: LocationSortOption,
        ascending: Bool,
        manual: LocationOrder
    ) -> [String] {
        switch option {
        case .manual:
            return manual.arranged(tallies.map(\.name))

        case .name:
            let sorted = tallies.sorted { byName($0, $1) }
            return (ascending ? sorted : sorted.reversed()).map(\.name)

        case .spoolCount:
            // The count axis flips with `ascending`; the name tie-break does
            // not — a tie-break that flips with sort direction is exactly the
            // shuffle a tie-break exists to prevent.
            return tallies.sorted { a, b in
                if a.spoolCount != b.spoolCount {
                    return ascending ? a.spoolCount < b.spoolCount : a.spoolCount > b.spoolCount
                }
                return byName(a, b)
            }.map(\.name)
        }
    }

    private static func byName(_ a: LocationTally, _ b: LocationTally) -> Bool {
        let comparison = a.name.localizedCaseInsensitiveCompare(b.name)
        if comparison == .orderedSame { return a.name < b.name }
        return comparison == .orderedAscending
    }
}
