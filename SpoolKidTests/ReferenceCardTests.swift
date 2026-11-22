//
//  ReferenceCardTests.swift
//  SpoolKidTests
//
//  Purpose: Tests for the reference card: three-band and single-patch detection
//  on a rectified grid (rejecting coloured and textured rectangles, accepting
//  colour casts and zero black bands), and the white-balance and brightness
//  correction from the card's patches.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
@testable import SpoolKid

/// 30×10 grid (10×30 when vertical) of three equal bands, each one colour, along the long axis.
nonisolated func bandColors(_ colors: [LinearRGB], vertical: Bool = false) -> PixelGrid {
    let width = vertical ? 10 : 30
    let height = vertical ? 30 : 10
    let pixels = (0..<(width * height)).map { index -> LinearRGB in
        let along = vertical ? index / width : index % width
        return colors[along / 10]
    }
    return PixelGrid(width: width, height: height, pixels: pixels)
}

/// 30×10 grid (10×30 when vertical) of three equal neutral bands along the long axis.
nonisolated func bands(_ levels: [Double], vertical: Bool = false) -> PixelGrid {
    bandColors(levels.map { LinearRGB(r: $0, g: $0, b: $0) }, vertical: vertical)
}

/// 30×10 grid filled with one colour.
nonisolated func bands(rgb: LinearRGB) -> PixelGrid {
    PixelGrid(width: 30, height: 10, pixels: Array(repeating: rgb, count: 30 * 10))
}

/// 30×10 grid of 1-pixel checker cells alternating `a` and `b`.
nonisolated func checkerboard(_ a: Double, _ b: Double) -> PixelGrid {
    let pixels = (0..<(30 * 10)).map { index -> LinearRGB in
        let x = index % 30, y = index / 30
        let v = (x + y).isMultiple(of: 2) ? a : b
        return LinearRGB(r: v, g: v, b: v)
    }
    return PixelGrid(width: 30, height: 10, pixels: pixels)
}

struct ReferenceCardTests {

    // MARK: - ReferenceCardAnalyzer

    @Test func threeBandCardIsFound() {                  // bands 0.02 / 0.12 / 0.60 neutral
        #expect(ReferenceCardAnalyzer.patches(in: bands([0.02, 0.12, 0.60]))?.map { ($0.r * 100).rounded() } == [2, 12, 60])
    }

    @Test func uniformGreyIsOnePatch() {
        let patches = ReferenceCardAnalyzer.patches(in: bands([0.18, 0.18, 0.18]))
        #expect(patches?.count == 1)
        #expect(abs((patches?.first?.g ?? 0) - 0.18) < 0.005)
    }

    @Test func coloredRectangleIsNotACard() {
        #expect(ReferenceCardAnalyzer.patches(in: bands(rgb: LinearRGB(hex: "D9622B")!)) == nil)
    }

    @Test func texturedRectangleIsNotACard() {
        #expect(ReferenceCardAnalyzer.patches(in: checkerboard(0.05, 0.5)) == nil)
    }

    @Test func verticalCardSplitsAlongLongAxis() {
        #expect(ReferenceCardAnalyzer.patches(in: bands([0.02, 0.12, 0.60], vertical: true))?.count == 3)
    }

    @Test func ambiguousBandStepIsNotACard() {           // 1.22× steps: neither 1.5× nor within 1.15×
        #expect(ReferenceCardAnalyzer.patches(in: bands([0.18, 0.18, 0.22])) == nil)
    }

    @Test func warmCastCardIsStillFound() {              // bands × (1.2, 1.0, 0.8)
        let cast = [0.02, 0.12, 0.60].map { LinearRGB(r: $0 * 1.2, g: $0 * 1.0, b: $0 * 0.8) }
        #expect(ReferenceCardAnalyzer.patches(in: bandColors(cast))?.count == 3)
    }

    @Test func darkTintedBandWithinAbsoluteSpreadIsNeutral() {   // spread 0.013 < 0.02 below luminance 0.05
        let tinted = LinearRGB(r: 0.035, g: 0.03, b: 0.022)
        let grid = bandColors([tinted, LinearRGB(r: 0.12, g: 0.12, b: 0.12), LinearRGB(r: 0.6, g: 0.6, b: 0.6)])
        #expect(ReferenceCardAnalyzer.patches(in: grid)?.count == 3)
    }

    @Test func zeroBlackBandKeepsTheCard() {             // black band at exactly zero, grey 0.18, white 0.60
        let grid = bandColors([LinearRGB(r: 0, g: 0, b: 0), LinearRGB(r: 0.18, g: 0.18, b: 0.18), LinearRGB(r: 0.6, g: 0.6, b: 0.6)])
        let patches = ReferenceCardAnalyzer.patches(in: grid)
        #expect(patches?.count == 3)
        #expect(patches?.first?.luminance == 0)

        let r = ColorCorrection.correct(LinearRGB(r: 0.3, g: 0.2, b: 0.1), patches: patches ?? [])
        // Black is dropped; white and grey, role-known by index, still fix the brightness.
        #expect(r?.notes == [.tooDark])
        #expect(r?.correctedBrightness == true)
    }

