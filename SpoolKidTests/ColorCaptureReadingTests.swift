//
//  ColorCaptureReadingTests.swift
//  SpoolKidTests
//
//  Purpose: Tests for one color-capture reading: the sampled circle, the optional
//  reference card (rectified, analyzed, and used to correct the sampled color),
//  the saved hex, and the notes that say what was not used.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
import CoreGraphics
@testable import SpoolKid

/// 120×160 scene: the cast background with an optional three-band card.
nonisolated private enum ReadingScene {

    /// Multiplies linear channels by the warm cast (1.2, 1.0, 0.8), clamped to 1.
    static func casted(_ c: LinearRGB) -> LinearRGB {
        LinearRGB(r: min(c.r * 1.2, 1), g: min(c.g * 1.0, 1), b: min(c.b * 0.8, 1))
    }

    static let background = casted(LinearRGB(hex: "D9622B")!)
    /// Three grey bands (0.02, 0.12, 0.60) under the same cast, darkest first.
    static let cardPatches = [0.02, 0.12, 0.60].map { casted(LinearRGB(r: $0, g: $0, b: $0)) }

    /// Normalized rectangles, top-left origin.
    static let cardRect = CGRect(x: 0.05, y: 0.70, width: 0.40, height: 0.10)
    static let verticalCardRect = CGRect(x: 0.70, y: 0.05, width: 0.10, height: 0.40)
    static let orangeRect = CGRect(x: 0.55, y: 0.70, width: 0.40, height: 0.10)

    static let circleCenter = CGPoint(x: 0.5, y: 0.3)
    static let radius = 0.1

    static let scene = grid(card: cardRect, vertical: false, bands: cardPatches)

    static func quad(_ r: CGRect) -> Quad {
        Quad(topLeft: CGPoint(x: r.minX, y: r.minY),
             topRight: CGPoint(x: r.maxX, y: r.minY),
             bottomRight: CGPoint(x: r.maxX, y: r.maxY),
             bottomLeft: CGPoint(x: r.minX, y: r.maxY))
    }

    /// Background everywhere; inside `card` the bands fill the long side, darkest first.
    static func grid(card: CGRect?, vertical: Bool, bands: [LinearRGB]) -> PixelGrid {
        let width = 120, height = 160
        var pixels: [LinearRGB] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let nx = (CGFloat(x) + 0.5) / CGFloat(width)
                let ny = (CGFloat(y) + 0.5) / CGFloat(height)
                var color = background
                if let card, nx >= card.minX, nx < card.maxX, ny >= card.minY, ny < card.maxY {
                    let t = vertical ? (ny - card.minY) / card.height : (nx - card.minX) / card.width
                    color = bands[min(Int(t * CGFloat(bands.count)), bands.count - 1)]
                }
                pixels.append(color)
            }
        }
        return PixelGrid(width: width, height: height, pixels: pixels)
    }
}

struct ColorCaptureReadingTests {

    /// The cast background with the cast removed, as the card correction maps it.
    private static let castRemovedExpectedHex =
        ColorCorrection.correct(ReadingScene.background, patches: ReadingScene.cardPatches)!.color.hex

    private func read(card: Quad?, grid: PixelGrid = ReadingScene.scene) -> ColorCaptureReading? {
        ColorCaptureReading.make(grid: grid, circleCenter: ReadingScene.circleCenter,
                                 radiusFraction: ReadingScene.radius, card: card)
    }

    @Test func noCardSavesRaw() {
        let r = read(card: nil)!
        #expect(r.correctedHex == nil)
        #expect(r.savedHex == r.rawHex)
        #expect(r.rawHex == ReadingScene.background.hex)
        #expect(r.notes == [])
        #expect(!r.usedFallback)
    }

    @Test func cardSavesCorrected() {
        let r = read(card: ReadingScene.quad(ReadingScene.cardRect))!
        #expect(r.correctedHex != nil)
        #expect(r.savedHex == r.correctedHex)
        #expect(dE(r.correctedHex!, Self.castRemovedExpectedHex) < 3)
        #expect(r.notes == [])
    }

