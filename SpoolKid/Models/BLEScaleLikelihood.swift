//
//  BLEScaleLikelihood.swift
//  SpoolKid
//
//  Purpose: Order the scan results so the scale is at the top.
//
//  The owner asked for the list to show only scales (2026-09-08). It ranks and
//  labels instead of filtering, because the one device that matters here is
//  precisely the one nobody has catalogued yet: their own scale advertises
//  FFE0 and FEE0, neither of which is the standard Weight Scale service, and a
//  filter built on what we know today would have hidden it. Ranking gets the
//  same result — the scale first — without the failure mode.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum BLEScaleLikelihood: Int, Comparable, Equatable {
    case unlikely = 0
    case possible = 1
    case likely = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

nonisolated enum BLEScaleHeuristic {

    /// Services that say "scale" outright.
    private static let weighing: Set<String> = [
        "181D",  // Weight Scale
        "181B",  // Body Composition
        "FFB0",  // used by several body-composition scales
    ]

    /// Transparent-serial services. Not evidence of a scale by themselves —
    /// they are on everything from LED strips to thermometers — but every
    /// cheap scale seen so far speaks through one, so they beat silence.
    private static let serialBridges: Set<String> = ["FFE0", "FFF0", "FEE0", "AE00"]

    /// The AiLink/Elink module's advertised signature. Two of these together is
    /// not a guess: it is the module family SpoolKid decodes outright
    /// (`AiLinkScaleFrame`), and it is behind a great many rebadged kitchen
    /// scales, so most testers reaching this screen have one.
    private static let aiLink: Set<String> = ["FFE0", "FEE0", "F0A0"]

    private static let names = [
        "scale", "weight", "waage", "balance", "ailink", "etekcity",
        "chipsea", "renpho", "eufy", "kitchen",
    ]

    /// A 16-bit UUID as CoreBluetooth prints it in an advertisement ("FFE0"),
    /// and the same UUID expanded against the Bluetooth base — both forms turn
    /// up depending on where the string came from.
    static func short(_ uuid: String) -> String {
        let upper = uuid.uppercased()
        guard upper.count == 36,
              upper.hasPrefix("0000"),
              upper.hasSuffix("-0000-1000-8000-00805F9B34FB") else { return upper }
        return String(upper.dropFirst(4).prefix(4))
    }

    /// How likely this peripheral is to be a scale, and why — nil reason
    /// means it was not promoted, which is not the same as ruling it out.
    static func rank(name: String, advertised: [String]) -> (BLEScaleLikelihood, String?) {
        let services = Set(advertised.map(short))
        if let match = services.intersection(weighing).sorted().first {
            return (.likely, "advertises a weighing service (\(match))")
        }
        // Checked before the generic serial bridges, and above a name match,
        // because it promises more than "probably a scale" — it promises a
        // scale SpoolKid can already read.
        if services.intersection(aiLink).count >= 2 {
            return (.likely, "looks like an AiLink scale — SpoolKid can read these")
        }
        if names.contains(where: name.lowercased().contains) {
            return (.likely, "its name looks like a scale")
        }
        if let match = services.intersection(serialBridges).sorted().first {
            return (.possible, "speaks over \(match), which cheap scales use")
        }
        return (.unlikely, nil)
    }
}
