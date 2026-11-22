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

    @Test func mergedLocationsIncludesRegistryNamesTheBackendCannotHold() {
        let merged = ManageLocationsView.mergedLocations(
            observed: ["Shelf A"],
            known: ["Shelf B"],
            registered: ["Shelf D", "  ", "Shelf A"]
        )

        #expect(merged == ["Shelf A", "Shelf B", "Shelf D"])
    }

    @Test func locationAssignmentDraftStatesOnlyTheLocation() {
        let draft = SpoolDraft.locationAssignment(.set("Shelf A"))

        #expect(draft.location == .set("Shelf A"))
        #expect(draft.filamentId == nil)
        #expect(draft.remainingWeight == .ignore)
        #expect(draft.comment == .ignore)
        #expect(draft.extra == .ignore)
    }

    @Test func locationAssignmentDraftCanClearTheLocation() {
        let draft = SpoolDraft.locationAssignment(.setNil)

        #expect(draft.location == .setNil)
    }
}
