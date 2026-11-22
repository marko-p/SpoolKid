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
//    Page  4       (4B)  = Header: 7B 00 65 00 (magic byte 0x7B at byte 0)
//    Pages 5-9     (20B) = SKU (null-padded ASCII; page 9 carries characters 17-20)
//    Pages 10-13   (16B) = Brand (null-padded ASCII)
//    Pages 15-18   (16B) = Material type (null-padded ASCII)
//    Page  20      (4B)  = Color as ABGR (A, B, G, R)
//    Page  24      (4B)  = Extruder temp: [minLo, minHi, maxLo, maxHi] (LE uint16)
//    Page  29      (4B)  = Hotbed temp:   [minLo, minHi, maxLo, maxHi] (LE uint16)
//    Page  30      (4B)  = Filament params: [diameter ÷ 0.01 mm (LE uint16), length m (LE uint16)]
//    Page  31      (4B)  = Net weight, grams (LE uint16, then two zero bytes)
//
//  The SKU carries `SM<id>` when SpoolKid writes a tag for a spool SpoolLink can
//  resolve (see `SpoolLinkSKU`); it decodes back to `spoolmanId`, not `name`.
//
//  Pages 30 and 31 are corrected against a factory Anycubic PLA tag dumped on
//  real hardware (issue #5, 2026-09-12): page 30 reads `AF 00 4A 01` — 175,
//  i.e. hundredths of a millimetre, where the third-party spec said tenths —
//  and page 31 reads `E8 03 00 00`, a 1000 g spool the spec did not map.
//  The same tag carries `32 00 C8 00` on page 23, unidentified, so SpoolKid
//  writes zeros there. It also carries `65` in byte 2 of page 4. That byte is
//  unidentified too, but an ACE Pro needs it (issue #16), so SpoolKid writes it.
//
//  Factory tags are password-protected against writes (CFG0 AUTH0 = 0x04),
//  so only a blank or previously user-written tag can take this layout.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

struct AnycubicACEPayload {
    
    // MARK: - Constants
    
    static let magicByte: UInt8 = 0x7B
    
    // Page indices (each page = 4 bytes)
    static let pageHeader: Int       = 4
    static let pageSKUStart: Int     = 5
    static let pageSKUEnd: Int       = 9
    static let pageBrandStart: Int   = 10
    static let pageBrandEnd: Int     = 13
    static let pageMaterialStart: Int = 15
    static let pageMaterialEnd: Int  = 18
    static let pageColor: Int        = 20
    static let pageExtruderTemp: Int = 24
    static let pageHotbedTemp: Int   = 29
    static let pageFilamentParams: Int = 30
    static let pageNetWeight: Int    = 31
    
    // Total pages we need to read (through page 31 inclusive = 32 pages × 4 bytes = 128 bytes).
    // The scan already READs page 28, which returns 28-31; the buffer used to
    // stop at 30, so page 31 came off the tag and was dropped.
    static let totalPages: Int = 32
    static let bytesPerPage: Int = 4
    static let skuPageCount: Int = pageSKUEnd - pageSKUStart + 1
    static let totalBytes: Int = totalPages * bytesPerPage

    /// The READ (0x30) addresses that fill pages 0-31; each READ returns four
    /// pages. Clone Tag copies pages 4-31 out of this read, so a gap here would
    /// copy zeros that never came off the tag.
    static let readPages: [Int] = [0, 4, 8, 12, 16, 20, 24, 28]
    
    // MARK: - Encode (produces page-by-page write commands)
    
