//
//  ManufacturerPickerSectionsTests.swift
//  SpoolKidTests
//
//  Purpose: The manufacturer picker's rows — the backend's manufacturers, the
//  catalogue minus those, and when the typed name gets a Use "…" row.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
@testable import SpoolKid

struct ManufacturerPickerSectionsTests {
    private let vendors = [Vendor(id: 2, name: "Elegoo"), Vendor(id: 1, name: "anycubic")]
    private let catalog = ["Sunlu", "ELEGOO", "Bambu Lab", "sunlu", "Polymaker", "  "]

    @Test func withoutSearchEveryManufacturerAppearsOnceSorted() {
        let sections = ManufacturerPickerSections.build(vendors: vendors, catalog: catalog, search: "")

        #expect(sections.mine == [.existing(id: 1, name: "anycubic"), .existing(id: 2, name: "Elegoo")])
        // ELEGOO is the backend's own; sunlu is Sunlu; the blank is dropped.
        #expect(sections.catalog == ["Bambu Lab", "Polymaker", "Sunlu"])
        #expect(sections.customName == nil)
    }

    @Test func searchFiltersBothSections() {
        let sections = ManufacturerPickerSections.build(vendors: vendors, catalog: catalog, search: "ma")

        #expect(sections.mine.isEmpty)
        #expect(sections.catalog == ["Polymaker"])
    }

    @Test func aTypedNameNoListHasGetsAUseRow() {
        let sections = ManufacturerPickerSections.build(vendors: vendors, catalog: catalog, search: "  Rosa3D ")
        #expect(sections.customName == "Rosa3D")
    }

    @Test func aTypedNameAListHasGetsNoUseRow() {
        #expect(ManufacturerPickerSections.build(vendors: vendors, catalog: catalog, search: "ELEGOO").customName == nil)
        #expect(ManufacturerPickerSections.build(vendors: vendors, catalog: catalog, search: "sunlu ").customName == nil)
        #expect(ManufacturerPickerSections.build(vendors: vendors, catalog: catalog, search: "   ").customName == nil)
    }

    @Test func aStoredNameMapsToNoneExistingOrNew() {
        #expect(ManufacturerChoice.named("", in: vendors) == ManufacturerChoice.none)
        #expect(ManufacturerChoice.named(" elegoo ", in: vendors) == .existing(id: 2, name: "Elegoo"))
        #expect(ManufacturerChoice.named(" Rosa3D ", in: vendors) == .new(name: "Rosa3D"))
    }

    @Test func choicesMatchByIdOrByNameKey() {
        #expect(ManufacturerChoice.existing(id: 2, name: "x").matches(.existing(id: 2, name: "y")))
        #expect(ManufacturerChoice.new(name: "Sunlu").matches(.new(name: " sunlu")))
        #expect(ManufacturerChoice.none.matches(.none))
        #expect(!ManufacturerChoice.new(name: "Elegoo").matches(.existing(id: 2, name: "Elegoo")))
        #expect(!ManufacturerChoice.none.matches(.new(name: "Sunlu")))
    }

    @Test func onlyNoneHasNoName() {
        #expect(ManufacturerChoice.none.name == nil)
        #expect(ManufacturerChoice.existing(id: 2, name: "Elegoo").name == "Elegoo")
        #expect(ManufacturerChoice.new(name: "Rosa3D").name == "Rosa3D")
    }
}
