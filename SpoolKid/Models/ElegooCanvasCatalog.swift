//
//  ElegooCanvasCatalog.swift
//  SpoolKid
//
//  Purpose: The filaments an ELEGOO Centauri Canvas knows, as page 19 of an
//  ELEGOO tag names them: byte 0 is the type index, byte 1 the subtype ID.
//
//  Evidence: PLA 0/0 is on every factory spool captured (five, 2026-05 and
//  2026-09); PLA 0/4 "PLA-CF" is on DnG-Crafts' dump (github.com/DnG-Crafts/
//  ELG-RFID). Every other pair is the table below, unverified on a printer
//  until a Canvas reads a tag SpoolKid wrote.
//
//  The table is transcribed from canvasspoolrfidprogrammer
//  (github.com/AnxiousDoorMat/canvasspoolrfidprogrammer, FilamentModel.swift),
//  gaps included, under its licence:
//
//    MIT License
//    Copyright (c) 2025 Martin (iOS Implementation)
//    Canvas format conversion and iOS adaptation: Matt Steuer, 2026
//
//    Permission is hereby granted, free of charge, to any person obtaining a
//    copy of this software and associated documentation files (the
//    "Software"), to deal in the Software without restriction, including
//    without limitation the rights to use, copy, modify, merge, publish,
//    distribute, sublicense, and/or sell copies of the Software, and to permit
//    persons to whom the Software is furnished to do so, subject to the
//    following conditions:
//
//    The above copyright notice and this permission notice shall be included
//    in all copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
//    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
//    NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
//    DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
//    OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
//    USE OR OTHER DEALINGS IN THE SOFTWARE.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum ElegooCanvasCatalog {

    nonisolated struct Entry: Equatable, Hashable, Identifiable, Sendable {
        let typeIndex: UInt8
        /// The type's name — what page 18 carries, in BCD-ASCII.
        let material: String
        let subtypeID: UInt8
        /// The Canvas's name for this filament.
        let name: String

        var id: String { "\(typeIndex)/\(subtypeID)" }
        /// The type's plain entry: "PLA", not "PLA Silk".
        var isBase: Bool { name == material }
    }

    /// What an entry looks like in `FilamentTagData`.
    nonisolated struct TagFields: Equatable, Sendable {
        let material: String
        let subtype: String?
    }

    static let entries: [Entry] = {
        let table: [(material: String, subtypes: [(UInt8, String)])] = [
            ("PLA", [(0, "PLA"), (1, "PLA+"), (2, "PLA PRO"), (3, "PLA Silk"), (4, "PLA-CF"),
                     (6, "PLA Matte"), (8, "PLA Wood"), (9, "PLA Basic"), (10, "RAPID PLA+"),
                     (11, "PLA Marble"), (12, "PLA Galaxy"), (13, "PLA Red Copper")]),
            ("PETG", [(0, "PETG"), (1, "PETG-CF"), (2, "PETG-GF"), (3, "PETG PRO"),
                      (4, "PETG Translucent"), (5, "RAPID PETG")]),
            ("ABS", [(0, "ABS")]),
            ("TPU", [(1, "TPU 95A"), (2, "RAPID TPU 95A")]),
            ("PA", [(0, "PAHT-CF")]),
            ("CPE", [(0, "CPE")]),
            ("PC", [(0, "PC"), (2, "PC-FR")]),
            ("PVA", [(0, "PVA")]),
            ("ASA", [(0, "ASA")]),
            ("BVOH", [(0, "BVOH")]),
            ("EVA", [(0, "EVA")]),
            ("HIPS", [(0, "HIPS")]),
            ("PP", [(0, "PP")]),
            ("PPA", [(0, "PPA")]),
            ("PPS", [(0, "PPS")])
        ]
        return table.enumerated().flatMap { typeIndex, type in
            type.subtypes.map { subtypeID, name in
                Entry(typeIndex: UInt8(typeIndex), material: type.material, subtypeID: subtypeID, name: name)
            }
        }
    }()

    static func entry(typeIndex: UInt8, subtypeID: UInt8) -> Entry? {
        entries.first { $0.typeIndex == typeIndex && $0.subtypeID == subtypeID }
    }

    static func tagFields(for entry: Entry) -> TagFields {
        TagFields(material: entry.material, subtype: entry.isBase ? nil : entry.name)
    }

    /// The exact inverse of `tagFields` — the only lookup the encoder uses, so
    /// nothing it writes is a guess.
    static func entry(forTagMaterial material: String, subtype: String?) -> Entry? {
        let subtype = subtype?.trimmingCharacters(in: .whitespaces) ?? ""
        return entries.first { entry in
            guard entry.material.caseInsensitiveCompare(material) == .orderedSame else { return false }
            return subtype.isEmpty
                ? entry.isBase
                : entry.name.caseInsensitiveCompare(subtype) == .orderedSame
        }
    }

    /// The write form's starting choice for a spool, nil when the Canvas has no
    /// equivalent material. Prefill only — the user sees and can change it.
    /// Ladder: exact tag fields → material (or alias) → subtype words within
    /// that type → the alias's preferred entry → the type's plain entry.
    static func suggestedEntry(material: String, subtype: String?) -> Entry? {
        if let exact = entry(forTagMaterial: material, subtype: subtype) { return exact }

        let trimmed = material.trimmingCharacters(in: .whitespaces)
        let alias = materialAliases.first { $0.key.caseInsensitiveCompare(trimmed) == .orderedSame }?.value
        let typeName = alias?.type ?? trimmed
        let typeEntries = entries.filter { $0.material.caseInsensitiveCompare(typeName) == .orderedSame }
        guard !typeEntries.isEmpty else { return nil }

        // "Basic" is SpoolKid's default subtype, so it means plain — the ID
        // every factory spool carries — not the Canvas's "PLA Basic".
        let isBasic = subtype?.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Basic") == .orderedSame
        let wanted = isBasic ? [] : tokens(of: subtype ?? "")
        if !wanted.isEmpty,
           let match = typeEntries.first(where: { wanted.isSubset(of: tokens(of: $0.name)) }) {
            return match
        }
        if let preferred = alias?.preferred, let match = typeEntries.first(where: { $0.name == preferred }) {
            return match
        }
        return typeEntries.first(where: \.isBase) ?? typeEntries.first
    }

    // MARK: - Suggestion helpers

    /// SpoolKid material names (`AppConfig.materialPresets`) that name a Canvas
    /// type differently.
    private static let materialAliases: [String: (type: String, preferred: String?)] = [
        "PLA+": ("PLA", "PLA+"),
        "Flexible (TPU)": ("TPU", nil),
        "Polycarbonate (PC)": ("PC", nil),
        "Polypropylene (PP)": ("PP", nil)
    ]

    /// Lowercased words of a name, split on spaces and hyphens, with SpoolKid's
    /// "Carbon Fiber" spelled the Canvas's way: "PLA-CF" is {pla, cf}.
    private static func tokens(of name: String) -> Set<String> {
        let spelled = name.lowercased().replacingOccurrences(of: "carbon fiber", with: "cf")
        return Set(spelled.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init))
    }
}
