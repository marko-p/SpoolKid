//
//  ColorFilterService.swift
//  SpoolKid
//
//  Purpose: Pure logic for the Manage Spools color filter — harmony target
//  derivation, spool matching, role grouping, availability islands, and
//  spectrum-map position math. Color-space conversion and ΔE live in
//  ColorMatching (single source of truth); this service only composes them.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import CoreGraphics

nonisolated enum ColorFilterService {

    // MARK: - Tunables (starting values per spec; change here only)

    static let toleranceRange: ClosedRange<Double> = 5...35
    static let defaultTolerance: Double = 18
    /// HSL saturation below which a color counts as grey/white/black.
    static let achromaticSaturationThreshold = 0.10
    static let shadesLightnessHeadroom = 0.05
    static let lightnessBucketWidth = 0.08
    static let islandGrowthPerSpool: CGFloat = 3
    static let islandSnapRadius: CGFloat = 16
    static let islandBaseDiameterBounds: ClosedRange<Double> = 8...20

    // MARK: - Canonical map space (WYSIWYG matching)

    /// Height of the canonical unit-width map. Rendering locks the on-screen
    /// map to this 2:1 aspect so drawn regions equal matched regions exactly.
    static let mapAspectHeight = 0.5

    /// Normalized map position of a chromatic color: x = hue/360 (wrapping
    /// unit width), y = (1 − lightness) × mapAspectHeight. Nil for
    /// achromatics — they live on the strip.
    static func unitPoint(forHex hex: String) -> CGPoint? {
        guard let hsl = ColorMatching.hsl(from: hex), hsl.s >= achromaticSaturationThreshold else { return nil }
        return CGPoint(x: hsl.h / 360, y: (1 - hsl.l) * mapAspectHeight)
    }

    /// Normalized radius shared by every tolerance circle (anchor + targets).
    static func unitRadius(tolerance: Double) -> Double { tolerance / 100 }

    /// Hue-wrapped Euclidean distance between two unit-space points.
    static func unitDistance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dxRaw = abs(Double(a.x - b.x))
        let dx = min(dxRaw, 1 - dxRaw)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - Harmony targets

    struct HarmonyTarget: Hashable {
        let role: String
        let hex: String
    }

    /// ΔE point targets for the spec's harmony, anchor first. Hue-band modes
    /// (shades/monochromatic) return only the anchor — they match by predicate;
    /// the single entry exists so the UI can draw the anchor circle.
    static func targets(for spec: ColorFilterSpec) -> [HarmonyTarget] {
        guard let anchorHex = ColorMatching.normalize(spec.anchorHex) else { return [] }
        let anchorRole = spec.harmony == .single ? "Matches" : "Anchor"
        let anchor = HarmonyTarget(role: anchorRole, hex: anchorHex)
        guard let hsl = ColorMatching.hsl(from: anchorHex) else { return [anchor] }
        func rotated(_ role: String, _ offset: Double) -> HarmonyTarget {
            HarmonyTarget(role: role, hex: ColorMatching.hex(h: hsl.h + offset, s: hsl.s, l: hsl.l))
        }
        switch spec.harmony {
        case .single, .shades, .monochromatic:
            return [anchor]
        case .analogous:
            return [anchor, rotated("−30°", -30), rotated("+30°", 30)]
        case .complementary:
            return [anchor, rotated("Complement", 180)]
        case .splitComplementary:
            return [anchor, rotated("Split −", 150), rotated("Split +", 210)]
        case .triad:
            return [anchor, rotated("Triad 1", 120), rotated("Triad 2", 240)]
        case .square:
            return [anchor, rotated("+90°", 90), rotated("Complement", 180), rotated("+270°", 270)]
        case .compound:
            return [anchor, rotated("+30°", 30), rotated("Complement", 180), rotated("+210°", 210)]
        }
    }

    /// True when the hex parses and its saturation is below the achromatic
    /// threshold. Invalid hex is not achromatic (it is nothing).
    static func isAchromatic(_ hex: String) -> Bool {
        guard let hsl = ColorMatching.hsl(from: hex) else { return false }
        return hsl.s < achromaticSaturationThreshold
    }

    /// Circular hue distance in degrees (0...180).
    static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    // MARK: - Swatches

    /// All valid swatches of a spool: filament color_hex + each entry of the
    /// comma-separated multi_color_hexes, normalized, de-duplicated in order.
    static func swatches(of spool: Spool) -> [String] {
        var hexes: [String] = []
        if let main = ColorMatching.normalize(spool.filament.colorHex) { hexes.append(main) }
        if let multi = spool.filament.multiColorHexes {
            for part in multi.split(separator: ",") {
                if let hex = ColorMatching.normalize(String(part)) { hexes.append(hex) }
            }
        }
        var seen = Set<String>()
        return hexes.filter { seen.insert($0).inserted }
    }

    // MARK: - Matching

    /// The role this spool matches, or nil. WYSIWYG geometry: a swatch matches
    /// when its map/strip position falls inside a drawn circle or band — the
    /// rendered regions are the match truth (not ΔE).
    static func matchRole(spool: Spool, spec: ColorFilterSpec) -> String? {
        let hexes = swatches(of: spool)
        guard !hexes.isEmpty else { return nil }
        if spec.harmony.isHueBand {
            return hueBandRole(swatchHexes: hexes, spec: spec)
        }
        guard let anchorHex = ColorMatching.normalize(spec.anchorHex) else { return nil }
        if isAchromatic(anchorHex) {
            return achromaticIntervalRole(swatchHexes: hexes, anchorHex: anchorHex, spec: spec)
        }
        let radius = unitRadius(tolerance: spec.toleranceDeltaE)
        let centers: [(role: String, point: CGPoint)] = targets(for: spec).compactMap { target in
            guard let point = unitPoint(forHex: target.hex) else { return nil }
            return (target.role, point)
        }
        var best: (role: String, distance: Double)?
        for hex in hexes {
            guard let point = unitPoint(forHex: hex) else { continue }
            for center in centers {
                let d = unitDistance(point, center.point)
                if d <= radius, d < (best?.distance ?? .infinity) {
                    best = (center.role, d)
                }
            }
        }
        return best?.role
    }

    private static func hueBandRole(swatchHexes: [String], spec: ColorFilterSpec) -> String? {
        guard let anchorHex = ColorMatching.normalize(spec.anchorHex),
              let anchor = ColorMatching.hsl(from: anchorHex) else { return nil }
        let anchorIsAchromatic = anchor.s < achromaticSaturationThreshold
        var best: (role: String, distance: Double)?
        for hex in swatchHexes {
            guard let swatch = ColorMatching.hsl(from: hex) else { continue }
            let swatchIsAchromatic = swatch.s < achromaticSaturationThreshold
            guard swatchIsAchromatic == anchorIsAchromatic else { continue }
            if !anchorIsAchromatic {
                guard hueDistance(swatch.h, anchor.h) <= spec.toleranceDeltaE else { continue }
            }
            if spec.harmony == .shades {
                guard swatch.l <= anchor.l + shadesLightnessHeadroom else { continue }
            }
            let role = lightnessBucket(swatchL: swatch.l, anchorL: anchor.l)
            let distance = anchorIsAchromatic ? abs(swatch.l - anchor.l) : hueDistance(swatch.h, anchor.h)
            if distance < (best?.distance ?? .infinity) {
                best = (role, distance)
            }
        }
        return best?.role
    }

    /// Achromatic anchor (strip pick): an interval of the same normalized
    /// radius along the strip's lightness axis.
    private static func achromaticIntervalRole(swatchHexes: [String], anchorHex: String, spec: ColorFilterSpec) -> String? {
        guard let anchor = ColorMatching.hsl(from: anchorHex) else { return nil }
        let radius = unitRadius(tolerance: spec.toleranceDeltaE)
        var best: Double?
        for hex in swatchHexes {
            guard let hsl = ColorMatching.hsl(from: hex), hsl.s < achromaticSaturationThreshold else { continue }
            let d = abs(hsl.l - anchor.l)
            if d <= radius, d < (best ?? .infinity) { best = d }
        }
        return best == nil ? nil : targets(for: spec).first?.role
    }

    private static func lightnessBucket(swatchL: Double, anchorL: Double) -> String {
        if swatchL < anchorL - lightnessBucketWidth { return "Darker" }
        if swatchL > anchorL + lightnessBucketWidth { return "Lighter" }
        return "Anchor"
    }

    // MARK: - Grouping

    struct RoleGroup {
        let role: String
        let swatchHex: String
        let spools: [Spool]
    }

    /// Section order + header swatch per role. Point-target modes reuse the
    /// targets; hue-band modes use lightness buckets with the anchor hue/sat
    /// shifted ±0.2 lightness (clamped 0.05...0.95) as header swatches.
    static func roleOrder(for spec: ColorFilterSpec) -> [HarmonyTarget] {
        guard spec.harmony.isHueBand else { return targets(for: spec) }
        guard let anchorHex = ColorMatching.normalize(spec.anchorHex),
              let anchor = ColorMatching.hsl(from: anchorHex) else { return [] }
        func bucketHex(_ shift: Double) -> String {
            ColorMatching.hex(h: anchor.h, s: anchor.s, l: min(max(anchor.l + shift, 0.05), 0.95))
        }
        let anchorTarget = HarmonyTarget(role: "Anchor", hex: anchorHex)
        let darker = HarmonyTarget(role: "Darker", hex: bucketHex(-0.2))
        if spec.harmony == .shades { return [anchorTarget, darker] }
        return [HarmonyTarget(role: "Lighter", hex: bucketHex(0.2)), anchorTarget, darker]
    }

    static func groupedMatches(_ spools: [Spool], spec: ColorFilterSpec) -> [RoleGroup] {
        var byRole: [String: [Spool]] = [:]
        for spool in spools {
            if let role = matchRole(spool: spool, spec: spec) {
                byRole[role, default: []].append(spool)
            }
        }
        return roleOrder(for: spec).compactMap { entry in
            guard let matched = byRole[entry.role], !matched.isEmpty else { return nil }
            return RoleGroup(role: entry.role, swatchHex: entry.hex, spools: matched)
        }
    }

    // MARK: - Display strings

    static func matchSummary(groups: [RoleGroup]) -> String {
        let total = groups.reduce(0) { $0 + $1.spools.count }
        guard total > 0 else { return "No spools match" }
        let noun = total == 1 ? "spool matches" : "spools match"
        guard groups.count > 1 else { return "\(total) \(noun)" }
        let parts = groups.map { "\($0.spools.count) \($0.role.lowercased())" }
        return "\(total) \(noun) · \(parts.joined(separator: ", "))"
    }

    static func toleranceLabel(harmony: ColorHarmony, tolerance: Double) -> String {
        let value = Int(tolerance.rounded())
        return harmony.isHueBand ? "± \(value)°" : "\(value) %"
    }

    // MARK: - Availability islands

    struct ColorIsland: Identifiable, Hashable {
        let hex: String
        let spoolCount: Int
        /// Hue 0..<360; nil = achromatic (rendered on the strip, not the map).
        let hue: Double?
        let lightness: Double
        var id: String { hex }
    }

    /// One island per distinct swatch hex across the given spools, with the
    /// number of spools carrying it. Deterministic order (hex ascending).
    static func islands(for spools: [Spool]) -> [ColorIsland] {
        var counts: [String: Int] = [:]
        for spool in spools {
            for hex in swatches(of: spool) {
                counts[hex, default: 0] += 1
            }
        }
        return counts
            .compactMap { hex, count -> ColorIsland? in
                guard let hsl = ColorMatching.hsl(from: hex) else { return nil }
                let achromatic = hsl.s < achromaticSaturationThreshold
                return ColorIsland(hex: hex, spoolCount: count, hue: achromatic ? nil : hsl.h, lightness: hsl.l)
            }
            .sorted { $0.hex < $1.hex }
    }

    // MARK: - Map position math

    static func mapPoint(hue: Double, lightness: Double, in size: CGSize) -> CGPoint {
        CGPoint(x: hue / 360 * size.width, y: (1 - lightness) * size.height)
    }

    /// Position of a chromatic hex on the map; nil for achromatics (strip).
    static func mapPoint(forHex hex: String, in size: CGSize) -> CGPoint? {
        guard let hsl = ColorMatching.hsl(from: hex), hsl.s >= achromaticSaturationThreshold else { return nil }
        return mapPoint(hue: hsl.h, lightness: hsl.l, in: size)
    }

    /// The full-saturation HSL color under a map point, clamped to bounds.
    static func hex(atMapPoint point: CGPoint, in size: CGSize) -> String {
        guard size.width > 0, size.height > 0 else { return "000000" }
        let hue = min(max(point.x / size.width, 0), 1) * 360
        let lightness = 1 - min(max(point.y / size.height, 0), 1)
        return ColorMatching.hex(h: hue, s: 1, l: lightness)
    }

    static func stripX(forLightness lightness: Double, width: CGFloat) -> CGFloat {
        (1 - lightness) * width
    }

    /// Achromatic color at a 0...1 fraction along the strip (0 = white).
    static func hex(atStripFraction x: Double) -> String {
        ColorMatching.hex(h: 0, s: 0, l: 1 - min(max(x, 0), 1))
    }

    // MARK: - Snapping

    /// Nearest chromatic island within the snap radius (hue-wrapped), or nil.
    static func snappedHex(nearMapPoint point: CGPoint, islands: [ColorIsland], in size: CGSize) -> String? {
        var best: (hex: String, distance: CGFloat)?
        for island in islands {
            guard let hue = island.hue else { continue }
            let center = mapPoint(hue: hue, lightness: island.lightness, in: size)
            let dxRaw = abs(center.x - point.x)
            let dx = min(dxRaw, size.width - dxRaw)
            let dy = center.y - point.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance <= islandSnapRadius, distance < (best?.distance ?? .infinity) {
                best = (island.hex, distance)
            }
        }
        return best?.hex
    }

    /// Nearest achromatic island within the snap radius along the strip, or nil.
    static func snappedHex(nearStripX x: CGFloat, islands: [ColorIsland], width: CGFloat) -> String? {
        var best: (hex: String, distance: CGFloat)?
        for island in islands where island.hue == nil {
            let distance = abs(stripX(forLightness: island.lightness, width: width) - x)
            if distance <= islandSnapRadius, distance < (best?.distance ?? .infinity) {
                best = (island.hex, distance)
            }
        }
        return best?.hex
    }

    // MARK: - Sizing

    /// Island diameter: base + growth per extra spool, capped at 2×base.
    /// Base is clamped to the settings bounds so a hand-edited default can't
    /// break layout.
    static func islandDiameter(spoolCount: Int, baseDiameter: Double) -> CGFloat {
        let base = min(max(baseDiameter, islandBaseDiameterBounds.lowerBound), islandBaseDiameterBounds.upperBound)
        let diameter = base + Double(max(spoolCount - 1, 0)) * Double(islandGrowthPerSpool)
        return CGFloat(min(diameter, base * 2))
    }
}
