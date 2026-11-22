//
//  MaterialPairing.swift
//  SpoolKid
//
//  Purpose: A material's base: "PLA+", "PLA Silk" and "PLA-CF" are PLA.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum MaterialPairing {
    /// PLA with any variant is one base: "PLA+", "PLA Silk" and "PLA-CF" are PLA.
    static func baseMaterial(_ material: String) -> String {
        let upper = material.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let end = upper.firstIndex { !$0.isLetter && !$0.isNumber } ?? upper.endIndex
        return String(upper[..<end])
    }
}
