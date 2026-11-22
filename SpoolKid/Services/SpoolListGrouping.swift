//
//  SpoolListGrouping.swift
//  SpoolKid
//
//  Purpose: Groups, orders, totals and folds spools for the grouped spool list
//  (Manage Spools and Select Spool). Views render the groups; the rules live
//  here (conventions A2/A3).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// How the spool list is grouped. Manage Spools and Select Spool each remember
/// their own choice (`AppConfig.spoolGroupingKey` and `AppConfig.spoolPickerGroupingKey`).
///
/// `nonisolated`: the target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`;
/// this pure value type must stay usable from nonisolated contexts.
nonisolated enum SpoolGrouping: String, CaseIterable, Identifiable, Sendable {
    case filament, manufacturer, material, color, location, none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .filament: "Filament"
        case .manufacturer: "Manufacturer"
        case .material: "Material"
        case .color: "Color"
        case .location: "Location"
        case .none: "None"
        }
    }

    var systemImage: String {
        switch self {
        case .filament: "scribble"
        case .manufacturer: "building.2"
        case .material: "cube"
        case .color: "paintpalette"
        case .location: "mappin.and.ellipse"
        case .none: "list.bullet"
        }
    }

    /// The toolbar symbol: the plain group icon for None, otherwise this grouping's own icon.
    var toolbarSymbol: String {
        self == .none ? "rectangle.3.group" : systemImage
    }

    /// Whether the toolbar button shows grouping is active: any grouping other than None.
    var isHighlightedInToolbar: Bool { self != .none }

    /// The screen title when the grouping menu stands in for it: what the list
    /// is made of under this grouping.
    var titleMenuLabel: String {
        switch self {
        case .filament: "Filaments"
        case .manufacturer: "Manufacturers"
        case .material: "Materials"
        case .color: "Colors"
        case .location: "Locations"
        case .none: "All Spools"
        }
    }
}

/// How a row presents its spool's filament. The header already names what the
/// group shares, so a row repeats only what the header does not.
nonisolated enum SpoolRowStyle: Equatable, Sendable {
    case underFilament
    case withFilament
    case withFilamentNameOnly
    /// Under a material header: the brand and name, without repeating the
    /// material the header already names.
    case withFilamentNoMaterial

    /// Whether a row in this style names its filament's material. A filament
    /// header and a material header already name it.
    var showsMaterial: Bool {
        self == .withFilament || self == .withFilamentNameOnly
    }
}

nonisolated struct SpoolListLayout: Equatable, Sendable {
    let mode: SpoolGrouping
    let showsHeaders: Bool
    let rowStyle: SpoolRowStyle

    /// Whether identical unused spools fold into one row. Only rows under a
    /// filament fold (owner decision O24, 2026-10-24): a fold reads "2 unused ·
    /// 1 kg each" with no filament of its own, so under any other header it sat
    /// misaligned beside rows that do name theirs.
    var foldsUnused: Bool { rowStyle == .underFilament }

    /// Whether the list lowers its row height to `SpoolUsageRow.compactRowHeight`.
    /// Only rows under a filament are compact (owner decision O25, 2026-10-25):
    /// under any other header, or none, a spool row is a normal list row.
    var usesCompactRows: Bool { rowStyle == .underFilament }
}

/// Identical unused spools shown as one row. `basis` is the full weight each
/// spool was measured against, which is shared by every member, so it is
/// always known: a spool without a weight basis never folds.
nonisolated struct SpoolFold: Identifiable, Sendable {
    let id: String
    let spools: [Spool]
    let basis: Double
}

nonisolated enum SpoolListEntry: Identifiable, Sendable {
    case spool(Spool)
    case fold(SpoolFold)

    var id: String {
        switch self {
        case .spool(let spool): "spool:\(spool.id)"
        case .fold(let fold): fold.id
        }
    }
}

/// One section of the grouped list. Totals count every non-archived spool in the
/// whole list, not the rows on screen, so a search never changes a header.
nonisolated struct SpoolGroup: Identifiable, Sendable {
    let id: String
    let title: String
    let isNoneGroup: Bool
    let filament: Filament?
    let vendor: Vendor?
    let location: String?
    let entries: [SpoolListEntry]
    let spoolIDs: [Int]
    let spoolCount: Int
    /// Nil when none of the counted spools states a remaining weight, so a header
    /// shows no total instead of a false "0 g".
    let remaining: Double?
    /// True while a search is running: the group stays open so a match is never
    /// hidden, and its collapse toggle does nothing. The service decides it, so
    /// every screen follows the same rule.
    var forcedOpen: Bool = false
    /// Under Color grouping, the hue family the header shows.
    var colorFamily: ColorFamily? = nil
}

