import Foundation
import Testing
@testable import SpoolKid

struct FilamentFormPrefillTests {
    @Test func prefillMapsTagDataToFormFields() {
        let tagData = FilamentTagData(
            name: "PLA Pro",
            material: "PLA",
            brand: "Bambu",
            colorHex: "FF0000",
            minNozzleTemp: 200,
            maxNozzleTemp: 220,
            minBedTemp: 55,
            maxBedTemp: 65,
            density: 1.24
        )

        let values = FilamentFormView.initialFieldValues(from: tagData)

        #expect(values.name == "PLA Pro")
        #expect(values.material == "PLA")
        #expect(values.colors.primaryHex == "FF0000")
        #expect(values.density == "1.24")
        #expect(values.extruderTemp == "210")
        #expect(values.bedTemp == "60")
    }

    @Test func prefillHandlesMissingNameAndDensity() {
        let tagData = FilamentTagData(
            material: "PETG",
            brand: "Generic",
            colorHex: "0000FF",
            minNozzleTemp: 230,
            maxNozzleTemp: 250,
            minBedTemp: 70,
            maxBedTemp: 80
        )

        let values = FilamentFormView.initialFieldValues(from: tagData)

        #expect(values.name == "")
        #expect(values.material == "PETG")
        #expect(values.colors.primaryHex == "0000FF")
        // No density on the tag: PETG's typical one, not PLA's.
        #expect(values.density == "1.27")
        #expect(values.extruderTemp == "240")
        #expect(values.bedTemp == "75")
    }

    @Test func prefillFallsBackToDefaultDensityForUnknownMaterial() {
        let tagData = FilamentTagData(
            material: "Mike's Exotic Blend",
            brand: "Generic",
            colorHex: "0000FF",
            minNozzleTemp: 200,
            maxNozzleTemp: 220,
            minBedTemp: 50,
            maxBedTemp: 60
        )

        let values = FilamentFormView.initialFieldValues(from: tagData)

        #expect(values.density == String(AppConfig.Defaults.density))
    }

    /// Spoolman and the Library keep a filament without temperatures; the
    /// form starts empty rather than from the placeholders.
    @Test func prefillLeavesTemperaturesATagDoesNotStateEmpty() {
        var tagData = FilamentTagData(
            material: "PETG",
            brand: "Overture",
            colorHex: "F5F5F4",
            minNozzleTemp: 200,
            maxNozzleTemp: 220,
            minBedTemp: 60,
            maxBedTemp: 80
        )
        tagData.nozzleTempsStated = false
        tagData.bedTempsStated = false

        let values = FilamentFormView.initialFieldValues(from: tagData)

        #expect(values.extruderTemp == "")
        #expect(values.bedTemp == "")
    }

    @Test func materialPickSeedsItsDensity() {
        #expect(FilamentFormView.seededDensity(forMaterial: "PETG") == "1.27")
        // Menu names reach the registry through its alias table.
        #expect(FilamentFormView.seededDensity(forMaterial: "Nylon") == "1.14")
        #expect(FilamentFormView.seededDensity(forMaterial: "Flexible (TPU)") == "1.21")
        // Ambiguous on purpose (which base polymer?): PLA's default.
        #expect(FilamentFormView.seededDensity(forMaterial: "Carbon Fiber") == String(AppConfig.Defaults.density))
    }
}
