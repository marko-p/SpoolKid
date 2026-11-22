//
//  ColorFilterSpec.swift
//  SpoolKid
//
//  Purpose: Value types for the Manage Spools color filter — the selected
//  anchor color, tolerance, and harmony mode.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// Harmony modes for the color filter. Raw values are stable identifiers.
nonisolated enum ColorHarmony: String, CaseIterable, Identifiable {
    case single
    case analogous
    case complementary
    case splitComplementary
    case triad
    case square
    case compound
    case shades
    case monochromatic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .single: return "Single"
        case .analogous: return "Analogous"
        case .complementary: return "Complementary"
        case .splitComplementary: return "Split Complementary"
        case .triad: return "Triad"
        case .square: return "Square"
        case .compound: return "Compound"
        case .shades: return "Shades"
        case .monochromatic: return "Monochromatic"
        }
    }

    /// Hue-band modes match by hue window (tolerance read as ± degrees)
    /// instead of ΔE point targets.
    var isHueBand: Bool { self == .shades || self == .monochromatic }

    /// Hue rotations are meaningless for achromatic anchors; the UI disables
    /// these modes when the anchor is grey/white/black.
    var requiresChromaticAnchor: Bool { self != .single && !isHueBand }
}

/// The active color filter: anchor color, tolerance, harmony mode.
nonisolated struct ColorFilterSpec: Hashable {
    var anchorHex: String
    var toleranceDeltaE: Double
    var harmony: ColorHarmony
}
