//
//  SpoolWeightMath.swift
//  SpoolKid
//
//  Purpose: The weight arithmetic shared by every surface that lets a user
//  state a spool's weight. Extracted from `SpoolFormView` when the weigh
//  session became a second caller — one implementation per concept.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum SpoolWeightMath {

    /// Grams from a box the user typed into, or nil when it states no number.
    /// Accepts a comma decimal separator because a large part of the user base
    /// types on a locale keyboard that offers one.
    static func parseWeight(_ value: String) -> Double? {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    /// Grams, without a trailing `.0` on a whole number — the field is one the
    /// user types into, so it has to read like something they would type.
    ///
    /// `Int(_:)` TRAPS on a value outside `Int`'s range and on `inf`/`nan`, and
    /// every caller is fed by an unbounded `.decimalPad` a user can type or
    /// paste 20 digits into — which `parseWeight` happily returns as `1e20`.
    /// `Int(exactly:)` is the total form of the same conversion: it returns nil
    /// for a value `Int` cannot hold AND for a fractional one, so a number that
    /// cannot be printed as a whole is printed as the `Double` it is rather
    /// than crashing the screen showing it.
    static func formatWeight(_ grams: Double) -> String {
        guard let whole = Int(exactly: grams) else { return String(grams) }
        return String(whole)
    }

    /// Grams as shown (never typed), rounded to 0.1 g: a remaining weight
    /// computed from a scale reading or a slicer's used grams carries noise
    /// no one weighs to (owner, 2026-11-03).
    static func displayWeight(_ grams: Double) -> String {
        // `+ 0` turns the -0.0 a tiny negative rounds to into 0.
        formatWeight((grams * 10).rounded() / 10 + 0)
    }

    /// The NET filament a GROSS scale reading implies.
    ///
    /// Deliberately does NOT clamp at zero. A reading lighter than the spool's
    /// stated core weight means one of the two numbers is wrong, and the caller
    /// has to be able to see that; clamping would render it as a plausible
    /// "0 g remaining" and destroy the evidence.
    static func netFromGross(gross: Double, emptySpoolWeight: Double) -> Double {
        gross - emptySpoolWeight
    }
}
