import Testing
@testable import SpoolKid

struct FilamentTagDataExtensionsTests {
    @Test func fromSpoolMapsAliasMaterialToOpenPrintTagMaterialTypeID() {
        let filament = SpoolmanFilament(
            id: 1,
            name: "Alias TPU",
            material: "Flexible (TPU)",
            vendor: SpoolmanVendor(id: 9, name: "Generic"),
            colorHex: "112233"
        )
        let spool = SpoolmanSpool(id: 42, filament: filament)

        let tagData = FilamentTagData.from(spool: spool)

        #expect(tagData.openPrintTagMaterialTypeID == 2)
        #expect(tagData.material == "Flexible (TPU)")
    }

    @Test func fromSpoolPopulatesDensityAndInfersMaterialTagsFromName() {
        let filament = SpoolmanFilament(
            id: 2,
            name: "PLA Silk Glitter Glow Carbon Fiber",
            material: "PLA-CF",
            vendor: SpoolmanVendor(id: 11, name: "Example"),
            colorHex: "445566",
            density: 1.24
        )
        let spool = SpoolmanSpool(id: 77, filament: filament)

        let tagData = FilamentTagData.from(spool: spool)

        #expect(tagData.density == 1.24)
        #expect((tagData.materialTags ?? []).contains(17))
        #expect((tagData.materialTags ?? []).contains(23))
        #expect((tagData.materialTags ?? []).contains(24))
        #expect((tagData.materialTags ?? []).contains(31))
    }
}
