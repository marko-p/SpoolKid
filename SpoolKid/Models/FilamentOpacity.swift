//
//  FilamentOpacity.swift
//  SpoolKid
//
//  Purpose: Turns a filament's TD into the colour alpha tags and toolheads
//  carry (0 transparent … 255 opaque), and decides what alpha a write gets.
//  TD is read as the thickness that blocks 90% of light, HueForge's working
//  meaning. The inverse is for display only, marked as an estimate: TD is
//  measured, a tag's alpha may be a guess, so nothing is ever stored from it.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// `nonisolated`: pure rules, used from the codecs and tests.
nonisolated enum FilamentOpacity {
    static let opaque = 255
    /// The wall thickness, in mm, the alpha describes.
    static let referenceThickness = 1.0

    /// Opaque without a valid TD: a value `TransmissionDistance` rejects says
    /// nothing about the filament, and TD 0 would divide by zero.
    static func alpha(forTD td: Double?) -> Int {
        guard let td, TransmissionDistance.isValid(td) else { return opaque }
        return Int((Double(opaque) * (1 - pow(10, -referenceThickness / td))).rounded())
    }

    /// A tag's alpha as something worth keeping. Nil for 255 (opaque), for 0
    /// (a writer that left the byte blank: no filament is invisible) and for
    /// anything that is not a byte.
    static func stated(alpha: Int) -> Int? {
        (1..<opaque).contains(alpha) ? alpha : nil
    }

    /// The TD an alpha stands for, for display only; nil when the alpha is
    /// not stated or lands outside `TransmissionDistance`'s range.
    static func estimatedTD(alpha: Int) -> Double? {
        guard let alpha = stated(alpha: alpha) else { return nil }
        let td = TransmissionDistance.rounded(-referenceThickness / log10(1 - Double(alpha) / Double(opaque)))
        return TransmissionDistance.isValid(td) ? td : nil
    }

    /// The toolhead sheet's line under the filament: the Library's measured
    /// TD, else one estimated from the printer's alpha (marked ≈), then the
    /// printer's own opacity. Nil when there is neither.
    static func toolheadText(alpha: Int, libraryTD: Double?) -> String? {
        let measured = libraryTD.flatMap { TransmissionDistance.isValid($0) ? $0 : nil }
        let td = measured.map { "TD \(TransmissionDistance.displayText($0))" }
            ?? estimatedTD(alpha: alpha).map { "TD ≈ \(TransmissionDistance.displayText($0))" }
        let opacity = stated(alpha: alpha).map(displayText(alpha:))
        let parts = [td, opacity].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func displayText(alpha: Int) -> String {
        "Opacity \(Int((Double(alpha) / Double(opaque) * 100).rounded()))%"
    }

    /// The Write Tag form offers the switch for a filament with a TD, on a
    /// format that has somewhere to put the result.
    static func offersWriteSwitch(td: Double?, format: TagFormat) -> Bool {
        guard let td else { return false }
        return TransmissionDistance.isValid(td) && format.carriesAlpha
    }

    /// The alpha a tag write carries, nil for opaque. TD wins; with none, the
    /// alpha the source tag carried stays, so rewriting a format with no TD
    /// field does not turn a translucent tag opaque.
    static func alphaToWrite(td: Double?, carried: Int?, format: TagFormat, enabled: Bool) -> Int? {
        guard enabled, format.carriesAlpha else { return nil }
        if let td, TransmissionDistance.isValid(td) { return stated(alpha: alpha(forTD: td)) }
        return carried.flatMap(stated(alpha:))
    }
}
