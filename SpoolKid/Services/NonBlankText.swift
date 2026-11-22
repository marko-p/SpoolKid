//
//  NonBlankText.swift
//  SpoolKid
//
//  Purpose: One rule for an optional field's display text: trimmed, and nil
//  when blank. The record pages (FilamentPage, ManufacturerPage) treat a blank
//  field as absent rather than showing an empty row.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

extension Optional where Wrapped == String {
    /// The value trimmed, or nil when it is nil or blank.
    nonisolated var nonBlank: String? {
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
