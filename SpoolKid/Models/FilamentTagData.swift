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
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

struct FilamentTagData: Codable, Identifiable, Sendable {
    var id: UUID? = UUID() // Local ID for list identification, not encoded to tag
    var name: String? // Filament Name
    var material: String
    var subtype: String? // Material Variant (e.g. Basic, Rapid, Silk, HF)
    var brand: String
    var colorHex: String
    /// Colors after `colorHex` on a multi-color filament. Nil for a single color.
    /// Optional on decode, so Recent Tags saved before this field still load.
    var additionalColorHexes: [String]?
    /// The colors' alpha, 1–254; nil is opaque. What a tag stated when read,
    /// what a write puts on it when written (`FilamentOpacity`). Never stored
    /// on a backend. Optional on decode, like `additionalColorHexes`.
    var colorAlpha: Int?
    var minNozzleTemp: Int
    var maxNozzleTemp: Int
    var minBedTemp: Int
    var maxBedTemp: Int
    /// False only when the tag carried no nozzle (bed) temperature, which
    /// OpenSpool allows. The Int fields then hold placeholders for the write
    /// form; what creates or matches a filament reads `statedExtruderTemp` /
    /// `statedBedTemp` instead. Not encoded: Recent Tags hold written tags,
    /// and every write states both.
    var nozzleTempsStated = true
    var bedTempsStated = true
    var spoolmanId: Int?
    var density: Double?
    /// Filament diameter in mm. Written to OpenTag3D (0x8C, mm ÷ 0.001).
    var diameter: Double?
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
    /// Grams a printer has used, from an OpenPrintTag's aux region (key 0).
    /// Read from the tag only: nothing writes it back to a backend.
    var consumedWeight: Double?
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
        additionalColorHexes: [String]? = nil,
        minNozzleTemp: Int,
        maxNozzleTemp: Int,
        minBedTemp: Int,
        maxBedTemp: Int,
        spoolmanId: Int? = nil,
        density: Double? = nil,
        diameter: Double? = nil,
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
        tagURL: String? = nil,
        consumedWeight: Double? = nil,
        colorAlpha: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.material = material
        self.subtype = subtype
        self.brand = brand
        self.colorHex = colorHex
        self.additionalColorHexes = additionalColorHexes
        self.colorAlpha = colorAlpha
        self.minNozzleTemp = minNozzleTemp
        self.maxNozzleTemp = maxNozzleTemp
        self.minBedTemp = minBedTemp
        self.maxBedTemp = maxBedTemp
        self.spoolmanId = spoolmanId
        self.density = density
        self.diameter = diameter
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
        self.consumedWeight = consumedWeight
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
        case additionalColorHexes = "additional_color_hexes"
        case colorAlpha = "color_alpha"
        case minNozzleTemp = "min_nozzle_temp"
        case maxNozzleTemp = "max_nozzle_temp"
        case minBedTemp = "min_bed_temp"
        case maxBedTemp = "max_bed_temp"
        case spoolmanId = "spool_id"
        case density
        case diameter
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
        case consumedWeight = "consumed_weight"
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
        if ColorMatching.parseHex(colorHex) == nil {
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
    
    /// A measurement a codec can write. Zero is the write form's empty state
    /// rather than a measurement, so it reads as absent like nil does — and a
    /// codec then falls back to its default or writes the field as unset.
    /// `dryingTime` is MINUTES (OpenPrintTag's unit, and the write form's);
    /// OpenTag3D and TigerTag store whole HOURS. Rounds to the nearest hour,
    /// but a stated time never becomes 0 — on both tags 0 means "this tag
    /// does not say". Nil when there is no time to write.
    nonisolated static func wholeDryingHours(fromMinutes minutes: Int?) -> Int? {
        guard let minutes, minutes > 0 else { return nil }
        return max(1, Int((Double(minutes) / 60).rounded()))
    }

    nonisolated static func statedMeasurement(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    /// The middle of a temperature range, to the nearest 5 °C (a half step
    /// rounds up: 185–200 gives 195). Every midpoint SpoolKid proposes or
    /// writes comes from here.
    nonisolated static func midpointTemperature(_ low: Int, _ high: Int) -> Int {
        Int((Double(low + high) / 10).rounded()) * 5
    }

    /// The one temperature Spoolman and the Library keep: the middle of the
    /// tag's range, or nil when the tag states none.
    nonisolated var statedExtruderTemp: Int? {
        nozzleTempsStated ? Self.midpointTemperature(minNozzleTemp, maxNozzleTemp) : nil
    }

    nonisolated var statedBedTemp: Int? {
        bedTempsStated ? Self.midpointTemperature(minBedTemp, maxBedTemp) : nil
    }

    /// The alpha byte a codec writes: `0xFF` unless the data is translucent.
    nonisolated var writtenAlphaByte: UInt8 {
        colorAlpha.flatMap(FilamentOpacity.stated(alpha:)).map(UInt8.init) ?? 0xFF
    }

    /// "Opacity 55%" for a translucent tag, nil for an opaque one.
    nonisolated var opacityText: String? {
        colorAlpha.flatMap(FilamentOpacity.stated(alpha:)).map(FilamentOpacity.displayText(alpha:))
    }

    /// Every color the tag carries, primary first.
    nonisolated var colors: FilamentColors {
        FilamentColors(hexes: [colorHex] + (additionalColorHexes ?? []), pattern: .coextruded)
    }

    /// The valid colors of the tag, first `max`, as RGB (six digits: an alpha
    /// pair is dropped). Invalid rows are dropped.
    nonisolated func trimmedColors(max: Int) -> [String] {
        Array(([colorHex] + (additionalColorHexes ?? [])).compactMap(Self.rgbHex).prefix(max))
    }

    /// The colors after the primary, as RGB, for a codec whose total color
    /// count is capped at `maxTotal`. Taken from the stored extras directly, so
    /// an invalid primary cannot cost the first valid extra.
    nonisolated func extraColorsRGB(maxTotal: Int) -> [String] {
        Array((additionalColorHexes ?? []).compactMap(Self.rgbHex).prefix(max(0, maxTotal - 1)))
    }

    private nonisolated static func rgbHex(_ raw: String) -> String? {
        FilamentColors.normalizedHex(raw).map { String($0.prefix(6)) }
    }

    /// The full weight a Prusa printer counts down from: the actual net
    /// weight, else the nominal one.
    nonisolated var fullWeightOnTag: Double? {
        Self.statedMeasurement(actualNetWeight) ?? Self.statedMeasurement(nominalNetWeight)
    }

    /// What the tag says is left: full weight minus the printer's consumed
    /// weight. Nil unless the tag states both.
    nonisolated var remainingOnTag: Double? {
        guard let consumedWeight, let full = fullWeightOnTag else { return nil }
        return max(0, full - consumedWeight)
    }

    /// Grams to record as consumed so a printer starts from `remaining`.
    /// Nil when there is nothing to record: no stated full weight, no or
    /// negative remaining, or remaining at or above full.
    nonisolated static func consumption(fullWeight: Double?, remaining: Double?) -> Double? {
        guard let full = statedMeasurement(fullWeight),
              let remaining, remaining >= 0, remaining < full else { return nil }
        return full - remaining
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
