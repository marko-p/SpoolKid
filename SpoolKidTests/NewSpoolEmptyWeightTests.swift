//
//  NewSpoolEmptyWeightTests.swift
//  SpoolKidTests
//
//  Purpose: What a new spool's Empty Spool Weight starts as, and when a
//  filament change refills it.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

struct NewSpoolEmptyWeightTests {
    @Test func theDefaultEntryBeatsTheLastUsedValue() {
        #expect(SpoolFormView.newSpoolEmptyWeight(entryWeight: 250, lastUsed: "180") == "250")
    }

    @Test func aFractionalDefaultIsFormattedAsTyped() {
        #expect(SpoolFormView.newSpoolEmptyWeight(entryWeight: 172.5, lastUsed: "0") == "172.5")
    }

    @Test func withNoDefaultTheLastUsedValueStays() {
        #expect(SpoolFormView.newSpoolEmptyWeight(entryWeight: nil, lastUsed: "180") == "180")
    }

    @Test func withNoDefaultAndNoLastUsedValueTheFieldIsEmpty() {
        #expect(SpoolFormView.newSpoolEmptyWeight(entryWeight: nil, lastUsed: "") == "")
    }

    // MARK: - Following the filament's brand

    @Test func aBrandChangeRefillsAnUntouchedField() {
        #expect(SpoolFormView.refilledEmptyWeight(current: "250", autoFilled: "250", isNewSpool: true, entryWeight: 140, lastUsed: "180") == "140")
    }

    /// Spoolman and FilaMan load the filament list after the form opens: the
    /// brand appears late, over the general default already in the field.
    @Test func aLateBrandRefillsAnUntouchedField() {
        #expect(SpoolFormView.refilledEmptyWeight(current: "0", autoFilled: "0", isNewSpool: true, entryWeight: 215.5, lastUsed: "0") == "215.5")
    }

    @Test func aTypedWeightIsKept() {
        #expect(SpoolFormView.refilledEmptyWeight(current: "300", autoFilled: "250", isNewSpool: true, entryWeight: 140, lastUsed: "180") == nil)
    }

    /// A pick or an applied scale suggestion clears `autoFilled`.
    @Test func aPickedOrAppliedWeightIsKept() {
        #expect(SpoolFormView.refilledEmptyWeight(current: "250", autoFilled: nil, isNewSpool: true, entryWeight: 140, lastUsed: "180") == nil)
    }

    @Test func editModeNeverRefills() {
        #expect(SpoolFormView.refilledEmptyWeight(current: "250", autoFilled: "250", isNewSpool: false, entryWeight: 140, lastUsed: "180") == nil)
    }

    @Test func aBrandWithNothingRefillsToTheLastUsedValue() {
        #expect(SpoolFormView.refilledEmptyWeight(current: "140", autoFilled: "140", isNewSpool: true, entryWeight: nil, lastUsed: "180") == "180")
    }

    // MARK: - The filament's own spool weight

    /// Decision 4: a weight the filament states beats the library's brand default.
    @Test func filamentWeightWinsOverTheLibrary() {
        #expect(SpoolFormView.newSpoolEmptyWeight(filamentWeight: 193, entryWeight: 250, lastUsed: "0") == "193")
    }

    @Test func unknownFilamentWeightFallsThrough() {
        #expect(SpoolFormView.newSpoolEmptyWeight(filamentWeight: 0, entryWeight: 250, lastUsed: "0") == "250")
        #expect(SpoolFormView.newSpoolEmptyWeight(filamentWeight: nil, entryWeight: 250, lastUsed: "0") == "250")
        #expect(SpoolFormView.newSpoolEmptyWeight(filamentWeight: 0, entryWeight: nil, lastUsed: "180") == "180")
        #expect(SpoolFormView.newSpoolEmptyWeight(filamentWeight: nil, entryWeight: nil, lastUsed: "180") == "180")
    }

    @Test func followRuleUsesTheFilamentWeight() {
        #expect(SpoolFormView.refilledEmptyWeight(
            current: "250", autoFilled: "250", isNewSpool: true,
            filamentWeight: 193, entryWeight: 250, lastUsed: "0") == "193")
        #expect(SpoolFormView.refilledEmptyWeight(
            current: "180", autoFilled: "250", isNewSpool: true,
            filamentWeight: 193, entryWeight: 250, lastUsed: "0") == nil)
        #expect(SpoolFormView.refilledEmptyWeight(
            current: "250", autoFilled: "250", isNewSpool: false,
            filamentWeight: 193, entryWeight: 250, lastUsed: "0") == nil)
    }
}
