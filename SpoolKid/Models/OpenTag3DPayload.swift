//
//  OpenTag3DPayload.swift
//  SpoolKid
//
//  Purpose: Encode/decode the OpenTag3D NFC format.
//  Spec: https://opentag3d.info/spec — memory map taken from `_data/spec.json`
//        in github.com/GooborgStudios/OpenTag3D (spec version 2.001).
//
//  Format: NDEF media record with MIME type "application/opentag3d"
//  Payload: Binary memory-mapped layout (big-endian unsigned ints, UTF-8 strings).
//
//  Fields SpoolKid writes (offset, length):
//    0x00 (2B) = tag_version    — int with 3 implied decimals (2001 = v2.001)
//    0x02 (5B) = material       — base material name, e.g. "PLA"
//    0x07 (5B) = material_mod   — modifier, e.g. "CF"
//    0x0C (16B) = manufacturer
//    0x1C (32B) = color_name
//    0x3C (4B) = color_1        — R, G, B, A
//    0x40 / 0x44 / 0x48 (4B)    = color_2..4 — R, G, B, A (unused: 00 00 00 00)
//    0x8C (2B) = diameter       — mm ÷ 0.001 (1750 = 1.750 mm)
//    0x90 (1B) = print_temp     — °C ÷ 5, target
//    0x91 (1B) = min_print_temp — °C ÷ 5
//    0x92 (1B) = max_print_temp — °C ÷ 5
//    0x93 (1B) = chamber_temp   — °C ÷ 5
//    0x94 (1B) = bed_temp       — °C ÷ 5, target
//    0x95 (1B) = min_bed_temp   — °C ÷ 5
//    0x96 (1B) = max_bed_temp   — °C ÷ 5
//    0x9C (2B) = density        — g/cm³ ÷ 0.001 (1240 = 1.240 g/cm³)
//    0x9E (2B) = weight         — target net weight in grams
//
//  Optional fields SpoolKid writes when the form states them (0x00 otherwise):
//    0x84 (4B) = mfg_date           — year (2B), month (1B), day (1B), UTC
//    0x9A (1B) = max_dry_temp       — °C ÷ 5
//    0x9B (1B) = dry_time           — whole hours (the model keeps MINUTES)
//    0xA0 (2B) = empty_spool_weight — grams; the payload grows to 0xA2 only
//                                     when this is written
//
//  Everything else in the map (serial, SKU, barcode, manufacture
//  time, tolerance, volumetric speeds, TD, MFI, data URL) is left at 0x00,
//  which the spec defines as the value of an absent byte.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

struct OpenTag3DPayload {

    // MARK: - Constants

    /// Spec version this writer emits. The field is an integer with three
    /// implied decimal points, so 2001 means v2.001 — not a packed
    /// major/minor byte pair.
    private static let currentVersion: UInt16 = 2001
    /// Below v1.000 there is no OpenTag3D layout to read.
    private static let minimumReadableVersion: UInt16 = 1000
    /// The spec tells readers to refuse a newer *major* version rather than
    /// guess at a layout they were not written against.
    private static let firstUnreadableVersion: UInt16 = 3000

    // Field offsets
    private static let offTagVersion: Int    = 0x00
    private static let offMaterial: Int      = 0x02
    private static let offMaterialMod: Int   = 0x07
    private static let offManufacturer: Int  = 0x0C
    private static let offColorName: Int     = 0x1C
    private static let offColor1: Int        = 0x3C
    private static let offColor2: Int        = 0x40
    private static let offColor3: Int        = 0x44
    private static let offColor4: Int        = 0x48
    private static let offDiameter: Int      = 0x8C
    private static let offPrintTemp: Int     = 0x90
    private static let offMinPrintTemp: Int  = 0x91
    private static let offMaxPrintTemp: Int  = 0x92
    private static let offChamberTemp: Int   = 0x93
    private static let offBedTemp: Int       = 0x94
    private static let offMinBedTemp: Int    = 0x95
    private static let offMaxBedTemp: Int    = 0x96
    private static let offDensity: Int       = 0x9C
    private static let offWeight: Int        = 0x9E
    private static let offMfgDate: Int       = 0x84
    private static let offMaxDryTemp: Int    = 0x9A
    private static let offDryTime: Int       = 0x9B
    private static let offEmptySpoolWeight: Int = 0xA0

