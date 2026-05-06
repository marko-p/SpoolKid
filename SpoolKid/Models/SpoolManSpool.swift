//
//  SpoolmanSpool.swift
//  SpoolKid
//
//  Purpose: Data models reflecting the JSON structure returned by the Spoolman API.
//  Contains:
//  - `SpoolmanSpool`: Represents a physical spool instance.
//  - `SpoolmanFilament`: Represents a filament definition (type, color, vendor).
//  - `SpoolmanVendor`: Represents a manufacturer.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import Foundation

struct SpoolmanSpool: Codable, Identifiable, Sendable {
    let id: Int
    let filament: SpoolmanFilament
    let remainingWeight: Double?
    let initialWeight: Double?
    let spoolWeight: Double?
    let usedWeight: Double?
    let price: Double?
    /// Firmware-compatible UID mapping field. Format: `card_uid:XXX[,card_uid:YYY]`
    /// Managed by `SpoolMappingService`. Nil when not set or not returned by Spoolman.
    let lotNr: String?

    enum CodingKeys: String, CodingKey {
        case id
        case filament
        case remainingWeight = "remaining_weight"
        case initialWeight = "initial_weight"
        case spoolWeight = "spool_weight"
        case usedWeight = "used_weight"
        case price
        case lotNr = "lot_nr"
    }
}

struct SpoolmanFilament: Codable, Identifiable, Sendable {
    let id: Int
    let name: String?
    let material: String?
    let vendor: SpoolmanVendor?
    let colorHex: String?
    let density: Double?
    let diameter: Double?
    let settingsExtruderTemp: Int?
    let settingsBedTemp: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case material
        case vendor
        case colorHex = "color_hex"
        case density
        case diameter
        case settingsExtruderTemp = "settings_extruder_temp"
        case settingsBedTemp = "settings_bed_temp"
    }
}

struct SpoolmanVendor: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
}
