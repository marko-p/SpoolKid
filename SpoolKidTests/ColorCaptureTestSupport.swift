//
//  ColorCaptureTestSupport.swift
//  SpoolKidTests
//
//  Purpose: Shared helpers for the color-capture tests: ΔE76 between two hex
//  colors and deterministic noisy pixel generation (seeded LCG, never system
//  randomness) so every run sees the same pixels.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

@testable import SpoolKid

/// CIEDE2000 difference between two hex colors. Unparseable input yields infinity,
/// so a bad hex fails any `< threshold` expectation.
nonisolated func dE(_ a: String, _ b: String) -> Double {
    guard let labA = ColorMatching.lab(from: a), let labB = ColorMatching.lab(from: b) else {
        return .infinity
    }
    return ColorMatching.deltaE2000(labA, labB)
}

/// `count` pixels around `hex`: each sRGB channel is offset by a uniform integer
/// in `-spread...spread` and clamped to 0...255, then converted to linear light.
/// A fresh LCG seeded from `seed` is used per call, so equal arguments give equal pixels.
nonisolated func noisy(_ hex: String, spread: Int, count: Int, seed: UInt64 = 1) -> [LinearRGB] {
    guard let base = ColorMatching.parseHex(hex) else { return [] }
    let channels = [base.r, base.g, base.b].map { Int(($0 * 255).rounded()) }
    var state = seed
    func nextOffset() -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(2 * spread + 1)) - spread
    }
    return (0..<count).map { _ in
        let v = channels.map { min(max($0 + nextOffset(), 0), 255) }
        return LinearRGB(r: ColorMatching.linearized(Double(v[0]) / 255),
                         g: ColorMatching.linearized(Double(v[1]) / 255),
                         b: ColorMatching.linearized(Double(v[2]) / 255))
    }
}
