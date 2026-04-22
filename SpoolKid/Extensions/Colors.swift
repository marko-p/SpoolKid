//
//  Colors.swift
//  SpoolKid
//
//  Purpose: Semantic color tokens for consistent use across the app.
//  All UI colors should reference these tokens rather than hardcoding
//  system colors or named colors directly in views.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI

extension Color {
    // MARK: - Status colors
    /// Use for success states (connection valid, write complete)
    static let statusSuccess  = Color(.systemGreen)
    /// Use for error / failure states (connection failed, error messages)
    static let statusError    = Color(.systemRed)
    /// Use for warning states (incompatible material, advisory notices)
    static let statusWarning  = Color(.systemOrange)

    // MARK: - Surface colors
    /// Use for color swatch borders — adapts correctly in light and dark mode
    static let swatchBorder   = Color(.systemGray4)
    /// Use as fallback fill when a filament hex color cannot be parsed
    static let swatchFallback = Color(.systemGray3)
}
