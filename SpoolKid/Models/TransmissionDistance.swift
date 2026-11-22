//
//  TransmissionDistance.swift
//  SpoolKid
//
//  Purpose: The rules for a filament's HueForge TD (transmission distance, mm):
//  how a stored value is read, what range is valid, how entry is rounded, and
//  the wire form Spoolman's registered `td` field takes. Every backend, form
//  and tag path goes through these (conventions A4).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// `nonisolated`: pure rules, used from the payload builders and tests.
nonisolated enum TransmissionDistance {
    /// The filament field key — what spoolpalette scores highest when it picks
    /// a TD field, and what the owner's Spoolman already declares.
    static let fieldKey = "td"
    static let fieldName = "Transmission Distance (TD)"

    /// Reads a stored value as tolerantly as spoolpalette does: a bare JSON
    /// number, or one wrapped in up to two JSON string layers, with a comma
    /// decimal allowed. Anything outside the valid range reads as no TD.
    static func decode(_ raw: String?) -> Double? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        for _ in 0..<2 where text.hasPrefix("\"") {
            guard let data = text.data(using: .utf8),
                  let inner = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String
            else { return nil }
            text = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), isValid(value) else { return nil }
        return value
    }

    /// `0 < TD ≤ 100`, spoolpalette's own bounds — judged after rounding, so a
    /// value below the 0.1 resolution is no TD rather than a "0.0" that can
    /// never be saved.
    static func isValid(_ value: Double) -> Bool {
        value.isFinite && rounded(value) > 0 && value <= 100
    }

    /// Entry keeps one decimal: HueForge, TigerTag's ×10 field and the TD1s's
    /// ±7.5% all make finer digits noise.
    static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    /// Spoolman validates an extra value against its registered type: a
    /// `float` takes the bare number (a wrapped one is a 400, probed
    /// 2026-11-02), a `text` field the JSON-string form. Any other type cannot
    /// hold a decimal TD, so nil — the caller reports it.
    static func spoolmanWireValue(_ value: Double, fieldType: String) -> String? {
        let number = String(value)
        switch fieldType {
        case "float": return number
        case "text": return "\"\(number)\""
        default: return nil
        }
    }

    static func displayText(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US_POSIX")))) mm"
    }
}
