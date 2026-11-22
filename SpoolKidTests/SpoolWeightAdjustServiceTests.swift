//
//  SpoolWeightAdjustServiceTests.swift
//  SpoolKidTests
//
//  Purpose: The draft and the confirmation text the Scan Result Hub's weight
//  card saves through. The save itself reads the store, so it is covered by
//  the device pass rather than here.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
@testable import SpoolKid

@MainActor
struct SpoolWeightAdjustServiceTests {

    @Test func draft_used_setsRemainingAndLeavesMeasuredUnset() {
        let draft = SpoolWeightAdjustService.draft(for: .used(52), newRemaining: 760)
        if case .set(let value) = draft.remainingWeight {
            #expect(value == 760)
        } else {
            Issue.record("remainingWeight not set")
        }
        #expect(draft.measuredWeight == nil)
    }

    @Test func draft_measured_setsRemainingAndGrossReading() {
        let draft = SpoolWeightAdjustService.draft(for: .measured(gross: 1050), newRemaining: 800)
        if case .set(let value) = draft.remainingWeight {
            #expect(value == 800)
        } else {
            Issue.record("remainingWeight not set")
        }
        #expect(draft.measuredWeight == 1050)
    }

    @Test func savedMessage_roundsToATenthOfAGram() {
        #expect(SpoolWeightAdjustService.savedMessage(remaining: 759.87) == "Saved — 759.9 g remaining")
    }

    @Test func savedMessage_statesTheRemainingWeightWritten() {
        #expect(SpoolWeightAdjustService.savedMessage(remaining: 760) == "Saved — 760 g remaining")
    }
}

// Appended: the post-read decision, pure so the fresh-read rule is tested
// without a store.
extension SpoolWeightAdjustServiceTests {

    private func spool(remaining: Double?, spoolWeight: Double? = 200) -> Spool {
        Spool(id: 7, filament: Filament(id: 1, name: "F", material: "PLA"),
              remainingWeight: remaining, spoolWeight: spoolWeight,
              statusId: nil, externalId: nil, purchaseDate: nil)
    }

    @Test func decide_used_subtractsFromFreshRemainingNotPreview() {
        // The fresh read says 700 g; the hub preview may have shown 812 g.
        let plan = SpoolWeightAdjustService.decide(.used(52), spool: spool(remaining: 700), freshReadFailed: false)
        #expect(plan == .write(remaining: 648))
    }

    @Test func decide_freshReadFailed_failsAndWritesNothing() {
        let plan = SpoolWeightAdjustService.decide(.used(52), spool: spool(remaining: 700), freshReadFailed: true)
        #expect(plan == .failed(SpoolWeightAdjustService.readFailedMessage))
    }

    @Test func decide_spoolMissing_fails() {
        let plan = SpoolWeightAdjustService.decide(.used(52), spool: nil, freshReadFailed: false)
        #expect(plan == .failed("The spool could not be found."))
    }

    @Test func decide_usedOverRemaining_refusesWithNegativeNote() {
        let plan = SpoolWeightAdjustService.decide(.used(52), spool: spool(remaining: 40), freshReadFailed: false)
        #expect(plan == .refused(SpoolWeightAdjustment.negativeNote))
    }
}
