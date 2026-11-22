//
//  AiLinkScaleFrameTests.swift
//  SpoolKidTests
//
//  Every frame here is a real one, lifted from the owner's captures of
//  2026-09-08. The expected grams are the numbers that were on the scale's own
//  display, taken from the owner's written bench log and from the PacketLogger
//  trace of the vendor app reading the same scale.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing

@testable import SpoolKid

/// The mask of the owner's TBRFP FS2H. Only a fixture — the app derives this
/// from an empty pan rather than hardcoding it.
private let ownerMask: UInt16 = 0x83B7

private func frame(_ hex: String) -> Data {
    Data(stride(from: 0, to: hex.count, by: 2).map { offset in
        let start = hex.index(hex.startIndex, offsetBy: offset)
        let end = hex.index(start, offsetBy: 2)
        return UInt8(hex[start..<end], radix: 16)!
    })
}

@Suite struct AiLinkScaleFrameTests {

    @Test func anEmptyPanReadsExactlyZero() {
        let reading = AiLinkScaleFrame.reading(from: frame("A7006C09EB560383B76DEA42028E7A"), zeroMask: ownerMask)
        #expect(reading?.grams == 0)
    }

    @Test func theMaskIsWhateverAnEmptyPanSends() {
        // The calibration step, in one assertion: read the pan empty and the
        // bytes you get back are the mask that decodes every later frame.
        #expect(AiLinkScaleFrame.zeroMask(from: frame("A7006C09EB560383B76DEA42028E7A")) == ownerMask)
    }

    @Test(arguments: [
        // Settled readings from the vendor-app trace, against the owner's log.
        ("A7006C09EB640387546DEA42013C7A", 1251),   // logged 1252 g
        ("A7006C09EB6C038AF86DEA4201EB7A", 2383),   // logged 2383 g
        ("A7006C09EB740389896DEA4201837A", 2622),   // logged 2622 g
    ])
    func settledFramesDecodeToTheDisplayedWeight(hex: String, grams: Int) {
        let reading = AiLinkScaleFrame.reading(from: frame(hex), zeroMask: ownerMask)
        #expect(reading?.grams == grams)
        #expect(reading?.isSettled == true)
    }

    @Test func aMovingPanIsNotReportedAsSettled() {
        let reading = AiLinkScaleFrame.reading(from: frame("A7006C09EB510383B56DEA4202877A"), zeroMask: ownerMask)
        #expect(reading?.isSettled == false)
        #expect(reading?.grams == 2)
    }

    @Test func aFrameFromTheSpoolKidExplorerDecodesWithTheSameMask() throws {
        // Captured hours earlier, by a different app, with the vendor handshake
        // never answered. Same mask — which is what makes it a device constant
        // rather than something negotiated per session.
        let reading = try #require(
            AiLinkScaleFrame.reading(from: frame("A7006C09EB2D0383BF6DEA42026D7A"), zeroMask: ownerMask)
        )
        #expect(reading.grams == 8)
        #expect(reading.sequence == 0x2D)
    }

    @Test func aCorruptedFrameIsRefusedRatherThanDecoded() {
        // One byte of the weight flipped; the checksum no longer agrees. A
        // scale that reports the wrong weight is worse than one that reports
        // none, so this must be nil and not a plausible-looking number.
        #expect(AiLinkScaleFrame.reading(from: frame("A7006C09EB640387556DEA42013C7A"), zeroMask: ownerMask) == nil)
    }

    @Test func theShortHelloFrameIsNotAWeight() {
        // Sent once per connection. Well-formed, correct checksum, carries no
        // weight — the reason SpoolKid once reported the scale as "talking"
        // while no reading had arrived for eight seconds.
        #expect(AiLinkScaleFrame.payload(of: frame("A7006C02E842987A")) != nil)
        #expect(AiLinkScaleFrame.reading(from: frame("A7006C02E842987A"), zeroMask: ownerMask) == nil)
    }

    @Test func aNonGramsUnitIsRefusedRatherThanMisreported() {
        // Byte 6 is the unit code; only 0x03 has ever been seen, and it was
        // grams. An unknown code could be ounces or millilitres, and reporting
        // those as grams would silently corrupt a spool's weight.
        var bytes = [UInt8](frame("A7006C09EB640387546DEA42013C7A"))
        bytes[6] = 0x04
        bytes[13] = UInt8(bytes[1...12].reduce(0) { $0 + Int($1) } & 0xFF)
        #expect(AiLinkScaleFrame.reading(from: Data(bytes), zeroMask: ownerMask) == nil)
    }

    @Test func aTruncatedFrameIsRefused() {
        #expect(AiLinkScaleFrame.payload(of: frame("A7006C09EB64")) == nil)
        #expect(AiLinkScaleFrame.payload(of: Data()) == nil)
    }
}

/// A real AiLink weight frame for a given weight, checksum and all, on the
/// owner's scale. Built rather than pasted so a fixture cannot drift from the
/// format it claims to be in.
private func aiLinkFrame(grams: Int, settled: Bool, seq: UInt8) -> Data {
    let masked = UInt16(grams) ^ ownerMask
    let body: [UInt8] = [
        0x00, 0x6C, 0x09, 0xEB, seq, 0x03,
        UInt8(masked >> 8), UInt8(masked & 0xFF),
        0x6D, 0xEA, 0x42, settled ? 0x01 : 0x02,
    ]
    let sum = UInt8(body.reduce(0) { $0 + Int($1) } & 0xFF)
    return Data([0xA7] + body + [sum, 0x7A])
}

