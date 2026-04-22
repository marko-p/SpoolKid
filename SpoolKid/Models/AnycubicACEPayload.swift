//
//  AnycubicACEPayload.swift
//  SpoolKid
//
//  Purpose: Encode/decode the Anycubic ACE NFC format.
//  Reverse-engineered spec: https://github.com/DnG-Crafts/ACE-RFID
//
//  Format: Raw NFC page writes (NOT NDEF). Requires NFCTagReaderSession + NFCMiFareTag.
//  Each "page" is 4 bytes on NTAG213/215 (MIFARE Ultralight compatible).
//
//  Memory map:
//    Page  4       (4B)  = Header / magic byte 0x7B at byte 0
//    Pages 5-8     (16B) = SKU (null-padded ASCII)
//    Pages 10-13   (16B) = Brand (null-padded ASCII)
//    Pages 15-18   (16B) = Material type (null-padded ASCII)
//    Page  20      (4B)  = Color as ABGR (A, B, G, R)
//    Page  24      (4B)  = Extruder temp: [minLo, minHi, maxLo, maxHi] (LE uint16)
//    Page  29      (4B)  = Hotbed temp:   [minLo, minHi, maxLo, maxHi] (LE uint16)
//    Page  30      (4B)  = Filament params: [diameterX10Lo, diameterX10Hi, lengthLo, lengthHi]
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import Foundation

struct AnycubicACEPayload {
    
    // MARK: - Constants
    
    static let magicByte: UInt8 = 0x7B
    
    // Page indices (each page = 4 bytes)
    static let pageHeader: Int       = 4
    static let pageSKUStart: Int     = 5
    static let pageSKUEnd: Int       = 8
    static let pageBrandStart: Int   = 10
    static let pageBrandEnd: Int     = 13
    static let pageMaterialStart: Int = 15
    static let pageMaterialEnd: Int  = 18
    static let pageColor: Int        = 20
    static let pageExtruderTemp: Int = 24
    static let pageHotbedTemp: Int   = 29
    static let pageFilamentParams: Int = 30
    
    // Total pages we need to read (through page 30 inclusive = 31 pages × 4 bytes = 124 bytes)
    static let totalPages: Int = 31
    static let bytesPerPage: Int = 4
    static let totalBytes: Int = 31 * 4 // 124
    
    // MARK: - Encode (produces page-by-page write commands)
    
    /// Returns an array of (pageNumber, 4-byte Data) tuples for writing to the tag.
    static func encodePages(from data: FilamentTagData) -> [(page: Int, data: Data)] {
        var pages: [(page: Int, data: Data)] = []
        
        // Page 4: Header with magic byte
        pages.append((pageHeader, Data([magicByte, 0x00, 0x00, 0x00])))
        
        // Pages 5-8: SKU (use filament name or "material brand" as SKU)
        let sku = data.name ?? "\(data.material)"
        let skuPages = stringToPages(sku, pageCount: 4)
        for (i, pageData) in skuPages.enumerated() {
            pages.append((pageSKUStart + i, pageData))
        }
        
        // Page 9: separator (zeroed)
        pages.append((9, Data([0x00, 0x00, 0x00, 0x00])))
        
        // Pages 10-13: Brand
        let brandPages = stringToPages(data.brand, pageCount: 4)
        for (i, pageData) in brandPages.enumerated() {
            pages.append((pageBrandStart + i, pageData))
        }
        
        // Page 14: separator (zeroed)
        pages.append((14, Data([0x00, 0x00, 0x00, 0x00])))
        
        // Pages 15-18: Material type
        let materialPages = stringToPages(data.material, pageCount: 4)
        for (i, pageData) in materialPages.enumerated() {
            pages.append((pageMaterialStart + i, pageData))
        }
        
        // Page 19: separator (zeroed)
        pages.append((19, Data([0x00, 0x00, 0x00, 0x00])))
        
        // Page 20: Color as ABGR
        let colorABGR = colorHexToABGR(data.colorHex)
        pages.append((pageColor, Data(colorABGR)))
        
        // Pages 21-23: zeroed padding
        for p in 21...23 {
            pages.append((p, Data([0x00, 0x00, 0x00, 0x00])))
        }
        
        // Page 24: Extruder temp (LE uint16 min, LE uint16 max)
        let extMinLo = UInt8(data.minNozzleTemp & 0xFF)
        let extMinHi = UInt8((data.minNozzleTemp >> 8) & 0xFF)
        let extMaxLo = UInt8(data.maxNozzleTemp & 0xFF)
        let extMaxHi = UInt8((data.maxNozzleTemp >> 8) & 0xFF)
        pages.append((pageExtruderTemp, Data([extMinLo, extMinHi, extMaxLo, extMaxHi])))
        
        // Pages 25-28: zeroed padding
        for p in 25...28 {
            pages.append((p, Data([0x00, 0x00, 0x00, 0x00])))
        }
        
        // Page 29: Hotbed temp (LE uint16 min, LE uint16 max)
        let bedMinLo = UInt8(data.minBedTemp & 0xFF)
        let bedMinHi = UInt8((data.minBedTemp >> 8) & 0xFF)
        let bedMaxLo = UInt8(data.maxBedTemp & 0xFF)
        let bedMaxHi = UInt8((data.maxBedTemp >> 8) & 0xFF)
        pages.append((pageHotbedTemp, Data([bedMinLo, bedMinHi, bedMaxLo, bedMaxHi])))
        
        // Page 30: Filament params (diameter × 10, LE uint16; length in meters, LE uint16)
        let diameterX10 = UInt16(AppConfig.Defaults.diameter * 10) // 17 for 1.75mm
        let lengthMeters: UInt16 = 330 // ~330m for a 1kg PLA spool (reasonable default)
        pages.append((pageFilamentParams, Data([
            UInt8(diameterX10 & 0xFF), UInt8((diameterX10 >> 8) & 0xFF),
            UInt8(lengthMeters & 0xFF), UInt8((lengthMeters >> 8) & 0xFF)
        ])))
        
        return pages
    }
    
