//
//  FilamentSearchEmptyStateTests.swift
//  SpoolKidTests
//
//  Purpose: When Select Filament's search shows the full-size "No Results" —
//  only when neither My Filaments nor the SpoolmanDB catalog matches.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
@testable import SpoolKid

struct FilamentSearchEmptyStateTests {
    @Test func nothingMatchingAnywhereGetsTheFullView() {
        #expect(FilamentSelectionView.searchMatchesNothing(
            searchText: "tiger orange", localMatches: 0, catalogMatches: 0, catalogAnswered: true
        ))
    }

    /// The owner's case: My Filaments empty, the catalog has the filament.
    @Test func aCatalogMatchKeepsTheFullViewAway() {
        #expect(!FilamentSelectionView.searchMatchesNothing(
            searchText: "tiger orange", localMatches: 0, catalogMatches: 1, catalogAnswered: true
        ))
    }

    @Test func aLocalMatchKeepsTheFullViewAway() {
        #expect(!FilamentSelectionView.searchMatchesNothing(
            searchText: "petg", localMatches: 2, catalogMatches: 0, catalogAnswered: true
        ))
    }

    @Test func aCatalogStillLoadingHasNotAnswered() {
        #expect(!FilamentSelectionView.searchMatchesNothing(
            searchText: "petg", localMatches: 0, catalogMatches: 0, catalogAnswered: false
        ))
    }

    @Test func anEmptySearchIsNotANoResult() {
        #expect(!FilamentSelectionView.searchMatchesNothing(
            searchText: "", localMatches: 0, catalogMatches: 0, catalogAnswered: true
        ))
    }
}
