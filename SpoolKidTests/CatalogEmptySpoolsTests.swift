//
//  CatalogEmptySpoolsTests.swift
//  SpoolKidTests
//
//  Purpose: The catalogue's empty-spool weights as the Empty Spools picker
//  lists them: one row per brand, spool type and weight, the chosen brand
//  first, and how each catalogue answers. No test touches the network; every
//  FilaManDB call goes through an injected fetch.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

struct CatalogEmptySpoolsTests {
    private static func entry(
        _ manufacturer: String = "Prusament", name: String = "Galaxy Black",
        spoolType: String? = "plastic", weight: Double? = 1000, spoolWeight: Double? = 193
    ) -> SpoolmanDBFilament {
        SpoolmanDBFilament(
            id: UUID().uuidString, manufacturer: manufacturer, name: name, material: "PLA",
            spoolType: spoolType, density: 1.24, weight: weight, spoolWeight: spoolWeight, diameter: 1.75,
            colorHex: nil, extruderTemp: nil, bedTemp: nil
        )
    }

    // MARK: - Rows

    /// SpoolmanDB's Prusament 193 g spool holds 1 kg and 800 g: one row, both sizes.
    @Test func oneRowPerBrandTypeAndWeightListingItsSizes() throws {
        let sections = CatalogEmptySpools.sections(from: [
            Self.entry(name: "Jet Black", weight: 1000),
            Self.entry(name: "Galaxy Black", weight: 800),
            Self.entry(name: "Galaxy Black", weight: 1000),
            Self.entry(name: "Galaxy Black", weight: 2000, spoolWeight: 219)
        ], forManufacturer: "Prusament")

        let rows = try #require(sections.brand).rows
        #expect(rows.map(\.grams) == [193, 219])
        #expect(rows[0].netWeights == [800, 1000])
        #expect(rows[0].productCount == 3)
        #expect(rows[0].exampleName == "Galaxy Black")
        #expect(rows[0].spoolType == "plastic")
        #expect(rows[1].netWeights == [2000])
    }

    @Test func entriesWithoutASpoolWeightAreLeftOut() {
        let sections = CatalogEmptySpools.sections(from: [
            Self.entry(spoolWeight: nil), Self.entry(spoolWeight: 0)
        ], forManufacturer: "Prusament")
        #expect(sections.brand == nil)
        #expect(sections.others.isEmpty)
    }

    /// The type is compared trimmed and ignoring case; no type is its own row.
    @Test func spoolTypeIgnoresCaseAndNoTypeStaysApart() throws {
        let sections = CatalogEmptySpools.sections(from: [
            Self.entry(spoolType: "Plastic"), Self.entry(spoolType: " plastic "), Self.entry(spoolType: nil)
        ], forManufacturer: "Prusament")
        let rows = try #require(sections.brand).rows
        #expect(rows.count == 2)
        #expect(Set(rows.map(\.spoolType)) == ["plastic", nil])
    }

    /// A size the entry does not state is not listed, but the product counts.
    @Test func anUnstatedSizeIsNotListed() throws {
        let sections = CatalogEmptySpools.sections(from: [
            Self.entry(weight: nil), Self.entry(weight: 1000)
        ], forManufacturer: "Prusament")
        let row = try #require(sections.brand?.rows.first)
        #expect(row.netWeights == [1000])
        #expect(row.productCount == 2)
    }

    // MARK: - Sections

    @Test func theChosenBrandComesFirstAndTheOthersAToZ() throws {
        let sections = CatalogEmptySpools.sections(from: [
            Self.entry("Sunlu", spoolWeight: 140),
            Self.entry("Bambu Lab", spoolWeight: 250),
            Self.entry("Prusament"),
            Self.entry("elegoo", spoolWeight: 160)
        ], forManufacturer: " prusament ")

        #expect(try #require(sections.brand).brand == "Prusament")
        #expect(sections.others.map(\.brand) == ["Bambu Lab", "elegoo", "Sunlu"])
    }

    @Test func noChosenBrandListsEveryBrand() {
        let entries = [Self.entry("Sunlu", spoolWeight: 140), Self.entry("Prusament")]
        for manufacturer in [nil, "", "  ", "Nobody"] {
            let sections = CatalogEmptySpools.sections(from: entries, forManufacturer: manufacturer)
            #expect(sections.brand == nil)
            #expect(sections.others.map(\.brand) == ["Prusament", "Sunlu"])
        }
    }

    /// One brand spelled two ways is one section, under the first spelling met.
    @Test func oneBrandUnderTwoSpellingsIsOneSection() {
        let sections = CatalogEmptySpools.sections(from: [
            Self.entry("Prusament"), Self.entry("PRUSAMENT ", spoolWeight: 280)
        ], forManufacturer: nil)
        #expect(sections.others.count == 1)
        #expect(sections.others.first?.brand == "Prusament")
        #expect(sections.others.first?.rows.map(\.grams) == [193, 280])
    }
}

/// The URLs a stubbed FilaManDB was asked for.
private nonisolated final class AskedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func record(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        urls.append(url)
    }

    var all: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}

