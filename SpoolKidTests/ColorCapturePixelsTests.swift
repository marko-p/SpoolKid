//
//  ColorCapturePixelsTests.swift
//  SpoolKidTests
//
//  Purpose: Tests for the color-capture pixel model: sRGB round trips through
//  LinearRGB, circular sampling, perspective rectification, per-pixel averaging
//  and the aspect-fill view ⇄ image mapping.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
import CoreGraphics
@testable import SpoolKid

struct ColorCapturePixelsTests {

    // MARK: - LinearRGB

    @Test func linearRoundTripsHex() {
        for hex in ["000000", "FFFFFF", "D9622B", "141414", "808080"] {
            #expect(LinearRGB(hex: hex)?.hex == hex)
        }
    }

    @Test func linearRejectsInvalidHex() {
        #expect(LinearRGB(hex: "xyz") == nil)
    }

    @Test func encodedInvertsLinearized() {
        for v in stride(from: 0.0, through: 1.0, by: 0.05) {
            #expect(abs(ColorMatching.encoded(ColorMatching.linearized(v)) - v) < 1e-9)
        }
    }

    @Test func luminanceAndChromaOfPrimaries() {
        let red = LinearRGB(r: 1, g: 0, b: 0)
        #expect(abs(red.luminance - 0.2126) < 1e-9)
        #expect(red.maxChannel == 1)
        #expect(red.chroma == 1)
        #expect(LinearRGB(r: 0, g: 0, b: 0).chroma == 0)
        #expect(LinearRGB(r: 0.5, g: 0.5, b: 0.5).chroma == 0)
    }

    // MARK: - PixelGrid sampling

    @Test func circleSamplesOnlyInside() {
        let grid = PixelGrid(width: 10, height: 10, pixels: Array(repeating: LinearRGB(r: 0.5, g: 0.5, b: 0.5), count: 100))
        let inside = grid.pixels(inCircleCenter: CGPoint(x: 0.5, y: 0.5), radiusFraction: 0.2)   // radius 2 px
        #expect((9...16).contains(inside.count))
    }

    @Test func circleClippedAtEdge() {
        let grid = PixelGrid(width: 10, height: 10, pixels: Array(repeating: LinearRGB(r: 0.5, g: 0.5, b: 0.5), count: 100))
        let corner = grid.pixels(inCircleCenter: CGPoint(x: 0, y: 0), radiusFraction: 0.2)
        let centered = grid.pixels(inCircleCenter: CGPoint(x: 0.5, y: 0.5), radiusFraction: 0.2)
        #expect(!corner.isEmpty && corner.count < centered.count)
        #expect(grid.pixels(inCircleCenter: CGPoint(x: 3, y: 3), radiusFraction: 0.2).isEmpty)
    }

    @Test func averageIsPerPixelMean() {
        let a = PixelGrid(width: 1, height: 1, pixels: [LinearRGB(r: 0.2, g: 0.4, b: 0.6)])
        let b = PixelGrid(width: 1, height: 1, pixels: [LinearRGB(r: 0.4, g: 0.6, b: 0.8)])
        let mean = PixelGrid.average([a, b])!.pixels[0]
        #expect(abs(mean.r - 0.3) < 1e-9 && abs(mean.g - 0.5) < 1e-9 && abs(mean.b - 0.7) < 1e-9)
        #expect(PixelGrid.average([]) == nil)
    }

    @Test func averageRejectsMismatchedSizes() {
        let a = PixelGrid(width: 1, height: 1, pixels: [LinearRGB(r: 0, g: 0, b: 0)])
        let b = PixelGrid(width: 2, height: 1, pixels: [LinearRGB(r: 0, g: 0, b: 0), LinearRGB(r: 0, g: 0, b: 0)])
        #expect(PixelGrid.average([a, b]) == nil)
    }

    @Test func rectifiedCropsTheQuad() {
        // 4×4 grid: left half black, right half white; quad = right half.
        var px = [LinearRGB]()
        for _ in 0..<4 { px += [.init(r: 0, g: 0, b: 0), .init(r: 0, g: 0, b: 0), .init(r: 1, g: 1, b: 1), .init(r: 1, g: 1, b: 1)] }
        let grid = PixelGrid(width: 4, height: 4, pixels: px)
        let quad = Quad(topLeft: .init(x: 0.5, y: 0), topRight: .init(x: 1, y: 0), bottomRight: .init(x: 1, y: 1), bottomLeft: .init(x: 0.5, y: 1))
        #expect(grid.rectified(quad, width: 2, height: 2).pixels.allSatisfy { $0.r == 1 })
    }

