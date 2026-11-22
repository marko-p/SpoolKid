//
//  ReferenceCard.swift
//  SpoolKid
//
//  Purpose: Reference card for camera color capture. ReferenceCardAnalyzer finds
//  a neutral card in a rectified grid (three graded bands, or one uniform grey
//  patch). ColorCorrection white-balances a sampled color from the card's patches
//  and, when two or more of its black, grey and white patches are usable, also
//  maps its brightness onto nominal reflectances. Pure functions; no UIKit.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

// MARK: - ReferenceCardAnalyzer

nonisolated enum ReferenceCardAnalyzer {

    /// Share of each band, at both ends along the long axis, left out of its statistics.
    private static let bandMarginFraction = 0.15
    /// A band is uniform when the standard deviation of its luminance is at most this fraction of its mean.
    private static let maxBandVariation = 0.10
    /// Bands at or above this mean luminance are judged neutral by relative chroma.
    private static let neutralLuminanceFloor = 0.05
    /// A band at or above `neutralLuminanceFloor` is neutral when its relative chroma is at most this.
    /// Loose enough for a warm or cool cast on a white or grey band.
    private static let maxRelativeChroma = 0.35
    /// A band below `neutralLuminanceFloor` is neutral when its channel spread (max − min, linear)
    /// is at most this. Relative chroma is noise there; a few codes of tint is still a cast.
    private static let maxAbsoluteSpread = 0.02
    /// Darkest-first bands must each step up by at least this factor to be three patches.
    private static let patchStepRatio = 1.5
    /// Bands whose luminances all fall within this factor of each other are one patch.
    private static let sameSpanRatio = 1.15

    /// Patch colors of a neutral reference card in a rectified grid, darkest first.
    /// The card is three equal bands along the longer axis. Each band, with its
    /// margins trimmed, must be uniform and neutral. Bands that step apart in
    /// luminance are three patches; bands that all match are one patch (their mean).
    /// Anything else is not a card and yields nil.
    static func patches(in grid: PixelGrid) -> [LinearRGB]? {
        guard grid.width > 0, grid.height > 0 else { return nil }

        let vertical = grid.height > grid.width
        let longLength = Double(vertical ? grid.height : grid.width)
        let bandLength = longLength / 3

        var bandPixels = [[LinearRGB]](repeating: [], count: 3)
        for (index, pixel) in grid.pixels.enumerated() {
            let along = Double(vertical ? index / grid.width : index % grid.width) + 0.5
            let band = min(Int(along / bandLength), 2)
            let fraction = along / bandLength - Double(band)
            if fraction >= bandMarginFraction && fraction < 1 - bandMarginFraction {
                bandPixels[band].append(pixel)
            }
        }

        var means: [LinearRGB] = []
        for pixels in bandPixels {
            guard let mean = uniformNeutralMean(of: pixels) else { return nil }
            means.append(mean)
        }

        let ordered = means.sorted { $0.luminance < $1.luminance }
        let darkest = ordered[0].luminance
        let middle = ordered[1].luminance
        let brightest = ordered[2].luminance

        // Strict ordering keeps an all-black card (every band at zero) off the three-patch path.
        // A zero-luminance darkest band still steps up: its patch is dropped as too dark by ColorCorrection.
        if middle > darkest, brightest > middle,
           middle >= patchStepRatio * darkest, brightest >= patchStepRatio * middle {
            return ordered
        }
        if brightest <= sameSpanRatio * darkest {
            // A black phone or box lid is not a reference.
            let mean = ColorSampler.mean(means)
            return mean.luminance >= ColorCorrection.minLonePatchLuminance ? [mean] : nil
        }
        return nil
    }

    // MARK: - Private

    /// Mean of a band's pixels when they are uniform and neutral; nil otherwise, or when empty.
    private static func uniformNeutralMean(of pixels: [LinearRGB]) -> LinearRGB? {
        guard !pixels.isEmpty else { return nil }
        let mean = ColorSampler.mean(pixels)
        let meanLuminance = mean.luminance
        let variance = pixels.reduce(0.0) { sum, pixel in
            let deviation = pixel.luminance - meanLuminance
            return sum + deviation * deviation
        } / Double(pixels.count)

        guard variance.squareRoot() <= maxBandVariation * meanLuminance, isNeutral(mean) else { return nil }
        return mean
    }

    private static func isNeutral(_ mean: LinearRGB) -> Bool {
        if mean.luminance >= neutralLuminanceFloor {
            return mean.chroma <= maxRelativeChroma
        }
        return mean.maxChannel - min(mean.r, mean.g, mean.b) <= maxAbsoluteSpread
    }
}

