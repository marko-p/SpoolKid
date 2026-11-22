//
//  ColorMatching.swift
//  SpoolKid
//
//  Purpose: Unified hex parsing and perceptual color similarity (CIELAB ΔE76).
//  Single source of truth for color matching across FilamentMatchService and
//  ScanResolutionService. Replaces prior RGB Euclidean distance and duplicate
//  CIELAB implementations.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum ColorMatching {

    // MARK: - Normalize

    /// Returns a canonical `RRGGBB` string (no `#`, uppercase) or nil for
    /// invalid / nil input. Accepts optional `#` prefix and 3-char shorthand.
    static func normalize(_ hex: String?) -> String? {
        guard var s = hex?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, s.allSatisfy({ $0.isHexDigit }) else { return nil }
        return s
    }

    // MARK: - Hex parsing

    /// Parses a hex color string to normalized RGB components (0...1).
    /// Accepts optional `#` prefix, 3-char (expanded) and 6-char formats.
    /// Returns nil for invalid input.
    static func parseHex(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))

        let expanded: String
        if cleaned.count == 3 {
            expanded = cleaned.map { "\($0)\($0)" }.joined()
        } else {
            expanded = cleaned
        }

        guard expanded.count == 6, let value = UInt32(expanded, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (r, g, b)
    }

    // MARK: - CIELAB conversion

    /// Converts a hex color string to CIELAB (L*, a*, b*).
    /// Returns nil if the hex cannot be parsed.
    static func lab(from hex: String) -> (l: Double, a: Double, b: Double)? {
        guard let rgb = parseHex(hex) else { return nil }

        let r = linearized(rgb.r)
        let g = linearized(rgb.g)
        let b = linearized(rgb.b)

        let x = r * 0.4124564 + g * 0.3575761 + b * 0.1804375
        let y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750
        let z = r * 0.0193339 + g * 0.1191920 + b * 0.9503041

        let xr = x / 0.95047
        let yr = y / 1.00000
        let zr = z / 1.08883

        let fx = labF(xr)
        let fy = labF(yr)
        let fz = labF(zr)

        let l = max(0.0, 116.0 * fy - 16.0)
        let a = 500.0 * (fx - fy)
        let bVal = 200.0 * (fy - fz)
        return (l, a, bVal)
    }

    /// CIELAB back to a canonical `RRGGBB`; the inverse of `lab(from:)`,
    /// clamping what sRGB can't show.
    static func hex(lab: (l: Double, a: Double, b: Double)) -> String {
        let epsilon = 216.0 / 24389.0
        let kappa = 24389.0 / 27.0
        let fy = (lab.l + 16) / 116
        let fx = fy + lab.a / 500
        let fz = fy - lab.b / 200
        func inverse(_ f: Double) -> Double { f * f * f > epsilon ? f * f * f : (116 * f - 16) / kappa }
        let x = inverse(fx) * 0.95047
        let y = (lab.l > kappa * epsilon ? fy * fy * fy : lab.l / kappa)
        let z = inverse(fz) * 1.08883
        let r = x * 3.2404542 - y * 1.5371385 - z * 0.4985314
        let g = -x * 0.9692660 + y * 1.8760108 + z * 0.0415560
        let b = x * 0.0556434 - y * 0.2040259 + z * 1.0572252
        func byte(_ linear: Double) -> Int { Int((encoded(linear) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    // MARK: - Delta E 2000

    /// CIEDE2000, the one colour distance in the app. Formula and test vectors
    /// from Sharma, Wu and Dalal (2005).
    static func deltaE2000(_ lhs: (l: Double, a: Double, b: Double), _ rhs: (l: Double, a: Double, b: Double)) -> Double {
        let toRadians = Double.pi / 180
        let meanC = (hypot(lhs.a, lhs.b) + hypot(rhs.a, rhs.b)) / 2
        let meanC7 = pow(meanC, 7)
        let g = 0.5 * (1 - sqrt(meanC7 / (meanC7 + pow(25, 7))))
        let a1 = (1 + g) * lhs.a
        let a2 = (1 + g) * rhs.a
        let c1 = hypot(a1, lhs.b)
        let c2 = hypot(a2, rhs.b)

        func hue(_ a: Double, _ b: Double) -> Double {
            if a == 0, b == 0 { return 0 }
            let degrees = atan2(b, a) / toRadians
            return degrees < 0 ? degrees + 360 : degrees
        }
        let h1 = hue(a1, lhs.b)
        let h2 = hue(a2, rhs.b)
        let hasHue = c1 * c2 != 0

        var dh = h2 - h1
        if !hasHue { dh = 0 } else if dh > 180 { dh -= 360 } else if dh < -180 { dh += 360 }
        let dL = rhs.l - lhs.l
        let dC = c2 - c1
        let dH = 2 * sqrt(c1 * c2) * sin(dh / 2 * toRadians)

        let meanL = (lhs.l + rhs.l) / 2
        let meanCp = (c1 + c2) / 2
        var meanH = h1 + h2
        if hasHue {
            if abs(h1 - h2) <= 180 {
                meanH /= 2
            } else if meanH < 360 {
                meanH = (meanH + 360) / 2
            } else {
                meanH = (meanH - 360) / 2
            }
        }

        let t1 = 0.17 * cos((meanH - 30) * toRadians)
        let t2 = 0.24 * cos(2 * meanH * toRadians)
        let t3 = 0.32 * cos((3 * meanH + 6) * toRadians)
        let t4 = 0.20 * cos((4 * meanH - 63) * toRadians)
        let t = 1 - t1 + t2 + t3 - t4
        let dTheta = 30 * exp(-pow((meanH - 275) / 25, 2))
        let meanCp7 = pow(meanCp, 7)
        let rc = 2 * sqrt(meanCp7 / (meanCp7 + pow(25, 7)))
        let lOffset = pow(meanL - 50, 2)
        let sl = 1 + 0.015 * lOffset / sqrt(20 + lOffset)
        let sc = 1 + 0.045 * meanCp
        let sh = 1 + 0.015 * meanCp * t
        let rt = -sin(2 * dTheta * toRadians) * rc

        let termL = dL / sl
        let termC = dC / sc
        let termH = dH / sh
        return sqrt(termL * termL + termC * termC + termH * termH + rt * termC * termH)
    }

    // MARK: - Similarity

    /// The ΔE2000 at which two colors count as nothing alike. CIEDE2000 packs
    /// large differences together (pure red to pure blue is about 52, where
    /// ΔE76 said 176), so a cap of 100 scored those half alike.
    static let unrelatedDeltaE = 50.0

    /// Returns a 0...1 similarity score based on perceptual color difference.
    /// 1.0 = identical, 0.0 = nothing alike (ΔE ≥ `unrelatedDeltaE`).
    /// Returns 0 if either hex fails to parse.
    static func similarity01(hexA: String, hexB: String?) -> Double {
        guard let labA = lab(from: hexA),
              let labB = lab(from: hexB ?? "") else {
            return 0
        }
        let deltaE = deltaE2000(labA, labB)
        return max(0.0, 1.0 - min(deltaE, unrelatedDeltaE) / unrelatedDeltaE)
    }

    // MARK: - HSL conversion

    /// Converts a hex color to HSL. Hue in degrees 0..<360 (0 when achromatic),
    /// saturation and lightness 0...1. Nil for invalid hex.
    static func hsl(from hex: String) -> (h: Double, s: Double, l: Double)? {
        guard let rgb = parseHex(hex) else { return nil }
        let maxC = max(rgb.r, rgb.g, rgb.b)
        let minC = min(rgb.r, rgb.g, rgb.b)
        let l = (maxC + minC) / 2
        let delta = maxC - minC
        guard delta > 0.0001 else { return (0, 0, l) }
        let s = delta / (1 - abs(2 * l - 1))
        var h: Double
        if maxC == rgb.r {
            h = ((rgb.g - rgb.b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxC == rgb.g {
            h = (rgb.b - rgb.r) / delta + 2
        } else {
            h = (rgb.r - rgb.g) / delta + 4
        }
        h *= 60
        if h < 0 { h += 360 }
        return (h, min(max(s, 0), 1), l)
    }

    /// Converts HSL (hue in degrees, wrapped mod 360; s/l 0...1) to a canonical
    /// `RRGGBB` hex string.
    static func hex(h: Double, s: Double, l: Double) -> String {
        let hue = ((h.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r1, g1, b1): (Double, Double, Double)
        switch hue {
        case ..<60: (r1, g1, b1) = (c, x, 0)
        case ..<120: (r1, g1, b1) = (x, c, 0)
        case ..<180: (r1, g1, b1) = (0, c, x)
        case ..<240: (r1, g1, b1) = (0, x, c)
        case ..<300: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        func byte(_ v: Double) -> Int { Int((min(max(v + m, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(r1), byte(g1), byte(b1))
    }

    // MARK: - sRGB transfer

    /// sRGB channel (0...1) to linear light.
    static func linearized(_ channel: Double) -> Double {
        if channel <= 0.04045 {
            return channel / 12.92
        }
        return pow((channel + 0.055) / 1.055, 2.4)
    }

    /// Linear light (clamped to 0...1) back to an sRGB channel; inverse of `linearized`.
    static func encoded(_ linear: Double) -> Double {
        let v = min(max(linear, 0), 1)
        if v <= 0.0031308 {
            return v * 12.92
        }
        return 1.055 * pow(v, 1.0 / 2.4) - 0.055
    }

    // MARK: - Private helpers

    private static func labF(_ t: Double) -> Double {
        let epsilon = 216.0 / 24389.0
        let kappa = 24389.0 / 27.0
        if t > epsilon {
            return pow(t, 1.0 / 3.0)
        }
        return (kappa * t + 16.0) / 116.0
    }
}
