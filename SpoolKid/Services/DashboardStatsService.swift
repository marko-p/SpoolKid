//
//  DashboardStatsService.swift
//  SpoolKid
//
//  Purpose: Pure inventory statistics for the Home dashboard — fill-level
//  bucketing, totals, value, currency formatting, and per-material grouping.
//  All Home-tab math lives here so views only render (conventions A2/A3).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// Fill-level classification for a spool by remaining-weight percentage.
/// `allCases` order matches the dashboard's Spool Status row (Full → Empty).
/// Fixed bands: Spoolman has no per-spool minimum, so "Low"/"Critical" are
/// fixed percentage ranges rather than a configurable threshold.
///
/// `nonisolated`: the target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`;
/// this pure value type must stay usable from nonisolated contexts (tests, the
/// pure service below).
nonisolated enum SpoolFillBucket: String, CaseIterable, Sendable {
    case full
    case normal
    case low
    case critical
    case empty

    /// Counter label.
    var title: String {
        switch self {
        case .full: "Full"
        case .normal: "Normal"
        case .low: "Low"
        case .critical: "Critical"
        case .empty: "Empty"
        }
    }

    /// The fixed band, as the Spool status card's (i) states it.
    var rangeText: String {
        switch self {
        case .full: ">75%"
        case .normal: "50–75%"
        case .low: "25–50%"
        case .critical: "<25%"
        case .empty: "0\u{00A0}g"
        }
    }
}

/// One row of the Filament Statistics table: a material with its spool count and
/// total remaining weight.
nonisolated struct MaterialStat: Identifiable, Equatable, Sendable {
    let material: String
    let spoolCount: Int
    let remainingWeightGrams: Double

    var id: String { material }
    var remainingKilograms: Double { remainingWeightGrams / 1000 }
}

nonisolated struct TagCoverage: Equatable, Sendable {
    let untagged: Int; let single: Int; let multi: Int
}

// TagCoverage is already a `nonisolated struct`, so its extension members are
// nonisolated automatically — do not repeat `nonisolated` on the extension.
extension TagCoverage {
    var tagged: Int { single + multi }
    var total: Int { untagged + single + multi }
    var taggedFraction: Double { total == 0 ? 0 : Double(tagged) / Double(total) }
    var percentTagged: Int { Int((taggedFraction * 100).rounded()) }
}

nonisolated struct ColorStat: Identifiable, Equatable, Sendable {
    let hex: String; let count: Int
    var id: String { hex }
}

nonisolated struct FilamentRunway: Identifiable, Equatable, Sendable {
    let filamentId: Int
    let title: String
    let colors: FilamentColors
    let remainingGrams: Double
    let ratePerDay: Double?
    let daysOfStock: Double?
    var id: Int { filamentId }
}

nonisolated enum RunwayTuning {
    static let minHistoryDays = 14.0
    static let minUsedGrams = 50.0
    static let reorderHorizonDays = 30.0
}

