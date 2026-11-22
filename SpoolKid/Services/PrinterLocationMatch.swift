//
//  PrinterLocationMatch.swift
//  SpoolKid
//
//  Purpose: The existing location a spool added from a printer tag goes to.
//  This flow never creates one: only a location whose whole name is the
//  printer's own name, or a word for "printer", fits (owner, 2026-11-11).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum PrinterLocationMatch {
    /// In the order they win; the list can grow.
    static let printerWords = [
        "Printer", "Snapmaker", "U1", "Drucker", "tiskalnik", "imprimante", "stampante",
        "impresora", "impressora", "drukarka", "tiskárna", "nyomtató"
    ]

    /// The location as it is spelled, or nil when none fits.
    static func location(in locations: [String], printerName: String) -> String? {
        for word in [printerName] + printerWords {
            let wanted = folded(word)
            guard !wanted.isEmpty else { continue }
            if let match = locations.first(where: { folded($0) == wanted }) { return match }
        }
        return nil
    }

    private static func folded(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
