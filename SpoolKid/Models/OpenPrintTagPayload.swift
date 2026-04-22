//
//  OpenPrintTagPayload.swift
//  SpoolKid
//
//  Purpose: Encode/decode the OpenPrintTag (Prusa) NFC format.
//  Spec: https://github.com/OpenPrintTag/openprinttag-specification
//
//  Format: NDEF media record with MIME type "application/vnd.openprinttag"
//  Payload: CBOR-encoded map with integer keys.
//
//  Structure (simplified for filament data we care about):
//    Main section keys:
//      8  = material_class (text, e.g. "PLA")
//      9  = material_type  (text, e.g. "PLA")
//      10 = material_name  (text, e.g. "Prusament PLA Galaxy Black")
//      11 = brand_name     (text, e.g. "Prusament")
//      19 = primary_color  (byte string, 4 bytes RGBA)
//      34 = min_print_temperature (uint, °C)
//      35 = max_print_temperature (uint, °C)
//      37 = min_bed_temperature   (uint, °C)
//      38 = max_bed_temperature   (uint, °C)
//
//  Note: Uses a minimal inline CBOR encoder/decoder to avoid external dependencies.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import Foundation

struct OpenPrintTagPayload {
    
    // MARK: - CBOR Integer Keys (from OpenPrintTag spec)
    
    private enum Key {
        static let materialClass: Int = 8
        static let materialType: Int = 9
        static let materialName: Int = 10
        static let brandName: Int = 11
        static let primaryColor: Int = 19
        static let minPrintTemp: Int = 34
        static let maxPrintTemp: Int = 35
        static let minBedTemp: Int = 37
        static let maxBedTemp: Int = 38
    }
    
    // MARK: - Encode
    
    static func encode(from data: FilamentTagData) -> Data? {
        var map: [(Int, CBORValue)] = []
        
        // material_class and material_type both get the material string
        map.append((Key.materialClass, .text(data.material)))
        map.append((Key.materialType, .text(data.material)))
        
        // material_name: use filament name if available, otherwise "brand material"
        let materialName = data.name ?? "\(data.brand) \(data.material)"
        map.append((Key.materialName, .text(materialName)))
        
        // brand_name
        map.append((Key.brandName, .text(data.brand)))
        
        // primary_color: 4 bytes RGBA from hex color
        let rgba = colorHexToRGBA(data.colorHex)
        map.append((Key.primaryColor, .bytes(rgba)))
        
        // Temperatures (clamp to non-negative before encoding as unsigned)
        map.append((Key.minPrintTemp, .uint(UInt64(max(0, data.minNozzleTemp)))))
        map.append((Key.maxPrintTemp, .uint(UInt64(max(0, data.maxNozzleTemp)))))
        map.append((Key.minBedTemp, .uint(UInt64(max(0, data.minBedTemp)))))
        map.append((Key.maxBedTemp, .uint(UInt64(max(0, data.maxBedTemp)))))
        
        return MiniCBOR.encodeMap(map)
    }
    
    // MARK: - Decode
    
    static func decode(from data: Data) -> FilamentTagData? {
        guard let map = MiniCBOR.decodeMap(data) else { return nil }
        
        // Extract required fields
        guard let materialType = map[Key.materialType]?.textValue ?? map[Key.materialClass]?.textValue else {
            return nil
        }
        
        let brand = map[Key.brandName]?.textValue ?? "Unknown"
        let name = map[Key.materialName]?.textValue
        
        // Color: RGBA bytes -> hex string
        var colorHex = AppConfig.Defaults.colorHex
        if let colorBytes = map[Key.primaryColor]?.bytesValue, colorBytes.count >= 3 {
            colorHex = String(format: "%02X%02X%02X", colorBytes[0], colorBytes[1], colorBytes[2])
        }
        
        let minNozzle = map[Key.minPrintTemp]?.intValue ?? AppConfig.Defaults.minNozzleTemp
        let maxNozzle = map[Key.maxPrintTemp]?.intValue ?? AppConfig.Defaults.maxNozzleTemp
        let minBed = map[Key.minBedTemp]?.intValue ?? AppConfig.Defaults.minBedTemp
        let maxBed = map[Key.maxBedTemp]?.intValue ?? AppConfig.Defaults.maxBedTemp
        
        return FilamentTagData(
            id: UUID(),
            name: name,
            material: materialType,
            subtype: nil,
            brand: brand,
            colorHex: colorHex,
            minNozzleTemp: minNozzle,
            maxNozzleTemp: maxNozzle,
            minBedTemp: minBed,
            maxBedTemp: maxBed,
            spoolmanId: nil
        )
    }
    
