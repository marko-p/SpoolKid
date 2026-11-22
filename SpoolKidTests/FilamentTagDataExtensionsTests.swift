import Testing
@testable import SpoolKid

struct FilamentTagDataExtensionsTests {
    // MARK: - displayName

    private func makeTagData(
        name: String?, material: String, subtype: String? = nil, brand: String
    ) -> FilamentTagData {
        FilamentTagData(
            name: name,
            material: material,
            subtype: subtype,
            brand: brand,
            colorHex: "10A0FF",
            minNozzleTemp: 190,
            maxNozzleTemp: 230,
            minBedTemp: 0,
            maxBedTemp: 60
        )
    }

    // MARK: - Midpoint temperature

    /// The midpoint rounds to the nearest 5 °C, a half step up: the issue #23
    /// tag's 185–200 °C nozzle range proposes 195, not 192.
    @Test(arguments: [
        (185, 200, 195), (40, 70, 55), (80, 85, 85), (190, 200, 195),
        (200, 210, 205), (190, 196, 195), (190, 194, 190), (215, 215, 215),
    ])
    func midpointRoundsToTheNearestFiveDegrees(_ low: Int, _ high: Int, _ expected: Int) {
        #expect(FilamentTagData.midpointTemperature(low, high) == expected)
    }

    @Test func statedTemperaturesAreRoundedMidpoints() {
        var data = makeTagData(name: nil, material: "PLA", brand: "ReSpool")
        data.minNozzleTemp = 185
        data.maxNozzleTemp = 200
        data.minBedTemp = 40
        data.maxBedTemp = 70
        #expect(data.statedExtruderTemp == 195)
        #expect(data.statedBedTemp == 55)
    }

    @Test func tagFromFilamentCarriesTD() {
        let filament = Filament(id: 1, material: "PLA", colorHex: "FFFFFF", extra: ["td": "2.3"])
        #expect(FilamentTagData.from(filament: filament).transmissionDistance == 2.3)
    }

    @Test func displayNamePrefersNameTagCarries() {
        let tagData = makeTagData(name: "Silk Gold", material: "PLA", brand: "ELEGOO")
        #expect(tagData.displayName == "Silk Gold")
    }

    /// Real ELEGOO payload shape: the tag carries no name field (five captured
    /// spools differ only in UID and colour), so the label is constructed.
    @Test func displayNameConstructsBrandAndMaterialForNamelessTag() {
        let tagData = makeTagData(name: nil, material: "PLA", brand: "ELEGOO")
        #expect(tagData.displayName == "ELEGOO PLA")
    }

    @Test func displayNameIgnoresWhitespaceOnlyName() {
        let tagData = makeTagData(name: "   ", material: "PETG", brand: "Prusament")
        #expect(tagData.displayName == "Prusament PETG")
    }

    @Test func displayNameFallsBackToUnknownWhenNothingNamesIt() {
        let tagData = makeTagData(name: nil, material: "", brand: "")
        #expect(tagData.displayName == "Unknown Filament")
    }

    // MARK: - displayLabels

    /// Factory Anycubic ACE tag shape: the SKU is the name, the brand is the
    /// "AC" code, and the tag carries no subtype.
    @Test func displayLabelsNormalModeMatchesTodayLayout() {
        let tagData = makeTagData(name: "AHPLPBK-108", material: "PLA+", brand: "AC")
        let labels = tagData.displayLabels(nameBelowDescriptor: false)
        #expect(labels.headline == "AHPLPBK-108")
        #expect(labels.secondary == "AC • PLA+")
    }

    @Test func displayLabelsSwappedLeadsWithDescriptor() {
        let tagData = makeTagData(name: "AHPLPBK-108", material: "PLA+", brand: "AC")
        let labels = tagData.displayLabels(nameBelowDescriptor: true)
        #expect(labels.headline == "AC • PLA+")
        #expect(labels.secondary == "AHPLPBK-108")
    }

    /// An empty or `SM<id>` SKU decodes to a nil name; nothing renders under
    /// the descriptor.
    @Test func displayLabelsSwappedOmitsNilName() {
        let tagData = makeTagData(name: nil, material: "PLA+", brand: "AC")
        let labels = tagData.displayLabels(nameBelowDescriptor: true)
        #expect(labels.headline == "AC • PLA+")
        #expect(labels.secondary == nil)
    }

