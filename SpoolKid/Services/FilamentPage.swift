//
//  FilamentPage.swift
//  SpoolKid
//
//  Purpose: The pure rules the Filament page renders: which spec rows show, in
//  the filament form's order and with what text; which spools belong to a
//  filament, newest first; its section of the grouped list; and the header
//  subtitle. Views render these values; the rules live here (conventions A2/A3).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// One labelled line in a filament's specs.
nonisolated struct FilamentSpecRow: Equatable, Sendable {
    let label: String
    let value: String
}

/// `nonisolated`: the target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`;
/// these pure rules must stay usable from nonisolated contexts (tests included).
nonisolated enum FilamentPage {
    /// The one locale every number on the page is formatted in: a decimal point,
    /// like the app's weight and diameter text, so the page reads the same on
    /// every region.
    private static let decimalPointLocale = Locale(identifier: "en_US_POSIX")

    /// The spec rows a filament shows, in the filament form's order. A row is
    /// left out when its field is not visible, or when its value is nil or blank
    /// after trimming. Material, color, density and diameter have no field gate.
    /// Numbers use a decimal point, like the app's weight and diameter text.
    static func specRows(for filament: Filament, visibleFieldIDs: Set<String>) -> [FilamentSpecRow] {
        let validColors = filament.colors.hexes.compactMap(FilamentColors.normalizedHex)
        let colorText = validColors.isEmpty ? nil : validColors.joined(separator: ", ")
        let rows: [(label: String, gate: String?, value: String?)] = [
            ("Material", nil, filament.material.nonBlank),
            ("Color", nil, colorText),
            ("Density", nil, filament.density.map { "\($0.formatted(.number.locale(decimalPointLocale))) g/cm³" }),
            ("Diameter", nil, filament.diameter.map { "\($0.formatted(.number.locale(decimalPointLocale))) mm" }),
            ("TD", "td", filament.transmissionDistance.map(TransmissionDistance.displayText)),
            ("Extruder Temp", "settings_extruder_temp",
             filament.settingsExtruderTemp.map { "\($0.formatted(.number.locale(decimalPointLocale))) °C" }),
            ("Bed Temp", "settings_bed_temp",
             filament.settingsBedTemp.map { "\($0.formatted(.number.locale(decimalPointLocale))) °C" }),
            ("Price", "price",
             filament.price.map { $0.formatted(.number.precision(.fractionLength(2)).locale(decimalPointLocale)) }),
            ("Net Weight", "weight", filament.weight.map(SpoolUsage.weightText)),
            ("Default Spool Weight", "spool_weight", filament.spoolWeight.map(SpoolUsage.weightText)),
            ("Article Number", "article_number", filament.articleNumber.nonBlank),
            ("Comment", "comment", filament.comment.nonBlank),
            ("External ID", "external_id", filament.externalId.nonBlank),
        ]
        var result: [FilamentSpecRow] = []
        for row in rows {
            if let gate = row.gate, !visibleFieldIDs.contains(gate) { continue }
            guard let value = row.value else { continue }
            result.append(FilamentSpecRow(label: row.label, value: value))
        }
        return result
    }

    /// The filament's spools, newest first (`DashboardStatsService.isMoreRecent`).
    /// Archived spools are included only when `showArchived` is set.
    static func spools(ofFilament id: Int, in spools: [Spool], showArchived: Bool) -> [Spool] {
        spools
            .filter { $0.filament.id == id && (showArchived || $0.archived != true) }
            .sorted(by: DashboardStatsService.isMoreRecent)
    }

    /// The filament's section of the grouped spool list. Its totals count the
    /// filament's active spools, whether or not archived ones are shown.
    static func group(ofFilament id: Int, in spools: [Spool], showArchived: Bool) -> SpoolGroup? {
        SpoolListGrouping.groups(
            rows: Self.spools(ofFilament: id, in: spools, showArchived: showArchived),
            totalsFrom: spools.filter { $0.filament.id == id },
            mode: .filament,
            foldsUnused: true
        ).first
    }

    /// The Spools section's header: "Spools · 6 · 2.8 kg", without the weight
    /// when no spool states one, and "Spools" when the filament has none shown.
    static func spoolsHeader(_ group: SpoolGroup?) -> String {
        guard let group else { return "Spools" }
        var text = "Spools · \(group.spoolCount)"
        if let remaining = group.remaining {
            text += " · \(SpoolUsage.weightText(remaining))"
        }
        return text
    }

    /// The brand, material and diameter, for example "AzureFilm · PETG · 1.75 mm".
    /// Blank parts are dropped.
    static func headerSubtitle(_ filament: Filament) -> String {
        [filament.vendor?.name, filament.material, filament.diameterText]
            .compactMap { $0.nonBlank }
            .joined(separator: " · ")
    }
}