    // MARK: - Helpers
    
    private static func colorHexToRGBA(_ hex: String) -> [UInt8] {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count >= 6 else { return [0, 0, 0, 255] }
        
        let scanner = Scanner(string: clean)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        
        let r = UInt8((rgb >> 16) & 0xFF)
        let g = UInt8((rgb >> 8) & 0xFF)
        let b = UInt8(rgb & 0xFF)
        return [r, g, b, 255] // Full opacity
    }
}

// MARK: - Minimal CBOR Encoder/Decoder

/// A lightweight CBOR implementation covering only the types needed for OpenPrintTag.
/// Supports: unsigned int, negative int, byte string, text string, map with integer keys.
enum CBORValue {
    case uint(UInt64)
    case negint(UInt64) // Represents -(1 + value)
    case bytes([UInt8])
    case text(String)
    case array([CBORValue])
    case map([(Int, CBORValue)])
    case null
    
    var textValue: String? {
        if case .text(let s) = self { return s }
        return nil
    }
    
    var intValue: Int? {
        switch self {
        case .uint(let v):
            guard let i = Int(exactly: v) else { return nil }
            return i
        case .negint(let v):
            // CBOR negative int: -(1 + v). Guard against overflow.
            guard v <= UInt64(Int.max) else { return nil }
            let pos = Int(v)
            let result = -1 - pos // equivalent to -(1 + v) but avoids overflow on Int.min
            return result
        default: return nil
        }
    }
    
    var bytesValue: [UInt8]? {
        if case .bytes(let b) = self { return b }
        return nil
    }
}

enum MiniCBOR {
    
    // MARK: - Encode
    
    static func encodeMap(_ pairs: [(Int, CBORValue)]) -> Data {
        var out = Data()
        writeHeader(&out, major: 5, count: UInt64(pairs.count))
        for (key, value) in pairs {
            encodeValue(&out, .uint(UInt64(key)))
            encodeValue(&out, value)
        }
        return out
    }
    
    private static func encodeValue(_ out: inout Data, _ value: CBORValue) {
        switch value {
        case .uint(let v):
            writeHeader(&out, major: 0, count: v)
        case .negint(let v):
            writeHeader(&out, major: 1, count: v)
        case .bytes(let b):
            writeHeader(&out, major: 2, count: UInt64(b.count))
            out.append(contentsOf: b)
        case .text(let s):
            let utf8 = Array(s.utf8)
            writeHeader(&out, major: 3, count: UInt64(utf8.count))
            out.append(contentsOf: utf8)
        case .array(let items):
            writeHeader(&out, major: 4, count: UInt64(items.count))
            for item in items {
                encodeValue(&out, item)
            }
        case .map(let pairs):
            writeHeader(&out, major: 5, count: UInt64(pairs.count))
            for (key, val) in pairs {
                encodeValue(&out, .uint(UInt64(key)))
                encodeValue(&out, val)
            }
        case .null:
            out.append(0xF6) // CBOR null
        }
    }
    
    private static func writeHeader(_ out: inout Data, major: UInt8, count: UInt64) {
        let majorBits = major << 5
        if count < 24 {
            out.append(majorBits | UInt8(count))
        } else if count <= UInt8.max {
            out.append(majorBits | 24)
            out.append(UInt8(count))
        } else if count <= UInt16.max {
            out.append(majorBits | 25)
            out.append(UInt8(count >> 8))
            out.append(UInt8(count & 0xFF))
        } else if count <= UInt32.max {
            out.append(majorBits | 26)
            out.append(UInt8((count >> 24) & 0xFF))
            out.append(UInt8((count >> 16) & 0xFF))
            out.append(UInt8((count >> 8) & 0xFF))
            out.append(UInt8(count & 0xFF))
        } else {
            out.append(majorBits | 27)
            for shift in stride(from: 56, through: 0, by: -8) {
                out.append(UInt8((count >> shift) & 0xFF))
            }
        }
    }
    
