//
//  FilamentCreateRequirement.swift
//  SpoolKid
//
//  Purpose: The fields a backend refuses to create a filament without, named
//  one by one rather than as a sentence, so a caller can offer to supply them.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// A filament field the active backend requires on create and the draft does
/// not carry.
///
/// `FilaManRepository.createRequirements` already knew this, but only as the
/// FIRST missing one, phrased as a sentence for `errorMessage`. A sentence can
/// be read; it cannot be acted on. Migration needs the whole list, typed, to
/// render a control per missing field — telling a user their filament needs a
/// manufacturer while offering no way to give it one is where this started
/// (device finding, 2026-08-29).
///
/// `nonisolated`: a pure value type, used from Swift Testing off the main actor.
nonisolated enum FilamentCreateRequirement: String, Equatable, Sendable, CaseIterable, Identifiable {
    case name
    case material
    /// Spoolman's (a 422 without it, probed 2026-08-27); FilaMan has no such rule.
    case density
    case diameter
    case manufacturer

    var id: String { rawValue }

    /// The form label for this field. "Manufacturer", not "Vendor": every
    /// user-visible occurrence of this field is called that now, matching
    /// the label `FieldSchema` gives `vendor_id` on every backend.
    var label: String {
        switch self {
        case .name: "Name"
        case .material: "Material"
        case .density: "Density"
        case .diameter: "Diameter"
        case .manufacturer: "Manufacturer"
        }
    }
}
