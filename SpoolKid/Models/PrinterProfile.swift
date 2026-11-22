//
//  PrinterProfile.swift
//  SpoolKid
//
//  Purpose: What the app knows about a printer. `PrinterProfile` is fixed fact
//  about a model, `PrinterStack` is the software detected on it, and
//  `PrinterCapabilities` is the table views read, as they read
//  `BackendCapabilities`: never the stack itself.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct PrinterProfile: Equatable, Sendable {
    let name: String
    let toolheadCount: Int
    let canLayerMix: Bool
    let hasToolheadTagReaders: Bool
    let readsColorAlpha: Bool
    /// Toolhead indexes in the order cards are laid out, row by row: the U1's
    /// spools are loaded T1, T3 over T2, T4 (owner, 2026-11-07).
    let cardOrder: [Int]
    /// What Set by Hand offers, and nothing else (owner, 2026-11-09: U1
    /// compatibility first). The U1 takes any name, but its firmware has load,
    /// unload and soft-feed settings only for these types (filament parameters
    /// 1.0.4, read 2026-11-09); any other name gets a generic 250 °C and is fed
    /// as a hard filament.
    let materials: [String]
    /// The subtypes the firmware names for each material, from any
    /// manufacturer in its table — offered for every manufacturer (owner,
    /// 2026-11-09). The U1 accepts them all; for a manufacturer it has no
    /// entry for, it falls back to that material's generic settings. No
    /// subtype is always fine.
    private let subtypesByMaterial: [String: [String]]

    init(
        name: String, toolheadCount: Int, canLayerMix: Bool, hasToolheadTagReaders: Bool,
        readsColorAlpha: Bool, cardOrder: [Int], materials: [String], subtypes: [String: [String]]
    ) {
        self.name = name
        self.toolheadCount = toolheadCount
        self.canLayerMix = canLayerMix
        self.hasToolheadTagReaders = hasToolheadTagReaders
        self.readsColorAlpha = readsColorAlpha
        self.cardOrder = cardOrder
        self.materials = materials
        self.subtypesByMaterial = subtypes
    }

    static let snapmakerU1 = PrinterProfile(
        name: "Snapmaker U1", toolheadCount: 4, canLayerMix: true,
        hasToolheadTagReaders: true, readsColorAlpha: true, cardOrder: [0, 2, 1, 3],
        materials: [
            "PLA", "PLA-CF", "PETG", "PETG-CF", "ABS", "ASA", "PC", "PC-ABS", "PA", "PA-CF", "PA-GF",
            "PA6-CF", "PA6-GF", "PAHT-CF", "TPU", "PEBA", "PVA"
        ],
        subtypes: [
            "PLA": [
                "Aero", "Basic", "Full Spectrum", "Glow", "Marble", "Matte", "PolyLite", "PolySonic",
                "PolyTerra", "Rainbow", "Silk", "SnapSpeed", "Starlight", "Support", "Translucent", "Wood"
            ],
            "PETG": ["HF", "PolyLite", "Translucent"],
            "ABS": ["PolyLite"],
            "TPU": ["90A", "95A HF"],
            "PEBA": ["90A"]
        ]
    )

    /// `name` as this printer spells it, or "" when it is not one of its
    /// materials — "NONE" (the firmware's empty toolhead), "PLA+" from a tag.
    func material(matching name: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespaces)
        return materials.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? ""
    }

    /// The subtypes Set by Hand offers for `material`, A–Z.
    func subtypes(for material: String) -> [String] {
        subtypesByMaterial[material] ?? []
    }

    /// `name` as this printer spells it for `material`, or "" when it is not
    /// one of that material's subtypes.
    func subtype(matching name: String?, material: String) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespaces)
        return subtypes(for: material).first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? ""
    }

    /// `toolheads` in card order. One the printer did not report is left out.
    func arranged(_ toolheads: [ToolheadState]) -> [ToolheadState] {
        cardOrder.compactMap { index in toolheads.first { $0.index == index } }
    }
}

nonisolated enum PrinterStack: Equatable, Sendable {
    case stock
    case extendedFirmware
    case bespok3d

    var label: String {
        switch self {
        case .stock: "Stock firmware"
        case .extendedFirmware: "Extended firmware"
        case .bespok3d: "Stock + Bespok3d"
        }
    }

    /// `software_version` names the extended firmware ("2.0.0-paxx12-24", read
    /// from a U1 2026-11-07), with or without Spoolman. Bespok3d runs on stock
    /// firmware and adds no Klipper object of its own (read from a U1 on stock
    /// 2.0.0.205, 2026-11-15): Moonraker's config lists its files under
    /// `bespok3d/`, and that decides it. AFC objects say nothing: the extended
    /// firmware has them too.
    static func detect(softwareVersion: String, objects: [String], configFiles: [String] = []) -> PrinterStack {
        if softwareVersion.lowercased().contains("paxx12") || objects.contains("spoollink") { return .extendedFirmware }
        if objects.contains("bespok3d_rfid") || configFiles.contains(where: { $0.hasPrefix("bespok3d/") }) {
            return .bespok3d
        }
        return .stock
    }
}

/// Which reader fills the toolheads on the extended firmware. Stated in
/// `extended/extended2.cfg` as `rfid:` under `[components]`.
nonisolated enum PrinterReaderMode: Equatable, Sendable {
    case builtIn
    case openRFID
    /// Toolhead readers off: an outside reader pushes tags to the printer.
    case external
    /// The config could not be read, or names a mode this app does not know.
    /// Warnings then assume a tag may be read.
    case unknown

    static func parse(extendedConfig text: String) -> PrinterReaderMode {
        var inComponents = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { continue }
            if line.hasPrefix("[") { inComponents = line.lowercased() == "[components]"; continue }
            guard inComponents, line.lowercased().hasPrefix("rfid:") else { continue }
            let value = line.dropFirst("rfid:".count).trimmingCharacters(in: .whitespaces).lowercased()
            switch value {
            case "snapmaker": return .builtIn
            case "openrfid", "openrfid-generic": return .openRFID
            case "external": return .external
            default: return .unknown
            }
        }
        // `snapmaker` is the firmware's default when the line is commented out.
        return .builtIn
    }
}

nonisolated struct PrinterCapabilities: Equatable, Sendable {
    let stack: PrinterStack
    /// Tag formats a toolhead reader decodes. Nil when the reader is unknown.
    let tagFormatsRead: Set<TagFormat>?
    /// Whether a spool id can be sent, so the printer tracks usage.
    let assignsSpoolID: Bool
    let canReRead: Bool
    let canClear: Bool

    static func of(_ stack: PrinterStack, readerMode: PrinterReaderMode, hasSpoolman: Bool) -> PrinterCapabilities {
        let formats: Set<TagFormat>? = switch (stack, readerMode) {
        case (.stock, _): []
        case (.extendedFirmware, .builtIn): [.openSpool]
        case (.extendedFirmware, .openRFID): [.openSpool, .openTag3D, .tigerTag, .anycubicACE, .elegoo]
        case (.extendedFirmware, .external), (.extendedFirmware, .unknown): nil
        case (.bespok3d, _): [.openSpool, .openTag3D, .tigerTag, .openPrintTag, .anycubicACE, .elegoo]
        }
        return PrinterCapabilities(
            stack: stack, tagFormatsRead: formats,
            assignsSpoolID: stack == .extendedFirmware && hasSpoolman,
            canReRead: true, canClear: true
        )
    }
}
