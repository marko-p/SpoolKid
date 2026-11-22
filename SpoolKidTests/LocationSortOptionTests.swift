//
//  LocationSortOptionTests.swift
//  SpoolKidTests
//
//  Purpose: One entry point orders the shelves, so `.manual` and the automatic
//  sorts cannot disagree about what "the list" is.
//

import Testing
@testable import SpoolKid

struct LocationSortOptionTests {
    private let tallies = [
        LocationTally(name: "Shelf B", spoolCount: 2),
        LocationTally(name: "bin a", spoolCount: 9),
        LocationTally(name: "Shelf C", spoolCount: 2)
    ]

    @Test func nameSortsCaseInsensitivelyAscending() {
        let arranged = LocationSortOption.arrange(tallies, by: .name, ascending: true, manual: LocationOrder())

        #expect(arranged == ["bin a", "Shelf B", "Shelf C"])
    }

    @Test func nameDescendingIsTheExactReverse() {
        let arranged = LocationSortOption.arrange(tallies, by: .name, ascending: false, manual: LocationOrder())

        #expect(arranged == ["Shelf C", "Shelf B", "bin a"])
    }

    @Test func spoolCountAscendingPutsTheEmptiestFirst() {
        let arranged = LocationSortOption.arrange(tallies, by: .spoolCount, ascending: true, manual: LocationOrder())

        #expect(arranged == ["Shelf B", "Shelf C", "bin a"])
    }

    @Test func spoolCountTiesFallBackToNameSoTheListNeverShuffles() {
        let arranged = LocationSortOption.arrange(tallies, by: .spoolCount, ascending: false, manual: LocationOrder())

        #expect(arranged == ["bin a", "Shelf B", "Shelf C"])
    }

    @Test func manualDelegatesToTheHandArrangedOrder() {
        let manual = LocationOrder.seed(from: ["Shelf C", "bin a", "Shelf B"])

        let arranged = LocationSortOption.arrange(tallies, by: .manual, ascending: true, manual: manual)

        #expect(arranged == ["Shelf C", "bin a", "Shelf B"])
    }

    @Test func manualIgnoresAscendingBecauseThereIsNothingToReverse() {
        let manual = LocationOrder.seed(from: ["Shelf C", "bin a", "Shelf B"])

        let up = LocationSortOption.arrange(tallies, by: .manual, ascending: true, manual: manual)
        let down = LocationSortOption.arrange(tallies, by: .manual, ascending: false, manual: manual)

        #expect(up == down)
    }

    @Test func manualWithAnEmptyOrderIsTodaysNameOrder() {
        let arranged = LocationSortOption.arrange(tallies, by: .manual, ascending: true, manual: LocationOrder())

        #expect(arranged == ["bin a", "Shelf B", "Shelf C"])
    }

    @Test func everyCaseCarriesLabelAndIcon() {
        for option in LocationSortOption.allCases {
            #expect(!option.label.isEmpty)
            #expect(!option.systemImage.isEmpty)
        }
    }
}