    @Test func verticalCardSavesCorrected() {
        let grid = ReadingScene.grid(card: ReadingScene.verticalCardRect, vertical: true,
                                     bands: ReadingScene.cardPatches)
        let r = read(card: ReadingScene.quad(ReadingScene.verticalCardRect), grid: grid)!
        #expect(r.correctedHex != nil)
        #expect(dE(r.correctedHex!, Self.castRemovedExpectedHex) < 3)
        #expect(r.notes == [])
    }

    @Test func outlineOnNonCardIsReported() {
        let r = read(card: ReadingScene.quad(ReadingScene.orangeRect))!
        #expect(r.notes == [.cardNotRecognized])
        #expect(r.correctedHex == nil)
        #expect(r.savedHex == r.rawHex)
    }

    @Test func cardCoveringTheCircleIsNotUsed() {
        // The quad contains the circle centre, so the card might be the filament itself.
        let r = read(card: ReadingScene.quad(CGRect(x: 0.3, y: 0.2, width: 0.4, height: 0.2)))!
        #expect(r.notes == [.cardCoversSample])
        #expect(r.correctedHex == nil)
        #expect(r.savedHex == r.rawHex)
    }

    @Test func quadOverlapGeometry() {
        let q = ReadingScene.quad(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.1))
        // Centre inside.
        #expect(ColorCaptureReading.quad(q, overlapsCircleAt: .init(x: 0.5, y: 0.45), radiusFraction: 0.01, imageAspect: 1.5))
        // Outside, but the radius reaches the box horizontally.
        #expect(ColorCaptureReading.quad(q, overlapsCircleAt: .init(x: 0.7, y: 0.45), radiusFraction: 0.12, imageAspect: 1.5))
        // Outside and clear of it.
        #expect(!ColorCaptureReading.quad(q, overlapsCircleAt: .init(x: 0.9, y: 0.45), radiusFraction: 0.12, imageAspect: 1.5))
        // Vertically: radius 0.1 of width is 0.1/1.5 of height; 0.05 gap is reached, 0.1 is not.
        #expect(ColorCaptureReading.quad(q, overlapsCircleAt: .init(x: 0.5, y: 0.55), radiusFraction: 0.1, imageAspect: 1.5))
        #expect(!ColorCaptureReading.quad(q, overlapsCircleAt: .init(x: 0.5, y: 0.7), radiusFraction: 0.1, imageAspect: 1.5))
    }

    @Test func circleOffImageIsNil() {
        #expect(ColorCaptureReading.make(grid: ReadingScene.scene, circleCenter: .init(x: 5, y: 5),
                                         radiusFraction: 0.1, card: nil) == nil)
    }

    @Test func allClippedCardKeepsRawWithClippedNote() {
        // Every band white: one patch, clipped, so nothing is usable for correction.
        let white = LinearRGB(r: 1, g: 1, b: 1)
        let grid = ReadingScene.grid(card: ReadingScene.cardRect, vertical: false, bands: [white, white, white])
        let r = read(card: ReadingScene.quad(ReadingScene.cardRect), grid: grid)!
        #expect(r.correctedHex == nil)
        #expect(r.savedHex == r.rawHex)
        #expect(r.notes == [.patchClipped])
    }

    @Test func zeroBlackBandIsNotedTooDark() {
        // The black band is zero in every channel: dropped as too dark, correction still runs.
        let black = LinearRGB(r: 0, g: 0, b: 0)
        let grid = ReadingScene.grid(card: ReadingScene.cardRect, vertical: false,
                                     bands: [black, ReadingScene.cardPatches[1], ReadingScene.cardPatches[2]])
        let r = read(card: ReadingScene.quad(ReadingScene.cardRect), grid: grid)!
        #expect(r.correctedHex != nil)
        #expect(r.savedHex == r.correctedHex)
        #expect(r.notes == [.patchTooDark])
    }

    @Test func clippedAndTooDarkNotesFollowFixedOrder() {
        // Black band too dark, white band clipped, middle band usable.
        let black = LinearRGB(r: 0, g: 0, b: 0)
        let white = LinearRGB(r: 1, g: 1, b: 1)
        let grid = ReadingScene.grid(card: ReadingScene.cardRect, vertical: false,
                                     bands: [black, ReadingScene.cardPatches[1], white])
        let r = read(card: ReadingScene.quad(ReadingScene.cardRect), grid: grid)!
        #expect(r.correctedHex != nil)
        #expect(r.notes == [.patchClipped, .patchTooDark])
    }
}
