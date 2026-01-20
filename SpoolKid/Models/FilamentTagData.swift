//
//  FilamentTagData.swift
//  SpoolKid
//
//  Purpose: The data model representing the information stored on the NFC tag.
//  Notes:
//  - Conforms to `Codable` for easy JSON serialization/deserialization to the tag.
//  - `spoolmanId` is optional; if nil, it is omitted from the JSON (saving bytes).
//  - `id` is a local UUID for UI lists and is NOT written to the tag.
//

import Foundation

struct FilamentTagData: Codable, Identifiable, Sendable {
    var id: UUID? = UUID() // Local ID for list identification, not encoded to tag
    var name: String? // Filament Name
    var material: String
    var brand: String
    var colorHex: String
    var minNozzleTemp: Int
    var maxNozzleTemp: Int
    var minBedTemp: Int
    var maxBedTemp: Int
    var spoolmanId: Int?
    
    enum CodingKeys: String, CodingKey {
        case name
        case material
        case brand
        case colorHex = "color_hex"
        case minNozzleTemp = "min_nozzle_temp"
        case maxNozzleTemp = "max_nozzle_temp"
        case minBedTemp = "min_bed_temp"
        case maxBedTemp = "max_bed_temp"
        case spoolmanId = "spool_id"
    }
}
