//
//  FilamentMatchService.swift
//  SpoolKid
//
//  Purpose: Heuristic scoring of Spoolman spools against tag data.
//  Weights: material 35, brand 20, name tokens 20, color RGB distance 15, temps 7, diameter 3.
//  Brand mismatch caps confidence at 79 to prevent auto-accept.
//  Auto-accept: threshold 0 = always ask, 101 = never accept; brand mismatch always blocks.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import Foundation

// MARK: - Result types

struct FilamentMatchResult: Sendable {
    let spool: SpoolmanSpool
    /// 0–100
    let confidence: Int
    let band: ConfidenceBand
    let brandMismatch: Bool

    enum ConfidenceBand: Sendable {
        case high    // >= 80
        case medium  // 60 – 79
        case low     // < 60
    }
}

// MARK: - Service

enum FilamentMatchService {

    // MARK: Public API

    static func score(tag: FilamentTagData, against spool: SpoolmanSpool) -> FilamentMatchResult {
        var points = 0

        // Material (35 pts)
        let materialMatch = tag.material.lowercased() == (spool.filament.material ?? "").lowercased()
        if materialMatch { points += 35 }

        // Brand (20 pts)
        let tagBrand = tag.brand.lowercased().trimmingCharacters(in: .whitespaces)
        let spoolBrand = (spool.filament.vendor?.name ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        let brandMatch = !tagBrand.isEmpty && !spoolBrand.isEmpty && tagBrand == spoolBrand
        if brandMatch { points += 20 }
        let brandMismatch = !tagBrand.isEmpty && !spoolBrand.isEmpty && !brandMatch

        // Name token overlap (20 pts)
        let tagTokens = tokenize(tag.name ?? "")
        let spoolTokens = tokenize(spool.filament.name ?? "")
        if !tagTokens.isEmpty && !spoolTokens.isEmpty {
            let intersection = tagTokens.intersection(spoolTokens)
            let union = tagTokens.union(spoolTokens)
            let jaccard = Double(intersection.count) / Double(union.count)
            points += Int(jaccard * 20)
        }

        // Color (15 pts) — Euclidean RGB distance, max distance sqrt(3)*255 ≈ 441.7
        if let tagRGB = rgbComponents(hex: tag.colorHex),
           let spoolRGB = rgbComponents(hex: spool.filament.colorHex ?? "") {
            let dist = rgbDistance(tagRGB, spoolRGB)
            let similarity = 1.0 - (dist / 441.7)
            points += Int(similarity * 15)
        }

        // Temperatures (7 pts)
        if let spoolExtruder = spool.filament.settingsExtruderTemp {
            let midNozzle = (tag.minNozzleTemp + tag.maxNozzleTemp) / 2
            let nozzleDelta = abs(spoolExtruder - midNozzle)
            if nozzleDelta <= 10 { points += 4 }
            else if nozzleDelta <= 30 { points += 2 }
        }
        if let spoolBed = spool.filament.settingsBedTemp {
            let midBed = (tag.minBedTemp + tag.maxBedTemp) / 2
            let bedDelta = abs(spoolBed - midBed)
            if bedDelta <= 10 { points += 3 }
            else if bedDelta <= 20 { points += 1 }
        }

        // Diameter (3 pts)
        if let d = spool.filament.diameter {
            let standard = abs(d - 1.75) < 0.01 || abs(d - 3.0) < 0.01
            if standard { points += 3 }
        }

        // Cap at 100, then apply brand-mismatch cap
        var confidence = min(100, points)
        if brandMismatch {
            confidence = min(confidence, 79)
        }

        return FilamentMatchResult(
            spool: spool,
            confidence: confidence,
            band: band(for: confidence),
            brandMismatch: brandMismatch
        )
    }

    static func rank(tag: FilamentTagData, spools: [SpoolmanSpool]) -> [FilamentMatchResult] {
        spools
            .map { score(tag: tag, against: $0) }
            .sorted { $0.confidence > $1.confidence }
    }

    /// Returns true only when all conditions are met:
    /// - threshold is not 0 (always ask) and not ≥ 101 (never)
    /// - confidence >= threshold
    /// - no brand mismatch
    static func shouldAutoAccept(result: FilamentMatchResult, threshold: Int) -> Bool {
        guard threshold > 0, threshold < 101 else { return false }
        guard !result.brandMismatch else { return false }
        return result.confidence >= threshold
    }

    // MARK: Helpers

    private static func band(for confidence: Int) -> FilamentMatchResult.ConfidenceBand {
        if confidence >= 80 { return .high }
        if confidence >= 60 { return .medium }
        return .low
    }

    private static func tokenize(_ text: String) -> Set<String> {
        Set(
            text
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 1 }
        )
    }

    private static func rgbComponents(hex: String) -> (Double, Double, Double)? {
        let clean = hex
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespaces)
        guard clean.count == 6, let value = UInt32(clean, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF)
        let g = Double((value >>  8) & 0xFF)
        let b = Double( value        & 0xFF)
        return (r, g, b)
    }

    private static func rgbDistance(
        _ a: (Double, Double, Double),
        _ b: (Double, Double, Double)
    ) -> Double {
        let dr = a.0 - b.0
        let dg = a.1 - b.1
        let db = a.2 - b.2
        return sqrt(dr*dr + dg*dg + db*db)
    }
}
