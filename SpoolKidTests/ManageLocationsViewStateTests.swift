import Testing
@testable import SpoolKid

struct ManageLocationsViewStateTests {
    @Test func mergedLocationsDeduplicatesAndSortsObservedAndKnownLocations() {
        let merged = ManageLocationsView.mergedLocations(
            observed: ["Rack B", "", "Rack A", "Rack A", " Bin C "],
            known: ["Rack C", "Rack B", "bin c"]
        )

        #expect(merged == ["Bin C", "bin c", "Rack A", "Rack B", "Rack C"])
    }

    @Test func spoolIDsForLocationReturnsOnlyExactLocationMatches() {
        let filament = SpoolmanFilament(id: 1, name: "PLA")
        let spools = [
            SpoolmanSpool(id: 10, filament: filament, location: "Shelf A"),
            SpoolmanSpool(id: 20, filament: filament, location: "Shelf A"),
            SpoolmanSpool(id: 30, filament: filament, location: "shelf a"),
            SpoolmanSpool(id: 40, filament: filament, location: "Shelf A "),
            SpoolmanSpool(id: 50, filament: filament, location: nil)
        ]

        let ids = ManageLocationsView.spoolIDsForLocation("Shelf A", spools: spools)

        #expect(ids == [10, 20])
    }

    @Test func canonicalLocationPrefersKnownRawValueForTrimmedDisplay() {
        let canonical = ManageLocationsView.canonicalLocationName(
            for: "Bin C",
            observed: ["Rack A", " Bin C "],
            known: ["Rack B"]
        )

        #expect(canonical == " Bin C ")
    }

    @Test func canonicalLocationFallsBackToDisplayWhenNoRawMatchExists() {
        let canonical = ManageLocationsView.canonicalLocationName(
            for: "Shelf Z",
            observed: ["Shelf A"],
            known: ["Shelf B"]
        )

        #expect(canonical == "Shelf Z")
    }
}
