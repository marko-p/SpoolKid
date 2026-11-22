//
//  PrinterCommands.swift
//  SpoolKid
//
//  Purpose: The G-code SpoolKid sends a toolhead, and the check that the
//  printer took it. `SET_PRINT_FILAMENT_CONFIG` is used on every stack, never
//  `SET_SPOOL_ID`: on the extended firmware that one marks the toolhead
//  official, and loading an untagged spool then wipes it (spec, owner decision 4).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// What a toolhead is told to hold.
nonisolated struct ToolheadAssignment: Codable, Equatable, Sendable {
    var vendor: String
    var material: String
    var subtype: String
    var colorHexes: [String]
    var alpha: Int
    /// Sent only where the printer's Spoolman is the app's. 0 drops the
    /// toolhead's spool id; nil leaves the parameter out, which stock needs.
    var spoolID: Int?

    /// Use Tag Data: the tag's filament, keeping the spool the toolhead tracks.
    init(tag: ToolheadTagData, keepingSpoolID spoolID: Int?) {
        vendor = tag.vendor ?? "Generic"
        material = tag.material
        subtype = tag.subtype ?? ""
        colorHexes = tag.colorHexes
        alpha = tag.alpha
        self.spoolID = spoolID
    }

    private init(vendor: String, material: String, subtype: String, colorHexes: [String], alpha: Int, spoolID: Int?) {
        self.vendor = vendor
        self.material = material
        self.subtype = subtype
        self.colorHexes = colorHexes
        self.alpha = alpha
        self.spoolID = spoolID
    }

    /// Set by Hand. Nil until there is a material and a valid color. A hand
    /// entry is no longer that spool, so a spool id on the toolhead is dropped.
    static func byHand(
        material: String, vendor: String, subtype: String, colorHexes: [String],
        opacityPercent: Double, replacing toolhead: ToolheadState
    ) -> ToolheadAssignment? {
        let material = PrinterCommands.sanitized(material)
        let colors = Array(colorHexes.compactMap(FilamentColors.normalizedHex).map { String($0.prefix(6)) }
            .prefix(PrinterCommands.maxColors))
        guard !material.isEmpty, !colors.isEmpty else { return nil }
        let vendor = PrinterCommands.sanitized(vendor)
        return ToolheadAssignment(
            vendor: vendor.isEmpty ? "Generic" : vendor, material: material, subtype: subtype,
            colorHexes: colors, alpha: alpha(opacityPercent: opacityPercent),
            spoolID: toolhead.spoolID == nil ? nil : 0
        )
    }

    static func alpha(opacityPercent: Double) -> Int {
        Int((min(max(opacityPercent, 1), 100) / 100 * Double(FilamentOpacity.opaque)).rounded())
    }

    static func opacityPercent(alpha: Int) -> Double {
        (Double(alpha) / Double(FilamentOpacity.opaque) * 100).rounded()
    }

    @MainActor init(spool: Spool, sendsSpoolID: Bool) {
        let data = FilamentTagData.from(spool: spool)
        vendor = data.brand
        material = data.material
        subtype = data.subtype ?? ""
        colorHexes = data.trimmedColors(max: PrinterCommands.maxColors)
        alpha = FilamentOpacity.alpha(forTD: data.transmissionDistance)
        spoolID = sendsSpoolID ? spool.id : nil
    }
}

nonisolated enum PrinterCommands {
    static let maxColors = 5

    /// Klipper ends a command's arguments at `;`, `#` or `*`, even inside
    /// quotes, and a `"` or a line break would end the value early. Filament
    /// names are other people's text, so none of these may reach the printer.
    static func sanitized(_ text: String) -> String {
        let dropped = CharacterSet(charactersIn: "\";#*\\").union(.newlines).union(.controlCharacters)
        return String(text.unicodeScalars.filter { !dropped.contains($0) })
            .trimmingCharacters(in: .whitespaces)
    }

    static func assign(_ assignment: ToolheadAssignment, toolhead: Int, force: Bool) -> String {
        var parts = [
            "SET_PRINT_FILAMENT_CONFIG",
            "CONFIG_EXTRUDER=\(toolhead)",
            "VENDOR=\"\(sanitized(assignment.vendor))\"",
            "FILAMENT_TYPE=\"\(sanitized(assignment.material))\"",
            "FILAMENT_SUBTYPE=\"\(sanitized(assignment.subtype))\"",
            "COLOR_NUMS=\(assignment.colorHexes.count)",
            "COLORS=\(assignment.colorHexes.joined(separator: ","))",
            "MULTI_MODE=0",
            "ALPHA=\(assignment.alpha)"
        ]
        if let id = assignment.spoolID { parts.append("FILAMENT_SPOOL_ID=\(id)") }
        if force { parts.append("FORCE=1") }
        return parts.joined(separator: " ")
    }

    /// The firmware refuses to change an official toolhead, or one with a
    /// spool id when the command names none, unless it is forced.
    static func needsForce(_ toolhead: ToolheadState) -> Bool {
        toolhead.isOfficial || toolhead.spoolID != nil
    }

    /// Klipper's name for a toolhead: channel 0 is `extruder`, N is `extruderN`.
    static func extruderName(toolhead: Int) -> String {
        toolhead == 0 ? "extruder" : "extruder\(toolhead)"
    }

    /// FilaMan's Moonraker component assigns a spool per toolhead here
    /// (from its README; GPLv3, clean-room).
    static func filamanSpoolPath(toolhead: Int, spoolID: Int) -> String {
        "/server/filaman/spool_id?extruder=\(extruderName(toolhead: toolhead))&spool_id=\(spoolID)"
    }

    static func reRead(toolhead: Int) -> String { "FILAMENT_DT_UPDATE CHANNEL=\(toolhead)" }

    static func clear(toolhead: Int) -> String { "FILAMENT_DT_CLEAR CHANNEL=\(toolhead)" }

    /// Whether the toolhead read back shows what was sent. A write is not done
    /// until this says so.
    static func confirms(_ assignment: ToolheadAssignment, state: ToolheadState) -> Bool {
        func same(_ a: String?, _ b: String) -> Bool {
            (a ?? "").caseInsensitiveCompare(sanitized(b)) == .orderedSame
        }
        return same(state.material, assignment.material)
            && same(state.vendor, assignment.vendor)
            && state.colorHexes.map { $0.uppercased() } == assignment.colorHexes.map { $0.uppercased() }
            && spoolIDMatches(assignment.spoolID, state.spoolID)
    }

    private static func spoolIDMatches(_ sent: Int?, _ shown: Int?) -> Bool {
        guard let sent else { return true }
        return sent == 0 ? shown == nil : sent == shown
    }
}
