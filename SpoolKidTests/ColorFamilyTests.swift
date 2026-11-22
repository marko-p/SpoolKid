//
//  ColorFamilyTests.swift
//  SpoolKidTests
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
@testable import SpoolKid

@Suite struct ColorFamilyTests {
    @Test func commonFilamentColorsLandInTheirFamily() {
        let cases: [(String, ColorFamily)] = [
            ("FF0000", .red), ("C62828", .red), ("FF7F00", .orange), ("F7923A", .orange),
            ("5D4037", .brown), ("FFEB3B", .yellow), ("F5A800", .yellow), ("4CAF50", .green), ("00BCD4", .teal),
            ("2196F3", .blue), ("0D47A1", .blue), ("9C27B0", .purple), ("F48FB1", .pink),
            ("FFFFFF", .white), ("F5F5F5", .white), ("808080", .grey), ("000000", .black),
            ("1A1A1A", .black),
        ]
        for (hex, family) in cases {
            #expect(ColorFamily.of(hex: hex) == family, "\(hex)")
        }
    }

    @Test func aFilamentWithTwoColorsIsMulticolor() {
        let colors = FilamentColors(colorHex: nil, multiColorHexes: "FF0000,0000FF", multiColorDirection: nil)
        #expect(ColorFamily.of(colors) == .multicolor)
    }

    @Test func aFilamentWithNoColorHasNoFamily() {
        let colors = FilamentColors(colorHex: nil, multiColorHexes: nil, multiColorDirection: nil)
        #expect(ColorFamily.of(colors) == nil)
        #expect(ColorFamily.of(hex: "nope") == nil)
    }
}
