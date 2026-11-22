//
//  ColorSamplerTests.swift
//  SpoolKidTests
//
//  Purpose: Tests for ColorSampler: clipped highlights, specular glare and dark
//  gaps are excluded, uniform black and white areas keep their pixels, all-clipped
//  input falls back to the plain average, and empty input yields nil.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
@testable import SpoolKid

struct ColorSamplerTests {

    @Test func blackSpoolStaysBlack() {                       // 1000 px of 141414 ± 3
        let s = ColorSampler.sample(noisy("141414", spread: 3, count: 1000))!
        #expect(dE(s.color.hex, "141414") < 2)
        #expect(s.ignoredFraction < 0.05)
        #expect(!s.usedFallback)
    }

    @Test func whiteSpoolStaysWhite() {                       // 1000 px of F0F0F0 ± 3
        let s = ColorSampler.sample(noisy("F0F0F0", spread: 3, count: 1000))!
        #expect(dE(s.color.hex, "F0F0F0") < 2)
        #expect(s.ignoredFraction < 0.05)
    }

    @Test func glareIsIgnored() {                             // 900 px D9622B ± 4 + 100 px FAFAF5 ± 3
        let s = ColorSampler.sample(noisy("D9622B", spread: 4, count: 900) + noisy("FAFAF5", spread: 3, count: 100, seed: 2))!
        #expect(dE(s.color.hex, "D9622B") < 2)
        #expect((0.08...0.15).contains(s.ignoredFraction))
    }

    @Test func darkGapsAreIgnored() {                         // 850 px D9622B ± 4 + 150 px 1E0F08 ± 3
        let s = ColorSampler.sample(noisy("D9622B", spread: 4, count: 850) + noisy("1E0F08", spread: 3, count: 150, seed: 2))!
        #expect(dE(s.color.hex, "D9622B") < 2)
        #expect((0.13...0.20).contains(s.ignoredFraction))
    }

    @Test func neutralGlareIsIgnored() {                      // 900 px F0F0F0 ± 3 + 100 px F8F8F8 ± 1
        let s = ColorSampler.sample(noisy("F0F0F0", spread: 3, count: 900, seed: 1)
                                    + noisy("F8F8F8", spread: 1, count: 100, seed: 2))!
        #expect(dE(s.color.hex, "F0F0F0") < 1)
        #expect((0.08...0.15).contains(s.ignoredFraction))
    }

    @Test func desaturatedGlareInsideLuminanceWindowIsIgnored() {   // 900 px D9622B ± 4 + 100 px 9B8481 ± 2
        let area = LinearRGB(hex: "D9622B")!
        let patch = LinearRGB(hex: "9B8481")!
        // Precondition: the patch is brighter than the area by less than the
        // luminance window allows, and clearly less saturated. Only the chroma
        // rule can drop it.
        #expect((1.0...1.08).contains(patch.luminance / area.luminance))
        #expect(patch.chroma < 0.6 * area.chroma)
        let s = ColorSampler.sample(noisy("D9622B", spread: 4, count: 900)
                                    + noisy("9B8481", spread: 2, count: 100, seed: 2))!
        #expect(dE(s.color.hex, "D9622B") < 2)
        #expect(s.ignoredFraction >= 0.08)
    }

    @Test func allClippedFallsBack() {
        let s = ColorSampler.sample(Array(repeating: LinearRGB(r: 1, g: 1, b: 1), count: 50))!
        #expect(s.usedFallback)
        #expect(s.color.hex == "FFFFFF")
        #expect(s.ignoredFraction == 0)
    }

    @Test func emptyIsNil() {
        #expect(ColorSampler.sample([]) == nil)
    }
}
