//
//  DashboardInfo.swift
//  SpoolKid
//
//  Purpose: What the Home dashboard cards' (i) buttons say — how each card
//  counts. Every number comes from the constant `DashboardStatsService` uses,
//  so a changed threshold cannot leave its explanation behind.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum DashboardInfo {
    static var spoolStatus: [String] {
        let bands = SpoolFillBucket.allCases.map { "\($0.title) (\($0.rangeText))" }
        return [
            "Each spool falls into a band by how much filament is left compared with its starting weight: "
                + bands.dropLast().joined(separator: ", ") + " or " + (bands.last ?? "") + ".",
            "The starting weight is the spool's initial weight, or its filament's net weight if that isn't set. A spool with no remaining or starting weight isn't counted, and archived spools never are.",
            "Tap a number to see those spools."
        ]
    }

    static let tagCoverage = [
        "How many of your spools have no NFC tag, one tag, or two or more. Archived spools are left out.",
        "A tag counts when your library links it to the spool, or when this iPhone has read or written it for that spool.",
        "Tap Untagged to see the spools without one."
    ]

    static var reorderSoon: [String] {
        [
            "Filaments that will run out within \(Int(RunwayTuning.reorderHorizonDays)) days at the rate you've been using them.",
            "The rate comes from each spool's first and last use and the filament used in between, archived spools included. A filament needs \(Int(RunwayTuning.minHistoryDays)) days of history and \(Int(RunwayTuning.minUsedGrams))\u{00A0}g used before it is estimated, so new filaments don't appear here.",
            "The stock is what's left on all of the filament's spools. Tap a filament to see them."
        ]
    }

    static let colours = [
        "The colours of your spools, most common first. A multicolour spool counts by its first colour; archived spools are left out."
    ]

    static let materialStatistics = [
        "How many spools of each material you have, and how much filament is left on them. Spools with no material are listed as Unknown; archived spools are left out.",
        "Tap a material to see its spools."
    ]

    /// Mirrors `HomeDashboardView.load`: only a backend with a currency
    /// setting is asked for one; `formatCurrency` falls back to the region.
    static func totalValue(_ capabilities: BackendCapabilities) -> [String] {
        [
            "The purchase prices of your spools, added up. A spool with no price counts as nothing; archived spools are left out.",
            capabilities.supportsCurrencySetting
                ? "Shown in the currency set in \(capabilities.displayName)."
                : "Shown in your iPhone's region currency."
        ]
    }
}
