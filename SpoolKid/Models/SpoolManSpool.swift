//
//  SpoolManSpool.swift
//  SpoolKid
//
//  Purpose: Data models reflecting the JSON structure returned by the Spoolman API.
//  Contains:
//  - `SpoolManSpool`: Represents a physical spool instance.
//  - `SpoolManFilament`: Represents a filament definition (type, color, vendor).
//  - `SpoolManVendor`: Represents a manufacturer.
//

import Foundation

struct SpoolManSpool: Codable, Identifiable {
    let id: Int
    let filament: SpoolManFilament
    let remainingWeight: Double?
    let initialWeight: Double?
    let spoolWeight: Double?
    let usedWeight: Double?
    let price: Double?
    
    enum CodingKeys: String, CodingKey {
        case id
        case filament
        case remainingWeight = "remaining_weight"
        case initialWeight = "initial_weight"
        case spoolWeight = "spool_weight"
        case usedWeight = "used_weight"
        case price
    }
}

struct SpoolManFilament: Codable, Identifiable {
    let id: Int
    let name: String?
    let material: String?
    let vendor: SpoolManVendor?
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

struct SpoolManVendor: Codable, Identifiable {
    let id: Int
    let name: String
}
