//
//  SpoolListRowCopyTests.swift
//  SpoolKidTests
//
//  Purpose: The words and numbers the grouped spool list prints — the spool row,
//  the fold row, the group header and what VoiceOver reads for a spool row.
//  The views only render these strings, so the strings are what is tested.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct SpoolListRowCopyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let en = Locale(identifier: "en_US")

    private var azure: Vendor { Vendor(id: 1, name: "AzureFilm") }
    private var white: Filament { Filament(id: 7, name: "Original WHITE", material: "PETG", vendor: azure) }
    private var nameless: Filament { Filament(id: 9) }

    /// Spool #4 by default: AzureFilm Original WHITE, 244.2 g of a 1000 g basis,
    /// last used two days before `now`.
    private func spool(_ id: Int = 4, filament: Filament? = nil, remaining: Double? = 244.2,
                       initial: Double? = 1000, lastUsed: Date? = nil, archived: Bool? = nil,
                       extra: [String: String]? = nil, location: String? = nil) -> Spool {
        Spool(id: id, filament: filament ?? white,
              lastUsed: lastUsed ?? now.addingTimeInterval(-2 * 86_400),
              remainingWeight: remaining, initialWeight: initial, usedWeight: nil, location: location,
              archived: archived, extra: extra, statusId: nil, externalId: nil, purchaseDate: nil)
    }

    private func group(count: Int, remaining: Double? = 0, entries: [SpoolListEntry] = []) -> SpoolGroup {
        SpoolGroup(id: "filament:7", title: "Original WHITE", isNoneGroup: false, filament: white, vendor: nil,
                   location: nil, entries: entries, spoolIDs: [], spoolCount: count, remaining: remaining)
    }

    /// A group whose only spool is archived: it has entries, but no active count.
    private var archivedOnly: SpoolGroup {
        group(count: 0, remaining: nil, entries: [.spool(spool(4, archived: true))])
    }

    // MARK: - SpoolUsageRow

    @Test func gramsAndNoGrams() {
        #expect(SpoolUsageRow.gramsText(for: spool()) == "244 g")
        #expect(SpoolUsageRow.gramsText(for: spool(remaining: nil)) == nil)
    }

    @Test func barClamps() throws {
        let partial = try #require(SpoolUsageRow.barFraction(for: spool(remaining: 244.2, initial: 1000)))
        #expect(abs(partial - 0.2442) < 0.0001)
        #expect(SpoolUsageRow.barFraction(for: spool(remaining: 1200, initial: 1000)) == 1.0)
        #expect(SpoolUsageRow.barFraction(for: spool(remaining: -5, initial: 1000)) == 0.0)
        #expect(SpoolUsageRow.barFraction(for: spool(remaining: 500, initial: nil)) == nil)
    }

    @Test func titlesPerStyle() {
        #expect(SpoolUsageRow.title(for: spool(), style: .withFilament) == "AzureFilm Original WHITE")
        #expect(SpoolUsageRow.title(for: spool(), style: .withFilamentNameOnly) == "Original WHITE")
        #expect(SpoolUsageRow.title(for: spool(filament: nameless), style: .withFilament) == "Spool #4")
        #expect(SpoolUsageRow.title(for: spool(filament: nameless), style: .withFilamentNameOnly) == "Spool #4")
        // Material mode keeps the brand: only the material is dropped from the row.
        #expect(SpoolUsageRow.title(for: spool(), style: .withFilamentNoMaterial) == "AzureFilm Original WHITE")
    }

    @Test func usageLines() {
        #expect(SpoolUsageRow.usageLine(for: spool(), style: .underFilament, now: now, locale: en) == "used 2 days ago")
        #expect(SpoolUsageRow.usageLine(for: spool(), style: .withFilament, now: now, locale: en) == "PETG · used 2 days ago")
        #expect(SpoolUsageRow.usageLine(for: spool(archived: true), style: .underFilament, now: now, locale: en)
                == "Archived · used 2 days ago")
        // Under a material header the material is already named.
        #expect(SpoolUsageRow.usageLine(for: spool(), style: .withFilamentNoMaterial, now: now, locale: en)
                == "used 2 days ago")
        #expect(SpoolUsageRow.usageLine(for: spool(archived: true), style: .withFilamentNoMaterial, now: now, locale: en)
                == "Archived · used 2 days ago")
        #expect(SpoolUsageRow.usageLine(for: spool(), style: .withFilamentNameOnly, now: now, locale: en)
                == "PETG · used 2 days ago")
    }

    @Test func usageLineAppendsLocationOnlyWhenAsked() {
        #expect(SpoolUsageRow.usageLine(for: spool(location: "Drybox 1"), style: .underFilament, now: now, locale: en,
                                        showsLocation: true) == "used 2 days ago · Drybox 1")
        #expect(SpoolUsageRow.usageLine(for: spool(location: "Drybox 1"), style: .underFilament, now: now, locale: en)
                == "used 2 days ago")
        #expect(SpoolUsageRow.usageLine(for: spool(location: "  "), style: .underFilament, now: now, locale: en,
                                        showsLocation: true) == "used 2 days ago")
        #expect(SpoolUsageRow.usageLine(for: spool(), style: .underFilament, now: now, locale: en,
                                        showsLocation: true) == "used 2 days ago")
    }

    @Test func accessibilityLabelAppendsLocationOnlyWhenAsked() {
        #expect(SpoolUsageRow.accessibilityLabel(for: spool(location: "Drybox 1"), style: .underFilament,
                                                 now: now, locale: en, showsLocation: true)
                == "Spool 4, used 2 days ago, 244 grams left, Drybox 1")
        #expect(SpoolUsageRow.accessibilityLabel(for: spool(location: "Drybox 1"), style: .underFilament,
                                                 now: now, locale: en)
                == "Spool 4, used 2 days ago, 244 grams left")
        #expect(SpoolUsageRow.accessibilityLabel(for: spool(location: "  "), style: .underFilament,
                                                 now: now, locale: en, showsLocation: true)
                == "Spool 4, used 2 days ago, 244 grams left")
    }

    @Test func accessibilityLabels() {
        #expect(SpoolUsageRow.accessibilityLabel(for: spool(), style: .underFilament, now: now, locale: en)
                == "Spool 4, used 2 days ago, 244 grams left")
        #expect(SpoolUsageRow.accessibilityLabel(for: spool(), style: .withFilament, now: now, locale: en)
                == "Spool 4, AzureFilm Original WHITE, PETG, used 2 days ago, 244 grams left")
        #expect(SpoolUsageRow.accessibilityLabel(for: spool(archived: true), style: .underFilament, now: now, locale: en)
                == "Spool 4, used 2 days ago, 244 grams left, archived")
        #expect(SpoolUsageRow.accessibilityLabel(for: spool(remaining: nil), style: .underFilament, now: now, locale: en)
                == "Spool 4, used 2 days ago")
    }

    @Test func tagCountReadsMappedTags() {
        #expect(SpoolUsageRow.tagCount(for: spool(extra: ["card_uids": "\"04A1B2C3D4E5F6,04AABBCCDDEEFF\""])) == 2)
        #expect(SpoolUsageRow.tagCount(for: spool()) == 0)
    }

    @Test func accessibilityLabelNamesTags() {
        let twoTags = ["card_uids": "\"04A1B2C3D4E5F6,04AABBCCDDEEFF\""]
        let oneTag = ["card_uids": "\"04A1B2C3D4E5F6\""]
        #expect(SpoolUsageRow.accessibilityLabel(for: spool(extra: twoTags), style: .underFilament, now: now, locale: en)
                == "Spool 4, used 2 days ago, 2 tags, 244 grams left")
        #expect(SpoolUsageRow.accessibilityLabel(for: spool(extra: oneTag), style: .underFilament, now: now, locale: en)
                == "Spool 4, used 2 days ago, 1 tag, 244 grams left")
        #expect(SpoolUsageRow.accessibilityLabel(for: spool(), style: .underFilament, now: now, locale: en)
                == "Spool 4, used 2 days ago, 244 grams left")
    }

    @Test func accessibilityLabelSpellsKilogramsOut() {
        #expect(SpoolUsageRow.accessibilityLabel(for: spool(remaining: 1000), style: .underFilament, now: now, locale: en)
                == "Spool 4, used 2 days ago, 1 kilogram left")
        #expect(SpoolUsageRow.accessibilityLabel(for: spool(remaining: 2800), style: .underFilament, now: now, locale: en)
                == "Spool 4, used 2 days ago, 2.8 kilograms left")
    }

    // The material is on the group header, so VoiceOver need not read it per row.
    @Test func accessibilityLabelFollowsTheMaterialStyle() {
        #expect(SpoolUsageRow.accessibilityLabel(for: spool(), style: .withFilamentNoMaterial, now: now, locale: en)
                == "Spool 4, AzureFilm Original WHITE, used 2 days ago, 244 grams left")
    }

    @Test func idColumnFitsTheWidestIDInTheList() {
        #expect(SpoolUsageRow.idDigits(for: [spool(8), spool(12), spool(7)]) == 2)
        #expect(SpoolUsageRow.idDigits(for: [spool(8)]) == 1)
        #expect(SpoolUsageRow.idDigits(for: []) == 0)
        #expect(SpoolUsageRow.idColumnTemplate(digits: 3) == "#888")
        #expect(SpoolUsageRow.idColumnTemplate(digits: 0) == "#8")
    }

    @Test func onlyRowsUnderAFilamentDropTheListInsets() {
        #expect(SpoolUsageRow.rowInsets(for: .underFilament) == SpoolUsageRow.compactRowInsets)
        #expect(SpoolUsageRow.rowInsets(for: .withFilament) == nil)
        #expect(SpoolUsageRow.rowInsets(for: .withFilamentNameOnly) == nil)
        #expect(SpoolUsageRow.rowInsets(for: .withFilamentNoMaterial) == nil)
    }

    // MARK: - SpoolFoldRow

    @Test func foldLabels() {
        let pair = SpoolFold(id: "fold:pair", spools: [spool(4), spool(5)], basis: 1000)
        #expect(SpoolFoldRow.label(for: pair) == "2 unused · 1 kg each")

        let trio = SpoolFold(id: "fold:trio", spools: [spool(4), spool(5), spool(6)], basis: 818)
        #expect(SpoolFoldRow.label(for: trio) == "3 unused · 818 g each")
    }

    @Test func foldAccessibilityLabelNamesCountAndWeight() {
        let tiger = Filament(id: 4, name: "Original TIGER ORANGE", material: "PETG", vendor: azure)
        let pair = SpoolFold(id: "fold:pair", spools: [spool(2, filament: tiger), spool(8, filament: tiger)], basis: 1000)
        #expect(SpoolFoldRow.accessibilityLabel(for: pair) == "2 unused spools, 1 kilogram each")
        let trio = SpoolFold(id: "fold:trio", spools: [spool(4), spool(5), spool(6)], basis: 818)
        #expect(SpoolFoldRow.accessibilityLabel(for: trio) == "3 unused spools, 818 grams each")
    }

    // MARK: - SpoolGroupHeader

    @Test func headerCaptions() {
        #expect(SpoolGroupHeader.caption(for: group(count: 1), selectedCount: 0) == "1 spool")
        #expect(SpoolGroupHeader.caption(for: archivedOnly, selectedCount: 0) == "Archived only")
        #expect(SpoolGroupHeader.caption(for: group(count: 3), selectedCount: 2) == "3 spools · 2 selected")
    }

    @Test func headerCaptionSaysNoSpoolsForAnEmptyGroup() {
        #expect(SpoolGroupHeader.caption(for: group(count: 0), selectedCount: 0) == "No spools")
        #expect(SpoolGroupHeader.caption(for: archivedOnly, selectedCount: 0) == "Archived only")
    }

    @Test func chevronHiddenForAGroupWithNoRows() {
        #expect(!SpoolGroupHeader.showsChevron(for: group(count: 0)))
        #expect(SpoolGroupHeader.showsChevron(for: group(count: 1, entries: [.spool(spool())])))
        #expect(SpoolGroupHeader.showsChevron(for: archivedOnly))
    }

    @Test func headerTotals() {
        #expect(SpoolGroupHeader.totalText(for: group(count: 2, remaining: 2000)) == "2 kg")
        #expect(SpoolGroupHeader.totalText(for: group(count: 0)) == nil)
        #expect(SpoolGroupHeader.totalText(for: group(count: 1, remaining: nil)) == nil)
    }

    @Test func chevronNamesTheGroup() {
        #expect(SpoolGroupHeader.chevronLabel(for: group(count: 2), isCollapsed: false) == "Collapse Original WHITE")
        #expect(SpoolGroupHeader.chevronLabel(for: group(count: 2), isCollapsed: true) == "Expand Original WHITE")
    }

    @Test func chevronHintExplainsAForcedOpenGroup() {
        #expect(SpoolGroupHeader.chevronHint(isForcedOpen: true) == "The group stays open while searching.")
        #expect(SpoolGroupHeader.chevronHint(isForcedOpen: false) == nil)
    }

    @Test func filamentSubtitles() {
        #expect(SpoolGroupHeader.filamentSubtitle(Filament(id: 7, vendor: azure, diameter: 1.75)) == "AzureFilm · 1.75 mm")
        #expect(SpoolGroupHeader.filamentSubtitle(Filament(id: 7, diameter: 1.75)) == "1.75 mm")
        #expect(SpoolGroupHeader.filamentSubtitle(Filament(id: 7)) == "")
    }
}
