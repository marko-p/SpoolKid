//
//  LocationGrouping.swift
//  SpoolKid
//
//  Purpose: Turns the locations, the spools and the search field into the
//  groups the arrangement list renders. Owns two rules the view must not
//  reinvent: when Unassigned exists, and when a group is forced open.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum LocationGrouping {
    /// The Unassigned pseudo-group's display name, and the string a search is
    /// matched against for it. Not a location name — no spool is ever written
    /// with it.
    static let unassignedTitle = "Unassigned"

    /// Spools whose location matches exactly. Exact, not normalized: two
    /// locations differing only in case are two locations on every backend,
    /// and quietly merging them here would move spools the user never touched.
    ///
    /// Moved here from `ManageLocationsView` — a view was never the right home
    /// for it. `groups` does not call it (it resolves pending moves first), so
    /// this stands for callers holding a settled list: `LocationDetailView`,
    /// and the header captions.
    static func spools(in location: String, from spools: [Spool]) -> [Spool] {
        spools.filter { $0.location == location }
    }

    /// `locationOverride` layers a drop that has been applied on screen but not
    /// yet confirmed by the backend. It exists because every property on `Spool`
    /// is a `let`, so the view cannot hand us a moved copy — and because a drop
    /// that waits for a round trip before landing does not feel like a drop.
    static func groups(
        orderedLocations: [String],
        spools: [Spool],
        query: String,
        spoolSort: SpoolSortOption,
        spoolAscending: Bool,
        isDragging: Bool,
        locationOverride: [Int: String?] = [:]
    ) -> [LocationGroup] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearching = !trimmedQuery.isEmpty

        // Resolved once: the outer optional is "is there an override", the
        // inner one is the location it asserts, which may legitimately be nil.
        let placed = spools.map { spool in
            (spool: spool, location: locationOverride[spool.id] ?? spool.location)
        }

        var result: [LocationGroup] = []

        // Unassigned is pinned first, and exists for the whole of any drag so
        // there is always somewhere to drop — without a permanent "0 spools"
        // row for someone who has everything filed.
        let unassigned = placed.filter { LocationName.trimmed($0.location ?? "").isEmpty }.map(\.spool)
        if isDragging {
            result.append(
                LocationGroup(
                    name: "",
                    spoolIDs: ordered(unassigned, spoolSort, spoolAscending).map(\.id),
                    matchedByName: false,
                    forcedOpen: false
                )
            )
        } else if !unassigned.isEmpty,
                  let group = group(
                      name: "",
                      searchName: unassignedTitle,
                      members: unassigned,
                      query: trimmedQuery,
                      isSearching: isSearching,
                      spoolSort: spoolSort,
                      spoolAscending: spoolAscending
                  ) {
            result.append(group)
        }

        for name in orderedLocations {
            if let group = group(
                name: name,
                searchName: name,
                members: placed.filter { $0.location == name }.map(\.spool),
                query: trimmedQuery,
                isSearching: isSearching,
                spoolSort: spoolSort,
                spoolAscending: spoolAscending
            ) {
                result.append(group)
            }
        }

        return result
    }

    // MARK: - Private

    /// `nil` when a search is running and this group has nothing to do with it.
    private static func group(
        name: String,
        searchName: String,
        members: [Spool],
        query: String,
        isSearching: Bool,
        spoolSort: SpoolSortOption,
        spoolAscending: Bool
    ) -> LocationGroup? {
        let sorted = ordered(members, spoolSort, spoolAscending)

        guard isSearching else {
            return LocationGroup(name: name, spoolIDs: sorted.map(\.id), matchedByName: false, forcedOpen: false)
        }

        // A name match means the user asked for the SHELF, so show everything
        // on it and leave their open/closed choice alone.
        if SearchQuery.matches(query, in: [searchName]) {
            return LocationGroup(name: name, spoolIDs: sorted.map(\.id), matchedByName: true, forcedOpen: false)
        }

        // A spool match means the user asked for the REEL, so open the shelf
        // and show only what they asked for.
        let hits = sorted.filter { spool in
            SearchQuery.matches(
                query,
                in: [spool.listTitle] + spool.listDetailParts(includingLocation: false).map { Optional($0) }
            )
        }
        guard !hits.isEmpty else { return nil }
        return LocationGroup(name: name, spoolIDs: hits.map(\.id), matchedByName: false, forcedOpen: true)
    }

    private static func ordered(_ spools: [Spool], _ option: SpoolSortOption, _ ascending: Bool) -> [Spool] {
        let sorted = spools.sorted { option.areInIncreasingOrder($0, $1) }
        return ascending ? sorted : sorted.reversed()
    }
}
