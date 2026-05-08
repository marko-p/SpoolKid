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

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import Foundation

struct FilamentTagData: Codable, Identifiable, Sendable {
    var id: UUID? = UUID() // Local ID for list identification, not encoded to tag
    var name: String? // Filament Name
    var material: String
    var subtype: String? // Material Variant (e.g., Basic, Rapid, Silk, HF)
    var brand: String
    var colorHex: String
    var minNozzleTemp: Int
    var maxNozzleTemp: Int
    var minBedTemp: Int
    var maxBedTemp: Int
    var spoolmanId: Int?
    var density: Double?
    var openPrintTagMaterialTypeID: Int?
    var transmissionDistance: Double?
    var gtin: String?
    var manufacturedDateUnix: Int?
    var countryOfOrigin: String?
    var preheatTemp: Int?
    var dryingTemp: Int?
    var dryingTime: Int?
    var nominalNetWeight: Double?
    var actualNetWeight: Double?
    var emptyContainerWeight: Double?
    var materialTags: [Int]?
    var certifications: [Int]?
    var tagURL: String?

    init(
        id: UUID? = UUID(),
        name: String? = nil,
        material: String,
        subtype: String? = nil,
        brand: String,
        colorHex: String,
        minNozzleTemp: Int,
        maxNozzleTemp: Int,
        minBedTemp: Int,
        maxBedTemp: Int,
        spoolmanId: Int? = nil,
        density: Double? = nil,
        openPrintTagMaterialTypeID: Int? = nil,
        transmissionDistance: Double? = nil,
        gtin: String? = nil,
        manufacturedDateUnix: Int? = nil,
        countryOfOrigin: String? = nil,
        preheatTemp: Int? = nil,
        dryingTemp: Int? = nil,
        dryingTime: Int? = nil,
        nominalNetWeight: Double? = nil,
        actualNetWeight: Double? = nil,
        emptyContainerWeight: Double? = nil,
        materialTags: [Int]? = nil,
        certifications: [Int]? = nil,
        tagURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.material = material
        self.subtype = subtype
        self.brand = brand
        self.colorHex = colorHex
        self.minNozzleTemp = minNozzleTemp
        self.maxNozzleTemp = maxNozzleTemp
        self.minBedTemp = minBedTemp
        self.maxBedTemp = maxBedTemp
        self.spoolmanId = spoolmanId
        self.density = density
        self.openPrintTagMaterialTypeID = openPrintTagMaterialTypeID
        self.transmissionDistance = transmissionDistance
        self.gtin = gtin
        self.manufacturedDateUnix = manufacturedDateUnix
        self.countryOfOrigin = countryOfOrigin
        self.preheatTemp = preheatTemp
        self.dryingTemp = dryingTemp
        self.dryingTime = dryingTime
        self.nominalNetWeight = nominalNetWeight
        self.actualNetWeight = actualNetWeight
        self.emptyContainerWeight = emptyContainerWeight
        self.materialTags = materialTags
        self.certifications = certifications
        self.tagURL = tagURL
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case material
        case subtype
        case brand
        case colorHex = "color_hex"
        case minNozzleTemp = "min_nozzle_temp"
        case maxNozzleTemp = "max_nozzle_temp"
        case minBedTemp = "min_bed_temp"
        case maxBedTemp = "max_bed_temp"
        case spoolmanId = "spool_id"
        case density
        case openPrintTagMaterialTypeID = "openprinttag_material_type_id"
        case transmissionDistance = "transmission_distance"
        case gtin
        case manufacturedDateUnix = "manufactured_date"
        case countryOfOrigin = "country_of_origin"
        case preheatTemp = "preheat_temperature"
        case dryingTemp = "drying_temperature"
        case dryingTime = "drying_time"
        case nominalNetWeight = "nominal_netto_full_weight"
        case actualNetWeight = "actual_netto_full_weight"
        case emptyContainerWeight = "empty_container_weight"
        case materialTags = "material_tags"
        case certifications
        case tagURL = "tag_url"
    }
    
    // MARK: - Validation
    
    /// Validation errors that can occur before writing a tag.
    enum ValidationError: LocalizedError {
        case emptyMaterial
        case emptyBrand
        case invalidColorHex
        case nozzleTempInverted      // min > max
        case bedTempInverted          // min > max
        case nozzleTempOutOfRange     // outside 0-500°C
        case bedTempOutOfRange        // outside 0-200°C
        
        var errorDescription: String? {
            switch self {
            case .emptyMaterial:        return "Material type is required."
            case .emptyBrand:           return "Brand name is required."
            case .invalidColorHex:      return "Color hex must be a valid 6-character hex code (e.g. FF0000)."
            case .nozzleTempInverted:   return "Min nozzle temp cannot be higher than max nozzle temp."
            case .bedTempInverted:      return "Min bed temp cannot be higher than max bed temp."
            case .nozzleTempOutOfRange: return "Nozzle temperatures must be between 0 and 500°C."
            case .bedTempOutOfRange:    return "Bed temperatures must be between 0 and 200°C."
            }
        }
    }
    
    /// Validates the data for writing to an NFC tag.
    /// Returns nil if valid, or a `ValidationError` describing the first problem found.
    func validate() -> ValidationError? {
        if material.trimmingCharacters(in: .whitespaces).isEmpty {
            return .emptyMaterial
        }
        if brand.trimmingCharacters(in: .whitespaces).isEmpty {
            return .emptyBrand
        }
        // Validate hex: must be 3 or 6 hex characters (after stripping #)
        let cleanHex = colorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespaces)
        let hexChars = CharacterSet(charactersIn: "0123456789ABCDEFabcdef")
        if cleanHex.isEmpty || cleanHex.unicodeScalars.contains(where: { !hexChars.contains($0) }) || (cleanHex.count != 3 && cleanHex.count != 6) {
            return .invalidColorHex
        }
        if minNozzleTemp < 0 || maxNozzleTemp < 0 || minNozzleTemp > 500 || maxNozzleTemp > 500 {
            return .nozzleTempOutOfRange
        }
        if minBedTemp < 0 || maxBedTemp < 0 || minBedTemp > 200 || maxBedTemp > 200 {
            return .bedTempOutOfRange
        }
        if minNozzleTemp > maxNozzleTemp {
            return .nozzleTempInverted
        }
        if minBedTemp > maxBedTemp {
            return .bedTempInverted
        }
        return nil
    }
    
    /// Returns a sanitized copy with temperatures clamped to reasonable ranges.
    /// Use this when decoding from potentially corrupted tags.
    func clamped() -> FilamentTagData {
        var copy = self
        copy.minNozzleTemp = max(0, min(500, copy.minNozzleTemp))
        copy.maxNozzleTemp = max(0, min(500, copy.maxNozzleTemp))
        copy.minBedTemp = max(0, min(200, copy.minBedTemp))
        copy.maxBedTemp = max(0, min(200, copy.maxBedTemp))
        // Ensure min <= max
        if copy.minNozzleTemp > copy.maxNozzleTemp {
            swap(&copy.minNozzleTemp, &copy.maxNozzleTemp)
        }
        if copy.minBedTemp > copy.maxBedTemp {
            swap(&copy.minBedTemp, &copy.maxBedTemp)
        }
        return copy
    }
}