/// Pure dashboard math. `nonisolated` for the same reason as `SpoolFillBucket`.
nonisolated enum DashboardStatsService {
    /// Spools that count toward dashboard metrics: archived spools are excluded.
    static func activeSpools(_ spools: [Spool]) -> [Spool] {
        spools.filter { $0.archived != true }
    }

    /// The weight a spool's fill and used weight are measured against:
    /// `initialWeight`, falling back to the filament's net `weight`. Nil when
    /// neither is known or the value is not positive.
    static func weightBasis(for spool: Spool) -> Double? {
        guard let basis = spool.initialWeight ?? spool.filament.weight, basis > 0 else { return nil }
        return basis
    }

    /// Fraction (0…) of filament remaining, or nil when it can't be determined.
    /// Measured against `weightBasis(for:)`.
    static func fillFraction(for spool: Spool) -> Double? {
        guard let remaining = spool.remainingWeight, let basis = weightBasis(for: spool) else { return nil }
        return max(0, remaining) / basis
    }

    /// Fill bucket for a spool, or nil when the fill level is indeterminate
    /// (remaining known but no weight basis). Empty wins on remaining ≤ 0
    /// regardless of basis. Half-open bands: 75→Normal, 50→Low, 25→Critical.
    static func bucket(for spool: Spool) -> SpoolFillBucket? {
        if let remaining = spool.remainingWeight, remaining <= 0 { return .empty }
        guard let fraction = fillFraction(for: spool) else { return nil }
        let pct = fraction * 100
        switch pct {
        case let p where p > 75: return .full
        case let p where p > 50: return .normal
        case let p where p > 25: return .low
        default: return .critical
        }
    }

    /// Counts per bucket over active spools. Indeterminate spools are omitted.
    static func statusCounts(in spools: [Spool]) -> [SpoolFillBucket: Int] {
        var counts: [SpoolFillBucket: Int] = [:]
        for spool in activeSpools(spools) {
            if let bucket = bucket(for: spool) {
                counts[bucket, default: 0] += 1
            }
        }
        return counts
    }

    /// Sum of purchase prices over active spools.
    static func totalValue(of spools: [Spool]) -> Double {
        activeSpools(spools).reduce(0) { $0 + ($1.price ?? 0) }
    }

    /// Currency string for an amount. `code` is the Spoolman currency code
    /// (e.g. "EUR"); nil falls back to the device locale's currency. Separators
    /// always follow the device locale.
    static func formatCurrency(_ amount: Double, code: String?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        if let code, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            formatter.currencyCode = code
        }
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }

    /// Per-material rows, sorted by spool count descending then material name.
    static func filamentStatistics(for spools: [Spool]) -> [MaterialStat] {
        var grouped: [String: (count: Int, remaining: Double)] = [:]
        for spool in activeSpools(spools) {
            let key = materialKey(for: spool)
            var entry = grouped[key] ?? (count: 0, remaining: 0)
            entry.count += 1
            entry.remaining += spool.remainingWeight ?? 0
            grouped[key] = entry
        }
        return grouped
            .map { MaterialStat(material: $0.key, spoolCount: $0.value.count, remainingWeightGrams: $0.value.remaining) }
            .sorted { a, b in
                a.spoolCount != b.spoolCount
                    ? a.spoolCount > b.spoolCount
                    : a.material.localizedCaseInsensitiveCompare(b.material) == .orderedAscending
            }
    }

    /// Active spools in a given fill bucket — the drill-down predicate for the
    /// Spool Status / Low & Empty cards (single source of truth with `bucket`).
    static func spools(in spools: [Spool], bucket target: SpoolFillBucket) -> [Spool] {
        activeSpools(spools).filter { bucket(for: $0) == target }
    }

    /// Active spools of a given material key — the drill-down predicate for the
    /// Filament Statistics rows (uses the same key derivation as the grouping).
    static func spools(in spools: [Spool], material: String) -> [Spool] {
        activeSpools(spools).filter { materialKey(for: $0) == material }
    }

    /// True when `a` was active more recently than `b`: `recencyDate`
    /// (`COALESCE(last_used, registered)`, nothing reading as oldest), ties
    /// broken on the higher id. The one recency rule: the spool list's Recent
    /// sort and the filament page's spools both use it, so they cannot disagree.
    static func isMoreRecent(_ a: Spool, _ b: Spool) -> Bool {
        let da = a.recencyDate ?? .distantPast
        let db = b.recencyDate ?? .distantPast
        if da != db { return da > db }
        return a.id > b.id
    }

    // MARK: - Tag coverage

    private static func effectiveTagUIDs(for spool: Spool, ledger: [String: Int], cardUIDOwner: [String: Int]) -> Set<String> {
        var uids = Set(spool.mappedCardUIDs.map(SpoolMappingService.normalizeUID))
        for (uid, sid) in ledger where sid == spool.id {
            let norm = SpoolMappingService.normalizeUID(uid)
            if cardUIDOwner[norm] == nil {
                uids.insert(norm)
            }
        }
        return uids
    }

    private static func cardUIDOwnerMap(_ spools: [Spool]) -> [String: Int] {
        var owner: [String: Int] = [:]
        for spool in spools {
            for uid in spool.mappedCardUIDs { owner[SpoolMappingService.normalizeUID(uid)] = spool.id }
        }
        return owner
    }

    static func tagCoverage(in spools: [Spool], ledger: [String: Int]) -> TagCoverage {
        let active = activeSpools(spools)
        let owner = cardUIDOwnerMap(active)
        var untagged = 0, single = 0, multi = 0
        for spool in active {
            switch effectiveTagUIDs(for: spool, ledger: ledger, cardUIDOwner: owner).count {
            case 0: untagged += 1
            case 1: single += 1
            default: multi += 1
            }
        }
        return TagCoverage(untagged: untagged, single: single, multi: multi)
    }

    static func untaggedSpools(in spools: [Spool], ledger: [String: Int]) -> [Spool] {
        let active = activeSpools(spools)
        let owner = cardUIDOwnerMap(active)
        return active.filter { effectiveTagUIDs(for: $0, ledger: ledger, cardUIDOwner: owner).isEmpty }
    }

    // MARK: - Colour stats

    static func colorStats(in spools: [Spool]) -> [ColorStat] {
        var counts: [String: Int] = [:]
        for spool in activeSpools(spools) {
            guard let hex = ColorMatching.normalize(spool.filament.colors.primaryHex) else { continue }
            counts[hex, default: 0] += 1
        }
        return counts.map { ColorStat(hex: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.hex < $1.hex }
    }

    static func distinctColorCount(in spools: [Spool]) -> Int { colorStats(in: spools).count }

    // MARK: - Filament runway

    static func filamentRunway(in spools: [Spool], now: Date) -> [FilamentRunway] {
        let byFilament = Dictionary(grouping: spools, by: { $0.filament.id })
        var result: [FilamentRunway] = []
        for (fid, group) in byFilament {
            let active = group.filter { $0.archived != true }
            guard !active.isEmpty else { continue }
            let stock = active.reduce(0) { $0 + ($1.remainingWeight ?? 0) }
            let samples = group.filter { $0.firstUsed != nil && $0.lastUsed != nil && ($0.usedWeight ?? 0) > 0 }
            var rate: Double? = nil
            if !samples.isEmpty {
                let totalUsed = samples.reduce(0) { $0 + ($1.usedWeight ?? 0) }
                let earliest = samples.compactMap(\.firstUsed).min()!
                let latest = samples.compactMap(\.lastUsed).max()!
                let spanDays = max(1, latest.timeIntervalSince(earliest) / 86400)
                if totalUsed >= RunwayTuning.minUsedGrams && spanDays >= RunwayTuning.minHistoryDays {
                    rate = totalUsed / spanDays
                }
            }
            let days = rate.map { stock / $0 }
            let head = active.first!
            result.append(FilamentRunway(
                filamentId: fid, title: head.listTitle, colors: head.filament.colors,
                remainingGrams: stock, ratePerDay: rate, daysOfStock: days))
        }
        return result
    }

    static func reorderSoon(in spools: [Spool], now: Date) -> [FilamentRunway] {
        filamentRunway(in: spools, now: now)
            .filter { ($0.daysOfStock ?? .infinity) <= RunwayTuning.reorderHorizonDays }
            .sorted { ($0.daysOfStock ?? .infinity) < ($1.daysOfStock ?? .infinity) }
    }

    // MARK: - Material grouping

    /// Grouping key for a spool's material: trimmed material, or "Unknown".
    static func materialKey(for spool: Spool) -> String {
        let material = spool.filament.material?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (material?.isEmpty == false) ? material! : "Unknown"
    }
}
