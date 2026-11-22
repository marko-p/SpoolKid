import Testing
@testable import SpoolKid

struct SpoolInfoCardBackendLabelsTests {
    /// Factory Anycubic ACE shape as the backend stores it after a SpoolKid
    /// create: the SKU is the filament name, brand is the "AC" code.
    private func makeSpool(name: String?, variant: String? = nil) -> Spool {
        let filament = Filament(
            id: 10,
            name: name,
            material: "PLA+",
            vendor: Vendor(id: 1, name: "AC"),
            extra: variant.map { ["variant": $0] }
        )
        return Spool(id: 42, filament: filament, statusId: nil, externalId: nil, purchaseDate: nil)
    }

    @Test func backendLabelsNormalModeMatchesTodayLayout() {
        let labels = HubActionPlan.backendLabels(
            spool: makeSpool(name: "AHPLPBK-108", variant: "Matte"),
            tagData: nil,
            nameBelowDescriptor: false
        )
        #expect(labels.headline == "AHPLPBK-108")
        #expect(labels.secondary == "AC • PLA+ • Matte")
    }

    @Test func backendLabelsSwappedLeadsWithDescriptor() {
        let labels = HubActionPlan.backendLabels(
            spool: makeSpool(name: "AHPLPBK-108", variant: "Matte"),
            tagData: nil,
            nameBelowDescriptor: true
        )
        #expect(labels.headline == "AC • PLA+ • Matte")
        #expect(labels.secondary == "AHPLPBK-108")
    }

    /// `variant` falls back to "Basic" when nothing sets it, and a backend
    /// filament without a name renders no secondary line when swapped.
    @Test func backendLabelsSwappedOmitsNilName() {
        let labels = HubActionPlan.backendLabels(
            spool: makeSpool(name: nil),
            tagData: nil,
            nameBelowDescriptor: true
        )
        #expect(labels.headline == "AC • PLA+ • Basic")
        #expect(labels.secondary == nil)
    }

    @Test func backendLabelsNormalModeKeepsNilNameFallbacks() {
        let labels = HubActionPlan.backendLabels(
            spool: makeSpool(name: nil),
            tagData: nil,
            nameBelowDescriptor: false
        )
        #expect(labels.headline == "Unknown Filament")
        #expect(labels.secondary == "AC • PLA+ • Basic")
    }
}
