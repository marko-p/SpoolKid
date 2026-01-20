//
//  OpenSpoolPayload.swift
//  SpoolKid
//
//  matches the OpenSpool NFC tag specification.
//

import Foundation

struct OpenSpoolPayload: Codable {
    // Protocol metadata
    let `protocol`: String = "openspool"
    let version: String = "1.0"
    
    // Filament Data
    let type: String
    let brand: String
    let colorHex: String
    
    // Temperatures (Strings in OpenSpool spec)
    let minTemp: String
    let maxTemp: String
    let bedMinTemp: String
    let bedMaxTemp: String
    
    // Optional Extended Data (SpoolKid specifics)
    let spoolId: Int?
    let name: String?
    
    enum CodingKeys: String, CodingKey {
        case `protocol`
        case version
        case type
        case brand
        case colorHex = "color_hex"
        case minTemp = "min_temp"
        case maxTemp = "max_temp"
        case bedMinTemp = "bed_min_temp"
        case bedMaxTemp = "bed_max_temp"
        case spoolId = "spool_id"
        case name
    }
    
    // Convert from internal model
    init(from data: FilamentTagData) {
        self.type = data.material
        self.brand = data.brand
        self.colorHex = data.colorHex
        self.minTemp = String(data.minNozzleTemp)
        self.maxTemp = String(data.maxNozzleTemp)
        self.bedMinTemp = String(data.minBedTemp)
        self.bedMaxTemp = String(data.maxBedTemp)
        self.spoolId = data.spoolmanId
        self.name = data.name
    }
    
    // Convert to internal model
    func toFilamentTagData() -> FilamentTagData {
        return FilamentTagData(
            id: UUID(), // Generate new local ID
            name: self.name,
            material: self.type,
            brand: self.brand,
            colorHex: self.colorHex,
            minNozzleTemp: Int(self.minTemp) ?? 200, // Fallbacks
            maxNozzleTemp: Int(self.maxTemp) ?? 220,
            minBedTemp: Int(self.bedMinTemp) ?? 60,
            maxBedTemp: Int(self.bedMaxTemp) ?? 80,
            spoolmanId: self.spoolId
        )
    }
}