    /// Written length: through the last required field (weight, 0x9E–0x9F).
    private static let payloadSize: Int      = 0xA0
    /// Written length when the empty-spool weight (0xA0–0xA1) is stated. Kept
    /// conditional so a tag without one is byte-identical to earlier writes.
    private static let payloadSizeWithEmptySpoolWeight: Int = 0xA2
    /// Shortest payload that can carry a version and a material name.
    private static let minimumSize: Int      = 0x07

    // Field lengths
    private static let lenMaterial: Int      = 5
    private static let lenMaterialMod: Int   = 5
    private static let lenManufacturer: Int  = 16
    private static let lenColorName: Int     = 32

    /// Temperature fields are stored as °C ÷ 5.
    private static let temperatureScale: Int = 5
    /// Diameter and density are stored with three implied decimals.
    private static let milliScale: Double    = 1000

    // MARK: - Encode

    static func encode(from data: FilamentTagData) -> Data? {
        let emptySpoolWeight = FilamentTagData.statedMeasurement(data.emptyContainerWeight)
        var buf = [UInt8](
            repeating: 0,
            count: emptySpoolWeight == nil ? payloadSize : payloadSizeWithEmptySpoolWeight
        )

        writeUInt16(&buf, at: offTagVersion, currentVersion)

        writeFixedString(&buf, at: offMaterial, length: lenMaterial, string: data.material)
        writeFixedString(&buf, at: offMaterialMod, length: lenMaterialMod, string: data.subtype ?? "")
        writeFixedString(&buf, at: offManufacturer, length: lenManufacturer, string: data.brand)
        writeFixedString(&buf, at: offColorName, length: lenColorName, string: data.name ?? "")

        let rgba = colorHexToRGBA(data.colorHex, alpha: data.writtenAlphaByte)
        for i in 0..<4 {
            buf[offColor1 + i] = rgba[i]
        }
        for (offset, hex) in zip([offColor2, offColor3, offColor4], data.extraColorsRGB(maxTotal: TagFormat.openTag3D.maxColors)) {
            let extra = colorHexToRGBA(hex, alpha: data.writtenAlphaByte)
            for i in 0..<4 {
                buf[offset + i] = extra[i]
            }
        }

        // These three are required fields, so an absent *or* blank value falls
        // back to the app default rather than writing a zero a reader would
        // read as "this tag does not say".
        let diameter = FilamentTagData.statedMeasurement(data.diameter) ?? AppConfig.Defaults.diameter
        writeUInt16(&buf, at: offDiameter, scaledUInt16(diameter * milliScale))

        // The spec's print/bed temperatures are a target with an optional range
        // around it; SpoolKid carries the range, so the midpoint is the target.
        buf[offPrintTemp] = encodedTemperature(FilamentTagData.midpointTemperature(data.minNozzleTemp, data.maxNozzleTemp))
        buf[offMinPrintTemp] = encodedTemperature(data.minNozzleTemp)
        buf[offMaxPrintTemp] = encodedTemperature(data.maxNozzleTemp)
        // Chamber temperature is required but SpoolKid does not model one. 0 is
        // both "no heated chamber" and the spec's value for an absent byte, so
        // it is the honest answer rather than an invented number.
        buf[offChamberTemp] = 0
        buf[offBedTemp] = encodedTemperature(FilamentTagData.midpointTemperature(data.minBedTemp, data.maxBedTemp))
        buf[offMinBedTemp] = encodedTemperature(data.minBedTemp)
        buf[offMaxBedTemp] = encodedTemperature(data.maxBedTemp)

        let density = FilamentTagData.statedMeasurement(data.density) ?? AppConfig.Defaults.density
        writeUInt16(&buf, at: offDensity, scaledUInt16(density * milliScale))

        let weight = FilamentTagData.statedMeasurement(data.nominalNetWeight) ?? AppConfig.Defaults.nominalNetWeight
        writeUInt16(&buf, at: offWeight, scaledUInt16(weight))

        // Optional: written only when stated, since 0x00 is how the spec says
        // "this tag does not say".
        if let (year, month, day) = utcDate(fromUnixSeconds: data.manufacturedDateUnix) {
            writeUInt16(&buf, at: offMfgDate, UInt16(year))
            buf[offMfgDate + 2] = UInt8(month)
            buf[offMfgDate + 3] = UInt8(day)
        }
        if let dryTemp = data.dryingTemp, dryTemp > 0 {
            buf[offMaxDryTemp] = encodedTemperature(dryTemp)
        }
        if let hours = FilamentTagData.wholeDryingHours(fromMinutes: data.dryingTime) {
            buf[offDryTime] = UInt8(clamping: hours)
        }
        if let emptySpoolWeight {
            writeUInt16(&buf, at: offEmptySpoolWeight, scaledUInt16(emptySpoolWeight))
        }

        return Data(buf)
    }

