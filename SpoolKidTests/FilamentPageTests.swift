//
//  FilamentPageTests.swift
//  SpoolKidTests
//
//  Purpose: The rules the Filament page renders: which spec rows show, in the
//  filament form's order and with what text; which spools belong to a filament
//  and in what order; and the header subtitle.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
import Foundation
@testable import SpoolKid

struct FilamentPageTests {
    private var azure: Vendor { Vendor(id: 1, name: "AzureFilm") }
    private let touched = Date(timeIntervalSince1970: 1_800_000_000)

    /// Every field set, so every spec row has a value.
    private var full: Filament {
        Filament(id: 7, name: "Original WHITE", material: "PETG", vendor: azure, price: 19.9,
                 colorHex: "ff8800", density: 1.24, diameter: 1.75, weight: 1000, spoolWeight: 250,
                 articleNumber: "AZ-7", comment: "Dries well", settingsExtruderTemp: 240,
                 settingsBedTemp: 80, multiColorHexes: "ff0000,00ff00",
                 multiColorDirection: "Longitudinal", externalId: "ext-7")
    }

    /// A spool of filament `filament`, active unless `archived` is set.
    private func spool(_ id: Int, filament: Int = 7, remaining: Double? = nil, lastUsed: Date? = nil,
                       archived: Bool? = nil) -> Spool {
        Spool(id: id, filament: Filament(id: filament, name: "Original WHITE", material: "PETG", vendor: azure),
              lastUsed: lastUsed, remainingWeight: remaining, initialWeight: 1000, usedWeight: nil,
              archived: archived, statusId: nil, externalId: nil, purchaseDate: nil)
    }

    @Test func specRowsFollowTheFormsOrderAndGating() {
        let labels = FilamentPage.specRows(for: full, visibleFieldIDs: ["price", "comment"]).map(\.label)
        #expect(labels == ["Material", "Color", "Density", "Diameter", "Price", "Comment"])
    }

    @Test func specRowsUseTheFormsOrderWhenAllAreVisible() {
        let all: Set<String> = [
            "settings_extruder_temp", "settings_bed_temp", "price", "weight", "spool_weight", "article_number",
            "comment", "external_id",
        ]
        #expect(FilamentPage.specRows(for: full, visibleFieldIDs: all).map(\.label) == [
            "Material", "Color", "Density", "Diameter", "Extruder Temp", "Bed Temp", "Price", "Net Weight",
            "Default Spool Weight", "Article Number", "Comment",
            "External ID",
        ])
    }

    @Test func specRowsOmitBlankAndNilValues() {
        let blanks = Filament(id: 9, material: nil, colorHex: "FFFFFF", density: 1.24, diameter: 1.75,
                              articleNumber: "", comment: "  ")
        #expect(FilamentPage.specRows(for: blanks, visibleFieldIDs: ["comment", "article_number"]).map(\.label)
                == ["Color", "Density", "Diameter"])
    }

    @Test func specRowValuesAreFormatted() {
        let rows = FilamentPage.specRows(for: full, visibleFieldIDs: ["settings_extruder_temp", "weight"])
        #expect(rows.contains(FilamentSpecRow(label: "Density", value: "1.24 g/cm³")))
        #expect(rows.contains(FilamentSpecRow(label: "Diameter", value: "1.75 mm")))
        #expect(rows.contains(FilamentSpecRow(label: "Extruder Temp", value: "240 °C")))
        #expect(rows.contains(FilamentSpecRow(label: "Net Weight", value: "1 kg")))
    }

    @Test func priceHasTwoDecimalsAndColorIsUppercased() {
        let priced = Filament(id: 7, price: 19.9, colorHex: "ff8800")
        #expect(FilamentPage.specRows(for: priced, visibleFieldIDs: ["price"]) == [
            FilamentSpecRow(label: "Color", value: "FF8800"),
            FilamentSpecRow(label: "Price", value: "19.90"),
        ])
    }

    @Test func pageSpoolsHideArchivedUnlessAsked() {
        let all = [
            spool(1, remaining: 600),
            spool(2, remaining: 400, archived: true),
            spool(3, filament: 8, remaining: 1000),
        ]
        #expect(FilamentPage.spools(ofFilament: 7, in: all, showArchived: false).map(\.id) == [1])
        #expect(Set(FilamentPage.spools(ofFilament: 7, in: all, showArchived: true).map(\.id)) == [1, 2])
    }

    @Test func pageSpoolsNewestFirst() {
        let all = [
            spool(1, lastUsed: touched.addingTimeInterval(-86_400)),
            spool(2), // no last-used or registered date: reads as the oldest
            spool(3, lastUsed: touched),
        ]
        #expect(FilamentPage.spools(ofFilament: 7, in: all, showArchived: false).map(\.id) == [3, 1, 2])
    }

    @Test func pageGroupTotalsCountActiveSpoolsOnly() {
        let all = [spool(1, remaining: 600), spool(2, remaining: 400, archived: true)]
        let group = FilamentPage.group(ofFilament: 7, in: all, showArchived: true)
        #expect(group?.spoolCount == 1)
        #expect(group?.remaining == 600)
        #expect(Set(group?.spoolIDs ?? []) == [1, 2])
    }

    @Test func spoolsHeaderCountsAndWeighsTheActiveSpools() {
        let all = [spool(1, remaining: 2000), spool(2, remaining: 800), spool(3, remaining: 400, archived: true)]
        let group = FilamentPage.group(ofFilament: 7, in: all, showArchived: true)
        #expect(FilamentPage.spoolsHeader(group) == "Spools · 2 · \(SpoolUsage.weightText(2800))")
    }

    @Test func spoolsHeaderDropsAMissingWeightAndNamesAnEmptyPage() {
        let group = FilamentPage.group(ofFilament: 7, in: [spool(1)], showArchived: false)
        #expect(group?.remaining == nil)
        #expect(FilamentPage.spoolsHeader(group) == "Spools · 1")
        #expect(FilamentPage.spoolsHeader(nil) == "Spools")
    }

    @Test func pageGroupIsNilWhenEverySpoolIsArchivedAndHidden() {
        let all = [spool(1, remaining: 400, archived: true)]
        #expect(FilamentPage.group(ofFilament: 7, in: all, showArchived: false) == nil)
    }

    @Test func headerSubtitleJoinsBrandMaterialDiameter() {
        #expect(FilamentPage.headerSubtitle(full) == "AzureFilm · PETG · 1.75 mm")
        #expect(FilamentPage.headerSubtitle(Filament(id: 9, material: "  ")) == "")
    }

    @Test func headerSubtitleDropsAMissingVendor() {
        #expect(FilamentPage.headerSubtitle(Filament(id: 9, material: "PLA", diameter: 1.75)) == "PLA · 1.75 mm")
    }
}