    // MARK: - Decode
    
    /// Decodes from a flat byte array of raw NFC page data starting from page 0.
    /// Expects at least `totalBytes` bytes (pages 0-30, 124 bytes).
    static func decode(from pages: [UInt8]) -> FilamentTagData? {
        guard pages.count >= totalBytes else { return nil }
        
        // Validate magic byte at page 4
        let headerOffset = pageHeader * bytesPerPage
        guard pages[headerOffset] == magicByte else { return nil }
        
        // SKU (pages 5-8, 16 bytes)
        let skuOffset = pageSKUStart * bytesPerPage
        let sku = readNullTerminatedString(pages, at: skuOffset, maxLength: 16)
        
        // Brand (pages 10-13, 16 bytes)
        let brandOffset = pageBrandStart * bytesPerPage
        let brand = readNullTerminatedString(pages, at: brandOffset, maxLength: 16)
        
        // Material (pages 15-18, 16 bytes)
        let materialOffset = pageMaterialStart * bytesPerPage
        let material = readNullTerminatedString(pages, at: materialOffset, maxLength: 16)
        guard !material.isEmpty else { return nil }
        
        // Color (page 20, ABGR format)
        let colorOffset = pageColor * bytesPerPage
        let a = pages[colorOffset]
        let b = pages[colorOffset + 1]
        let g = pages[colorOffset + 2]
        let r = pages[colorOffset + 3]
        _ = a // Alpha unused in our hex representation
        let colorHex = String(format: "%02X%02X%02X", r, g, b)
        
        // Extruder temp (page 24, LE uint16 × 2)
        let extOffset = pageExtruderTemp * bytesPerPage
        let minNozzle = Int(pages[extOffset]) | (Int(pages[extOffset + 1]) << 8)
        let maxNozzle = Int(pages[extOffset + 2]) | (Int(pages[extOffset + 3]) << 8)
        
        // Hotbed temp (page 29, LE uint16 × 2)
        let bedOffset = pageHotbedTemp * bytesPerPage
        let minBed = Int(pages[bedOffset]) | (Int(pages[bedOffset + 1]) << 8)
        let maxBed = Int(pages[bedOffset + 2]) | (Int(pages[bedOffset + 3]) << 8)
        
        return FilamentTagData(
            id: UUID(),
            name: sku.isEmpty ? nil : sku,
            material: material,
            subtype: nil,
            brand: brand.isEmpty ? "Anycubic" : brand,
            colorHex: colorHex,
            minNozzleTemp: minNozzle,
            maxNozzleTemp: maxNozzle,
            minBedTemp: minBed,
            maxBedTemp: maxBed,
            spoolmanId: nil
        )
    }
    
    // MARK: - Helpers
    
    private static func stringToPages(_ string: String, pageCount: Int) -> [Data] {
        let maxBytes = pageCount * bytesPerPage
        // Truncate at character boundaries to avoid splitting multi-byte UTF-8 sequences.
        var truncated = string
        while Array(truncated.utf8).count > maxBytes {
            truncated = String(truncated.dropLast())
        }
        var utf8 = Array(truncated.utf8)
        // Pad to full length with nulls
        while utf8.count < maxBytes {
            utf8.append(0)
        }
        
        var pages = [Data]()
        for i in 0..<pageCount {
            let start = i * bytesPerPage
            let end = start + bytesPerPage
            pages.append(Data(utf8[start..<end]))
        }
        return pages
    }
    
    private static func readNullTerminatedString(_ bytes: [UInt8], at offset: Int, maxLength: Int) -> String {
        guard offset + maxLength <= bytes.count else { return "" }
        let slice = bytes[offset..<(offset + maxLength)]
        let trimmed: ArraySlice<UInt8>
        if let nullIdx = slice.firstIndex(of: 0) {
            trimmed = slice[slice.startIndex..<nullIdx]
        } else {
            trimmed = slice
        }
        return String(bytes: trimmed, encoding: .utf8) ?? ""
    }
    
    private static func colorHexToABGR(_ hex: String) -> [UInt8] {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count >= 6 else { return [255, 0, 0, 0] }
        
        let scanner = Scanner(string: clean)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        
        let r = UInt8((rgb >> 16) & 0xFF)
        let g = UInt8((rgb >> 8) & 0xFF)
        let b = UInt8(rgb & 0xFF)
        return [255, b, g, r] // ABGR format
    }
}
