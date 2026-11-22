//
//  SpoolUsage.swift
//  SpoolKid
//
//  Purpose: Pure usage and weight text for spool lists, and per-filament stock
//  totals for the grouped spool list's filament headers. Views render these
//  strings and numbers; the rules live here (conventions A2/A3).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// A filament's stock across its active spools: how many there are and what
/// they still hold. `remaining` is nil when none of the active spools has a
/// known weight, so unknown is never shown or sorted as "0 g".
///
/// `nonisolated`: the target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`;
/// this pure value type must stay usable from nonisolated contexts.
nonisolated struct FilamentStock: Equatable, Sendable {
    var spoolCount: Int
    var remaining: Double?
}

nonisolated enum SpoolUsage {
    /// Grams consumed from a spool, or nil when it cannot be told.
    ///
    /// A stored `usedWeight` above zero wins. Otherwise the figure is derived
    /// from the starting weight and what remains, because the on-device Library
    /// stores weigh-ins as `remainingWeight` and does not keep `usedWeight` in
    /// step. The basis is `DashboardStatsService.weightBasis(for:)`, the same
    /// one the fill fraction uses.
    static func effectiveUsedWeight(of spool: Spool) -> Double? {
        if let used = spool.usedWeight, used > 0 { return used }
        if let remaining = spool.remainingWeight,
           let basis = DashboardStatsService.weightBasis(for: spool) {
            return max(0, basis - remaining)
        }
        return spool.usedWeight
    }

    /// True when nothing indicates the spool was ever used: no last-used date
    /// and no consumed weight.
    static func isUnused(_ spool: Spool) -> Bool {
        spool.lastUsed == nil && (effectiveUsedWeight(of: spool) ?? 0) <= 0
    }

    /// "used 2 days ago", "used just now", "used" or "unused". A last-used date
    /// under a minute old, or in the future (clock skew between phone and
    /// server), reads "just now" rather than a negative or zero-second figure.
    static func text(for spool: Spool, now: Date = Date(), locale: Locale = .current) -> String {
        guard let lastUsed = spool.lastUsed else { return isUnused(spool) ? "unused" : "used" }
        if now.timeIntervalSince(lastUsed) < 60 { return "used just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .short
        formatter.locale = locale
        return "used " + formatter.localizedString(for: lastUsed, relativeTo: now)
    }

    /// Whole grams under 1000 ("244 g"), otherwise kilograms to one decimal
    /// with a trailing ".0" dropped ("2.8 kg", "2 kg"). Negative input reads
    /// "0 g".
    static func weightText(_ grams: Double) -> String {
        let (number, isKilograms) = weightParts(grams)
        return number + (isKilograms ? " kg" : " g")
    }

    /// `weightText` in words, for VoiceOver: "244 grams", "1 kilogram",
    /// "2.8 kilograms". Same rounding as `weightText`; only a figure of exactly 1
    /// is singular.
    static func spokenWeight(_ grams: Double) -> String {
        let (number, isKilograms) = weightParts(grams)
        let unit = isKilograms ? "kilogram" : "gram"
        return number + " " + unit + (number == "1" ? "" : "s")
    }

    /// The figure and unit both renderings share, so they cannot round apart.
    private static func weightParts(_ grams: Double) -> (number: String, isKilograms: Bool) {
        let whole = max(0, grams).rounded()
        guard whole >= 1000 else { return ("\(Int(whole))", false) }
        var kilograms = String(format: "%.1f", whole / 1000)
        if kilograms.hasSuffix(".0") { kilograms.removeLast(2) }
        return (kilograms, true)
    }

    static func spoolCountText(_ count: Int) -> String {
        count == 1 ? "1 spool" : "\(count) spools"
    }

    /// What a filament's stock reads as: "918 g · 1 spool", or "2 spools" when no
    /// active spool states a weight. `noSpoolsText` when there are no active spools.
    static func stockText(_ stock: FilamentStock?) -> String {
        guard let stock, stock.spoolCount > 0 else { return noSpoolsText }
        guard let remaining = stock.remaining else { return spoolCountText(stock.spoolCount) }
        return "\(weightText(remaining)) · \(spoolCountText(stock.spoolCount))"
    }

    static let noSpoolsText = "No spools"

    /// Stock per filament id. `spoolCount` and `remaining` count only
    /// non-archived spools.
    static func stock(of spools: [Spool]) -> [Int: FilamentStock] {
        var result: [Int: FilamentStock] = [:]
        for spool in spools {
            var entry = result[spool.filament.id] ?? FilamentStock(spoolCount: 0, remaining: nil)
            if spool.archived != true {
                entry.spoolCount += 1
                if let weight = spool.remainingWeight {
                    // A negative reading is an over-drawn spool: it holds nothing,
                    // it does not take grams off its neighbours.
                    entry.remaining = (entry.remaining ?? 0) + max(0, weight)
                }
            }
            result[spool.filament.id] = entry
        }
        return result
    }
}