    /// Returns an array of (pageNumber, 4-byte Data) tuples for writing to the tag.
    static func encodePages(from data: FilamentTagData) -> [(page: Int, data: Data)] {
        var pages: [(page: Int, data: Data)] = []
        
        // Page 4: Header — the magic byte, and 0x65 in byte 2 as a factory tag
        // carries it. An ACE Pro ignores a tag whose byte 2 is zero (issue #16).
        pages.append((pageHeader, Data([magicByte, 0x00, 0x65, 0x00])))
        
        // Pages 5-9: SKU (use filament name or "material brand" as SKU). Five
        // pages, as the reference writer lays it out: a 17-character ReSpool
        // SKU ends on page 9, which SpoolKid used to zero (issue #23).
        let sku = data.name ?? "\(data.material)"
        let skuPages = stringToPages(sku, pageCount: skuPageCount)
        for (i, pageData) in skuPages.enumerated() {
            pages.append((pageSKUStart + i, pageData))
        }
        
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
        
        // Page 30: Filament params (diameter in hundredths of a mm, LE uint16;
        // length in meters, LE uint16). A factory tag carries 175 for 1.75 mm.
        let diameter = FilamentTagData.statedMeasurement(data.diameter) ?? AppConfig.Defaults.diameter
        let diameterHundredths = UInt16(clamping: Int((diameter * 100).rounded()))
        let lengthMeters: UInt16 = 330 // ~330m for a 1kg PLA spool (reasonable default)
        pages.append((pageFilamentParams, Data([
            UInt8(diameterHundredths & 0xFF), UInt8((diameterHundredths >> 8) & 0xFF),
            UInt8(lengthMeters & 0xFF), UInt8((lengthMeters >> 8) & 0xFF)
        ])))

        // Page 31: Net weight in grams (LE uint16). An unknown weight is written
        // as zero rather than a guessed default, and written at all so a rewrite
        // does not leave the previous spool's weight on the tag.
        let weight = UInt16(clamping: Int((FilamentTagData.statedMeasurement(data.nominalNetWeight) ?? 0).rounded()))
        pages.append((pageNetWeight, Data([
            UInt8(weight & 0xFF), UInt8((weight >> 8) & 0xFF), 0x00, 0x00
        ])))
        
        return pages
    }
    
    // MARK: - Decode
    
    /// Decodes from a flat byte array of raw NFC page data starting from page 0.
    /// Expects at least `totalBytes` bytes (pages 0-31, 128 bytes).
    static func decode(from pages: [UInt8]) -> FilamentTagData? {
        guard pages.count >= totalBytes else { return nil }
        
        // Validate magic byte at page 4
        let headerOffset = pageHeader * bytesPerPage
        guard pages[headerOffset] == magicByte else { return nil }
        
        // SKU (pages 5-9, 20 bytes)
        let skuOffset = pageSKUStart * bytesPerPage
        let sku = readNullTerminatedString(pages, at: skuOffset, maxLength: skuPageCount * bytesPerPage)
        
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

        // Diameter (page 30, hundredths of a mm) and net weight (page 31, grams).
        // Zero is the tag not saying, as on tags SpoolKid wrote before page 31
        // was mapped.
        let paramsOffset = pageFilamentParams * bytesPerPage
        let diameterHundredths = Int(pages[paramsOffset]) | (Int(pages[paramsOffset + 1]) << 8)
        let weightOffset = pageNetWeight * bytesPerPage
        let weight = Int(pages[weightOffset]) | (Int(pages[weightOffset + 1]) << 8)
        
        // `SM<id>` is a spool, not a name. Reading it as a name made SpoolKid
        // worse at reading the very tags it writes.
        let spoolID = SpoolLinkSKU.spoolID(fromSKU: sku)

        return FilamentTagData(
            id: UUID(),
            name: sku.isEmpty || spoolID != nil ? nil : sku,
            material: material,
            subtype: nil,
            brand: brand.isEmpty ? "Anycubic" : brand,
            colorHex: colorHex,
            minNozzleTemp: minNozzle,
            maxNozzleTemp: maxNozzle,
            minBedTemp: minBed,
            maxBedTemp: maxBed,
            spoolmanId: spoolID,
            diameter: diameterHundredths == 0 ? nil : Double(diameterHundredths) / 100,
            nominalNetWeight: weight == 0 ? nil : Double(weight)
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
