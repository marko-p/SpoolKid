//
//  SpoolWeightAdjustmentTests.swift
//  SpoolKid
//
//  Purpose: Tests for the per-print weight adjustment arithmetic — input
//  parsing, the remaining-weight outcome, and the preview line.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
@testable import SpoolKid

struct SpoolWeightAdjustmentTests {

    // MARK: - input

    @Test func input_usedWholeNumber() {
        #expect(SpoolWeightAdjustment.input(used: "52", measured: "") == .used(52))
    }

    @Test func input_usedCommaDecimal() {
        #expect(SpoolWeightAdjustment.input(used: "52,5", measured: "") == .used(52.5))
    }

    @Test func input_usedRejectsZeroNegativeEmptyAndNonNumeric() {
        #expect(SpoolWeightAdjustment.input(used: "0", measured: "") == nil)
        #expect(SpoolWeightAdjustment.input(used: "-5", measured: "") == nil)
        #expect(SpoolWeightAdjustment.input(used: "", measured: "") == nil)
        #expect(SpoolWeightAdjustment.input(used: "abc", measured: "") == nil)
    }

    @Test func input_usedRejectsInfinity() {
        #expect(SpoolWeightAdjustment.input(used: "inf", measured: "") == nil)
    }

    @Test func input_measuredWholeNumber() {
        #expect(SpoolWeightAdjustment.input(used: "", measured: "1050") == .measured(gross: 1050))
    }

    @Test func input_measuredZeroIsNil() {
        #expect(SpoolWeightAdjustment.input(used: "", measured: "0") == nil)
    }

    @Test func input_bothFilledPrefersMeasured() {
        #expect(SpoolWeightAdjustment.input(used: "52", measured: "1050") == .measured(gross: 1050))
    }

    // MARK: - outcome

    @Test func outcome_usedSubtractsFromRemaining() {
        #expect(SpoolWeightAdjustment.outcome(of: .used(52), currentRemaining: 812, emptySpoolWeight: nil) == .remaining(760))
    }

    @Test func outcome_usedExactlyRemainingIsZeroNotNegative() {
        #expect(SpoolWeightAdjustment.outcome(of: .used(812), currentRemaining: 812, emptySpoolWeight: nil) == .remaining(0))
    }

    @Test func outcome_usedMoreThanRemainingIsNegative() {
        #expect(SpoolWeightAdjustment.outcome(of: .used(900), currentRemaining: 812, emptySpoolWeight: nil) == .negative(-88))
    }

    @Test func outcome_usedWithoutCurrentRemainingNeedsWeighing() {
        #expect(SpoolWeightAdjustment.outcome(of: .used(52), currentRemaining: nil, emptySpoolWeight: nil) == .needsCurrentRemaining)
    }

    @Test func outcome_measuredNetsOutEmptySpool() {
        #expect(SpoolWeightAdjustment.outcome(of: .measured(gross: 1050), currentRemaining: 812, emptySpoolWeight: 250) == .remaining(800))
    }

    @Test func outcome_measuredWithoutEmptySpoolWeightNeedsIt() {
        #expect(SpoolWeightAdjustment.outcome(of: .measured(gross: 1050), currentRemaining: 812, emptySpoolWeight: nil) == .needsEmptySpoolWeight)
    }

    @Test func outcome_measuredLighterThanCoreIsNegative() {
        #expect(SpoolWeightAdjustment.outcome(of: .measured(gross: 200), currentRemaining: 812, emptySpoolWeight: 250) == .negative(-50))
    }

    // MARK: - previewText

    @Test func previewText_remainingChange() {
        let preview = SpoolWeightAdjustment.Preview(before: 812, outcome: .remaining(760))
        #expect(SpoolWeightAdjustment.previewText(preview) == "Remaining: 812 g → 760 g")
    }

    @Test func previewText_roundsToATenthOfAGram() {
        let preview = SpoolWeightAdjustment.Preview(before: 812.3456, outcome: .remaining(760.04))
        #expect(SpoolWeightAdjustment.previewText(preview) == "Remaining: 812.3 g → 760 g")
    }

    @Test func previewText_remainingWithoutBefore() {
        let preview = SpoolWeightAdjustment.Preview(before: nil, outcome: .remaining(760))
        #expect(SpoolWeightAdjustment.previewText(preview) == "Remaining: 760 g")
    }

    @Test func previewText_negative() {
        let preview = SpoolWeightAdjustment.Preview(before: 812, outcome: .negative(-88))
        #expect(SpoolWeightAdjustment.previewText(preview) == "Remaining: 812 g → -88 g")
    }

    @Test func previewText_needsEmptySpoolWeightIsNil() {
        let preview = SpoolWeightAdjustment.Preview(before: 812, outcome: .needsEmptySpoolWeight)
        #expect(SpoolWeightAdjustment.previewText(preview) == nil)
    }

    @Test func previewText_needsCurrentRemainingIsNil() {
        let preview = SpoolWeightAdjustment.Preview(before: nil, outcome: .needsCurrentRemaining)
        #expect(SpoolWeightAdjustment.previewText(preview) == nil)
    }
}
