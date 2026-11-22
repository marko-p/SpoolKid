//
//  ColorMatchingTests.swift
//  SpoolKidTests
//
//  Tests for ColorMatching: hex parsing (3/6-char, # prefix, invalid),
//  CIELAB conversion, ΔE76, and similarity scoring.
//

import Testing
@testable import SpoolKid

struct ColorMatchingTests {

    // MARK: - normalize

    @Test func stripsHashAndUppercases() { #expect(ColorMatching.normalize("#abc123") == "ABC123") }
    @Test func expandsThreeDigit() { #expect(ColorMatching.normalize("f80") == "FF8800") }
    @Test func rejectsInvalid() { #expect(ColorMatching.normalize("xyz") == nil) }
    @Test func nilForEmpty() { #expect(ColorMatching.normalize(nil) == nil) }

    // MARK: - parseHex

    @Test func parseHex6CharReturnsCorrectRGB() {
        let result = ColorMatching.parseHex("FF0000")
        #expect(result?.r == 1.0)
        #expect(result?.g == 0.0)
        #expect(result?.b == 0.0)
    }

    @Test func parseHex6CharBlack() {
        let result = ColorMatching.parseHex("000000")
        #expect(result?.r == 0.0)
        #expect(result?.g == 0.0)
        #expect(result?.b == 0.0)
    }

    @Test func parseHex6CharWhite() {
        let result = ColorMatching.parseHex("FFFFFF")
        #expect(result?.r == 1.0)
        #expect(result?.g == 1.0)
        #expect(result?.b == 1.0)
    }

    @Test func parseHex3CharExpands() {
        let result = ColorMatching.parseHex("F00")
        #expect(result?.r == 1.0)
        #expect(result?.g == 0.0)
        #expect(result?.b == 0.0)
    }

    @Test func parseHex3CharMidGray() {
        let result = ColorMatching.parseHex("888")
        #expect(abs(result!.r - 0.5333) < 0.001)
        #expect(abs(result!.g - 0.5333) < 0.001)
        #expect(abs(result!.b - 0.5333) < 0.001)
    }

    @Test func parseHexWithHashPrefix() {
        let result = ColorMatching.parseHex("#FF0000")
        #expect(result?.r == 1.0)
        #expect(result?.g == 0.0)
        #expect(result?.b == 0.0)
    }

    @Test func parseHex3CharWithHashPrefix() {
        let result = ColorMatching.parseHex("#F00")
        #expect(result?.r == 1.0)
        #expect(result?.g == 0.0)
        #expect(result?.b == 0.0)
    }

    @Test func parseHexWithWhitespace() {
        let result = ColorMatching.parseHex("  FF0000  ")
        #expect(result?.r == 1.0)
        #expect(result?.g == 0.0)
        #expect(result?.b == 0.0)
    }

    @Test func parseHexInvalidLengthReturnsNil() {
        #expect(ColorMatching.parseHex("FF") == nil)
        #expect(ColorMatching.parseHex("FF00") == nil)
        #expect(ColorMatching.parseHex("FF000") == nil)
        #expect(ColorMatching.parseHex("FF00000") == nil)
    }

    @Test func parseHexInvalidCharsReturnsNil() {
        #expect(ColorMatching.parseHex("GG0000") == nil)
        #expect(ColorMatching.parseHex("ZZZ") == nil)
        #expect(ColorMatching.parseHex("FF00XX") == nil)
    }

    @Test func parseHexEmptyReturnsNil() {
        #expect(ColorMatching.parseHex("") == nil)
        #expect(ColorMatching.parseHex("#") == nil)
    }

    // MARK: - lab(from:)

    @Test func labFromWhiteReturnsExpectedValues() {
        let lab = ColorMatching.lab(from: "FFFFFF")
        #expect(lab != nil)
        #expect(abs(lab!.l - 100.0) < 0.5)
        #expect(abs(lab!.a) < 0.5)
        #expect(abs(lab!.b) < 0.5)
    }

    @Test func labFromBlackReturnsExpectedValues() {
        let lab = ColorMatching.lab(from: "000000")
        #expect(lab != nil)
        #expect(abs(lab!.l) < 0.5)
        #expect(abs(lab!.a) < 0.5)
        #expect(abs(lab!.b) < 0.5)
    }

    @Test func labFromInvalidHexReturnsNil() {
        #expect(ColorMatching.lab(from: "invalid") == nil)
        #expect(ColorMatching.lab(from: "") == nil)
    }

    // MARK: - deltaE2000

    /// Sharma, Wu and Dalal (2005), Table 1.
    @Test(arguments: [
        (50.0, 2.6772, -79.7751, 50.0, 0.0, -82.7485, 2.0425),
        (50.0, 0.0, 0.0, 50.0, -1.0, 2.0, 2.3669),
        (50.0, 2.49, -0.001, 50.0, -2.49, 0.0011, 7.2195),
        (50.0, 2.5, 0.0, 73.0, 25.0, -18.0, 27.1492),
        (50.0, 2.5, 0.0, 50.0, 3.1736, 0.5854, 1.0),
        (60.2574, -34.0099, 36.2677, 60.4626, -34.1751, 39.4387, 1.2644),
        (2.0776, 0.0795, -1.135, 0.9033, -0.0636, -0.5514, 0.9082)
    ])
    func deltaE2000MatchesSharma(row: (Double, Double, Double, Double, Double, Double, Double)) {
        let first = (l: row.0, a: row.1, b: row.2)
        let second = (l: row.3, a: row.4, b: row.5)
        #expect(abs(ColorMatching.deltaE2000(first, second) - row.6) < 0.0001)
        #expect(abs(ColorMatching.deltaE2000(second, first) - row.6) < 0.0001)
    }

    @Test func deltaE2000IdenticalColorsIsZero() throws {
        let lab = try #require(ColorMatching.lab(from: "FF0000"))
        #expect(ColorMatching.deltaE2000(lab, lab) == 0)
    }

    // MARK: - similarity01

    @Test func similarity01IdenticalColorsIsOne() {
        let similarity = ColorMatching.similarity01(hexA: "FF0000", hexB: "FF0000")
        #expect(abs(similarity - 1.0) < 0.001)
    }

    @Test func similarity01BlackWhiteIsZero() {
        let similarity = ColorMatching.similarity01(hexA: "000000", hexB: "FFFFFF")
        #expect(similarity < 0.01)
    }

    @Test func similarity01SimilarColorsIsHigh() {
        let similarity = ColorMatching.similarity01(hexA: "FF0000", hexB: "FE0000")
        #expect(similarity > 0.95)
    }

    @Test func similarity01DifferentColorsIsLower() {
        let similarity = ColorMatching.similarity01(hexA: "FF0000", hexB: "0000FF")
        #expect(similarity < 0.5)
    }

    @Test func similarity01InvalidFirstHexReturnsZero() {
        let similarity = ColorMatching.similarity01(hexA: "invalid", hexB: "FF0000")
        #expect(similarity == 0)
    }

    @Test func similarity01InvalidSecondHexReturnsZero() {
        let similarity = ColorMatching.similarity01(hexA: "FF0000", hexB: "invalid")
        #expect(similarity == 0)
    }

    @Test func similarity01NilSecondHexReturnsZero() {
        let similarity = ColorMatching.similarity01(hexA: "FF0000", hexB: nil)
        #expect(similarity == 0)
    }

    @Test func similarity01Accepts3CharHex() {
        let similarity = ColorMatching.similarity01(hexA: "F00", hexB: "FF0000")
        #expect(abs(similarity - 1.0) < 0.001)
    }

    @Test func similarity01AcceptsHashPrefix() {
        let similarity = ColorMatching.similarity01(hexA: "#FF0000", hexB: "#FF0000")
        #expect(abs(similarity - 1.0) < 0.001)
    }

    // MARK: - HSL

    @Test func hslPureRed() {
        let hsl = ColorMatching.hsl(from: "FF0000")
        #expect(hsl?.h == 0)
        #expect(hsl?.s == 1)
        #expect(hsl?.l == 0.5)
    }

    @Test func hslMidGreyIsAchromatic() {
        let hsl = ColorMatching.hsl(from: "808080")
        #expect(hsl?.h == 0)
        #expect(hsl?.s == 0)
        #expect(abs(hsl!.l - 0.502) < 0.001)
    }

    @Test func hslBlackAndWhite() {
        #expect(ColorMatching.hsl(from: "000000")?.l == 0)
        #expect(ColorMatching.hsl(from: "FFFFFF")?.l == 1)
        #expect(ColorMatching.hsl(from: "FFFFFF")?.s == 0)
    }

    @Test func hslInvalidReturnsNil() {
        #expect(ColorMatching.hsl(from: "nope") == nil)
    }

    @Test func hexFromHSLPrimaries() {
        #expect(ColorMatching.hex(h: 0, s: 1, l: 0.5) == "FF0000")
        #expect(ColorMatching.hex(h: 120, s: 1, l: 0.5) == "00FF00")
        #expect(ColorMatching.hex(h: 240, s: 1, l: 0.5) == "0000FF")
    }

    @Test func hexFromHSLWrapsHue() {
        #expect(ColorMatching.hex(h: 360, s: 1, l: 0.5) == "FF0000")
        #expect(ColorMatching.hex(h: 480, s: 1, l: 0.5) == "00FF00")
        #expect(ColorMatching.hex(h: -30, s: 1, l: 0.5) == ColorMatching.hex(h: 330, s: 1, l: 0.5))
    }

    @Test func hslRoundTripPreservesColor() {
        for hex in ["1D9E75", "C62828", "123B7A", "FAC775", "808080", "F5F5F5"] {
            let hsl = ColorMatching.hsl(from: hex)!
            #expect(ColorMatching.hex(h: hsl.h, s: hsl.s, l: hsl.l) == hex)
        }
    }
}