    // MARK: - Decode

    static func decode(from data: Data) -> FilamentTagData? {
        guard data.count >= minimumSize else { return nil }

        // "For any missing bytes … treat them as 0x00" — a tag that stops short
        // of the full map is legal, so pad rather than refuse.
        var bytes = Array(data)
        if bytes.count < payloadSizeWithEmptySpoolWeight {
            bytes += [UInt8](repeating: 0, count: payloadSizeWithEmptySpoolWeight - bytes.count)
        }

        let version = readUInt16(bytes, at: offTagVersion)
        guard version >= minimumReadableVersion, version < firstUnreadableVersion else { return nil }

        let material = readFixedString(bytes, at: offMaterial, length: lenMaterial)
        guard !material.isEmpty else { return nil }

        let modifier = readFixedString(bytes, at: offMaterialMod, length: lenMaterialMod)
        let brand = readFixedString(bytes, at: offManufacturer, length: lenManufacturer)
        let colorName = readFixedString(bytes, at: offColorName, length: lenColorName)

        let colorHex = String(format: "%02X%02X%02X",
                              bytes[offColor1], bytes[offColor1 + 1], bytes[offColor1 + 2])
        // A slot of four zero bytes is unused.
        let additionalColorHexes = [offColor2, offColor3, offColor4].compactMap { offset -> String? in
            guard bytes[offset..<offset + 4].contains(where: { $0 != 0 }) else { return nil }
            return String(format: "%02X%02X%02X", bytes[offset], bytes[offset + 1], bytes[offset + 2])
        }

        let (minNozzle, maxNozzle) = temperatureRange(
            target: bytes[offPrintTemp],
            minimum: bytes[offMinPrintTemp],
            maximum: bytes[offMaxPrintTemp],
            offset: AppConfig.Defaults.nozzleTempOffset)
        let (minBed, maxBed) = temperatureRange(
            target: bytes[offBedTemp],
            minimum: bytes[offMinBedTemp],
            maximum: bytes[offMaxBedTemp],
            offset: AppConfig.Defaults.bedTempOffset)

        let diameter = readUInt16(bytes, at: offDiameter)
        let density = readUInt16(bytes, at: offDensity)
        let weight = readUInt16(bytes, at: offWeight)
        let emptySpoolWeight = readUInt16(bytes, at: offEmptySpoolWeight)
        let maxDryTemp = bytes[offMaxDryTemp]
        let dryTimeHours = bytes[offDryTime]
        let manufactured = unixSeconds(
            year: Int(readUInt16(bytes, at: offMfgDate)),
            month: Int(bytes[offMfgDate + 2]),
            day: Int(bytes[offMfgDate + 3])
        )

        return FilamentTagData(
            id: UUID(),
            name: colorName.isEmpty ? nil : colorName,
            material: material,
            subtype: modifier.isEmpty ? nil : modifier,
            brand: brand.isEmpty ? "Unknown" : brand,
            colorHex: colorHex,
            additionalColorHexes: additionalColorHexes.isEmpty ? nil : additionalColorHexes,
            minNozzleTemp: minNozzle,
            maxNozzleTemp: maxNozzle,
            minBedTemp: minBed,
            maxBedTemp: maxBed,
            spoolmanId: nil,
            density: density == 0 ? nil : Double(density) / milliScale,
            diameter: diameter == 0 ? nil : Double(diameter) / milliScale,
            manufacturedDateUnix: manufactured,
            dryingTemp: maxDryTemp == 0 ? nil : Int(maxDryTemp) * temperatureScale,
            dryingTime: dryTimeHours == 0 ? nil : Int(dryTimeHours) * 60,
            nominalNetWeight: weight == 0 ? nil : Double(weight),
            emptyContainerWeight: emptySpoolWeight == 0 ? nil : Double(emptySpoolWeight),
            colorAlpha: FilamentOpacity.stated(alpha: Int(bytes[offColor1 + 3]))
        )
    }

