//
//  EmptySpoolRowTests.swift
//  SpoolKidTests
//
//  Purpose: What VoiceOver reads for one empty-spool row — the row is one
//  element, so its label carries the manufacturer and name, the grams and the default mark.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

struct EmptySpoolRowTests {
    private func record(
        manufacturer: String = "", name: String, weight: Double, isDefault: Bool, isManufacturerDefault: Bool = false
    ) -> EmptySpoolRecord {
        EmptySpoolRecord(
            id: UUID(), manufacturer: manufacturer, name: name, weight: weight, photo: nil,
            isDefault: isDefault, isManufacturerDefault: isManufacturerDefault, createdAt: Date()
        )
    }

    @Test func theDefaultEntrySaysSo() {
        let label = EmptySpoolRow.accessibilityLabel(
            for: record(name: "Bambu reusable", weight: 250, isDefault: true)
        )
        #expect(label == "Bambu reusable, 250 grams, default")
    }

    @Test func aFractionalWeightIsReadAsTyped() {
        let label = EmptySpoolRow.accessibilityLabel(
            for: record(name: "Sunlu cardboard", weight: 132.5, isDefault: false)
        )
        #expect(label == "Sunlu cardboard, 132.5 grams")
    }

    @Test func theManufacturerIsReadBeforeTheName() {
        let label = EmptySpoolRow.accessibilityLabel(
            for: record(manufacturer: "Elegoo", name: "cardboard", weight: 132.5, isDefault: false)
        )
        #expect(label == "Elegoo cardboard, 132.5 grams")
    }

    @Test func aBrandDefaultNamesItsBrand() {
        let label = EmptySpoolRow.accessibilityLabel(
            for: record(manufacturer: "Polymaker", name: "cardboard", weight: 140, isDefault: false, isManufacturerDefault: true)
        )
        #expect(label == "Polymaker cardboard, 140 grams, default for Polymaker spools")
    }

    @Test func bothDefaultsAreRead() {
        let label = EmptySpoolRow.accessibilityLabel(
            for: record(manufacturer: "Polymaker", name: "cardboard", weight: 140, isDefault: true, isManufacturerDefault: true)
        )
        #expect(label == "Polymaker cardboard, 140 grams, default, default for Polymaker spools")
    }
}
