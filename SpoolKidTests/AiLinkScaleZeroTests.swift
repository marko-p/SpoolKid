//
//  AiLinkScaleZeroTests.swift
//  SpoolKidTests
//
//  The sequences here are the shapes the owner's real captures take: a burst
//  while a load changes, then silence. Raw values are the actual bytes; the
//  owner's scale masks with 0x83B7.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing

@testable import SpoolKid

private let ownerMask: UInt16 = 0x83B7
/// Raw value for a weight, on the owner's scale.
private func raw(_ grams: Int) -> UInt16 { UInt16(grams) ^ ownerMask }

@Suite struct AiLinkScaleZeroTests {

    @Test func anEmptyPanGoingQuietTeachesTheMask() {
        var zero = AiLinkScaleZero()
        zero.observe(value: raw(0), isSettled: false)
        zero.observeSilence()
        #expect(zero.mask == ownerMask)
        #expect(zero.grams(of: raw(2383)) == 2383)
    }

    @Test func noWeightIsReportedBeforeTheMaskIsKnown() {
        // A weight nobody can check is worse than no weight at all.
        let zero = AiLinkScaleZero()
        #expect(zero.grams(of: raw(2383)) == nil)
    }

    @Test func aLoadRestingOnThePanIsNotMistakenForZero() {
        // The scale marks a resting LOAD as settled. That is the whole
        // discriminator, and it is what stops a spool left on the pan from
        // being adopted as the empty reading.
        var zero = AiLinkScaleZero()
        zero.observe(value: raw(1252), isSettled: true)
        zero.observeSilence()
        #expect(zero.mask == nil)
    }

    @Test func aFullWeighingTeachesTheMaskAndThenReadsTheSpool() {
        var zero = AiLinkScaleZero()
        // Pan empty, scale idles and goes quiet.
        zero.observe(value: raw(0), isSettled: false)
        zero.observeSilence()
        // Spool goes on: a burst that settles.
        for g in [97, 433, 928, 1215, 1252] { zero.observe(value: raw(g), isSettled: false) }
        zero.observe(value: raw(1252), isSettled: true)
        zero.observeSilence()
        #expect(zero.mask == ownerMask)
        #expect(zero.grams(of: raw(1252)) == 1252)
    }

    @Test func driftAtRestIsAdoptedAsTheNewZero() {
        // A scale left on drifts a few grams. The captures show 0–8 g.
        var zero = AiLinkScaleZero(mask: ownerMask)
        zero.observe(value: raw(6), isSettled: false)
        zero.observeSilence()
        #expect(zero.mask == raw(6))
        #expect(zero.grams(of: raw(6)) == 0)
    }

    @Test func anAlreadyCorrectZeroDoesNotDriftOnRepeatedSilence() {
        // Idempotence matters: the silence check runs on a timer, and a mask
        // that walked a gram on every tick would be worse than no tracking.
        var zero = AiLinkScaleZero(mask: ownerMask)
        zero.observe(value: raw(0), isSettled: false)
        for _ in 0..<20 { zero.observeSilence() }
        #expect(zero.mask == ownerMask)
    }

    @Test func aRestingSpoolIsTooHeavyToBeAdoptedAsDrift() {
        // The lightest load in any capture was 239 g; the tolerance is 60 g.
        // Even if a load somehow arrives unsettled, it cannot become zero.
        var zero = AiLinkScaleZero(mask: ownerMask)
        zero.observe(value: raw(239), isSettled: false)
        zero.observeSilence()
        #expect(zero.mask == ownerMask)
    }

    @Test func theUserAlwaysWins() {
        var zero = AiLinkScaleZero(mask: 0x0000)
        zero.setZero(raw(0))
        #expect(zero.mask == ownerMask)
        #expect(zero.grams(of: raw(2622)) == 2622)
    }

    // MARK: - Is the held frame the scale's last word?
    //
    // The link drops every ~5 s (the unanswered handshake), and a drop loses
    // whatever the scale sent while it was down. With the link up, the
    // captures show the scale's follow-up frame always inside 1.3 s.

