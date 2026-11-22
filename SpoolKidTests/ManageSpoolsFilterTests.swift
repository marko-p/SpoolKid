import Testing
import Foundation
@testable import SpoolKid

struct ManageSpoolsFilterTests {

    private func makeSpool(
        id: Int,
        filamentId: Int,
        material: String? = "PLA",
        remaining: Double? = nil,
        initial: Double? = nil,
        archived: Bool? = nil
    ) -> Spool {
        Spool(
            id: id,
            filament: Filament(id: filamentId, name: "Filament \(filamentId)", material: material),
            remainingWeight: remaining,
            initialWeight: initial,
            archived: archived,
            statusId: nil, externalId: nil, purchaseDate: nil
        )
    }

    @Test func filterByFilamentReturnsOnlyMatchingSpools() {
        let spools = [
            makeSpool(id: 1, filamentId: 10),
            makeSpool(id: 2, filamentId: 20),
            makeSpool(id: 3, filamentId: 10),
            makeSpool(id: 4, filamentId: 30)
        ]

        let result = ManageSpoolsView.applyFilter(spools, filter: .filament(10))

        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.filament.id == 10 })
        #expect(result.map(\.id) == [1, 3])
    }

    @Test func filterByNilReturnsAllSpools() {
        let spools = [
            makeSpool(id: 1, filamentId: 10),
            makeSpool(id: 2, filamentId: 20)
        ]

        let result = ManageSpoolsView.applyFilter(spools, filter: nil)

        #expect(result.count == 2)
        #expect(result.map(\.id) == [1, 2])
    }

    @Test func filterByNonExistentFilamentReturnsEmpty() {
        let spools = [
            makeSpool(id: 1, filamentId: 10),
            makeSpool(id: 2, filamentId: 20)
        ]

        let result = ManageSpoolsView.applyFilter(spools, filter: .filament(999))

        #expect(result.isEmpty)
    }

    @Test func filterByFillBucketRoutesToStatsService() {
        let spools = [
            makeSpool(id: 1, filamentId: 10, remaining: 100, initial: 1000), // critical
            makeSpool(id: 2, filamentId: 20, remaining: 1000, initial: 1000) // full
        ]

        let result = ManageSpoolsView.applyFilter(spools, filter: .fillBucket(.critical))

        #expect(result.map(\.id) == [1])
    }

    @Test func excludingArchivedHidesArchivedWhenToggleOff() {
        let spools = [
            makeSpool(id: 1, filamentId: 10),
            makeSpool(id: 2, filamentId: 20, archived: true),
            makeSpool(id: 3, filamentId: 30)
        ]
        #expect(ManageSpoolsView.excludingArchived(spools, showArchived: false).map(\.id) == [1, 3])
        #expect(ManageSpoolsView.excludingArchived(spools, showArchived: true).map(\.id) == [1, 2, 3])
    }

    @Test func filterByMaterialRoutesToStatsService() {
        let spools = [
            makeSpool(id: 1, filamentId: 10, material: "PLA"),
            makeSpool(id: 2, filamentId: 20, material: "ASA"),
            makeSpool(id: 3, filamentId: 30, material: "PLA")
        ]

        let result = ManageSpoolsView.applyFilter(spools, filter: .material("PLA"))

        #expect(result.map(\.id) == [1, 3])
    }

    @Test func untaggedFilterUsesLedger() {
        let a = Spool(id: 1, filament: Filament(id: 1), statusId: nil, externalId: nil, purchaseDate: nil)
        let b = Spool(id: 2, filament: Filament(id: 2), statusId: nil, externalId: nil, purchaseDate: nil)
        let out = ManageSpoolsView.applyFilter([a, b], filter: .untagged, ledger: ["FF": 1])
        #expect(out.map(\.id) == [2])
    }

    private func makeColoredSpool(id: Int, colorHex: String?) -> Spool {
        Spool(
            id: id,
            filament: Filament(id: id * 10, name: "F\(id)", material: "PLA", colorHex: colorHex),
            statusId: nil, externalId: nil, purchaseDate: nil
        )
    }

    @Test func applyColorFilterNilPassesThrough() {
        let spools = [makeColoredSpool(id: 1, colorHex: "FF0000"), makeColoredSpool(id: 2, colorHex: nil)]
        #expect(ManageSpoolsView.applyColorFilter(spools, spec: nil).map(\.id) == [1, 2])
    }

    @Test func applyColorFilterKeepsMatchesInRoleOrder() {
        let spec = ColorFilterSpec(anchorHex: "FF0000", toleranceDeltaE: 15, harmony: .complementary)
        let spools = [
            makeColoredSpool(id: 1, colorHex: "00FFFF"),
            makeColoredSpool(id: 2, colorHex: "FF0000"),
            makeColoredSpool(id: 3, colorHex: "888888")
        ]
        #expect(ManageSpoolsView.applyColorFilter(spools, spec: spec).map(\.id) == [2, 1])
    }

    @Test func applyMaterialsEmptySelectionPassesThrough() {
        let spools = [makeSpool(id: 1, filamentId: 10, material: "PLA"), makeSpool(id: 2, filamentId: 20, material: "PETG")]
        #expect(ManageSpoolsView.applyMaterials(spools, selected: []).map(\.id) == [1, 2])
    }

    @Test func applyMaterialsKeepsSelectedOnly() {
        let spools = [
            makeSpool(id: 1, filamentId: 10, material: "PLA"),
            makeSpool(id: 2, filamentId: 20, material: "PETG"),
            makeSpool(id: 3, filamentId: 30, material: " PLA "),
            makeSpool(id: 4, filamentId: 40, material: nil)
        ]
        #expect(ManageSpoolsView.applyMaterials(spools, selected: ["PLA"]).map(\.id) == [1, 3])
        #expect(ManageSpoolsView.applyMaterials(spools, selected: ["Unknown"]).map(\.id) == [4])
    }

    @Test func hasActiveFiltersPredicate() {
        #expect(!ManageSpoolsView.hasActiveFilters(colorSpec: nil, selectedMaterials: []))
        #expect(ManageSpoolsView.hasActiveFilters(colorSpec: nil, selectedMaterials: ["PLA"]))
        let spec = ColorFilterSpec(anchorHex: "FF0000", toleranceDeltaE: 18, harmony: .single)
        #expect(ManageSpoolsView.hasActiveFilters(colorSpec: spec, selectedMaterials: []))
    }

    // MARK: - activeFilterChips

    @Test func noActiveFiltersYieldsNoChips() {
        let chips = ManageSpoolsView.activeFilterChips(colorSpec: nil, selectedMaterials: [], showArchived: false)
        #expect(chips.isEmpty)
    }

    @Test func singleColorChipUsesGenericLabelAndAnchorSwatch() {
        let spec = ColorFilterSpec(anchorHex: "1D9E75", toleranceDeltaE: 18, harmony: .single)
        let chips = ManageSpoolsView.activeFilterChips(colorSpec: spec, selectedMaterials: [], showArchived: false)
        #expect(chips.count == 1)
        #expect(chips[0].id == "color")
        #expect(chips[0].label == "Color")
        #expect(chips[0].swatchHex == "1D9E75")
        #expect(chips[0].kind == .color)
    }

    @Test func harmonyColorChipUsesHarmonyDisplayName() {
        let spec = ColorFilterSpec(anchorHex: "1D9E75", toleranceDeltaE: 18, harmony: .analogous)
        let chips = ManageSpoolsView.activeFilterChips(colorSpec: spec, selectedMaterials: [], showArchived: false)
        #expect(chips.count == 1)
        #expect(chips[0].label == "Analogous")
    }

    @Test func materialChipsAreSortedCaseInsensitivelyOnePerMaterial() {
        let chips = ManageSpoolsView.activeFilterChips(colorSpec: nil, selectedMaterials: ["petg", "PLA", "ABS"], showArchived: false)
        #expect(chips.map(\.label) == ["ABS", "petg", "PLA"])
        #expect(chips.map(\.kind) == [.material("ABS"), .material("petg"), .material("PLA")])
        #expect(chips.map(\.id) == ["material:ABS", "material:petg", "material:PLA"])
        #expect(chips.allSatisfy { $0.swatchHex == nil })
    }

    @Test func archivedChipPresentOnlyWhenShown() {
        let on = ManageSpoolsView.activeFilterChips(colorSpec: nil, selectedMaterials: [], showArchived: true)
        #expect(on.map(\.id) == ["archived"])
        #expect(on[0].label == "Archived")
        #expect(on[0].kind == .archived)
        #expect(on[0].swatchHex == nil)
        let off = ManageSpoolsView.activeFilterChips(colorSpec: nil, selectedMaterials: [], showArchived: false)
        #expect(off.isEmpty)
    }

    @Test func combinedChipsOrderIsColorMaterialsArchived() {
        let spec = ColorFilterSpec(anchorHex: "FF0000", toleranceDeltaE: 10, harmony: .complementary)
        let chips = ManageSpoolsView.activeFilterChips(colorSpec: spec, selectedMaterials: ["PLA", "PETG"], showArchived: true)
        #expect(chips.map(\.id) == ["color", "material:PETG", "material:PLA", "archived"])
        #expect(Set(chips.map(\.id)).count == chips.count)
    }

    @Test func withoutSpoolsChipPresentOnlyWhenShown() {
        let on = ManageSpoolsView.activeFilterChips(colorSpec: nil, selectedMaterials: [], showArchived: false,
                                                    showsWithoutSpools: true)
        #expect(on.map(\.id) == ["withoutSpools"])
        #expect(on[0].label == "Without Spools")
        #expect(on[0].kind == .withoutSpools)
        #expect(on[0].swatchHex == nil)
        let off = ManageSpoolsView.activeFilterChips(colorSpec: nil, selectedMaterials: [], showArchived: false,
                                                     showsWithoutSpools: false)
        #expect(off.isEmpty)
    }

    @Test func withoutSpoolsChipComesLastAfterArchived() {
        let spec = ColorFilterSpec(anchorHex: "FF0000", toleranceDeltaE: 10, harmony: .complementary)
        let chips = ManageSpoolsView.activeFilterChips(colorSpec: spec, selectedMaterials: ["PLA"], showArchived: true,
                                                       showsWithoutSpools: true)
        #expect(chips.map(\.id) == ["color", "material:PLA", "archived", "withoutSpools"])
    }
}