    // MARK: - Decode
    
    /// Decodes a CBOR map with integer keys. Returns nil if the data is not a valid CBOR map.
    static func decodeMap(_ data: Data) -> [Int: CBORValue]? {
        let bytes = Array(data)
        var offset = 0
        guard let value = decodeValue(bytes, offset: &offset) else { return nil }
        
        if case .map(let pairs) = value {
            var dict = [Int: CBORValue]()
            for (k, v) in pairs {
                dict[k] = v
            }
            return dict
        }
        return nil
    }
    
    private static func decodeValue(_ bytes: [UInt8], offset: inout Int) -> CBORValue? {
        guard offset < bytes.count else { return nil }
        
        let initial = bytes[offset]
        let major = initial >> 5
        let additional = initial & 0x1F
        offset += 1
        
        // Special values
        if initial == 0xF6 { return .null }
        if initial == 0xF4 { return .uint(0) } // false
        if initial == 0xF5 { return .uint(1) } // true
        
        guard let count = readCount(bytes, additional: additional, offset: &offset) else { return nil }
        
        switch major {
        case 0: // Unsigned int
            return .uint(count)
        case 1: // Negative int
            return .negint(count)
        case 2: // Byte string
            guard let byteCount = Int(exactly: count) else { return nil }
            let end = offset + byteCount
            guard end <= bytes.count else { return nil }
            let b = Array(bytes[offset..<end])
            offset = end
            return .bytes(b)
        case 3: // Text string
            guard let strCount = Int(exactly: count) else { return nil }
            let end = offset + strCount
            guard end <= bytes.count else { return nil }
            let b = Array(bytes[offset..<end])
            offset = end
            guard let s = String(bytes: b, encoding: .utf8) else { return nil }
            return .text(s)
        case 4: // Array
            guard let arrCount = Int(exactly: count) else { return nil } // Prevent absurd counts
            var items = [CBORValue]()
            for _ in 0..<arrCount {
                guard let item = decodeValue(bytes, offset: &offset) else { return nil }
                items.append(item)
            }
            return .array(items)
        case 5: // Map
            guard let mapCount = Int(exactly: count) else { return nil } // Prevent absurd counts
            var pairs = [(Int, CBORValue)]()
            for _ in 0..<mapCount {
                guard let keyVal = decodeValue(bytes, offset: &offset) else { return nil }
                guard let valVal = decodeValue(bytes, offset: &offset) else { return nil }
                let key: Int
                switch keyVal {
                case .uint(let k):
                    guard let ik = Int(exactly: k) else { return nil }
                    key = ik
                case .negint(let k):
                    guard k <= UInt64(Int.max) else { return nil }
                    key = -1 - Int(k)
                default:
                    // Non-integer key — skip this pair rather than silently mapping to 0
                    continue
                }
                pairs.append((key, valVal))
            }
            return .map(pairs)
        default:
            // Major type 6 (tag) or 7 (simple/float) — skip for our use case
            return nil
        }
    }
    
    private static func readCount(_ bytes: [UInt8], additional: UInt8, offset: inout Int) -> UInt64? {
        if additional < 24 {
            return UInt64(additional)
        } else if additional == 24 {
            guard offset < bytes.count else { return nil }
            let val = UInt64(bytes[offset])
            offset += 1
            return val
        } else if additional == 25 {
            guard offset + 1 < bytes.count else { return nil }
            let val = UInt64(bytes[offset]) << 8 | UInt64(bytes[offset + 1])
            offset += 2
            return val
        } else if additional == 26 {
            guard offset + 3 < bytes.count else { return nil }
            let val = UInt64(bytes[offset]) << 24 | UInt64(bytes[offset + 1]) << 16 |
                      UInt64(bytes[offset + 2]) << 8 | UInt64(bytes[offset + 3])
            offset += 4
            return val
        } else if additional == 27 {
            guard offset + 7 < bytes.count else { return nil }
            var val: UInt64 = 0
            for i in 0..<8 {
                val = val << 8 | UInt64(bytes[offset + i])
            }
            offset += 8
            return val
        }
        return nil // Indefinite length or reserved — not supported
    }
}