    /// Seconds into a capture, as a date.
    private func at(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: seconds) }

    @Test func noFrameMeansNothingIsHeld() {
        #expect(AiLinkScaleZero().heldFrame(at: at(10)) == .none)
    }

    @Test func aFrameIsStillArrivingInsideTheFollowUpWindow() {
        var zero = AiLinkScaleZero(mask: ownerMask)
        zero.observe(value: raw(1249), isSettled: false, at: at(14.155))
        #expect(zero.heldFrame(at: at(15.0)) == .arriving)
    }

    @Test func aFrameTheLinkOutlivedIsFinal() {
        var zero = AiLinkScaleZero(mask: ownerMask)
        zero.observe(value: raw(0), isSettled: false, at: at(62.933))
        #expect(zero.heldFrame(at: at(64.5)) == .final)
        // A drop after the window loses nothing: the scale had finished.
        zero.observeLinkDrop(at: at(64.6))
        #expect(zero.heldFrame(at: at(70)) == .final)
    }

    @Test func aDropBeforeTheSettledFrameCutsTheReadingOff() {
        // Owner capture 2026-09-08 23:16: 1249 g arrives still moving, the
        // link drops 0.79 s later, and the settled frame never comes. The
        // spool sat there for 20 s while the screen said "wait".
        var zero = AiLinkScaleZero(mask: ownerMask)
        for (t, g) in [(13.855, 1191), (14.005, 1228), (14.155, 1249)] {
            zero.observe(value: raw(g), isSettled: false, at: at(t))
        }
        zero.observeLinkDrop(at: at(14.941))
        #expect(zero.heldFrame(at: at(20)) == .cutOff)
    }

    @Test func aNewFrameEndsACutOff() {
        var zero = AiLinkScaleZero(mask: ownerMask)
        zero.observe(value: raw(1249), isSettled: false, at: at(14.155))
        zero.observeLinkDrop(at: at(14.941))
        zero.observe(value: raw(1250), isSettled: false, at: at(35.695))
        #expect(zero.heldFrame(at: at(35.8)) == .arriving)
    }

    @Test func aLiftCutOffByADropDoesNotMoveTheZero() {
        // Owner capture 2026-09-08 18:55: a spool coming off, the link drops
        // 29 ms after a 34 g frame, and the scale is silent for 4.6 s. The
        // old rule called that a resting pan 34 g off and adopted it, so the
        // next spool read 297 g instead of 267 g.
        var zero = AiLinkScaleZero(mask: ownerMask)
        for (t, g) in [(66.923, 437), (67.073, 304), (67.223, 145), (67.433, 34)] {
            zero.observe(value: raw(g), isSettled: false, at: at(t))
        }
        zero.observeLinkDrop(at: at(67.462))
        zero.observeSilence()
        #expect(zero.mask == ownerMask)
    }

    @Test func aCutOffFrameDoesNotTeachAFirstZero() {
        var zero = AiLinkScaleZero()
        zero.observe(value: raw(34), isSettled: false, at: at(67.433))
        zero.observeLinkDrop(at: at(67.462))
        zero.observeSilence()
        #expect(zero.mask == nil)
    }

    @Test func driftAfterAnUnbrokenRestIsStillAdopted() {
        var zero = AiLinkScaleZero(mask: ownerMask)
        zero.observe(value: raw(3), isSettled: false, at: at(9.983))
        zero.observeLinkDrop(at: at(12.0))  // after the window: the rest was seen
        zero.observeSilence()
        #expect(zero.mask == raw(3))
    }

    // MARK: - What "Pan is empty — zero it" may take

    @Test func aFinalUnsettledFrameCanBeTakenAsZero() {
        var zero = AiLinkScaleZero(mask: 0x0000)
        zero.observe(value: raw(0), isSettled: false, at: at(62.933))
        #expect(zero.zeroCandidate(at: at(64.5)) == raw(0))
    }

    @Test func aSettledFrameIsALoadNotAnEmptyPan() {
        // The scale marks a reading steady only when something is on it.
        var zero = AiLinkScaleZero(mask: ownerMask)
        zero.observe(value: raw(1255), isSettled: true, at: at(69.160))
        #expect(zero.zeroCandidate(at: at(80)) == nil)
    }

    @Test func aFrameStillArrivingCannotBeTakenAsZero() {
        var zero = AiLinkScaleZero(mask: ownerMask)
        zero.observe(value: raw(9), isSettled: false, at: at(31.193))
        #expect(zero.zeroCandidate(at: at(31.3)) == nil)
    }

    @Test func aCutOffFrameCannotBeTakenAsZero() {
        // The frame held may be the spool on its way off. Zeroing against it
        // saves a zero a spool's weight out, and the next spool reads roughly
        // double — the XOR of two spool weights.
        var zero = AiLinkScaleZero(mask: ownerMask)
        zero.observe(value: raw(851), isSettled: false, at: at(133.193))
        zero.observeLinkDrop(at: at(133.220))
        #expect(zero.zeroCandidate(at: at(140)) == nil)
    }

    @Test func silenceBeforeAnyFrameTeachesNothing() {
        var zero = AiLinkScaleZero()
        zero.observeSilence()
        #expect(zero.mask == nil)
    }

    // MARK: - A scale that zeroes itself

    /// A plain-grams scale (`CAScaleFrame`) is zeroed by its own Tare button.
    /// Adopting a resting few grams as zero would shift every later reading.
    @Test func aSelfZeroingScaleNeverLearnsAZero() {
        var zero = AiLinkScaleZero.selfZeroing
        zero.observe(value: 6, isSettled: false, at: at(10))
        zero.observeSilence()
        #expect(zero.grams(of: 6) == 6)
    }

    @Test func aSelfZeroingScaleOffersNoZeroCorrection() {
        var zero = AiLinkScaleZero.selfZeroing
        zero.observe(value: 0, isSettled: false, at: at(10))
        #expect(zero.zeroCandidate(at: at(20)) == nil)
    }
}
