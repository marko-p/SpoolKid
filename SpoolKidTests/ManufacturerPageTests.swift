//
//  ManufacturerPageTests.swift
//  SpoolKidTests
//
//  Purpose: The rules the Manufacturer page renders: which filaments belong to
//  a vendor and in what order; the header line; the vendor's spec rows; its
//  brand's empty spools; and the stock text the Manufacturer page shows.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

struct ManufacturerPageTests {
    private var azure: Vendor { Vendor(id: 1, name: "AzureFilm") }
    private var azureLower: Vendor { Vendor(id: 2, name: "azurefilm") }

    /// Vendor 1 owns 10 and 11; vendor 2, named the same in another case, owns 12.
    private var all: [Filament] {
        [
            Filament(id: 11, name: "Vivid", material: "PLA", vendor: azure),
            Filament(id: 10, name: "Bright", material: "PETG", vendor: azure),
            Filament(id: 12, name: "Dark", material: "PLA", vendor: azureLower),
        ]
    }

    /// A spool of filament `filament`, active unless `archived` is set.
    private func spool(_ id: Int, filament: Int, remaining: Double?, archived: Bool? = nil) -> Spool {
        Spool(id: id, filament: Filament(id: filament), remainingWeight: remaining, archived: archived,
              statusId: nil, externalId: nil, purchaseDate: nil)
    }

    private func record(_ manufacturer: String, _ name: String, isDefault: Bool = false,
                        brandDefault: Bool = false) -> EmptySpoolRecord {
        EmptySpoolRecord(id: UUID(), manufacturer: manufacturer, name: name, weight: 100, photo: nil,
                         isDefault: isDefault, isManufacturerDefault: brandDefault, createdAt: Date())
    }

    // MARK: - Filaments

    @Test func filamentsAreMatchedByVendorIDInNameOrder() {
        #expect(ManufacturerPage.filaments(ofVendor: 1, in: all).map(\.id) == [10, 11])
    }

    @Test func aNilNameSortsByMaterial() {
        let unnamed = Filament(id: 13, material: "ABS", vendor: azure)
        #expect(ManufacturerPage.filaments(ofVendor: 1, in: all + [unnamed]).map(\.id) == [13, 10, 11])
    }

    @Test func equalNamesKeepAStableOrderByID() {
        let twins = [Filament(id: 21, name: "Same", vendor: azure), Filament(id: 20, name: "Same", vendor: azure)]
        #expect(ManufacturerPage.filaments(ofVendor: 1, in: twins).map(\.id) == [20, 21])
    }

    @Test func aRowTitleFallsBackFromABlankName() {
        #expect(ManufacturerPage.title(of: Filament(id: 1, name: "  Vivid ", material: "PLA")) == "Vivid")
        #expect(ManufacturerPage.title(of: Filament(id: 2, name: "  ", material: "ABS")) == "ABS")
        #expect(ManufacturerPage.title(of: Filament(id: 3)) == "Filament")
    }

    // MARK: - Header

    @Test func headerCountsActiveSpoolsOfTheVendorOnly() {
        let spools = [
            spool(1, filament: 10, remaining: 600),
            spool(2, filament: 11, remaining: 400),
            spool(3, filament: 10, remaining: 1000, archived: true),
            spool(4, filament: 12, remaining: 500),
        ]
        #expect(ManufacturerPage.headerText(vendorID: 1, filaments: all, spools: spools)
                == "2 filaments · 2 spools · \(SpoolUsage.weightText(1000)) left")
    }

    @Test func headerOmitsWeightWhenNothingIsKnown() {
        #expect(ManufacturerPage.headerText(vendorID: 1, filaments: all, spools: []) == "2 filaments · 0 spools")
        let unweighed = [spool(1, filament: 10, remaining: nil)]
        #expect(ManufacturerPage.headerText(vendorID: 1, filaments: all, spools: unweighed)
                == "2 filaments · 1 spool")
    }

    @Test func headerUsesSingularForOne() {
        #expect(ManufacturerPage.headerText(vendorID: 2, filaments: all, spools: []) == "1 filament · 0 spools")
    }

    // MARK: - Spec rows

    @Test func fieldRowsFollowVisibility() {
        let vendor = Vendor(id: 1, name: "AzureFilm", comment: "Cardboard", emptySpoolWeight: 164,
                            externalId: "x")
        #expect(ManufacturerPage.fieldRows(for: vendor, visibleFieldIDs: ["empty_spool_weight"])
                == [FilamentSpecRow(label: "Empty Spool Weight", value: SpoolUsage.weightText(164))])
        #expect(ManufacturerPage.fieldRows(for: vendor,
                                           visibleFieldIDs: ["comment", "empty_spool_weight", "external_id"])
                .map(\.label) == ["Comment", "Empty Spool Weight", "External ID"])
    }

    @Test func blankFieldValuesAreOmitted() {
        let vendor = Vendor(id: 1, name: "AzureFilm", comment: "  ", emptySpoolWeight: nil, externalId: "")
        #expect(ManufacturerPage.fieldRows(for: vendor,
                                           visibleFieldIDs: ["comment", "empty_spool_weight", "external_id"]).isEmpty)
    }

    // MARK: - Empty spools

    @Test func emptySpoolsUseTheLibrarysBrandRule() {
        let entries = [
            record("AzureFilm", "cardboard", isDefault: true),
            record("", "Generic"),
        ]
        #expect(ManufacturerPage.emptySpools(forVendorNamed: "azurefilm ", in: entries).map(\.name) == ["cardboard"])
    }

    // MARK: - Stock text

    @Test func stockTextReadsWeightAndCountOrNoSpools() {
        #expect(SpoolUsage.stockText(FilamentStock(spoolCount: 1, remaining: 918))
                == "\(SpoolUsage.weightText(918)) · 1 spool")
        #expect(SpoolUsage.stockText(FilamentStock(spoolCount: 2, remaining: nil)) == "2 spools")
        #expect(SpoolUsage.stockText(nil) == "No spools")
        #expect(SpoolUsage.stockText(FilamentStock(spoolCount: 0, remaining: nil)) == "No spools")
        #expect(SpoolUsage.noSpoolsText == "No spools")
    }
}