/// Pure grouping for the spool list. `nonisolated` for the same reason as the
/// types above.
nonisolated enum SpoolListGrouping {
    /// What the list shows for a grouping. Drilling into one filament replaces
    /// the grouping with a flat list of that filament's spools.
    static func layout(grouping: SpoolGrouping, isFilamentDrillDown: Bool) -> SpoolListLayout {
        if isFilamentDrillDown {
            return SpoolListLayout(mode: .none, showsHeaders: false, rowStyle: .underFilament)
        }
        switch grouping {
        case .filament:
            return SpoolListLayout(mode: .filament, showsHeaders: true, rowStyle: .underFilament)
        case .manufacturer:
            return SpoolListLayout(mode: .manufacturer, showsHeaders: true, rowStyle: .withFilamentNameOnly)
        case .material:
            return SpoolListLayout(mode: .material, showsHeaders: true, rowStyle: .withFilamentNoMaterial)
        case .color:
            return SpoolListLayout(mode: .color, showsHeaders: true, rowStyle: .withFilament)
        case .location:
            return SpoolListLayout(mode: .location, showsHeaders: true, rowStyle: .withFilament)
        case .none:
            return SpoolListLayout(mode: .none, showsHeaders: false, rowStyle: .withFilament)
        }
    }

    /// Groups in the order their first spool appears in `rows`, with the none
    /// group (no manufacturer, no location, unknown material) last. Only keys
    /// present in `rows` produce a group; `totalsFrom` supplies the counts.
    /// `isSearching` marks every group `forcedOpen`. `idPrefix` keeps a second
    /// set of groups on the same screen (Recently Added) apart from the first.
    static func groups(rows: [Spool], totalsFrom: [Spool], mode: SpoolGrouping, foldsUnused: Bool,
                       isSearching: Bool = false, idPrefix: String = "") -> [SpoolGroup] {
        var keys: [GroupKey] = []
        var spoolsByID: [String: [Spool]] = [:]
        for spool in rows {
            let key = groupKey(for: spool, mode: mode)
            if spoolsByID[key.id] == nil { keys.append(key) }
            spoolsByID[key.id, default: []].append(spool)
        }

        var totals: [String: (count: Int, remaining: Double?)] = [:]
        for spool in totalsFrom where spool.archived != true {
            let id = groupKey(for: spool, mode: mode).id
            var total = totals[id] ?? (count: 0, remaining: nil)
            total.count += 1
            // A negative reading is an over-drawn spool: it holds nothing, it does
            // not take grams off its neighbours.
            if let weight = spool.remainingWeight { total.remaining = (total.remaining ?? 0) + max(0, weight) }
            totals[id] = total
        }

        // Color groups follow the spectrum, not the order spools appear in.
        let named = keys.filter { !$0.isNoneGroup }
        let ordered = (mode == .color
            ? named.sorted { ($0.colorFamily?.rawValue ?? 0) < ($1.colorFamily?.rawValue ?? 0) }
            : named) + keys.filter { $0.isNoneGroup }
        return ordered.map { key in
            let groupID = idPrefix + key.id
            let groupEntries = entries(for: spoolsByID[key.id] ?? [], groupID: groupID, foldsUnused: foldsUnused)
            let total = totals[key.id] ?? (count: 0, remaining: nil)
            return SpoolGroup(
                id: groupID, title: key.title, isNoneGroup: key.isNoneGroup,
                filament: key.filament, vendor: key.vendor, location: key.location,
                entries: groupEntries, spoolIDs: groupEntries.flatMap(spoolIDs(in:)),
                spoolCount: total.count, remaining: total.remaining, forcedOpen: isSearching,
                colorFamily: key.colorFamily)
        }
    }

    /// Headers with no rows, by title: under Filament grouping every filament no
    /// visible spool belongs to, under Manufacturer every manufacturer none of
    /// them is made by. Empty under any other grouping, and while a colour or
    /// material filter is active.
    static func groupsWithoutSpools(filaments: [Filament], vendors: [Vendor], visibleSpools: [Spool],
                                    mode: SpoolGrouping, filtersActive: Bool,
                                    searchText: String) -> [SpoolGroup] {
        guard !filtersActive else { return [] }
        let headers: [(title: String, filament: Filament?, vendor: Vendor?, id: String)]
        switch mode {
        case .filament:
            let withSpools = Set(visibleSpools.map { $0.filament.id })
            headers = filaments
                .filter { !withSpools.contains($0.id) }
                .filter { SearchQuery.matches(searchText, in: [$0.name, $0.vendor?.name, $0.material]) }
                .map { (filamentTitle($0), $0, nil, "filament:\($0.id)") }
        case .manufacturer:
            let withSpools = Set(visibleSpools.compactMap { $0.filament.vendor?.id })
            headers = vendors
                .filter { !withSpools.contains($0.id) }
                .filter { SearchQuery.matches(searchText, in: [$0.name]) }
                .map { ($0.name, nil, $0, "manufacturer:\($0.id)") }
        case .material, .color, .location, .none:
            return []
        }
        return headers
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map { header in
                SpoolGroup(id: header.id, title: header.title, isNoneGroup: false,
                           filament: header.filament, vendor: header.vendor, location: nil,
                           entries: [], spoolIDs: [], spoolCount: 0, remaining: nil, forcedOpen: false)
            }
    }

    // MARK: - Recently Added

    /// Spools added within the last day sit above the grouped list in their
    /// own section, so a spool just added is found without a scroll or a
    /// search (owner 2026-11-10).
    static let recentlyAddedWindow: TimeInterval = 24 * 60 * 60
    static let recentlyAddedIDPrefix = "recent:"

    /// Only the Library's own list, and not while a search or a filter is
    /// narrowing it: the matches then show in their usual groups.
    static func offersRecentlyAdded(isLibraryList: Bool, isSearching: Bool, filtersActive: Bool) -> Bool {
        isLibraryList && !isSearching && !filtersActive
    }

    /// The spools added within `recentlyAddedWindow` before `now`, newest
    /// first, and the rest in their given order. An archived spool, or one with
    /// no `registered` date (a Library spool created before it recorded one),
    /// is never recent. A date ahead of `now` is a server clock running a
    /// little fast, so it counts as just added.
    static func splittingRecentlyAdded(_ rows: [Spool], now: Date) -> (recent: [Spool], rest: [Spool]) {
        var recent: [Spool] = []
        var rest: [Spool] = []
        for spool in rows {
            if spool.archived != true, let registered = spool.registered,
               now.timeIntervalSince(registered) < recentlyAddedWindow {
                recent.append(spool)
            } else {
                rest.append(spool)
            }
        }
        recent.sort { ($0.registered ?? .distantPast, $0.id) > ($1.registered ?? .distantPast, $1.id) }
        return (recent, rest)
    }

    /// The recent spools grouped and folded exactly as the rest of the list is
    /// (owner 2026-11-10: they must look the same), under ids of their own so a
    /// filament in both lists collapses and expands each separately. Their
    /// headers total the recent spools only: the rows beneath them.
    static func recentlyAddedGroups(_ recent: [Spool], mode: SpoolGrouping, foldsUnused: Bool) -> [SpoolGroup] {
        groups(rows: recent, totalsFrom: recent, mode: mode, foldsUnused: foldsUnused,
               idPrefix: recentlyAddedIDPrefix)
    }

    // MARK: - Keys

    /// The one title a filament header shows, and the order it sorts by: the
    /// trimmed name, else the brand-and-name fallback.
    private static func filamentTitle(_ filament: Filament) -> String {
        let name = filament.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? filament.listTitle : name
    }

    /// The header facts one spool contributes to its group.
    nonisolated private struct GroupKey {
        let id: String
        let title: String
        let isNoneGroup: Bool
        let filament: Filament?
        let vendor: Vendor?
        let location: String?
        var colorFamily: ColorFamily? = nil
    }

    /// The key decides membership; the title is display only. Missing values
    /// get a fixed key flagged `isNoneGroup`, so `groups` can order them last.
    private static func groupKey(for spool: Spool, mode: SpoolGrouping) -> GroupKey {
        switch mode {
        case .filament:
            return GroupKey(id: "filament:\(spool.filament.id)", title: filamentTitle(spool.filament),
                            isNoneGroup: false, filament: spool.filament, vendor: nil, location: nil)
        case .manufacturer:
            guard let vendor = spool.filament.vendor else {
                return GroupKey(id: "manufacturer:", title: "No manufacturer",
                                isNoneGroup: true, filament: nil, vendor: nil, location: nil)
            }
            return GroupKey(id: "manufacturer:\(vendor.id)", title: vendor.name,
                            isNoneGroup: false, filament: nil, vendor: vendor, location: nil)
        case .material:
            let material = DashboardStatsService.materialKey(for: spool)
            return GroupKey(id: "material:\(material)", title: material,
                            isNoneGroup: material == "Unknown", filament: nil, vendor: nil, location: nil)
        case .color:
            guard let family = ColorFamily.of(spool.filament.colors) else {
                return GroupKey(id: "color:", title: "No color",
                                isNoneGroup: true, filament: nil, vendor: nil, location: nil)
            }
            return GroupKey(id: "color:\(family.rawValue)", title: family.label, isNoneGroup: false,
                            filament: nil, vendor: nil, location: nil, colorFamily: family)
        case .location:
            // Trimmed, like the fold key: a stray space never splits a shelf in two.
            let location = spool.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !location.isEmpty else {
                return GroupKey(id: "location:", title: "No location",
                                isNoneGroup: true, filament: nil, vendor: nil, location: nil)
            }
            return GroupKey(id: "location:\(location)", title: location,
                            isNoneGroup: false, filament: nil, vendor: nil, location: location)
        case .none:
            return GroupKey(id: "all", title: "", isNoneGroup: false, filament: nil, vendor: nil, location: nil)
        }
    }

    // MARK: - Folds

    /// The identity two unused spools must share to fold into one row. Location
    /// is part of it: spools on different shelves are not interchangeable. So
    /// is the remaining weight in whole grams: an unused spool at 1200 g is not
    /// the same stock as one at 1000 g on the same basis. Location is trimmed, so
    /// a stray space never splits a shelf in two.
    nonisolated private struct FoldBucket: Hashable {
        let filamentID: Int
        let basis: Double
        let remaining: Double
        let location: String
    }

    /// The bucket a spool folds into, or nil when it is not a candidate.
    /// Archived spools never fold: they are out of circulation. A spool with no
    /// weight basis never folds either: "unused" then says nothing about how
    /// much it holds, so two of them cannot be shown as the same stock.
    private static func foldBucket(for spool: Spool) -> FoldBucket? {
        guard spool.archived != true, SpoolUsage.isUnused(spool),
              let basis = DashboardStatsService.weightBasis(for: spool) else { return nil }
        let location = spool.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return FoldBucket(filamentID: spool.filament.id, basis: basis,
                          remaining: (spool.remainingWeight ?? 0).rounded(), location: location)
    }

    /// Spool entries for one group. A bucket of two or more becomes a single
    /// fold at its first member's position; everything else stays a row.
    private static func entries(for spools: [Spool], groupID: String, foldsUnused: Bool) -> [SpoolListEntry] {
        var members: [FoldBucket: [Spool]] = [:]
        if foldsUnused {
            for spool in spools {
                if let bucket = foldBucket(for: spool) { members[bucket, default: []].append(spool) }
            }
        }

        var emitted: Set<FoldBucket> = []
        var result: [SpoolListEntry] = []
        for spool in spools {
            guard let bucket = foldBucket(for: spool),
                  let folded = members[bucket], folded.count >= 2 else {
                result.append(.spool(spool))
                continue
            }
            guard emitted.insert(bucket).inserted else { continue }
            // Keyed on the bucket, not on the first member, so the id survives a
            // re-sort of the same spools.
            let id = "fold:\(groupID):\(bucket.filamentID):\(bucket.basis):\(bucket.remaining):\(bucket.location)"
            result.append(.fold(SpoolFold(id: id, spools: folded, basis: bucket.basis)))
        }
        return result
    }

    private static func spoolIDs(in entry: SpoolListEntry) -> [Int] {
        switch entry {
        case .spool(let spool): [spool.id]
        case .fold(let fold): fold.spools.map(\.id)
        }
    }
}