    @Test func displayLabelsSwappedTreatsWhitespaceNameAsAbsent() {
        let tagData = makeTagData(name: "   ", material: "PLA+", brand: "AC")
        let labels = tagData.displayLabels(nameBelowDescriptor: true)
        #expect(labels.secondary == nil)
    }

    @Test func displayLabelsDescriptorIncludesSubtypeWhenPresent() {
        let tagData = makeTagData(name: "Matte PLA", material: "PLA", subtype: "Matte", brand: "Bambu Lab")
        let labels = tagData.displayLabels(nameBelowDescriptor: true)
        #expect(labels.headline == "Bambu Lab • PLA • Matte")
        #expect(labels.secondary == "Matte PLA")
    }

    @Test func fromSpoolPopulatesDensity() {
        let filament = Filament(
            id: 2,
            name: "PLA Silk Glitter Glow Carbon Fiber",
            material: "PLA-CF",
            vendor: Vendor(id: 11, name: "Example"),
            colorHex: "445566",
            density: 1.24
        )
        let spool = Spool(id: 77, filament: filament, statusId: nil, externalId: nil, purchaseDate: nil)

        let tagData = FilamentTagData.from(spool: spool)

        #expect(tagData.density == 1.24)
        #expect(tagData.material == "PLA-CF")
    }

    // MARK: - Spool weights, diameter and consumption

    /// A 1,000 g spool with 612 g left. Its filament states 750 g and 250 g,
    /// which the spool's own weights override.
    static func weighedSpool(
        initialWeight: Double? = 1000, spoolWeight: Double? = 196, remainingWeight: Double? = 612
    ) -> Spool {
        let filament = Filament(
            id: 3, name: "PLA Galaxy", material: "PLA", vendor: Vendor(id: 11, name: "Prusament"),
            colorHex: "3D3E3D", density: 1.24, diameter: 1.75, weight: 750, spoolWeight: 250
        )
        return Spool(
            id: 9, filament: filament, remainingWeight: remainingWeight, initialWeight: initialWeight,
            spoolWeight: spoolWeight, statusId: nil, externalId: nil, purchaseDate: nil
        )
    }

    @Test func fromSpoolCarriesWeightsDiameterAndConsumption() {
        let tagData = FilamentTagData.from(spool: Self.weighedSpool())

        #expect(tagData.nominalNetWeight == 1000)
        #expect(tagData.emptyContainerWeight == 196)
        #expect(tagData.diameter == 1.75)
        #expect(tagData.density == 1.24)
        #expect(tagData.consumedWeight == 388)
        #expect(tagData.remainingOnTag == 612)
    }

    @Test func fromSpoolFallsBackToTheFilament() {
        let tagData = FilamentTagData.from(
            spool: Self.weighedSpool(initialWeight: nil, spoolWeight: nil, remainingWeight: nil)
        )

        #expect(tagData.nominalNetWeight == 750)
        #expect(tagData.emptyContainerWeight == 250)
        #expect(tagData.consumedWeight == nil)
    }

    /// Zero is how some backends say "not stated", so it must not shadow the
    /// filament's value, and no default density or diameter stands in.
    @Test func aZeroWeightIsNotStated() {
        let spool = Self.weighedSpool(initialWeight: 0, spoolWeight: 0)
        let tagData = FilamentTagData.from(spool: spool)
        #expect(tagData.nominalNetWeight == 750)
        #expect(tagData.emptyContainerWeight == 250)

        let bare = FilamentTagData.from(filament: Filament(id: 4, diameter: 0, weight: 0, spoolWeight: 0))
        #expect(bare.nominalNetWeight == nil)
        #expect(bare.emptyContainerWeight == nil)
        #expect(bare.diameter == nil)
    }

    @Test func fromFilamentCarriesItsWeightsAndDiameter() {
        let tagData = FilamentTagData.from(filament: Self.weighedSpool().filament)

        #expect(tagData.nominalNetWeight == 750)
        #expect(tagData.emptyContainerWeight == 250)
        #expect(tagData.diameter == 1.75)
        #expect(tagData.consumedWeight == nil)
    }
}
