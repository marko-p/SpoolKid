//
//  MigrationFixViewTests.swift
//  SpoolKidTests
//
//  The Save gate on the migration fix sheet: a fix that does not satisfy every
//  requirement the backend named would just reproduce the refusal that opened
//  the sheet.
//

import Testing
@testable import SpoolKid

@Suite struct MigrationFixViewTests {
    private func complete(
        _ requirements: [FilamentCreateRequirement],
        name: String = "",
        manufacturerName: String? = nil,
        newManufacturerName: String = "",
        material: String = "",
        diameter: Double? = nil,
        density: Double? = nil
    ) -> Bool {
        MigrationFixView.isComplete(
            requirements: requirements,
            name: name,
            manufacturerName: manufacturerName,
            newManufacturerName: newManufacturerName,
            material: material,
            diameter: diameter,
            density: density
        )
    }

    @Test func nothingRequiredIsAlreadyComplete() {
        #expect(complete([]))
    }

    @Test func aManufacturerCanBeChosenOrNamed() {
        #expect(complete([.manufacturer]) == false)
        #expect(complete([.manufacturer], manufacturerName: "Polymaker"))
        #expect(complete([.manufacturer], newManufacturerName: "Polymaker"))
    }

    @Test func thePickedNameWinsOverWhateverWasTypedBeforeIt() {
        #expect(MigrationFixView.resolvedManufacturer(picked: "Polymaker", typed: "Bambu") == "Polymaker")
        #expect(MigrationFixView.resolvedManufacturer(picked: nil, typed: " Bambu ") == "Bambu")
        #expect(MigrationFixView.resolvedManufacturer(picked: nil, typed: "  ") == nil)
    }

    @Test func whitespaceIsNotAValue() {
        #expect(complete([.manufacturer], newManufacturerName: "   ") == false)
        #expect(complete([.material], material: " ") == false)
        #expect(complete([.name], name: "\t") == false)
    }

    @Test func everyNamedRequirementMustBeSatisfied() {
        // The half-filled case: a manufacturer given, the material still not.
        #expect(complete([.manufacturer, .material], manufacturerName: "Polymaker") == false)
        #expect(complete([.manufacturer, .material], manufacturerName: "Polymaker", material: "PLA"))
    }

    @Test func anUnparseableOrZeroDensityIsNotADensity() {
        #expect(complete([.density]) == false)
        #expect(complete([.density], density: 0) == false)
        #expect(complete([.density], density: 1.24))
    }

    @Test func anUnparseableDiameterIsNotADiameter() {
        #expect(complete([.diameter]) == false)
        #expect(complete([.diameter], diameter: 1.75))
    }
}
