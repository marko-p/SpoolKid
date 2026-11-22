//
//  CAScaleFrameTests.swift
//  SpoolKidTests
//
//  Every frame here is a real one, from the "Kitchen Scale3" capture attached
//  to issue #21 (a Futula Kitchen Scale 5, 2026-10-21). The settled grams are
//  the numbers the tester typed from the scale's own display.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing

@testable import SpoolKid

private func frame(_ hex: String) -> Data {
    Data(stride(from: 0, to: hex.count, by: 2).map { offset in
        let start = hex.index(hex.startIndex, offsetBy: offset)
        let end = hex.index(start, offsetBy: 2)
        return UInt8(hex[start..<end], radix: 16)!
    })
}

@Suite struct CAScaleFrameTests {

    @Test(arguments: [
        ("CA00002C000000000400E2", 44),    // display read 44 g
        ("CA0000810000000004004F", 129),   // 129 g
        ("CA0000B00000000004007E", 176),   // 176 g
    ])
    func settledFramesReadAsTheDisplayedGrams(hex: String, grams: Int) throws {
        let weight = try #require(CAScaleFrame.weightFrame(from: frame(hex)))
        #expect(Int(weight.masked) == grams)
        #expect(weight.isSettled)
    }

    @Test func theWeightIsLittleEndianAcrossTwoBytes() {
        #expect(CAScaleFrame.weightFrame(from: frame("CA00000C020000000400C0"))?.masked == 524)
    }

    @Test func aMovingPanIsNotSettled() throws {
        let weight = try #require(CAScaleFrame.weightFrame(from: frame("CA00008F00000000040140")))
        #expect(weight.masked == 143)
        #expect(!weight.isSettled)
    }

    /// The unit byte follows the display, but the number does not change with
    /// it: 1127 is sent while the display cycles through every unit.
    @Test(arguments: ["CA000067040000000501AD", "CA000067040000000601AE", "CA000067040000000101A9"])
    func everyDisplayUnitReadsInGrams(hex: String) {
        #expect(CAScaleFrame.weightFrame(from: frame(hex))?.masked == 1127)
    }

    /// Byte 2 is set only on unsettled frames, and what it means is unknown
    /// (66 and 322 g fit it equally badly), so those frames are not weights.
    @Test func aFrameWithByteTwoSetIsNotAWeight() {
        #expect(CAScaleFrame.weightFrame(from: frame("CA0001420000000004018C")) == nil)
    }

    @Test func aBadChecksumIsRefused() {
        #expect(CAScaleFrame.weightFrame(from: frame("CA00002C000000000400E3")) == nil)
    }

    @Test func anythingElseIsRefused() {
        // Truncated, another header, and an AiLink frame.
        #expect(CAScaleFrame.weightFrame(from: frame("CA00002C0000000004")) == nil)
        #expect(CAScaleFrame.weightFrame(from: frame("CB00002C000000000400E3")) == nil)
        #expect(CAScaleFrame.weightFrame(from: frame("A7006C09EB560383B76DEA42028E7A")) == nil)
    }
}

/// The 16-byte frames of an AccuWeight CK780BLE, from the capture attached to
/// issue #22 (2026-10-24). The grams are the numbers on the tester's photos of
/// the scale's display.
@Suite struct CAScaleLongFrameTests {

    @Test(arguments: [
        ("CA000001016500000000000000000000", 357),   // photo: 357 g
        ("CA00000101E000000000000000000000", 480),   // photo: 480 g
        ("CA000001007C00000000000000000000", 124),   // photo: 124 g
        ("CA00000100CE00000000000000000000", 206),   // photo: 206 g
    ])
    func framesReadAsTheDisplayedGrams(hex: String, grams: Int) throws {
        let weight = try #require(CAScaleFrame.weightFrame(from: frame(hex)))
        #expect(Int(weight.masked) == grams)
        #expect(weight.isSettled)
    }

    /// Byte 3 was 01 on every frame captured. Another value may be another
    /// display unit, whose number would not be grams.
    @Test func anUnseenByteThreeIsNotAWeight() {
        #expect(CAScaleFrame.weightFrame(from: frame("CA000002016500000000000000000000")) == nil)
    }

    @Test func aFrameWithAnythingInItsTailIsNotAWeight() {
        #expect(CAScaleFrame.weightFrame(from: frame("CA000001016500000000000000000001")) == nil)
    }
}

@MainActor
struct CAScaleServiceTests {

    @Test func aPlainGramsFrameReadsAtOnceWithNoZeroToLearn() {
        let service = BLEScaleService()
        service.noteWeight(in: frame("CA00002C000000000400E2"))
        #expect(service.reading?.grams == 44)
        #expect(service.reading?.isSettled == true)
        #expect(service.knowsZero)
    }

    @Test func aLongFrameReadsAtOnceWithNoZeroToLearn() {
        let service = BLEScaleService()
        service.noteWeight(in: frame("CA000001016500000000000000000000"))
        #expect(service.reading?.grams == 357)
        #expect(service.knowsZero)
    }
}