struct CatalogEmptySpoolsFilaManDBTests {
    private static let manufacturers = Data("""
    {"total":1,"page":1,"page_size":200,"items":[{"id":689,"name":"Prusament"}]}
    """.utf8)

    private static let prusamentFilaments = Data("""
    {"total":1,"page":1,"page_size":200,"items":[{"id":1,"color_name":"Galaxy Black","designation":"x",
     "hex_color":"#1A1A1A","diameter_mm":1.75,"density_g_cm3":1.24,"nominal_weight_g":1000,
     "manufacturer":{"id":689,"name":"Prusament"},"material":{"id":11,"key":"pla","name":"PLA"},
     "spool_profile":{"id":1,"name":"Spool","empty_weight_g":220,"spool_material":"Plastic"}}]}
    """.utf8)

    private static func catalog(_ asked: AskedURLs, failing: Bool = false) -> FilaManDBCatalog {
        FilaManDBCatalog(fetch: { url in
            asked.record(url)
            if failing { throw URLError(.notConnectedToInternet) }
            return url.path.hasSuffix("/manufacturers") ? Self.manufacturers : Self.prusamentFilaments
        })
    }

    /// Only the chosen brand: FilaManDB pages by brand, and listing every
    /// brand would be hundreds of requests.
    @Test func readsTheChosenBrandsFilaments() async throws {
        let asked = AskedURLs()
        let load = await CatalogEmptySpools.filamanDBEntries(
            forManufacturer: "Prusament", catalog: Self.catalog(asked)
        )

        #expect(load.answer == .answered)
        #expect(load.entries.map(\.spoolWeight) == [220])
        let filamentURL = try #require(asked.all.last)
        #expect(filamentURL.path.hasSuffix("/filaments"))
        #expect(filamentURL.query?.contains("manufacturer_id=689") == true)
    }

    @Test func noBrandAsksNothing() async {
        let asked = AskedURLs()
        for manufacturer in [nil, "", "   "] {
            let load = await CatalogEmptySpools.filamanDBEntries(
                forManufacturer: manufacturer, catalog: Self.catalog(asked)
            )
            #expect(load.answer == .noBrand)
            #expect(load.entries.isEmpty)
        }
        #expect(asked.all.isEmpty)
    }

    @Test func aBrandFilaManDBDoesNotListIsNoBrand() async {
        let asked = AskedURLs()
        let load = await CatalogEmptySpools.filamanDBEntries(forManufacturer: "Nobody", catalog: Self.catalog(asked))
        #expect(load.answer == .noBrand)
        #expect(asked.all.allSatisfy { $0.path.hasSuffix("/manufacturers") })
    }

    @Test func anUnreachableCatalogueFails() async {
        let load = await CatalogEmptySpools.filamanDBEntries(
            forManufacturer: "Prusament", catalog: Self.catalog(AskedURLs(), failing: true)
        )
        #expect(load.answer == .failed)
        #expect(load.entries.isEmpty)
    }
}

@MainActor
struct CatalogEmptySpoolRowTextTests {
    private static func row(
        spoolType: String? = "plastic", grams: Double = 193, netWeights: [Double] = [800, 1000],
        productCount: Int = 53, exampleName: String = "Galaxy Black"
    ) -> CatalogEmptySpool {
        CatalogEmptySpool(
            brand: "Prusament", spoolType: spoolType, grams: grams, netWeights: netWeights,
            productCount: productCount, exampleName: exampleName
        )
    }

    @Test func titleNamesTheSpoolType() {
        #expect(CatalogEmptySpoolRow.title(for: Self.row()) == "Plastic spool")
        #expect(CatalogEmptySpoolRow.title(for: Self.row(spoolType: "cardboard")) == "Cardboard spool")
        #expect(CatalogEmptySpoolRow.title(for: Self.row(spoolType: nil)) == "Spool")
    }

    @Test func detailListsSizesAndProducts() {
        #expect(CatalogEmptySpoolRow.detail(for: Self.row()) == "800 g, 1 kg · 53 products, e.g. Galaxy Black")
        #expect(
            CatalogEmptySpoolRow.detail(for: Self.row(netWeights: [800], productCount: 1, exampleName: "Galaxy Black (NFC)"))
                == "800 g · 1 product: Galaxy Black (NFC)"
        )
        #expect(CatalogEmptySpoolRow.detail(for: Self.row(netWeights: [], productCount: 9)) == "9 products, e.g. Galaxy Black")
    }

    /// Whole hundreds from 1 kg up read as kilograms; anything else stays grams.
    @Test func sizesReadAsKilogramsOnlyWhenRound() {
        #expect(CatalogEmptySpoolRow.size(1000) == "1 kg")
        #expect(CatalogEmptySpoolRow.size(2500) == "2.5 kg")
        #expect(CatalogEmptySpoolRow.size(1034) == "1034 g")
        #expect(CatalogEmptySpoolRow.size(500) == "500 g")
    }

    @Test func accessibilityLabelReadsTheWholeRow() {
        #expect(
            CatalogEmptySpoolRow.accessibilityLabel(for: Self.row())
                == "Plastic spool, 193 grams, 800 g, 1 kg · 53 products, e.g. Galaxy Black"
        )
    }
}
