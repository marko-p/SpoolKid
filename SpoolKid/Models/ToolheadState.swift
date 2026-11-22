//
//  ToolheadState.swift
//  SpoolKid
//
//  Purpose: One toolhead as the printer sees it, built from the Moonraker
//  `print_task_config`, `filament_detect` and `print_stats` objects. Field
//  shapes were read from a U1 on 2.0.0-paxx12-24 (2026-11-07).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// What a toolhead's reader decoded from the tag.
nonisolated struct ToolheadTagData: Equatable, Sendable {
    var vendor: String?
    var material: String
    var subtype: String?
    var colorHexes: [String]
    var alpha: Int
    /// The rest are nil where the tag says 0 or nothing, as the U1's own
    /// tags do for weight and diameter.
    var hotendMinTemp: Int? = nil
    var hotendMaxTemp: Int? = nil
    var bedTemp: Int? = nil
    /// Grams.
    var weight: Double? = nil
    /// Millimetres; the firmware reports hundredths (175 = 1.75 mm).
    var diameter: Double? = nil

    /// Nil when the reader decoded no filament. `RGB_n` are integers, and
    /// `COLOR_NUMS` says how many mean anything.
    static func parse(_ info: [String: Any]?) -> ToolheadTagData? {
        guard let info, let material = ToolheadState.stated(info["MAIN_TYPE"]) else { return nil }
        let count = min(max(info["COLOR_NUMS"] as? Int ?? 1, 1), PrinterCommands.maxColors)
        let hexes = (1...count).compactMap { index in
            (info["RGB_\(index)"] as? Int).map { String(format: "%06X", $0 & 0xFFFFFF) }
        }
        return ToolheadTagData(
            vendor: ToolheadState.stated(info["VENDOR"]), material: material,
            subtype: ToolheadState.stated(info["SUB_TYPE"]), colorHexes: hexes,
            alpha: info["ALPHA"] as? Int ?? FilamentOpacity.opaque,
            hotendMinTemp: positive(info["HOTEND_MIN_TEMP"]),
            hotendMaxTemp: positive(info["HOTEND_MAX_TEMP"]),
            bedTemp: positive(info["BED_TEMP"]),
            weight: positive(info["WEIGHT"]).map(Double.init),
            diameter: positive(info["DIAMETER"]).map { Double($0) / 100 }
        )
    }

    private static func positive(_ value: Any?) -> Int? {
        (value as? Int).flatMap { $0 > 0 ? $0 : nil }
    }
}

nonisolated struct ToolheadState: Equatable, Identifiable, Sendable {
    enum Source: Equatable, Sendable {
        case empty, tag, spoolman, snapmaker, byHand

        var label: String? {
            switch self {
            case .empty: nil
            case .tag: "Tag"
            case .spoolman: "Spoolman"
            case .snapmaker: "Snapmaker"
            case .byHand: "Set by hand"
            }
        }
    }

    let index: Int
    var material: String?
    var vendor: String?
    var subtype: String?
    var colorHexes: [String]
    var alpha: Int
    /// `filament_exist`: filament is at the toolhead.
    var isLoaded: Bool
    var isOfficial: Bool
    /// `filament_spool_id`, nil for 0 or a stack without one.
    var spoolID: Int?
    var tagUID: String?
    var tagType: String?
    var tag: ToolheadTagData?

    init(
        index: Int, material: String? = nil, vendor: String? = nil, subtype: String? = nil,
        colorHexes: [String], alpha: Int, isLoaded: Bool, isOfficial: Bool,
        spoolID: Int? = nil, tagUID: String? = nil, tagType: String? = nil, tag: ToolheadTagData? = nil
    ) {
        self.index = index
        self.material = material
        self.vendor = vendor
        self.subtype = subtype
        self.colorHexes = colorHexes
        self.alpha = alpha
        self.isLoaded = isLoaded
        self.isOfficial = isOfficial
        self.spoolID = spoolID
        self.tagUID = tagUID
        self.tagType = tagType
        self.tag = tag
    }

    var id: Int { index }
    var name: String { "T\(index + 1)" }
    /// The printer holds filament data for this toolhead, loaded or not.
    var hasData: Bool { material != nil }

    var source: Source {
        guard hasData else { return .empty }
        if spoolID != nil { return .spoolman }
        if tagUID != nil { return .tag }
        return isOfficial ? .snapmaker : .byHand
    }

    var colors: FilamentColors { FilamentColors(hexes: colorHexes, pattern: .coextruded) }

    /// "NONE" is the firmware's empty value, and a blank is no value.
    static func stated(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces),
              !text.isEmpty, text.uppercased() != "NONE" else { return nil }
        return text
    }

    /// `CARD_UID` is an array of bytes on a read and 0 without one.
    static func uid(from value: Any?) -> String? {
        guard let bytes = value as? [Int], !bytes.isEmpty else { return nil }
        return SpoolMappingService.normalizeUID(bytes.map { String(format: "%02X", $0 & 0xFF) }.joined())
    }

    /// Nil only when the printer sent no `print_task_config` for this index.
    static func parse(index: Int, status: [String: [String: Any]]) -> ToolheadState? {
        guard let config = status["print_task_config"],
              let types = config["filament_type"] as? [Any], types.indices.contains(index) else { return nil }
        func at<T>(_ key: String, _ type: T.Type) -> T? {
            guard let list = config[key] as? [Any], list.indices.contains(index) else { return nil }
            return list[index] as? T
        }
        let multi = at("filament_color_multi", [String: Any].self)
        let material = stated(types[index])
        var hexes = (multi?["colors"] as? [String] ?? []).compactMap(FilamentColors.normalizedHex)
        if hexes.isEmpty, let rgba = at("filament_color_rgba", String.self) {
            hexes = FilamentColors.normalizedHex(rgba).map { [String($0.prefix(6))] } ?? []
        }
        let detected = ((status["filament_detect"]?["info"] as? [Any]) ?? []).dropFirst(index).first as? [String: Any]
        let spoolID = at("filament_spool_id", Int.self).flatMap { $0 > 0 ? $0 : nil }
        return ToolheadState(
            index: index,
            material: material,
            vendor: stated(at("filament_vendor", String.self)),
            subtype: stated(at("filament_sub_type", String.self)),
            colorHexes: material == nil ? [] : hexes,
            alpha: multi?["alpha"] as? Int ?? FilamentOpacity.opaque,
            isLoaded: at("filament_exist", Bool.self) ?? false,
            isOfficial: at("filament_official", Bool.self) ?? false,
            spoolID: spoolID,
            tagUID: uid(from: detected?["CARD_UID"]),
            tagType: stated(detected?["CARD_TYPE"]),
            tag: ToolheadTagData.parse(detected)
        )
    }
}

/// `print_stats.state` as far as the tab cares.
nonisolated enum PrinterActivity: Equatable, Sendable {
    case idle
    case printing(percent: Int?)
    case paused

    /// Every toolhead write is refused in these.
    var blocksWrites: Bool { self != .idle }

    var label: String {
        switch self {
        case .idle: "Idle"
        case .printing(let percent): percent.map { "Printing \($0)%" } ?? "Printing"
        case .paused: "Paused"
        }
    }

    static func parse(status: [String: [String: Any]]) -> PrinterActivity {
        switch status["print_stats"]?["state"] as? String {
        case "printing":
            let progress = status["virtual_sdcard"]?["progress"] as? Double
            return .printing(percent: progress.map { Int(($0 * 100).rounded()) })
        case "paused": return .paused
        default: return .idle
        }
    }
}
