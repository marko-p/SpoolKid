//
//  ColorFamily.swift
//  SpoolKid
//
//  Purpose: The hue family a filament's color belongs to, for the Library's
//  Color grouping. A fixed spectrum order, so the groups read like a color
//  wheel rather than in whatever order their first spool appeared.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// `nonisolated`: the target defaults to MainActor; this pure value type must
/// stay usable from nonisolated contexts.
nonisolated enum ColorFamily: Int, CaseIterable, Sendable {
    case red, orange, brown, yellow, green, teal, blue, purple, pink, white, grey, black, multicolor

    var label: String {
        switch self {
        case .red: "Red"
        case .orange: "Orange"
        case .brown: "Brown"
        case .yellow: "Yellow"
        case .green: "Green"
        case .teal: "Teal"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .white: "White"
        case .grey: "Grey"
        case .black: "Black"
        case .multicolor: "Multicolor"
        }
    }

    /// The color a header shows for this family.
    var swatchHexes: [String] {
        switch self {
        case .red: ["E53935"]
        case .orange: ["FB8C00"]
        case .brown: ["795548"]
        case .yellow: ["FDD835"]
        case .green: ["43A047"]
        case .teal: ["00ACC1"]
        case .blue: ["1E88E5"]
        case .purple: ["8E24AA"]
        case .pink: ["EC407A"]
        case .white: ["FFFFFF"]
        case .grey: ["9E9E9E"]
        case .black: ["000000"]
        case .multicolor: ["E53935", "FDD835", "1E88E5"]
        }
    }

    /// The family of one color, or nil for a hex that does not parse. Colors
    /// below the color filter's achromatic threshold are white, grey or black
    /// by lightness; dark oranges are brown.
    static func of(hex: String) -> ColorFamily? {
        guard let hsl = ColorMatching.hsl(from: hex) else { return nil }
        if hsl.s < ColorFilterService.achromaticSaturationThreshold || hsl.l > 0.92 || hsl.l < 0.08 {
            if hsl.l > 0.85 { return .white }
            if hsl.l < 0.15 { return .black }
            return .grey
        }
        switch hsl.h {
        case 10..<40: return hsl.l < 0.35 ? .brown : .orange
        case 40..<70: return .yellow
        case 70..<165: return .green
        case 165..<195: return .teal
        case 195..<255: return .blue
        case 255..<300: return .purple
        case 300..<345: return .pink
        default: return .red
        }
    }

    /// The family of a filament: Multicolor for two or more colors, else its
    /// one color's family; nil when it states no color.
    static func of(_ colors: FilamentColors) -> ColorFamily? {
        let hexes = colors.hexes.filter { !$0.isEmpty }
        if hexes.count >= 2 { return .multicolor }
        return hexes.first.flatMap { of(hex: $0) }
    }
}
