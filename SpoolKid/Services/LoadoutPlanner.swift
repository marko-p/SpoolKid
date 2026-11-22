//
//  LoadoutPlanner.swift
//  SpoolKid
//
//  Purpose: Color Matching's rules: for each picked color, the closest spool
//  of the plan's material with enough left, and the others close enough to
//  be alternatives. Pure. No mixing and no toolheads (owner, 2026-11-13).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum LoadoutPlanner {
    /// Another filament is an alternative this close (CIEDE2000): the color
    /// filter's default tolerance (owner, 2026-11-13).
    static let alternativeDeltaE = ColorFilterService.defaultTolerance
    static let alternativesPerColor = 3

    struct Spool: Equatable, Sendable, Identifiable {
        var id: Int
        var filamentID: Int
        /// The filament's name.
        var title: String
        var material: String
        var hex: String
        var remaining: Double
        var isMultiColor = false
        /// Every colour of a multi-colour spool. In a match, `hex` is the one
        /// that matched.
        var colorHexes: [String] = []
    }

    struct Request: Sendable {
        var hexes: [String]
        var spools: [Spool]
        var primaryMaterial: String
        var minimumRemaining: Double
        /// Multi-colour spools can match on any of their colours.
        var includesMultiColor = false
    }

    struct Match: Equatable, Sendable {
        var spool: Spool
        var deltaE: Double
    }

    struct ColorResult: Equatable, Sendable {
        var hex: String
        var closest: Match?
        var alternatives: [Match]
    }

    enum Failure: Error, Equatable {
        case noTargets
        case noSpools(material: String, minimumRemaining: Double)

        var message: String {
            switch self {
            case .noTargets:
                "Pick at least one color."
            case .noSpools(let material, let minimum):
                "No \(material) spool has \(Int(minimum)) g left. Lower the minimum or choose another material."
            }
        }
    }

    static func match(_ request: Request) -> Result<[ColorResult], Failure> {
        guard !request.hexes.isEmpty else { return .failure(.noTargets) }
        let base = MaterialPairing.baseMaterial(request.primaryMaterial)
        let candidates = eligible(request, base: base)
        guard !candidates.isEmpty else {
            return .failure(.noSpools(material: base, minimumRemaining: request.minimumRemaining))
        }
        return .success(request.hexes.map { hex in
            guard let target = ColorMatching.lab(from: hex) else { return ColorResult(hex: hex, closest: nil, alternatives: []) }
            let ranked = candidates
                .map { Match(spool: $0.spool, deltaE: ColorMatching.deltaE2000(target, $0.lab)) }
                .sorted { $0.deltaE != $1.deltaE ? $0.deltaE < $1.deltaE : $0.spool.remaining > $1.spool.remaining }
            // One row per filament: its closest, fullest spool.
            var seen = Set<Int>()
            let byFilament = ranked.filter { seen.insert($0.spool.filamentID).inserted }
            let alternatives = byFilament.dropFirst()
                .filter { $0.deltaE <= alternativeDeltaE }
                .prefix(alternativesPerColor)
            return ColorResult(hex: hex, closest: byFilament.first, alternatives: Array(alternatives))
        })
    }

    /// One candidate per colour: a multi-colour spool appears once for each.
    private static func eligible(
        _ request: Request, base: String
    ) -> [(spool: Spool, lab: (l: Double, a: Double, b: Double))] {
        request.spools.flatMap { spool -> [(spool: Spool, lab: (l: Double, a: Double, b: Double))] in
            guard spool.remaining >= request.minimumRemaining,
                  MaterialPairing.baseMaterial(spool.material) == base else { return [] }
            if spool.isMultiColor && !request.includesMultiColor { return [] }
            let hexes = spool.isMultiColor && !spool.colorHexes.isEmpty ? spool.colorHexes : [spool.hex]
            return hexes.compactMap { hex in
                guard let lab = ColorMatching.lab(from: hex) else { return nil }
                var colored = spool
                colored.hex = hex
                return (colored, lab)
            }
        }
    }
}