    // MARK: - ColorCorrection

    @Test func singlePatchNeutralisesItsOwnCast() {
        let cast = LinearRGB(r: 0.25, g: 0.18, b: 0.12)
        let r = ColorCorrection.correct(cast, patches: [cast])!
        #expect(abs(r.color.r - r.color.g) < 1e-3 && abs(r.color.g - r.color.b) < 1e-3)
        #expect(abs(r.color.luminance - cast.luminance) < 1e-3)
        #expect(!r.correctedBrightness)
    }

    @Test func threePatchesFixBrightness() {
        let card = [LinearRGB(r: 0.02, g: 0.02, b: 0.02), LinearRGB(r: 0.12, g: 0.12, b: 0.12), LinearRGB(r: 0.6, g: 0.6, b: 0.6)]
        #expect(abs(ColorCorrection.correct(card[2], patches: card)!.color.g - 0.90) < 0.005)
        #expect(abs(ColorCorrection.correct(card[0], patches: card)!.color.g - 0.031) < 0.005)
        #expect(abs(ColorCorrection.correct(card[1], patches: card)!.color.g - 0.18) < 0.01)
    }

    @Test func patchOrderDoesNotMatter() {
        let card = [LinearRGB(r: 0.6, g: 0.6, b: 0.6), LinearRGB(r: 0.02, g: 0.02, b: 0.02), LinearRGB(r: 0.12, g: 0.12, b: 0.12)]
        let r = ColorCorrection.correct(LinearRGB(r: 0.12, g: 0.12, b: 0.12), patches: card)!
        #expect(abs(r.color.g - 0.18) < 0.01)
        #expect(r.correctedBrightness)
        #expect(r.notes.isEmpty)
    }

    @Test func clippedWhiteStillCorrectsBrightnessFromGreyAndBlack() {
        let card = [LinearRGB(r: 0.02, g: 0.02, b: 0.02), LinearRGB(r: 0.12, g: 0.12, b: 0.12), LinearRGB(r: 1, g: 1, b: 1)]
        let grey = ColorCorrection.correct(card[1], patches: card)!
        #expect(abs(grey.color.g - 0.18) < 0.01)
        #expect(grey.correctedBrightness)
        #expect(grey.notes == [.clipped])
        let black = ColorCorrection.correct(card[0], patches: card)!
        #expect(abs(black.color.g - 0.031) < 0.005)
    }

    @Test func tooDarkBlackStillCorrectsBrightnessFromWhiteAndGrey() {
        let card = [LinearRGB(r: 0.001, g: 0.001, b: 0.001), LinearRGB(r: 0.12, g: 0.12, b: 0.12), LinearRGB(r: 0.6, g: 0.6, b: 0.6)]
        let white = ColorCorrection.correct(card[2], patches: card)!
        #expect(abs(white.color.g - 0.90) < 0.01)
        #expect(white.correctedBrightness)
        #expect(white.notes == [.tooDark])
        let grey = ColorCorrection.correct(card[1], patches: card)!
        #expect(abs(grey.color.g - 0.18) < 0.01)
    }

    @Test func darkUniformRectangleIsNotACard() {
        let dark = LinearRGB(r: 0.004, g: 0.005, b: 0.007)
        #expect(ReferenceCardAnalyzer.patches(in: bands(rgb: dark)) == nil)
    }

    @Test func darkSaturatedBandIsNotNeutral() {
        let red = LinearRGB(r: 0.2, g: 0, b: 0)
        let grid = bandColors([red, LinearRGB(r: 0.12, g: 0.12, b: 0.12), LinearRGB(r: 0.6, g: 0.6, b: 0.6)])
        #expect(ReferenceCardAnalyzer.patches(in: grid) == nil)
    }

    @Test func loneDarkPatchIsNotUsedForWhiteBalance() {
        let dark = LinearRGB(r: 0.03, g: 0.03, b: 0.03)     // above the too-dark level, below the lone floor
        #expect(ColorCorrection.correct(LinearRGB(r: 0.3, g: 0.2, b: 0.1), patches: [dark]) == nil)
        #expect(ColorCorrection.droppedNotes(for: [dark]) == [.tooDark])
    }

    @Test func zeroChannelPatchIsTooDark() {
        let grey = LinearRGB(r: 0.18, g: 0.18, b: 0.18)
        let redOnly = LinearRGB(r: 0.5, g: 0, b: 0)
        let r = ColorCorrection.correct(grey, patches: [grey, redOnly])!
        #expect(r.notes == [.tooDark])
        #expect(!r.correctedBrightness)
    }

    @Test func noUsablePatchIsNil() {
        #expect(ColorCorrection.correct(LinearRGB(r: 0.3, g: 0.2, b: 0.1), patches: [LinearRGB(r: 0.001, g: 0.001, b: 0.001)]) == nil)
    }
}