// MARK: - ColorCorrection

nonisolated enum ColorCorrection {

    /// Linear reflectance of the card's patches, from common grey-card specifications:
    /// white near 90 %, 18 % grey, black near 3 %.
    static let nominalWhite = 0.90
    static let nominalGrey = 0.18
    static let nominalBlack = 0.031
    /// A patch darker than this luminance cannot be white-balanced from.
    static let tooDarkLevel = 0.004
    /// A single usable patch must be at least this bright to white-balance from.
    static let minLonePatchLuminance = 0.05

    /// Why a card patch was not used for correction.
    nonisolated enum PatchNote: Equatable, Sendable {
        case clipped
        case tooDark
    }

    /// A corrected color, whether the card's brightness was mapped, and why any patches were dropped.
    nonisolated struct Result: Equatable, Sendable {
        let color: LinearRGB
        let correctedBrightness: Bool
        let notes: [PatchNote]
    }

    /// Corrects `color` using the card `patches`.
    ///
    /// Roles come from the array's shape, which is the analyzer's contract: three
    /// patches are black, grey and white, darkest first (a three-patch input is sorted
    /// by luminance, which leaves the analyzer's order untouched); one patch is a lone
    /// neutral reference. Any other count has no known roles and is used only for white
    /// balance, from the brightest usable patch.
    ///
    /// Clipped patches and patches too dark or with a zero channel are dropped, each
    /// adding a note in input order. A lone usable patch must also reach
    /// `minLonePatchLuminance`, else it is dropped as too dark. White balance comes
    /// from the grey patch, else the white one. With two or more usable role-known
    /// patches each channel is then stretched so two of them land on their nominal
    /// values (white and black, else grey and black, else white and grey), unless the
    /// higher one is not brighter than the lower one in every channel. Nil when no
    /// patch can white-balance.
    static func correct(_ color: LinearRGB, patches: [LinearRGB]) -> Result? {
        let assessment = assess(patches)
        let usable = assessment.usable
        guard !usable.isEmpty else { return nil }

        let grey = usable.first { $0.role == .grey }?.patch
        let white = usable.first { $0.role == .white }?.patch
        let black = usable.first { $0.role == .black }?.patch

        let reference: LinearRGB
        if let grey {
            reference = grey
        } else if let white {
            reference = white
        } else if let other = usable.filter({ $0.role == .lone || $0.role == .unknown })
            .map(\.patch).max(by: { $0.luminance < $1.luminance }) {
            reference = other
        } else {
            return nil
        }
        let gains = whiteBalanceGains(from: reference)
        let balancedColor = balanced(color, gains: gains)

        let pair: (low: LinearRGB, lowNominal: Double, high: LinearRGB, highNominal: Double)?
        if let white, let black {
            pair = (black, nominalBlack, white, nominalWhite)
        } else if let grey, let black {
            pair = (black, nominalBlack, grey, nominalGrey)
        } else if let white, let grey {
            pair = (grey, nominalGrey, white, nominalWhite)
        } else {
            pair = nil
        }

        if let pair {
            let low = balanced(pair.low, gains: gains)
            let high = balanced(pair.high, gains: gains)
            // A channel where the higher patch is not brighter cannot be stretched.
            if high.r > low.r, high.g > low.g, high.b > low.b {
                func map(_ value: Double, _ low: Double, _ high: Double) -> Double {
                    stretch(value, from: low, to: high, lowNominal: pair.lowNominal, highNominal: pair.highNominal)
                }
                return Result(
                    color: LinearRGB(
                        r: map(balancedColor.r, low.r, high.r),
                        g: map(balancedColor.g, low.g, high.g),
                        b: map(balancedColor.b, low.b, high.b)),
                    correctedBrightness: true,
                    notes: assessment.notes)
            }
        }
        return Result(color: clampedToUnit(balancedColor), correctedBrightness: false, notes: assessment.notes)
    }

    /// Why each dropped patch in `patches` is not used for correction, in input order,
    /// by the same rules as `correct`. Used by callers that report dropped patches
    /// when `correct` finds nothing usable.
    static func droppedNotes(for patches: [LinearRGB]) -> [PatchNote] {
        assess(patches).notes
    }

    /// Why `patch` is not used for correction, or nil when it is usable on its own
    /// terms. Clipped is checked first. The lone-patch luminance floor depends on the
    /// other patches and is applied by `correct`.
    static func dropNote(for patch: LinearRGB) -> PatchNote? {
        if patch.maxChannel >= ColorSampler.clipLevel { return .clipped }
        if patch.r > 0, patch.g > 0, patch.b > 0, patch.luminance >= tooDarkLevel { return nil }
        return .tooDark
    }

    // MARK: - Private

    /// Per-channel gains that make `patch` neutral at its own luminance.
    /// Only called with usable patches, whose channels are all positive.
    private static func whiteBalanceGains(from patch: LinearRGB) -> LinearRGB {
        let luminance = patch.luminance
        return LinearRGB(r: luminance / patch.r, g: luminance / patch.g, b: luminance / patch.b)
    }

    private static func balanced(_ color: LinearRGB, gains: LinearRGB) -> LinearRGB {
        LinearRGB(r: color.r * gains.r, g: color.g * gains.g, b: color.b * gains.b)
    }

    /// Maps `value` so that `low` becomes `lowNominal` and `high` becomes `highNominal`, clamped to 0...1.
    private static func stretch(_ value: Double, from low: Double, to high: Double,
                                lowNominal: Double, highNominal: Double) -> Double {
        unit(lowNominal + (value - low) * (highNominal - lowNominal) / (high - low))
    }

    private enum Role { case black, grey, white, lone, unknown }

    /// The usable patches with their roles, and the notes for the dropped ones.
    private static func assess(_ patches: [LinearRGB])
        -> (usable: [(role: Role, patch: LinearRGB)], notes: [PatchNote]) {
        let ordered = patches.count == 3 ? patches.sorted { $0.luminance < $1.luminance } : patches
        let roles: [Role]
        switch ordered.count {
        case 1: roles = [.lone]
        case 3: roles = [.black, .grey, .white]
        default: roles = Array(repeating: .unknown, count: ordered.count)
        }

        var notes: [PatchNote] = []
        var usable: [(role: Role, patch: LinearRGB)] = []
        for (role, patch) in zip(roles, ordered) {
            if let note = dropNote(for: patch) {
                notes.append(note)
            } else {
                usable.append((role, patch))
            }
        }
        if usable.count == 1, usable[0].patch.luminance < minLonePatchLuminance {
            usable = []
            notes.append(.tooDark)
        }
        return (usable, notes)
    }

    private static func clampedToUnit(_ color: LinearRGB) -> LinearRGB {
        LinearRGB(r: unit(color.r), g: unit(color.g), b: unit(color.b))
    }

    /// Clamps to 0...1; NaN becomes 0.
    private static func unit(_ value: Double) -> Double {
        value.isNaN ? 0 : min(max(value, 0), 1)
    }
}
