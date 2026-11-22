//
//  FilamentFormTransmissionDistanceTests.swift
//  SpoolKidTests
//
//  Purpose: The filament form's TD box: what it puts in the draft (rounded,
//  comma-tolerant, untouched = ignore), what it accepts, and the tag prefill.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
import Foundation
@testable import SpoolKid

@MainActor
struct FilamentFormTransmissionDistanceTests {
    private func draft(_ td: String, loaded: String = "") -> FilamentDraft {
        FilamentFormView.filamentPayload(
            name: "PLA", vendorId: 1, material: "PLA",
            colors: FilamentColors(hexes: ["111111"]),
            density: "1.24", diameter: "1.75", extruderTemp: "210", bedTemp: "60",
            price: "", weight: "", spoolWeight: "", articleNumber: "", comment: "", externalId: "",
            transmissionDistance: td,
            loadedTransmissionDistance: loaded
        )
    }

    @Test func typedTDIsRounded() {
        #expect(draft("3.46").transmissionDistance == .set(3.5))
        #expect(draft("3,5").transmissionDistance == .set(3.5))
    }

    /// A `td` another tool wrote that the app cannot read loads as an empty
    /// box; leaving the box alone must leave the stored value alone.
    @Test func untouchedTDIsIgnored() {
        #expect(draft("3.5", loaded: "3.5").transmissionDistance == .ignore)
        #expect(draft("", loaded: "").transmissionDistance == .ignore)
    }

    @Test func emptiedTDClears() {
        #expect(draft("", loaded: "3.5").transmissionDistance == .setNil)
    }

    @Test func tdValidity() {
        #expect(FilamentFormView.isValidTransmissionDistanceText(""))
        #expect(FilamentFormView.isValidTransmissionDistanceText("3.5"))
        #expect(FilamentFormView.isValidTransmissionDistanceText("3,5"))
        #expect(!FilamentFormView.isValidTransmissionDistanceText("0"))
        #expect(!FilamentFormView.isValidTransmissionDistanceText("101"))
        #expect(!FilamentFormView.isValidTransmissionDistanceText("x"))
    }

    @Test func tagPrefillsTD() {
        var tag = FilamentTagData(
            material: "PLA", brand: "Generic", colorHex: "FFFFFF",
            minNozzleTemp: 190, maxNozzleTemp: 220, minBedTemp: 50, maxBedTemp: 60
        )
        tag.transmissionDistance = 2.3
        #expect(FilamentFormView.initialFieldValues(from: tag).transmissionDistance == "2.3")
        tag.transmissionDistance = nil
        #expect(FilamentFormView.initialFieldValues(from: tag).transmissionDistance == "")
    }

    @Test func tdIsAFilamentFieldVisibleByDefault() {
        let field = FieldCatalog.filamentFields.first { $0.id == "td" }
        #expect(field?.label == "TD (HueForge)")
        #expect(field?.defaultVisible == true)
        #expect(field?.section == "Color")
    }

    @Test func filamentPageShowsTDWhenVisibleAndSet() {
        let withTD = Filament(id: 3, material: "PLA", colorHex: "FFFFFF", extra: ["td": "3.5"])
        let rows = FilamentPage.specRows(for: withTD, visibleFieldIDs: ["td"])
        #expect(rows.first { $0.label == "TD" }?.value == "3.5 mm")
        #expect(!FilamentPage.specRows(for: withTD, visibleFieldIDs: []).contains { $0.label == "TD" })
        let without = Filament(id: 4, material: "PLA", colorHex: "FFFFFF")
        #expect(!FilamentPage.specRows(for: without, visibleFieldIDs: ["td"]).contains { $0.label == "TD" })
    }
}