    // MARK: - Helpers

    /// A range is only as good as the bytes that carry it: an absent min or max
    /// falls back to the target ± the app's usual spread rather than to 0°C.
    private static func temperatureRange(
        target: UInt8,
        minimum: UInt8,
        maximum: UInt8,
        offset: Int
    ) -> (Int, Int) {
        let targetTemp = Int(target) * temperatureScale
        let low = minimum == 0 ? max(0, targetTemp - offset) : Int(minimum) * temperatureScale
        let high = maximum == 0 ? targetTemp + offset : Int(maximum) * temperatureScale
        return (low, high)
    }


    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// The UTC calendar day of a Unix timestamp, or nil when there is none to
    /// write or the year does not fit the field's two bytes.
    private static func utcDate(fromUnixSeconds unix: Int?) -> (year: Int, month: Int, day: Int)? {
        guard let unix, unix >= 0 else { return nil }
        let parts = utcCalendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: TimeInterval(unix)))
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              (1...Int(UInt16.max)).contains(year) else { return nil }
        return (year, month, day)
    }

    /// Midnight UTC of a stated date; nil for an absent (all-zero) or
    /// impossible one.
    private static func unixSeconds(year: Int, month: Int, day: Int) -> Int? {
        guard year > 0, (1...12).contains(month), (1...31).contains(day) else { return nil }
        let parts = DateComponents(year: year, month: month, day: day)
        guard parts.isValidDate(in: utcCalendar), let date = utcCalendar.date(from: parts) else { return nil }
        return Int(date.timeIntervalSince1970)
    }

    private static func encodedTemperature(_ celsius: Int) -> UInt8 {
        UInt8(clamping: celsius / temperatureScale)
    }

    private static func scaledUInt16(_ value: Double) -> UInt16 {
        guard value.isFinite, value > 0 else { return 0 }
        return UInt16(clamping: Int(value.rounded()))
    }

    private static func writeUInt16(_ buf: inout [UInt8], at offset: Int, _ value: UInt16) {
        buf[offset] = UInt8(value >> 8)
        buf[offset + 1] = UInt8(value & 0xFF)
    }

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    private static func writeFixedString(_ buf: inout [UInt8], at offset: Int, length: Int, string: String) {
        // Truncate at character boundaries to avoid splitting multi-byte UTF-8 sequences.
        // Start with the full string and drop characters from the end until it fits.
        var truncated = string
        while Array(truncated.utf8).count > length {
            truncated = String(truncated.dropLast())
        }
        let utf8 = Array(truncated.utf8)
        for i in 0..<utf8.count {
            buf[offset + i] = utf8[i]
        }
        // Remaining bytes stay 0 (null-padded)
    }

    private static func readFixedString(_ bytes: [UInt8], at offset: Int, length: Int) -> String {
        guard offset + length <= bytes.count else { return "" }
        let slice = bytes[offset..<(offset + length)]
        // Find null terminator
        let trimmed: ArraySlice<UInt8>
        if let nullIdx = slice.firstIndex(of: 0) {
            trimmed = slice[slice.startIndex..<nullIdx]
        } else {
            trimmed = slice
        }
        return String(bytes: trimmed, encoding: .utf8) ?? ""
    }

    private static func colorHexToRGBA(_ hex: String, alpha: UInt8) -> [UInt8] {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count >= 6 else { return [0, 0, 0, alpha] }

        let scanner = Scanner(string: clean)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)

        let r = UInt8((rgb >> 16) & 0xFF)
        let g = UInt8((rgb >> 8) & 0xFF)
        let b = UInt8(rgb & 0xFF)
        return [r, g, b, alpha]
    }
}