    // MARK: - Quad

    @Test func translatedMovesEveryCorner() {
        let quad = Quad(topLeft: .init(x: 0, y: 0), topRight: .init(x: 1, y: 0), bottomRight: .init(x: 1, y: 1), bottomLeft: .init(x: 0, y: 1))
        let moved = quad.translated(by: CGVector(dx: 0.5, dy: -0.25))
        #expect(moved == Quad(topLeft: .init(x: 0.5, y: -0.25), topRight: .init(x: 1.5, y: -0.25),
                              bottomRight: .init(x: 1.5, y: 0.75), bottomLeft: .init(x: 0.5, y: 0.75)))
    }

    // MARK: - AspectFillMapping

    @Test func aspectFillCenterMapsToCenter() {
        let m = AspectFillMapping(viewSize: CGSize(width: 390, height: 844), imageSize: CGSize(width: 720, height: 1280))
        let p = m.imagePoint(fromView: CGPoint(x: 195, y: 422))
        #expect(abs(p.x - 0.5) < 1e-6 && abs(p.y - 0.5) < 1e-6)
    }

    @Test func aspectFillCropsSides() {
        // scale = max(390/720, 844/1280) = 0.659375; shown width 474.75; x offset −42.375
        let m = AspectFillMapping(viewSize: CGSize(width: 390, height: 844), imageSize: CGSize(width: 720, height: 1280))
        let p = m.imagePoint(fromView: .zero)
        #expect(abs(p.x - 42.375 / 474.75) < 1e-6 && abs(p.y) < 1e-6)
        let back = m.viewPoint(fromImage: p)
        #expect(abs(back.x) < 1e-6 && abs(back.y) < 1e-6)
        #expect(abs(m.imageWidthFraction(fromViewLength: 47.475) - 0.1) < 1e-6)
    }

    // MARK: - Non-finite and degenerate input

    @Test func hexTreatsNonFiniteChannelsAsZero() {
        #expect(LinearRGB(r: .nan, g: .infinity, b: 0).hex == "000000")
    }

    @Test func circleWithNonFiniteOrHugeCenterSamplesNothing() {
        let grid = PixelGrid(width: 10, height: 10, pixels: Array(repeating: LinearRGB(r: 0.5, g: 0.5, b: 0.5), count: 100))
        #expect(grid.pixels(inCircleCenter: CGPoint(x: CGFloat.nan, y: 0.5), radiusFraction: 0.2).isEmpty)
        #expect(grid.pixels(inCircleCenter: CGPoint(x: 0.5, y: CGFloat.infinity), radiusFraction: 0.2).isEmpty)
        #expect(grid.pixels(inCircleCenter: CGPoint(x: 0.5, y: 0.5), radiusFraction: .nan).isEmpty)
        #expect(grid.pixels(inCircleCenter: CGPoint(x: 1e300, y: 0.5), radiusFraction: 0.2).isEmpty)
    }

    @Test func rectifiedSurvivesNonFiniteQuad() {
        let grid = PixelGrid(width: 4, height: 4, pixels: Array(repeating: LinearRGB(r: 1, g: 1, b: 1), count: 16))
        let quad = Quad(topLeft: .init(x: CGFloat.nan, y: 0), topRight: .init(x: 1, y: 0),
                        bottomRight: .init(x: 1, y: CGFloat.infinity), bottomLeft: .init(x: 0, y: 1))
        #expect(grid.rectified(quad, width: 2, height: 2).pixels.count == 4)
    }

    @Test func degenerateAspectFillReturnsZeroNotNaN() {
        let zeroView = AspectFillMapping(viewSize: .zero, imageSize: CGSize(width: 720, height: 1280))
        #expect(zeroView.imagePoint(fromView: CGPoint(x: 10, y: 10)) == .zero)
        #expect(zeroView.viewPoint(fromImage: CGPoint(x: 0.5, y: 0.5)) == .zero)
        #expect(zeroView.imageWidthFraction(fromViewLength: 10) == 0)

        let emptyImage = AspectFillMapping(viewSize: CGSize(width: 390, height: 844), imageSize: .zero)
        #expect(emptyImage.imagePoint(fromView: .zero) == .zero)
    }
}
