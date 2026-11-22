//
//  TransmissionDistanceTests.swift
//  SpoolKidTests
//
//  Purpose: The one set of TD rules every backend, form and tag path uses:
//  tolerant decoding of what another tool stored, the valid range, rounding,
//  and Spoolman's per-field-type wire form.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
import Foundation
@testable import SpoolKid

struct TransmissionDistanceTests {
    @Test func decodesBareNumber() { #expect(TransmissionDistance.decode("3.5") == 3.5) }

    @Test func decodesWrappedString() { #expect(TransmissionDistance.decode("\"3.5\"") == 3.5) }

    @Test func decodesCommaDecimal() { #expect(TransmissionDistance.decode("3,5") == 3.5) }

    @Test func rejectsOutOfRangeAndJunk() {
        for raw in ["0", "-1", "101", "abc", "", nil] as [String?] {
            #expect(TransmissionDistance.decode(raw) == nil)
        }
        #expect(TransmissionDistance.decode("100") == 100)
    }

    @Test func roundsToTenth() {
        #expect(TransmissionDistance.rounded(3.46) == 3.5)
        #expect(TransmissionDistance.rounded(3.44) == 3.4)
    }

    @Test func spoolmanWireFollowsFieldType() {
        #expect(TransmissionDistance.spoolmanWireValue(3.5, fieldType: "float") == "3.5")
        #expect(TransmissionDistance.spoolmanWireValue(3.5, fieldType: "text") == "\"3.5\"")
        #expect(TransmissionDistance.spoolmanWireValue(3.5, fieldType: "integer") == nil)
    }

    @Test func displayTextOneDecimal() {
        #expect(TransmissionDistance.displayText(3.5) == "3.5 mm")
        #expect(TransmissionDistance.displayText(3) == "3.0 mm")
    }

    @Test func filamentReadsTDFromExtra() {
        #expect(Filament(id: 1, extra: ["td": "2.8"]).transmissionDistance == 2.8)
        #expect(Filament(id: 1, extra: ["variant": "\"Silk\""]).transmissionDistance == nil)
    }

    /// Final review #2: below the 0.1 resolution a value rounds to 0, which
    /// is out of range — so it is no TD at all, never a "0.0" that locks Save.
    @Test func valuesThatRoundToZeroAreNoTD() {
        #expect(TransmissionDistance.decode("0.04") == nil)
        #expect(!TransmissionDistance.isValid(0.04))
        #expect(TransmissionDistance.isValid(0.05))
    }
}
