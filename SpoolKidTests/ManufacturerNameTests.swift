//
//  ManufacturerNameTests.swift
//  SpoolKidTests
//
//  Purpose: The one "same manufacturer" rule — trimmed, case-insensitive.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
@testable import SpoolKid

struct ManufacturerNameTests {
    private let vendors = [
        Vendor(id: 1, name: "ANYCUBIC"),
        Vendor(id: 2, name: "Elegoo")
    ]

    @Test func keyTrimsAndLowercases() {
        #expect(ManufacturerName.key("  Elegoo \n") == "elegoo")
    }

    @Test func matchesAcrossCaseAndSurroundingWhitespace() {
        #expect(ManufacturerName.vendor(named: "elegoo", in: vendors)?.id == 2)
        #expect(ManufacturerName.vendor(named: "ELEGOO", in: vendors)?.id == 2)
        #expect(ManufacturerName.vendor(named: "  Elegoo ", in: vendors)?.id == 2)
    }

    @Test func aStoredNameWithSpacesStillMatches() {
        let padded = [Vendor(id: 3, name: " Sunlu ")]
        #expect(ManufacturerName.vendor(named: "sunlu", in: padded)?.id == 3)
    }

    /// The scanned-brand case the filament form relied on: no literal-brand
    /// aliasing ("AC" is not ANYCUBIC).
    @Test func unknownNameMatchesNothing() {
        #expect(ManufacturerName.vendor(named: "AC", in: vendors) == nil)
    }

    @Test func blankNameMatchesNothing() {
        #expect(ManufacturerName.vendor(named: "", in: vendors) == nil)
        #expect(ManufacturerName.vendor(named: "  ", in: vendors) == nil)
    }

    // MARK: - Distinct names

    @Test func distinctKeepsOneSpellingPerManufacturerSorted() {
        let names = ManufacturerName.distinct(
            ["Sunlu", " sunlu", "Elegoo", "", "  ", "ELEGOO ", "Bambu Lab"]
        )
        #expect(names == ["Bambu Lab", "Elegoo", "Sunlu"])
    }

    // MARK: - Resolving a pending name on Save

    @MainActor @Test func resolveReusesAnExistingManufacturerWithoutCreating() async {
        var created: [String] = []
        let vendor = await ManufacturerName.resolve(" elegoo ", in: vendors) { name in
            created.append(name)
            return Vendor(id: 99, name: name)
        }
        #expect(vendor?.id == 2)
        #expect(created.isEmpty)
    }

    @MainActor @Test func resolveCreatesAMissingManufacturerOnceWithTheTrimmedName() async {
        var created: [String] = []
        let vendor = await ManufacturerName.resolve("  Rosa3D ", in: vendors) { name in
            created.append(name)
            return Vendor(id: 7, name: name)
        }
        #expect(vendor?.id == 7)
        #expect(created == ["Rosa3D"])
    }

    @MainActor @Test func resolveReportsAFailedCreateAsNil() async {
        let vendor = await ManufacturerName.resolve("Rosa3D", in: vendors) { _ in nil }
        #expect(vendor == nil)
    }
}
