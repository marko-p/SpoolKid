//
//  ToolheadMismatch.swift
//  SpoolKid
//
//  Purpose: Whether a toolhead's tag and its Library spool disagree, and
//  which of the two the printer is using. The tag and the Library are the
//  sources; the printer holds what one of them (or a hand entry) gave it.
//  Subtype is left out: SpoolLink blanks it when it resolves a tag (U1,
//  2026-11-07), so comparing it would flag every resolved spool.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

struct ToolheadMismatch: Equatable {
    var printerMatchesTag: Bool
    /// Nil without a Library spool.
    var printerMatchesLibrary: Bool?
    /// Nil without a Library spool.
    var libraryMatchesTag: Bool?

    var printerUsesNeither: Bool { !printerMatchesTag && printerMatchesLibrary != true }

    var title: String {
        libraryMatchesTag == false ? "Tag and Library Don't Match" : "Printer Doesn't Match the Tag"
    }

    var message: String {
        if printerMatchesTag { return "The printer is using the tag. The Library spool says otherwise." }
        if printerMatchesLibrary == true { return "The printer is using the Library spool. The tag says otherwise." }
        switch libraryMatchesTag {
        case nil: return "The printer isn't using the tag's data."
        case true?: return "The printer isn't using the tag or the Library spool."
        case false?: return "The tag, the Library and the printer all differ."
        }
    }

    /// Whether the iPhone can write the toolhead's tag. The U1 can't write
    /// tags (2.0.0-paxx12-24 has read, clear and query only), and the iPhone
    /// can't write MIFARE Classic, so only a tag the U1 reports as "NTAG".
    nonisolated static func phoneWritesTag(tagType: String?) -> Bool {
        tagType?.uppercased() == "NTAG"
    }

    private static func same(_ a: String?, _ b: String?) -> Bool {
        (a ?? "").caseInsensitiveCompare(b ?? "") == .orderedSame
    }

    private static func sameColors(_ a: [String], _ b: [String]) -> Bool {
        a.map { $0.uppercased() } == b.map { $0.uppercased() }
    }

    /// Nil without a tag, or when everything agrees.
    static func of(_ toolhead: ToolheadState, spool: Spool?) -> ToolheadMismatch? {
        guard let tag = toolhead.tag else { return nil }
        let printerMatchesTag = same(tag.material, toolhead.material) && sameColors(tag.colorHexes, toolhead.colorHexes)
        var mismatch = ToolheadMismatch(printerMatchesTag: printerMatchesTag)
        if let spool {
            let library = FilamentTagData.from(spool: spool)
            let libraryColors = library.trimmedColors(max: PrinterCommands.maxColors)
            mismatch.printerMatchesLibrary = same(library.material, toolhead.material)
                && sameColors(libraryColors, toolhead.colorHexes)
            mismatch.libraryMatchesTag = same(tag.material, library.material) && sameColors(tag.colorHexes, libraryColors)
        }
        return mismatch.printerMatchesTag && mismatch.libraryMatchesTag != false ? nil : mismatch
    }
}

/// Update Library from Tag: the tag's material and colors over the Library
/// spool's filament, which every spool of that filament shares.
struct FilamentCorrection: Equatable {
    var material: String
    var colorHexes: [String]
    /// Other spools of the filament, which change with it.
    var otherSpools: Int

    var note: String? {
        switch otherSpools {
        case 0: nil
        case 1: "Also changes 1 other spool of this filament."
        default: "Also changes \(otherSpools) other spools of this filament."
        }
    }

    static func from(tag: ToolheadTagData, spool: Spool, spools: [Spool]) -> FilamentCorrection {
        FilamentCorrection(
            material: tag.material,
            colorHexes: tag.colorHexes,
            otherSpools: spools.filter { $0.filament.id == spool.filament.id && $0.id != spool.id }.count
        )
    }
}
