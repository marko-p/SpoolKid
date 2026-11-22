//
//  TagTargetPickerTests.swift
//  SpoolKidTests
//
//  The picker's Suggested filaments (spec 2026-10-11 §1).
//

import Testing
@testable import SpoolKid

struct TagTargetPickerTests {
    private static let filaments = [
        Filament(id: 1, name: "PLA"),
        Filament(id: 2, name: "PETG"),
        Filament(id: 3, name: "ABS"),
    ]

    @Test func suggestionsKeepTheirOrder() {
        let suggested = TagTargetPicker.suggestedFilaments(ids: [3, 1], excluded: [], in: Self.filaments)
        #expect(suggested.map { $0.id } == [3, 1])
    }

    @Test func anExcludedFilamentIsNotSuggested() {
        let suggested = TagTargetPicker.suggestedFilaments(ids: [1, 2], excluded: [1], in: Self.filaments)
        #expect(suggested.map { $0.id } == [2])
    }

    @Test func aFilamentTheStoreDoesNotHoldIsNotSuggested() {
        let suggested = TagTargetPicker.suggestedFilaments(ids: [99, 2], excluded: [], in: Self.filaments)
        #expect(suggested.map { $0.id } == [2])
    }

    @Test func aFilamentIsSuggestedOnce() {
        let suggested = TagTargetPicker.suggestedFilaments(ids: [2, 2], excluded: [], in: Self.filaments)
        #expect(suggested.map { $0.id } == [2])
    }
}
