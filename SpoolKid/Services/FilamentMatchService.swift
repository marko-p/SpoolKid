//
//  FilamentMatchService.swift
//  SpoolKid
//
//  Purpose: Heuristic scoring of filament candidates against tag data.
//
//  Two weight sets live here — same service, different questions:
//
//  1. Spool matching (score/against — `FilamentMatchResult`):
//     material 35, brand 20, name tokens 20, color Lab 15, temps 7, diameter 3.
//     Brand mismatch caps confidence at 79. Used by the scan-resolution cascade
//     to rank existing Spoolman spools.
//
//  2. Suggestion scoring (scoreFilament — `Int`):
//     material 40, brand 25, name 15 (exact) / 7 (substring), color Lab 20,
//     near-miss penalty −8 (color ≤ 2 but material+brand match).
//     Used by `ScanResolutionService.newSpoolSourceCandidates` to rank candidate
//     filaments (local + the backend's catalogue) for the "Search ‹catalogue›
//     for Similar Filaments" list.
//
//  Auto-accept: threshold 0 = always ask, 101 = never accept; brand mismatch always blocks.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

// MARK: - Result types

struct FilamentMatchResult: Sendable {
    let spool: Spool
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

    static func score(tag: FilamentTagData, against spool: Spool) -> FilamentMatchResult {
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

        // Color (15 pts) — Perceptual Lab similarity (CIELAB ΔE76)
        let colorMatch = colorSimilarity(tag: tag.colors.hexes, filament: spool.filament.colors.hexes)
        points += Int(colorMatch * 15)

        // Temperatures (7 pts)
        if let spoolExtruder = spool.filament.settingsExtruderTemp, let midNozzle = tag.statedExtruderTemp {
            let nozzleDelta = abs(spoolExtruder - midNozzle)
            if nozzleDelta <= 10 { points += 4 }
            else if nozzleDelta <= 30 { points += 2 }
        }
        if let spoolBed = spool.filament.settingsBedTemp, let midBed = tag.statedBedTemp {
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

    static func rank(tag: FilamentTagData, spools: [Spool]) -> [FilamentMatchResult] {
        spools
            .map { score(tag: tag, against: $0) }
            .sorted { $0.confidence > $1.confidence }
    }

    static func scoreFilament(
        tag: FilamentTagData,
        name: String?,
        material: String?,
        brand: String?,
        colorHexes: [String]
    ) -> Int {
        var score = 0
        let tagMaterial = tag.material.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tagBrand = tag.brand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tagName = (tag.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if (material ?? "").lowercased() == tagMaterial { score += 40 }
        if (brand ?? "").lowercased() == tagBrand { score += 25 }
        if let candidateName = name?.lowercased(), !tagName.isEmpty {
            if candidateName == tagName { score += 15 }
            else if candidateName.contains(tagName) || tagName.contains(candidateName) { score += 7 }
        }

        let colorMatch = colorSimilarity(tag: tag.colors.hexes, filament: colorHexes)
        let colorScore = Int((colorMatch * 20.0).rounded())
        score += colorScore

        if colorScore <= 2,
           (material ?? "").lowercased() == tagMaterial,
           (brand ?? "").lowercased() == tagBrand {
            score -= 8
        }

        return score
    }

    /// How alike a tag's colors and a filament's colors are, 0…1.
    ///
    /// A single color on either side compares first with first, as it always
    /// has. Two or more on both sides compare as sets, ignoring order: each tag
    /// color scores its best match among the filament's colors, the mean of
    /// those is scaled by how many colors the two sides do not share. No
    /// colors on one side leave the comparison to the other side's first color.
    static func colorSimilarity(tag: [String], filament: [String]) -> Double {
        guard tag.count >= 2, filament.count >= 2 else {
            return ColorMatching.similarity01(hexA: tag.first ?? "", hexB: filament.first)
        }
        let bestMatches = tag.map { tagHex in
            filament.map { ColorMatching.similarity01(hexA: tagHex, hexB: $0) }.max() ?? 0
        }
        let mean = bestMatches.reduce(0, +) / Double(bestMatches.count)
        return mean * Double(min(tag.count, filament.count)) / Double(max(tag.count, filament.count))
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

}
