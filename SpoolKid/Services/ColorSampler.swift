//
//  ColorSampler.swift
//  SpoolKid
//
//  Purpose: Reduces the pixels of a sample area to one filament color. Drops
//  clipped highlights, specular glare and dark gaps (shadows, the spool's core
//  showing through), then averages what is left in linear light. Pure functions;
//  no UIKit.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

// MARK: - ColorSample

/// The reduced color of a sample area.
/// `ignoredFraction` is the share of input pixels dropped (0 on fallback).
/// `usedFallback` is true when every pixel was dropped and the plain average of
/// all input pixels was used instead.
nonisolated struct ColorSample: Equatable, Sendable {
    let color: LinearRGB
    let ignoredFraction: Double
    let usedFallback: Bool
}

// MARK: - ColorSampler

nonisolated enum ColorSampler {

    /// A pixel with any linear channel at or above this level is clipped (blown highlight).
    static let clipLevel = 0.98

    /// Luminance window half-width, in units of the robust spread.
    private static let outlierSigmas = 3.0
    /// Spread floor as a fraction of the median luminance. Kept small so the MAD
    /// of the area's own luminance sets the window; the floor only guards areas
    /// whose MAD is near zero.
    private static let relativeSpreadFloor = 0.01
    /// Spread floor in linear luminance. Keeps a near-black or uniform area whole.
    private static let absoluteSpreadFloor = 0.002
    /// A bright pixel is glare when its chroma is below this fraction of the median chroma.
    private static let glareChromaFraction = 0.6
    /// Glare is judged only when the area's median chroma reaches this level. Below
    /// it, chroma is dominated by sensor noise (noisy dark neutrals sit near 0.2).
    private static let glareMinimumMedianChroma = 0.25
    /// Scales the median absolute deviation to a standard-deviation estimate.
    private static let madToSigma = 1.4826

    /// Reduces `pixels` to one color. Nil only for empty input.
    static func sample(_ pixels: [LinearRGB]) -> ColorSample? {
        guard !pixels.isEmpty else { return nil }

        let unclipped = pixels.filter { $0.maxChannel < clipLevel }
        let kept = survivors(of: unclipped)

        guard !kept.isEmpty else {
            return ColorSample(color: mean(pixels), ignoredFraction: 0, usedFallback: true)
        }
        let dropped = pixels.count - kept.count
        return ColorSample(color: mean(kept),
                           ignoredFraction: Double(dropped) / Double(pixels.count),
                           usedFallback: false)
    }

    // MARK: - Private

    /// Unclipped pixels whose luminance lies inside the robust window around the
    /// median and which are not glare (bright and markedly less saturated than typical).
    private static func survivors(of pixels: [LinearRGB]) -> [LinearRGB] {
        guard !pixels.isEmpty else { return [] }

        let luminances = pixels.map(\.luminance)
        let center = median(luminances)
        let mad = median(luminances.map { abs($0 - center) })
        let spread = max(madToSigma * mad,
                         relativeSpreadFloor * center,
                         absoluteSpreadFloor)
        let medianChroma = median(pixels.map(\.chroma))

        return pixels.filter { pixel in
            let withinWindow = abs(pixel.luminance - center) <= outlierSigmas * spread
            let isGlare = medianChroma >= glareMinimumMedianChroma
                && pixel.luminance > center
                && pixel.chroma < glareChromaFraction * medianChroma
            return withinWindow && !isGlare
        }
    }

    /// Median of a non-empty array.
    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }

    /// Per-channel mean in linear light of a non-empty array.
    static func mean(_ pixels: [LinearRGB]) -> LinearRGB {
        let count = Double(pixels.count)
        return LinearRGB(
            r: pixels.reduce(0) { $0 + $1.r } / count,
            g: pixels.reduce(0) { $0 + $1.g } / count,
            b: pixels.reduce(0) { $0 + $1.b } / count)
    }
}
