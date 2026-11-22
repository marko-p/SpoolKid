//
//  CatalogFilamentDraftTests.swift
//  SpoolKidTests
//
//  Purpose: A catalogue entry becomes a FilamentDraft through one builder, and
//  the entry's empty-spool weight travels with it.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

struct CatalogFilamentDraftTests {
    private func entry(spoolWeight: Double?) -> SpoolmanDBFilament {
        SpoolmanDBFilament(
            id: "prusament_pla_galaxy_black", manufacturer: "Prusament", name: "Galaxy Black",
            material: "PLA", spoolType: nil, density: 1.24, weight: 1000, spoolWeight: spoolWeight,
            diameter: 1.75, colorHex: "3A3A3A", extruderTemp: 215, bedTemp: 60
        )
    }

    @Test func weightTravels() {
        let draft = entry(spoolWeight: 193).filamentDraft(vendorId: 7)

        #expect(draft.spoolWeight == .set(193))
        #expect(draft.name == "Galaxy Black")
        #expect(draft.vendorId == .set(7))
        #expect(draft.material == "PLA")
        #expect(draft.density == 1.24)
        #expect(draft.diameter == 1.75)
        #expect(draft.extruderTemp == .set(215))
        #expect(draft.bedTemp == .set(60))
        #expect(draft.colorHex == "3A3A3A")
    }

    @Test func multiColorEntryCreatesMultiDraft() throws {
        let json = """
        {"id":"x","manufacturer":"Prusament","name":"Prusament PLA Vanilla White Marble","material":"PLA",
         "density":1.24,"diameter":1.75,"color_hex":null,"color_hexes":["2c3232","5f5f5f"],
         "multi_color_direction":"longitudinal"}
        """
        let decoded = try JSONDecoder().decode(SpoolmanDBFilament.self, from: Data(json.utf8))

        let draft = decoded.filamentDraft(vendorId: 7)

        #expect(draft.colorHex == nil)
        #expect(draft.multiColorHexes == .set("2C3232,5F5F5F"))
        #expect(draft.multiColorDirection == .set("longitudinal"))
    }

    @Test func unknownWeightSaysNothing() {
        #expect(entry(spoolWeight: nil).filamentDraft(vendorId: 7).spoolWeight == .ignore)
        #expect(entry(spoolWeight: 0).filamentDraft(vendorId: 7).spoolWeight == .ignore)
    }
}
