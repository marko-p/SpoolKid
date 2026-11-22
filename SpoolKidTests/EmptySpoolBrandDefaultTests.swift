//
//  EmptySpoolBrandDefaultTests.swift
//  SpoolKidTests
//
//  Purpose: Which empty spool a brand starts with, and how the picker splits
//  the library by brand: `EmptySpoolLibrary.prefillEntry` and `pickerSections`.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

struct EmptySpoolBrandDefaultTests {
    private func record(_ manufacturer: String, _ name: String, isDefault: Bool = false, brand: Bool = false) -> EmptySpoolRecord {
        EmptySpoolRecord(
            id: UUID(), manufacturer: manufacturer, name: name, weight: 100, photo: nil,
            isDefault: isDefault, isManufacturerDefault: brand, createdAt: Date()
        )
    }

    // MARK: - prefillEntry

    @Test func theMarkedBrandDefaultWins() {
        let general = record("Bambu", "Reusable", isDefault: true)
        let a = record("Polymaker", "Cardboard")
        let b = record("Polymaker", "Plastic", brand: true)
        #expect(EmptySpoolLibrary.prefillEntry(forManufacturer: "Polymaker", in: [general, a, b]) == b)
    }

    @Test func aBrandsOnlyEntryIsItsDefault() {
        let general = record("Bambu", "Reusable", isDefault: true)
        let a = record("Polymaker", "Cardboard")
        #expect(EmptySpoolLibrary.prefillEntry(forManufacturer: "Polymaker", in: [general, a]) == a)
    }

    @Test func severalUnmarkedBrandEntriesFallBackToTheGeneralDefault() {
        let general = record("Bambu", "Reusable", isDefault: true)
        let entries = [general, record("Polymaker", "Cardboard"), record("Polymaker", "Plastic")]
        #expect(EmptySpoolLibrary.prefillEntry(forManufacturer: "Polymaker", in: entries) == general)
    }

    @Test func noBrandUsesTheGeneralDefault() {
        let general = record("Bambu", "Reusable", isDefault: true)
        let entries = [general, record("Polymaker", "Cardboard")]
        #expect(EmptySpoolLibrary.prefillEntry(forManufacturer: nil, in: entries) == general)
        #expect(EmptySpoolLibrary.prefillEntry(forManufacturer: "  ", in: entries) == general)
    }

    @Test func aBrandWithNoEntriesUsesTheGeneralDefault() {
        let general = record("Bambu", "Reusable", isDefault: true)
        #expect(EmptySpoolLibrary.prefillEntry(forManufacturer: "eSun", in: [general, record("Polymaker", "Cardboard")]) == general)
    }

    @Test func nothingToUseIsNil() {
        let entries = [record("Polymaker", "Cardboard"), record("Polymaker", "Plastic")]
        #expect(EmptySpoolLibrary.prefillEntry(forManufacturer: "eSun", in: entries) == nil)
        #expect(EmptySpoolLibrary.prefillEntry(forManufacturer: "Polymaker", in: []) == nil)
    }

    @Test func brandsMatchIgnoringCaseAndSpaces() {
        let general = record("Bambu", "Reusable", isDefault: true)
        let a = record("Polymaker", "Cardboard")
        #expect(EmptySpoolLibrary.prefillEntry(forManufacturer: " polymaker ", in: [general, a]) == a)
    }

    // MARK: - pickerSections

    @Test func theBrandsEntriesComeFirstWithItsDefaultOnTop() {
        let general = record("Bambu", "Reusable", isDefault: true)
        let a = record("Polymaker", "Cardboard")
        let b = record("Polymaker", "Plastic", brand: true)
        let sections = EmptySpoolLibrary.pickerSections(forManufacturer: "polymaker", in: [general, a, b])
        #expect(sections.brand == [b, a])
        #expect(sections.other == [general])
    }

    @Test func otherKeepsTheLibraryOrder() {
        let general = record("Bambu", "Reusable", isDefault: true)
        let esun = record("eSun", "Black")
        let sunlu = record("Sunlu", "Grey")
        let sections = EmptySpoolLibrary.pickerSections(
            forManufacturer: "Polymaker", in: [general, esun, record("Polymaker", "Cardboard"), sunlu]
        )
        #expect(sections.other == [general, esun, sunlu])
    }

    @Test func noBrandOrNoMatchLeavesTheBrandSectionEmpty() {
        let all = [record("Bambu", "Reusable", isDefault: true), record("Polymaker", "Cardboard")]
        for manufacturer in [nil, "", "Prusament"] as [String?] {
            let sections = EmptySpoolLibrary.pickerSections(forManufacturer: manufacturer, in: all)
            #expect(sections.brand.isEmpty)
            #expect(sections.other == all)
        }
    }

    @Test func anEntryThatIsBothDefaultsAppearsOnce() {
        let both = record("Polymaker", "Cardboard", isDefault: true, brand: true)
        let esun = record("eSun", "Black")
        let sections = EmptySpoolLibrary.pickerSections(forManufacturer: "Polymaker", in: [both, esun])
        #expect(sections.brand == [both])
        #expect(sections.other == [esun])
    }
}
