import Testing
@testable import SpoolKid

struct FilamentTagDataExtensionsTests {
    @Test func fromSpoolPopulatesDensity() {
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
        #expect(tagData.material == "PLA-CF")
    }
}
