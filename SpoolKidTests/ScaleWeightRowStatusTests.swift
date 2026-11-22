//
//  ScaleWeightRowStatusTests.swift
//  SpoolKidTests
//
//  What the scale row tells the user about the number on it. The row used to
//  say "wait for it to settle" about readings that would never settle — a
//  reading cut off by a link drop, and an empty pan, which this scale never
//  calls steady (owner, 2026-09-25).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
@testable import SpoolKid

@MainActor
struct ScaleWeightRowStatusTests {

    private func reading(_ grams: Int, settled: Bool) -> AiLinkScaleReading {
        AiLinkScaleReading(grams: grams, isSettled: settled, sequence: 0)
    }

    @Test func aSettledReadingIsSteadyWhateverTheLinkDid() {
        // The scale's own "steady" is its last word on that load.
        for held in [AiLinkScaleZero.HeldFrame.arriving, .final, .cutOff, .none] {
            #expect(ScaleWeightRow.status(of: reading(1250, settled: true), held: held) == .steady)
        }
    }

    @Test func aReadingStillArrivingIsMoving() {
        #expect(ScaleWeightRow.status(of: reading(949, settled: false), held: .arriving) == .moving)
    }

    @Test func aReadingCutOffByADropIsMissed() {
        #expect(ScaleWeightRow.status(of: reading(1249, settled: false), held: .cutOff) == .missed)
    }

    @Test func aReadingFromAnEarlierLinkIsMissed() {
        // Nothing vouches for a frame held over from before a reconnect.
        #expect(ScaleWeightRow.status(of: reading(1249, settled: false), held: .none) == .missed)
    }

    @Test func zeroAtRestIsAnEmptyPan() {
        #expect(ScaleWeightRow.status(of: reading(0, settled: false), held: .final) == .emptyPan)
    }

    @Test func anUnsteadyWeightAtRestIsNotAnEmptyPan() {
        // What a wrong zero looks like on an empty pan: a number, at rest,
        // that the scale never called steady.
        #expect(ScaleWeightRow.status(of: reading(1854, settled: false), held: .final) == .unsteadyAtRest)
    }
}
