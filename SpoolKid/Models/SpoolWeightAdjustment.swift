//
//  SpoolWeightAdjustment.swift
//  SpoolKid
//
//  Purpose: The arithmetic behind adjusting a spool's remaining weight after
//  a print — either by the grams the print used, or by a scale reading of
//  the spool. Pure: the hub save service and the shared weight component
//  both build on it, so the rule lives in one place.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum SpoolWeightAdjustment {

    /// What the user stated: grams the print used, or a gross scale reading.
    enum Input: Equatable {
        case used(Double)
        case measured(gross: Double)
    }

    /// The result of applying an input to a spool.
    enum Outcome: Equatable {
        /// The new NET remaining weight, never below zero.
        case remaining(Double)
        /// The would-be remaining weight, below zero. Shown, never saved.
        case negative(Double)
        /// A scale reading was given but the spool's core weight is unknown.
        case needsEmptySpoolWeight
        /// Grams were given but the spool has no remaining weight yet.
        case needsCurrentRemaining
    }

    struct Preview: Equatable {
        let before: Double?
        let outcome: Outcome
    }

    /// The input the two boxes state, or nil when neither states a usable
    /// number. Both boxes filled: the scale reading wins. The UI keeps them
    /// exclusive; this is only the tiebreak.
    static func input(used: String, measured: String) -> Input? {
        if let gross = positiveWeight(measured) {
            return .measured(gross: gross)
        }
        if let grams = positiveWeight(used) {
            return .used(grams)
        }
        return nil
    }

    static func outcome(of input: Input, currentRemaining: Double?, emptySpoolWeight: Double?) -> Outcome {
        switch input {
        case .used(let grams):
            guard let currentRemaining else { return .needsCurrentRemaining }
            return remainingOutcome(currentRemaining - grams)
        case .measured(let gross):
            guard let emptySpoolWeight else { return .needsEmptySpoolWeight }
            return remainingOutcome(SpoolWeightMath.netFromGross(gross: gross, emptySpoolWeight: emptySpoolWeight))
        }
    }

    /// The line showing the change, or nil when there is no change to show.
    static func previewText(_ preview: Preview) -> String? {
        let after: Double
        switch preview.outcome {
        case .remaining(let value), .negative(let value):
            after = value
        case .needsEmptySpoolWeight, .needsCurrentRemaining:
            return nil
        }
        let afterText = "\(SpoolWeightMath.displayWeight(after)) g"
        guard let before = preview.before else {
            return "Remaining: \(afterText)"
        }
        return "Remaining: \(SpoolWeightMath.displayWeight(before)) g → \(afterText)"
    }

    static let usedCaption = "Grams this print used, from the slicer. Taken off the remaining weight."
    static let negativeNote = "This would leave less than 0 g — check the number."
    static let needsEmptySpoolWeightNote = "Set this spool's empty-spool weight to weigh it"
    static let needsCurrentRemainingNote = "This spool has no remaining weight yet — weigh it instead."

    // MARK: - Private

    /// A typed weight that names a real, positive, finite amount of grams.
    /// `Double("inf")` parses, so finiteness is checked explicitly.
    private static func positiveWeight(_ value: String) -> Double? {
        guard let grams = SpoolWeightMath.parseWeight(value),
              grams.isFinite, grams > 0 else { return nil }
        return grams
    }

    private static func remainingOutcome(_ value: Double) -> Outcome {
        value < 0 ? .negative(value) : .remaining(value)
    }
}
