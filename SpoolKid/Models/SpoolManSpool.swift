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
    let firstUsed: Date?
    let lastUsed: Date?
    let remainingWeight: Double?
    let initialWeight: Double?
    let spoolWeight: Double?
    let usedWeight: Double?
    let price: Double?
    let location: String?
    /// Firmware-compatible UID mapping field. Format: `card_uid:XXX[,card_uid:YYY]`
    /// Managed by `SpoolMappingService`. Nil when not set or not returned by Spoolman.
    let lotNr: String?
    let comment: String?
    let archived: Bool?
    let extra: [String: String]?

    init(
        id: Int,
        filament: SpoolmanFilament,
        firstUsed: Date? = nil,
        lastUsed: Date? = nil,
        remainingWeight: Double? = nil,
        initialWeight: Double? = nil,
        spoolWeight: Double? = nil,
        usedWeight: Double? = nil,
        price: Double? = nil,
        location: String? = nil,
        lotNr: String? = nil,
        comment: String? = nil,
        archived: Bool? = nil,
        extra: [String: String]? = nil
    ) {
        self.id = id
        self.filament = filament
        self.firstUsed = firstUsed
        self.lastUsed = lastUsed
        self.remainingWeight = remainingWeight
        self.initialWeight = initialWeight
        self.spoolWeight = spoolWeight
        self.usedWeight = usedWeight
        self.price = price
        self.location = location
        self.lotNr = lotNr
        self.comment = comment
        self.archived = archived
        self.extra = extra
    }

    enum CodingKeys: String, CodingKey {
        case id
        case filament
        case firstUsed = "first_used"
        case lastUsed = "last_used"
        case remainingWeight = "remaining_weight"
        case initialWeight = "initial_weight"
        case spoolWeight = "spool_weight"
        case usedWeight = "used_weight"
        case price
        case location
        case lotNr = "lot_nr"
        case comment
        case archived
        case extra
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        filament = try container.decode(SpoolmanFilament.self, forKey: .filament)
        firstUsed = try container.decodeFlexibleDateIfPresent(forKey: .firstUsed)
        lastUsed = try container.decodeFlexibleDateIfPresent(forKey: .lastUsed)
        remainingWeight = try container.decodeIfPresent(Double.self, forKey: .remainingWeight)
        initialWeight = try container.decodeIfPresent(Double.self, forKey: .initialWeight)
        spoolWeight = try container.decodeIfPresent(Double.self, forKey: .spoolWeight)
        usedWeight = try container.decodeIfPresent(Double.self, forKey: .usedWeight)
        price = try container.decodeIfPresent(Double.self, forKey: .price)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        lotNr = try container.decodeIfPresent(String.self, forKey: .lotNr)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived)
        extra = try container.decodeIfPresent([String: String].self, forKey: .extra)
    }
}

private extension KeyedDecodingContainer where K == SpoolmanSpool.CodingKeys {
    func decodeFlexibleDateIfPresent(forKey key: K) throws -> Date? {
        guard contains(key) else {
            return nil
        }

        if try decodeNil(forKey: key) {
            return nil
        }

        if let secondsSince1970 = try? decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: secondsSince1970)
        }

        let value: String
        do {
            value = try decode(String.self, forKey: key)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Expected date to be a Unix timestamp or ISO8601 string."
            )
        }

        if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: value) {
            return date
        }

        if let date = ISO8601DateFormatter.standard.date(from: value) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Invalid date string: \(value)"
        )
    }
}

private extension ISO8601DateFormatter {
    static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct SpoolmanFilament: Codable, Identifiable, Sendable {
    let id: Int
    let name: String?
    let material: String?
    let vendor: SpoolmanVendor?
    let price: Double?
    let colorHex: String?
    let density: Double?
    let diameter: Double?
    let weight: Double?
    let spoolWeight: Double?
    let articleNumber: String?
    let comment: String?
    let settingsExtruderTemp: Int?
    let settingsBedTemp: Int?
    let multiColorHexes: String?
    let multiColorDirection: String?
    let externalId: String?
    let extra: [String: String]?

    init(
        id: Int,
        name: String? = nil,
        material: String? = nil,
        vendor: SpoolmanVendor? = nil,
        price: Double? = nil,
        colorHex: String? = nil,
        density: Double? = nil,
        diameter: Double? = nil,
        weight: Double? = nil,
        spoolWeight: Double? = nil,
        articleNumber: String? = nil,
        comment: String? = nil,
        settingsExtruderTemp: Int? = nil,
        settingsBedTemp: Int? = nil,
        multiColorHexes: String? = nil,
        multiColorDirection: String? = nil,
        externalId: String? = nil,
        extra: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.material = material
        self.vendor = vendor
        self.price = price
        self.colorHex = colorHex
        self.density = density
        self.diameter = diameter
        self.weight = weight
        self.spoolWeight = spoolWeight
        self.articleNumber = articleNumber
        self.comment = comment
        self.settingsExtruderTemp = settingsExtruderTemp
        self.settingsBedTemp = settingsBedTemp
        self.multiColorHexes = multiColorHexes
        self.multiColorDirection = multiColorDirection
        self.externalId = externalId
        self.extra = extra
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case material
        case vendor
        case price
        case colorHex = "color_hex"
        case density
        case diameter
        case weight
        case spoolWeight = "spool_weight"
        case articleNumber = "article_number"
        case comment
        case settingsExtruderTemp = "settings_extruder_temp"
        case settingsBedTemp = "settings_bed_temp"
        case multiColorHexes = "multi_color_hexes"
        case multiColorDirection = "multi_color_direction"
        case externalId = "external_id"
        case extra
    }
}

struct SpoolmanVendor: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let comment: String?
    let emptySpoolWeight: Double?
    let externalId: String?
    let extra: [String: String]?

    init(
        id: Int,
        name: String,
        comment: String? = nil,
        emptySpoolWeight: Double? = nil,
        externalId: String? = nil,
        extra: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.comment = comment
        self.emptySpoolWeight = emptySpoolWeight
        self.externalId = externalId
        self.extra = extra
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case comment
        case emptySpoolWeight = "empty_spool_weight"
        case externalId = "external_id"
        case extra
    }
}
