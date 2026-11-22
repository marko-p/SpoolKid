//
//  ColorCaptureReading.swift
//  SpoolKid
//
//  Purpose: One color-capture reading from a frozen image. Samples the circle,
//  and when a reference card is outlined, rectifies it, reads its patches and
//  corrects the sampled color with them. Reports what was not used as notes.
//  Pure functions; no UIKit.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import CoreGraphics

// MARK: - ColorCaptureReading

nonisolated struct ColorCaptureReading: Equatable, Sendable {

    /// What the card or its patches did not contribute, in display order.
    nonisolated enum Note: Equatable, Sendable {
        /// The outlined card covers the sample circle, so it was not used.
        case cardCoversSample
        /// The outlined quad does not hold a neutral reference card.
        case cardNotRecognized
        /// A card patch was clipped (blown highlight) and was not used.
        case patchClipped
        /// A card patch was too dark, or had a zero channel, and was not used.
        case patchTooDark
    }

    /// The sampled color, uppercase `RRGGBB`.
    let rawHex: String
    /// The card-corrected color; nil when no card was used.
    let correctedHex: String?
    /// Share of the sampled pixels dropped by `ColorSampler`.
    let ignoredFraction: Double
    /// True when every sampled pixel was dropped and the plain average was used.
    let usedFallback: Bool
    /// De-duplicated, in the order of `Note`.
    let notes: [Note]

    /// The hex to save: the corrected color when a card was used, else the raw one.
    var savedHex: String { correctedHex ?? rawHex }

    /// Reads the circle at `circleCenter` (normalized, top-left origin) with
    /// `radiusFraction` of the image width as radius. `card` is the outlined card
    /// quad, or nil for no card. Nil only when the circle covers no pixel.
    static func make(grid: PixelGrid, circleCenter: CGPoint, radiusFraction: Double, card: Quad?) -> ColorCaptureReading? {
        let pixels = grid.pixels(inCircleCenter: circleCenter, radiusFraction: radiusFraction)
        guard let sample = ColorSampler.sample(pixels) else { return nil }
        let rawHex = sample.color.hex

        func reading(corrected: String?, notes: [Note]) -> ColorCaptureReading {
            ColorCaptureReading(rawHex: rawHex, correctedHex: corrected,
                                ignoredFraction: sample.ignoredFraction,
                                usedFallback: sample.usedFallback, notes: notes)
        }

        guard let card else { return reading(corrected: nil, notes: []) }

        // The outline must not be the filament itself.
        if quad(card, overlapsCircleAt: circleCenter, radiusFraction: radiusFraction,
                imageAspect: Double(grid.height) / Double(grid.width)) {
            return reading(corrected: nil, notes: [.cardCoversSample])
        }

        guard let patches = cardPatches(in: grid, quad: card) else {
            return reading(corrected: nil, notes: [.cardNotRecognized])
        }

        let result = ColorCorrection.correct(sample.color, patches: patches)
        let patchNotes = result?.notes ?? ColorCorrection.droppedNotes(for: patches)
        return reading(corrected: result?.color.hex, notes: readingNotes(for: patchNotes))
    }

    /// Patches of the card outlined by `quad` in `grid`, darkest first; nil when the
    /// outline does not hold a neutral reference card. Shared by `make` and by live
    /// card detection, so both judge an outline the same way.
    static func cardPatches(in grid: PixelGrid, quad: Quad) -> [LinearRGB]? {
        let size = rectifiedSize(for: quad, gridWidth: grid.width, gridHeight: grid.height)
        let rectified = grid.rectified(quad, width: size.width, height: size.height)
        return ReferenceCardAnalyzer.patches(in: rectified)
    }

    /// True when the circle centre is inside `quad`, or the circle comes within its
    /// radius of the quad's bounding box. `radiusFraction` is a fraction of the image
    /// width; `imageAspect` is height/width, which converts it for y.
    static func quad(_ quad: Quad, overlapsCircleAt center: CGPoint, radiusFraction: Double, imageAspect: Double) -> Bool {
        let corners = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft]
        // Inside test by sign of cross products; handles either winding.
        var positive = false, negative = false
        for index in corners.indices {
            let a = corners[index], b = corners[(index + 1) % corners.count]
            let cross = (b.x - a.x) * (center.y - a.y) - (b.y - a.y) * (center.x - a.x)
            if cross > 0 { positive = true }
            if cross < 0 { negative = true }
        }
        if (positive || negative) && !(positive && negative) { return true }

        let xs = corners.map(\.x), ys = corners.map(\.y)
        let radiusX = radiusFraction
        let radiusY = imageAspect > 0 ? radiusFraction / imageAspect : radiusFraction
        let nearestX = min(max(Double(center.x), Double(xs.min() ?? 0)), Double(xs.max() ?? 0))
        let nearestY = min(max(Double(center.y), Double(ys.min() ?? 0)), Double(ys.max() ?? 0))
        let dx = (Double(center.x) - nearestX) / radiusX
        let dy = (Double(center.y) - nearestY) / radiusY
        return dx * dx + dy * dy <= 1
    }

    // MARK: - Private

    /// Rectified card size: 20×60 when the left and right edges are longer than the
    /// top and bottom edges, else 60×20. Edge lengths are measured in pixels, so a
    /// non-square image does not skew the comparison.
    private static func rectifiedSize(for card: Quad, gridWidth: Int, gridHeight: Int) -> (width: Int, height: Int) {
        func length(_ a: CGPoint, _ b: CGPoint) -> Double {
            let dx = (Double(b.x) - Double(a.x)) * Double(gridWidth)
            let dy = (Double(b.y) - Double(a.y)) * Double(gridHeight)
            return (dx * dx + dy * dy).squareRoot()
        }
        let topAndBottom = (length(card.topLeft, card.topRight) + length(card.bottomLeft, card.bottomRight)) / 2
        let leftAndRight = (length(card.topLeft, card.bottomLeft) + length(card.topRight, card.bottomRight)) / 2
        return leftAndRight > topAndBottom ? (20, 60) : (60, 20)
    }

    /// Maps patch notes to reading notes: one entry per kind, in `Note` order.
    private static func readingNotes(for patchNotes: [ColorCorrection.PatchNote]) -> [Note] {
        var notes: [Note] = []
        if patchNotes.contains(.clipped) { notes.append(.patchClipped) }
        if patchNotes.contains(.tooDark) { notes.append(.patchTooDark) }
        return notes
    }
}