private func weightEntry(grams: Int, settled: Bool, seq: UInt8, at: TimeInterval) -> BLELogEntry {
    BLELogEntry(
        at: Date(timeIntervalSince1970: at),
        content: .packet(characteristic: "FFE2", data: aiLinkFrame(grams: grams, settled: settled, seq: seq))
    )
}

/// The hypothesis the digest was missing. A field that tracks the load but fits
/// no scale factor is usually the reading under a constant transform — so the
/// digest has to show every reading against the one the stream rests at.
@Suite struct BLEDigestRestingTests {

    private func entries(_ steps: [(grams: Int, settled: Bool, at: TimeInterval)]) -> [BLELogEntry] {
        steps.enumerated().map { index, step in
            BLELogEntry(
                at: Date(timeIntervalSince1970: step.at),
                content: .packet(
                    characteristic: "FFE2",
                    data: aiLinkFrame(grams: step.grams, settled: step.settled, seq: UInt8(index))
                )
            )
        }
    }

    @Test func theValueAStreamGoesQuietOnIsReportedAsItsZero() throws {
        // Empty pan, a spool, empty pan again — each burst ended by the silence
        // that makes the packet before it a resting state.
        var steps: [(grams: Int, settled: Bool, at: TimeInterval)] = []
        for i in 0..<4 { steps.append((0, false, Double(i) * 0.2)) }
        for (i, g) in [433, 928, 1215, 1251].enumerated() {
            steps.append((g, false, 20 + Double(i) * 0.2))
        }
        steps.append((1251, true, 21.5))
        for i in 0..<4 { steps.append((0, false, 40 + Double(i) * 0.2)) }

        let digest = try #require(BLEStreamDigest.digests(for: entries(steps)).first)
        #expect(digest.resting == UInt32(ownerMask))
        let text = digest.detail.joined(separator: "\n")
        #expect(text.contains("Rests at"))
        // The XOR column is the weight that was on the display.
        #expect(text.contains("1251"))
        #expect(text.contains("should be the weight on your display"))
    }

    @Test func aStreamThatNeverRestsEmptyDoesNotClaimZero() throws {
        // A capture taken with a spool on the pan the whole time. Four of the
        // owner's eight sessions look like this, and none of them can say where
        // zero is — the digest must not pretend otherwise.
        let steps = (0..<12).map { i in (1251, i == 11, Double(i) * 0.2) }
        let digest = try #require(BLEStreamDigest.digests(for: entries(steps)).first)
        #expect(digest.resting != UInt32(ownerMask))
    }
}


/// A scale stops talking BECAUSE nothing is changing. Judging a mark by how
/// long the stream has been quiet condemns exactly the marks worth most.
@Suite struct BLESettledMarkTests {

    /// The owner's device session (2026-09-08): a steady 1250 g display,
    /// photographed 18.5 s after the scale had settled and gone quiet, and
    /// reported as "NOT MATCHABLE".
    private var restingThenLoaded: [BLELogEntry] {
        var entries: [BLELogEntry] = []
        for i in 0..<6 { entries.append(weightEntry(grams: 0, settled: false, seq: UInt8(i), at: Double(i) * 0.2)) }
        for (i, g) in [433, 928, 1215, 1250].enumerated() {
            entries.append(weightEntry(grams: g, settled: false, seq: UInt8(10 + i), at: 20 + Double(i) * 0.2))
        }
        entries.append(weightEntry(grams: 1250, settled: true, seq: 20, at: 21.5))
        for i in 0..<6 { entries.append(weightEntry(grams: 0, settled: false, seq: UInt8(30 + i), at: 60 + Double(i) * 0.2)) }
        return entries
    }

    @Test func aSettledReadingBeforeALongSilenceIsStillMatchable() throws {
        let entries = restingThenLoaded
        // 18.5 s after the scale settled at 1250 g and went quiet.
        let markedAt = Date(timeIntervalSince1970: 40)
        let settled = try #require(BLETranscript.settledWeight(before: markedAt, in: entries))
        #expect(settled == 1250)
        let text = BLETranscript.freshness(gap: 18.5, spread: nil, settledAt: settled)
        #expect(text.contains("MATCHABLE"))
        #expect(!text.contains("NOT MATCHABLE"))
        #expect(text.contains("1250"))
    }

    @Test func aMarkTakenWhileTheReadingIsStillMovingIsNotRedeemed() {
        // Mid-burst, before the settled frame: the scale is moving, and no
        // amount of decoding makes that mark worth pairing with a weight.
        let markedAt = Date(timeIntervalSince1970: 20.5)
        #expect(BLETranscript.settledWeight(before: markedAt, in: restingThenLoaded) == nil)
        #expect(BLETranscript.freshness(gap: 18.5, spread: nil).contains("NOT MATCHABLE"))
    }

    @Test func aMarkAfterTheLoadWasRemovedReadsTheNewSettledState() {
        // After the pan is emptied the last frame is unsettled zero, so the
        // gap rule applies again rather than a stale 1250 g being claimed.
        let markedAt = Date(timeIntervalSince1970: 90)
        #expect(BLETranscript.settledWeight(before: markedAt, in: restingThenLoaded) == nil)
    }

    @Test func aStreamWeCannotDecodeFallsBackToTheGapRule() {
        let entries = [
            BLELogEntry(at: Date(timeIntervalSince1970: 0),
                        content: .packet(characteristic: "FFE2", data: Data([0x01, 0x02, 0x03])))
        ]
        #expect(BLETranscript.settledWeight(before: Date(timeIntervalSince1970: 10), in: entries) == nil)
    }
}
