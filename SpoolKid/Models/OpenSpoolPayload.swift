//
//  OpenSpoolPayload.swift
//  SpoolKid
//
//  matches the OpenSpool NFC tag specification.
//  Example:
//  {
//      "protocol": "openspool",
//      "version": "1.0",
//      "type": "ASA",
//      "color_hex": "161616",
//      "brand": "AzureFilm",
//      "min_temp": "240",
//      "max_temp": "260",
//      "bed_min_temp": "90",
//      "bed_max_temp": "120"
//  }
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

struct OpenSpoolPayload: Codable, Sendable {
    // Protocol metadata
    let `protocol`: String = "openspool"
    let version: String = "1.0"
    
    // Filament Data
    let type: String
    let subtype: String?
    let brand: String
    let colorHex: String
    /// Colors after `color_hex`, at most four (five colors with the primary).
    let additionalColorHexes: [String]?
    /// Not in the OpenSpool spec. Two-digit hex like `color_hex`, absent when
    /// opaque. Never a JSON number: OpenRFID rejects the whole tag for one.
    let alpha: String?
    
    // Temperatures: SpoolKid writes strings. Only protocol, version, type and
    // color_hex are required, and other writers leave these off or write
    // numbers, so a read accepts either and an absent one stays nil.
    let minTemp: String?
    let maxTemp: String?
    let bedMinTemp: String?
    let bedMaxTemp: String?
    
    // Optional Extended Data (SpoolKid specifics)
    let spoolId: Int?
    let name: String?
    
    enum CodingKeys: String, CodingKey {
        case `protocol`
        case version
        case type
        case subtype
        case brand
        case colorHex = "color_hex"
        case additionalColorHexes = "additional_color_hexes"
        case alpha
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
        self.subtype = data.subtype
        self.brand = data.brand
        self.colorHex = data.colorHex
        let extras = data.extraColorsRGB(maxTotal: TagFormat.openSpool.maxColors)
        self.additionalColorHexes = extras.isEmpty ? nil : extras
        self.alpha = data.writtenAlphaByte == 0xFF ? nil : String(format: "%02X", data.writtenAlphaByte)
        self.minTemp = String(data.minNozzleTemp)
        self.maxTemp = String(data.maxNozzleTemp)
        self.bedMinTemp = String(data.minBedTemp)
        self.bedMaxTemp = String(data.maxBedTemp)
        self.spoolId = data.spoolmanId
        self.name = data.name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(String.self, forKey: .type)
        self.subtype = try container.decodeIfPresent(String.self, forKey: .subtype)
        self.brand = try container.decodeIfPresent(String.self, forKey: .brand) ?? AppConfig.Defaults.brand
        self.colorHex = try container.decode(String.self, forKey: .colorHex)
        self.additionalColorHexes = Self.additionalColors(in: container)
        self.alpha = Self.alphaText(in: container)
        self.minTemp = Self.temperature(in: container, .minTemp)
        self.maxTemp = Self.temperature(in: container, .maxTemp)
        self.bedMinTemp = Self.temperature(in: container, .bedMinTemp)
        self.bedMaxTemp = Self.temperature(in: container, .bedMaxTemp)
        self.spoolId = try container.decodeIfPresent(Int.self, forKey: .spoolId)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
    }

    /// Lenient: a value that is not an array of hex strings, or a junk entry,
    /// reads as absent. Four at most are used.
    private static func additionalColors(in container: KeyedDecodingContainer<CodingKeys>) -> [String]? {
        guard let raw = try? container.decodeIfPresent([LossyHex].self, forKey: .additionalColorHexes) else { return nil }
        let valid = Array(raw.compactMap { $0.text.flatMap(FilamentColors.normalizedHex) }.prefix(4))
        return valid.isEmpty ? nil : valid
    }

    /// One array entry: its string, or nil when the entry is not a string.
    /// Decoding entries one by one keeps a junk entry from voiding the rest.
    private nonisolated struct LossyHex: Decodable {
        let text: String?

        init(from decoder: Decoder) throws {
            text = try? decoder.singleValueContainer().decode(String.self)
        }
    }

    /// Readers disagree on the form, so a read takes what writers produce: a
    /// short string is hex, a three-digit string or a number decimal. Anything
    /// else reads as absent, and never fails the tag.
    private static func alphaText(in container: KeyedDecodingContainer<CodingKeys>) -> String? {
        let value: Int?
        if let number = try? container.decodeIfPresent(Int.self, forKey: .alpha) {
            value = number
        } else if let text = try? container.decodeIfPresent(String.self, forKey: .alpha) {
            value = Int(text, radix: text.count <= 2 ? 16 : 10)
        } else {
            value = nil
        }
        return value.flatMap(FilamentOpacity.stated(alpha:)).map { String(format: "%02X", $0) }
    }

    /// "190" or 190; anything else reads as absent.
    private static func temperature(in container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let text = try? container.decodeIfPresent(String.self, forKey: key) { return text }
        if let number = try? container.decodeIfPresent(Int.self, forKey: key) { return String(number) }
        return nil
    }

    /// One stated end stands for both; nil when neither end is a number.
    private static func range(_ low: String?, _ high: String?) -> (min: Int, max: Int)? {
        let min = low.flatMap { Int($0) }
        let max = high.flatMap { Int($0) }
        guard let lower = min ?? max, let upper = max ?? min else { return nil }
        return (lower, upper)
    }

    // Convert to internal model
    func toFilamentTagData() -> FilamentTagData {
        let nozzle = Self.range(minTemp, maxTemp)
        let bed = Self.range(bedMinTemp, bedMaxTemp)
        var data = FilamentTagData(
            id: UUID(), // Generate new local ID
            name: self.name,
            material: self.type,
            subtype: self.subtype,
            brand: self.brand,
            colorHex: self.colorHex,
            additionalColorHexes: self.additionalColorHexes,
            minNozzleTemp: nozzle?.min ?? 200, // Placeholders for the write form
            maxNozzleTemp: nozzle?.max ?? 220,
            minBedTemp: bed?.min ?? 60,
            maxBedTemp: bed?.max ?? 80,
            spoolmanId: self.spoolId,
            colorAlpha: self.alpha.flatMap { Int($0, radix: 16) }
        )
        data.nozzleTempsStated = nozzle != nil
        data.bedTempsStated = bed != nil
        return data
    }
}
