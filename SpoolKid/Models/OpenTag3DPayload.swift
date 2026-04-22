//
//  OpenTag3DPayload.swift
//  SpoolKid
//
//  Purpose: Encode/decode the OpenTag3D NFC format.
//  Spec: https://opentag3d.info/spec (v1.0)
//
//  Format: NDEF media record with MIME type "application/opentag3d"
//  Payload: Binary memory-mapped layout (big-endian unsigned ints, UTF-8 strings).
//
//  Core fields (0x00-0x6F, fits NTAG213 144 bytes):
//    0x00 (2B) = tag_version
//    0x02 (5B) = material_base (e.g. "PLA\0\0")
//    0x07 (5B) = material_mod  (e.g. "CF\0\0\0")
//    0x1B (16B) = manufacturer
//    0x2B (32B) = color_name
//    0x4B (4B) = color1_rgba (R, G, B, A)
//    0x60 (1B) = print_temp (°C / 5)
//    0x61 (1B) = bed_temp   (°C / 5)
//    0x62 (2B) = density    (g/cm³ × 100)
//
//  Extended fields (0x70+, needs NTAG215/SLIX2):
//    0xB4 (1B) = min_print_temp (°C / 5)
//    0xB5 (1B) = max_print_temp (°C / 5)
//    0xB6 (1B) = min_bed_temp   (°C / 5)
//    0xB7 (1B) = max_bed_temp   (°C / 5)
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import Foundation

struct OpenTag3DPayload {
    
    // MARK: - Constants
    
    private static let currentVersion: UInt16 = 0x0100 // v1.0
    
    // Core field offsets
    private static let offTagVersion: Int    = 0x00
    private static let offMaterialBase: Int  = 0x02
    private static let offMaterialMod: Int   = 0x07
    private static let offManufacturer: Int  = 0x1B
    private static let offColorName: Int     = 0x2B
    private static let offColor1RGBA: Int    = 0x4B
    private static let offPrintTemp: Int     = 0x60
    private static let offBedTemp: Int       = 0x61
    private static let offDensity: Int       = 0x62
    
    // Extended field offsets
    private static let offMinPrintTemp: Int  = 0xB4
    private static let offMaxPrintTemp: Int  = 0xB5
    private static let offMinBedTemp: Int    = 0xB6
    private static let offMaxBedTemp: Int    = 0xB7
    
    // Core payload minimum size (up through density at 0x62 + 2 bytes)
    private static let coreSize: Int         = 0x64
    // Extended payload size (through max_bed_temp at 0xB7 + 1 byte)
    private static let extendedSize: Int     = 0xB8
    
    // Field lengths
    private static let lenMaterialBase: Int  = 5
    private static let lenMaterialMod: Int   = 5
    private static let lenManufacturer: Int  = 16
    private static let lenColorName: Int     = 32
    
    // MARK: - Encode
    
    static func encode(from data: FilamentTagData) -> Data? {
        // Use extended size if we have distinct min/max temps, otherwise core size is enough.
        // Always write extended to include min/max temps when available.
        let size = extendedSize
        var buf = [UInt8](repeating: 0, count: size)
        
        // Tag version (big-endian)
        buf[offTagVersion] = UInt8(currentVersion >> 8)
        buf[offTagVersion + 1] = UInt8(currentVersion & 0xFF)
        
        // Material base (e.g. "PLA")
        writeFixedString(&buf, at: offMaterialBase, length: lenMaterialBase, string: data.material)
        
        // Material modifier (subtype, e.g. "CF", "Silk")
        writeFixedString(&buf, at: offMaterialMod, length: lenMaterialMod, string: data.subtype ?? "")
        
        // Manufacturer (brand)
        writeFixedString(&buf, at: offManufacturer, length: lenManufacturer, string: data.brand)
        
        // Color name (use filament name if available, otherwise empty)
        writeFixedString(&buf, at: offColorName, length: lenColorName, string: data.name ?? "")
        
        // Color RGBA
        let rgba = colorHexToRGBA(data.colorHex)
        for i in 0..<4 {
            buf[offColor1RGBA + i] = rgba[i]
        }
        
        // Temperatures (÷5 encoding): single print/bed temps = average of min/max
        let avgPrintTemp = (data.minNozzleTemp + data.maxNozzleTemp) / 2
        let avgBedTemp = (data.minBedTemp + data.maxBedTemp) / 2
        buf[offPrintTemp] = UInt8(clamping: avgPrintTemp / 5)
        buf[offBedTemp] = UInt8(clamping: avgBedTemp / 5)
        
        // Density (default 1.24 g/cm³ = 124)
        let densityEncoded = UInt16(AppConfig.Defaults.density * 100)
        buf[offDensity] = UInt8(densityEncoded >> 8)
        buf[offDensity + 1] = UInt8(densityEncoded & 0xFF)
        
        // Extended: min/max temps (÷5 encoding)
        buf[offMinPrintTemp] = UInt8(clamping: data.minNozzleTemp / 5)
        buf[offMaxPrintTemp] = UInt8(clamping: data.maxNozzleTemp / 5)
        buf[offMinBedTemp] = UInt8(clamping: data.minBedTemp / 5)
        buf[offMaxBedTemp] = UInt8(clamping: data.maxBedTemp / 5)
        
        return Data(buf)
    }
    
    // MARK: - Decode
    
    static func decode(from data: Data) -> FilamentTagData? {
        let bytes = Array(data)
        guard bytes.count >= coreSize else { return nil }
        
        // Validate tag version — must be 1.x
        let version = UInt16(bytes[offTagVersion]) << 8 | UInt16(bytes[offTagVersion + 1])
        guard (version >> 8) == 1 else { return nil }
        
        // Material base
        let material = readFixedString(bytes, at: offMaterialBase, length: lenMaterialBase)
        guard !material.isEmpty else { return nil }
        
        // Material modifier
        let modifier = readFixedString(bytes, at: offMaterialMod, length: lenMaterialMod)
        let subtype: String? = modifier.isEmpty ? nil : modifier
        
        // Manufacturer
        let brand = readFixedString(bytes, at: offManufacturer, length: lenManufacturer)
        
        // Color name
        let colorName = readFixedString(bytes, at: offColorName, length: lenColorName)
        let name: String? = colorName.isEmpty ? nil : colorName
        
        // Color RGBA -> hex
        var colorHex = AppConfig.Defaults.colorHex
        if offColor1RGBA + 3 < bytes.count {
            colorHex = String(format: "%02X%02X%02X",
                              bytes[offColor1RGBA], bytes[offColor1RGBA + 1], bytes[offColor1RGBA + 2])
        }
        
        // Temperatures: prefer extended min/max if available, else derive from single temp
        let minNozzle: Int
        let maxNozzle: Int
        let minBed: Int
        let maxBed: Int
        
        if bytes.count >= extendedSize {
            minNozzle = Int(bytes[offMinPrintTemp]) * 5
            maxNozzle = Int(bytes[offMaxPrintTemp]) * 5
            minBed = Int(bytes[offMinBedTemp]) * 5
            maxBed = Int(bytes[offMaxBedTemp]) * 5
        } else {
            // Only have single print/bed temp — create a range around it
            let printTemp = Int(bytes[offPrintTemp]) * 5
            let bedTemp = Int(bytes[offBedTemp]) * 5
            minNozzle = printTemp - AppConfig.Defaults.nozzleTempOffset
            maxNozzle = printTemp + AppConfig.Defaults.nozzleTempOffset
            minBed = bedTemp - AppConfig.Defaults.bedTempOffset
            maxBed = bedTemp + AppConfig.Defaults.bedTempOffset
        }
        
        return FilamentTagData(
            id: UUID(),
            name: name,
            material: material,
            subtype: subtype,
            brand: brand.isEmpty ? "Unknown" : brand,
            colorHex: colorHex,
            minNozzleTemp: minNozzle,
            maxNozzleTemp: maxNozzle,
            minBedTemp: minBed,
            maxBedTemp: maxBed,
            spoolmanId: nil
        )
    }
    
    // MARK: - Helpers
    
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
    
    private static func colorHexToRGBA(_ hex: String) -> [UInt8] {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count >= 6 else { return [0, 0, 0, 255] }
        
        let scanner = Scanner(string: clean)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        
        let r = UInt8((rgb >> 16) & 0xFF)
        let g = UInt8((rgb >> 8) & 0xFF)
        let b = UInt8(rgb & 0xFF)
        return [r, g, b, 255]
    }
}
