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
        static let gtin: Int = 4
        static let materialClass: Int = 8
        static let materialType: Int = 9
        static let materialName: Int = 10
        static let brandName: Int = 11
        static let manufacturedDate: Int = 14
        static let nominalNetWeight: Int = 16
        static let actualNetWeight: Int = 17
        static let emptyContainerWeight: Int = 18
        static let primaryColor: Int = 19
        static let transmissionDistance: Int = 27
        static let tags: Int = 28
        static let density: Int = 29
        static let minPrintTemp: Int = 34
        static let maxPrintTemp: Int = 35
        static let preheatTemp: Int = 36
        static let minBedTemp: Int = 37
        static let maxBedTemp: Int = 38
        static let countryOfOrigin: Int = 55
        static let certifications: Int = 56
        static let dryingTemp: Int = 57
        static let dryingTime: Int = 58
    }

    static let tagsImpliedByTag: [Int: [Int]] = [
        70: [11],
        20: [19],
        22: [21],
        31: [30],
        32: [30],
        72: [30],
        34: [33],
        39: [38],
        40: [38],
        41: [38],
        42: [41],
        43: [41],
        66: [38],
        45: [44],
        47: [46],
        48: [46],
        49: [46],
        50: [46],
        51: [46],
        52: [46],
        53: [46],
        54: [46]
    ]

    static func expandedMaterialTags(from selected: [Int]) -> [Int] {
        var visited = Set(selected)
        var queue = selected

        while let current = queue.popLast() {
            for implied in tagsImpliedByTag[current] ?? [] {
                if visited.insert(implied).inserted {
                    queue.append(implied)
                }
            }
        }

        return visited.sorted()
    }

    static func cappedCertifications(_ selected: [Int]) -> [Int] {
        let allowed = Set(AppConfig.openPrintTagCertifications.keys)
        var orderedUnique: [Int] = []
        var seen = Set<Int>()
        for value in selected where allowed.contains(value) {
            if seen.insert(value).inserted {
                orderedUnique.append(value)
                if orderedUnique.count == 8 {
                    break
                }
            }
        }
        return orderedUnique
    }

    struct DataModel: Equatable {
        let materialClassID: Int
        let materialTypeID: Int?
        let materialClassName: String
        let materialTypeName: String
        let materialName: String?
        let brandName: String
        let manufacturedDateUnix: Int?
        let nominalNetWeightGrams: Double?
        let actualNetWeightGrams: Double?
        let emptyContainerWeightGrams: Double?
        let primaryColorRGBA: [UInt8]
        let transmissionDistance: Double?
        let tags: [Int]
        let density: Double?
        let minPrintTempC: Int
        let maxPrintTempC: Int
        let preheatTempC: Int?
        let minBedTempC: Int
        let maxBedTempC: Int
        let gtin: String?
        let countryOfOrigin: String?
        let certifications: [Int]
        let dryingTempC: Int?
        let dryingTimeMinutes: Int?
    }

    static func encode(dataModel: DataModel) -> Data? {
        var map: [(Int, CBORValue)] = []

        map.append((Key.materialClass, .uint(UInt64(max(0, dataModel.materialClassID)))))
        map.append((Key.materialType, .uint(UInt64(max(0, dataModel.materialTypeID ?? dataModel.materialClassID)))))

        if let materialName = dataModel.materialName, !materialName.isEmpty {
            map.append((Key.materialName, .text(materialName)))
        }

        map.append((Key.brandName, .text(dataModel.brandName)))

        if let manufacturedDateUnix = dataModel.manufacturedDateUnix, manufacturedDateUnix >= 0 {
            map.append((Key.manufacturedDate, .uint(UInt64(manufacturedDateUnix))))
        }

        if let nominalNetWeightGrams = dataModel.nominalNetWeightGrams {
            map.append((Key.nominalNetWeight, .float32(Float32(nominalNetWeightGrams))))
        }

        if let actualNetWeightGrams = dataModel.actualNetWeightGrams {
            map.append((Key.actualNetWeight, .float32(Float32(actualNetWeightGrams))))
        }

        if let emptyContainerWeightGrams = dataModel.emptyContainerWeightGrams {
            map.append((Key.emptyContainerWeight, .float32(Float32(emptyContainerWeightGrams))))
        }

        map.append((Key.primaryColor, .bytes(dataModel.primaryColorRGBA)))

        if let transmissionDistance = dataModel.transmissionDistance {
            map.append((Key.transmissionDistance, .float32(Float32(transmissionDistance))))
        }

        let expandedTags = expandedMaterialTags(from: dataModel.tags)
        if !expandedTags.isEmpty {
            map.append((Key.tags, .array(expandedTags.map { .uint(UInt64($0)) })))
        }

        if let density = dataModel.density {
            map.append((Key.density, .float32(Float32(density))))
        }

        map.append((Key.minPrintTemp, .uint(UInt64(max(0, dataModel.minPrintTempC)))))
        map.append((Key.maxPrintTemp, .uint(UInt64(max(0, dataModel.maxPrintTempC)))))

        if let preheatTempC = dataModel.preheatTempC {
            map.append((Key.preheatTemp, .uint(UInt64(max(0, preheatTempC)))))
        }

        map.append((Key.minBedTemp, .uint(UInt64(max(0, dataModel.minBedTempC)))))
        map.append((Key.maxBedTemp, .uint(UInt64(max(0, dataModel.maxBedTempC)))))

        if let gtin = dataModel.gtin, !gtin.isEmpty {
            map.append((Key.gtin, .text(gtin)))
        }

        if let countryOfOrigin = dataModel.countryOfOrigin, !countryOfOrigin.isEmpty {
            map.append((Key.countryOfOrigin, .text(countryOfOrigin.uppercased())))
        }

        let cappedCertifications = cappedCertifications(dataModel.certifications)
        if !cappedCertifications.isEmpty {
            map.append((Key.certifications, .array(cappedCertifications.map { .uint(UInt64($0)) })))
        }

        if let dryingTempC = dataModel.dryingTempC {
            map.append((Key.dryingTemp, .uint(UInt64(max(0, dryingTempC)))))
        }

        if let dryingTimeMinutes = dataModel.dryingTimeMinutes {
            map.append((Key.dryingTime, .uint(UInt64(max(0, dryingTimeMinutes)))))
        }

        return MiniCBOR.encodeMap(map)
    }

    static func decodeDataModel(from data: Data) -> DataModel? {
        guard let map = MiniCBOR.decodeMap(data) else { return nil }

        guard let materialType = map[Key.materialType]?.textValue ?? map[Key.materialClass]?.textValue else {
            // material_type can be numeric enum per OpenPrintTag generator
            guard let materialTypeID = map[Key.materialType]?.intValue ?? map[Key.materialClass]?.intValue,
                  let materialTypeName = AppConfig.openPrintTagMaterialTypes[materialTypeID] else {
                return nil
            }

            let materialClassID = map[Key.materialClass]?.intValue ?? 0
            let materialClassName = materialClassID == 1 ? "SLA" : "FFF"

            return decodeDataModel(
                map: map,
                materialClassID: materialClassID,
                materialTypeID: materialTypeID,
                materialClassName: materialClassName,
                materialTypeName: materialTypeName
            )
        }

        let materialClassID = map[Key.materialClass]?.intValue ?? 0
        let materialClassName = materialClassID == 1 ? "SLA" : "FFF"
        let materialTypeID = map[Key.materialType]?.intValue
        let resolvedMaterialTypeName = if let materialTypeID {
            AppConfig.openPrintTagMaterialTypes[materialTypeID] ?? materialType
        } else {
            materialType
        }

        return decodeDataModel(
            map: map,
            materialClassID: materialClassID,
            materialTypeID: materialTypeID,
            materialClassName: materialClassName,
            materialTypeName: resolvedMaterialTypeName
        )
    }

    private static func decodeDataModel(
        map: [Int: CBORValue],
        materialClassID: Int,
        materialTypeID: Int?,
        materialClassName: String,
        materialTypeName: String
    ) -> DataModel {

        let materialName = map[Key.materialName]?.textValue
        let brandName = map[Key.brandName]?.textValue ?? "Unknown"

        let manufacturedDateUnix = map[Key.manufacturedDate]?.intValue
        let nominalNetWeightGrams = map[Key.nominalNetWeight]?.doubleValue
        let actualNetWeightGrams = map[Key.actualNetWeight]?.doubleValue
        let emptyContainerWeightGrams = map[Key.emptyContainerWeight]?.doubleValue

        let primaryColorRGBA: [UInt8]
        if let colorBytes = map[Key.primaryColor]?.bytesValue, colorBytes.count >= 4 {
            primaryColorRGBA = Array(colorBytes.prefix(4))
        } else if let colorBytes = map[Key.primaryColor]?.bytesValue, colorBytes.count >= 3 {
            primaryColorRGBA = [colorBytes[0], colorBytes[1], colorBytes[2], 255]
        } else {
            primaryColorRGBA = [0, 0, 0, 255]
        }

        let transmissionDistance = map[Key.transmissionDistance]?.doubleValue
        let tags = map[Key.tags]?.intArrayValue ?? []
        let density = map[Key.density]?.doubleValue
        let minPrintTempC = map[Key.minPrintTemp]?.intValue ?? AppConfig.Defaults.minNozzleTemp
        let maxPrintTempC = map[Key.maxPrintTemp]?.intValue ?? AppConfig.Defaults.maxNozzleTemp
        let preheatTempC = map[Key.preheatTemp]?.intValue
        let minBedTempC = map[Key.minBedTemp]?.intValue ?? AppConfig.Defaults.minBedTemp
        let maxBedTempC = map[Key.maxBedTemp]?.intValue ?? AppConfig.Defaults.maxBedTemp
        let gtin = map[Key.gtin]?.textValue
        let countryOfOrigin = map[Key.countryOfOrigin]?.textValue
        let certifications = map[Key.certifications]?.intArrayValue ?? []
        let dryingTempC = map[Key.dryingTemp]?.intValue
        let dryingTimeMinutes = map[Key.dryingTime]?.intValue

        return DataModel(
            materialClassID: materialClassID,
            materialTypeID: materialTypeID,
            materialClassName: materialClassName,
            materialTypeName: materialTypeName,
            materialName: materialName,
            brandName: brandName,
            manufacturedDateUnix: manufacturedDateUnix,
            nominalNetWeightGrams: nominalNetWeightGrams,
            actualNetWeightGrams: actualNetWeightGrams,
            emptyContainerWeightGrams: emptyContainerWeightGrams,
            primaryColorRGBA: primaryColorRGBA,
            transmissionDistance: transmissionDistance,
            tags: tags,
            density: density,
            minPrintTempC: minPrintTempC,
            maxPrintTempC: maxPrintTempC,
            preheatTempC: preheatTempC,
            minBedTempC: minBedTempC,
            maxBedTempC: maxBedTempC,
            gtin: gtin,
            countryOfOrigin: countryOfOrigin,
            certifications: certifications,
            dryingTempC: dryingTempC,
            dryingTimeMinutes: dryingTimeMinutes
        )
    }
    
    // MARK: - Encode
    
    static func encode(from data: FilamentTagData) -> Data? {
        let inferredTypeID = AppConfig.openPrintTagMaterialTypeID(for: data.material)
        let model = DataModel(
            materialClassID: 0,
            materialTypeID: data.openPrintTagMaterialTypeID ?? inferredTypeID,
            materialClassName: "FFF",
            materialTypeName: data.material,
            materialName: data.name ?? "\(data.brand) \(data.material)",
            brandName: data.brand,
            manufacturedDateUnix: data.manufacturedDateUnix,
            nominalNetWeightGrams: data.nominalNetWeight,
            actualNetWeightGrams: data.actualNetWeight,
            emptyContainerWeightGrams: data.emptyContainerWeight,
            primaryColorRGBA: colorHexToRGBA(data.colorHex),
            transmissionDistance: data.transmissionDistance,
            tags: data.materialTags ?? [],
            density: data.density,
            minPrintTempC: data.minNozzleTemp,
            maxPrintTempC: data.maxNozzleTemp,
            preheatTempC: data.preheatTemp,
            minBedTempC: data.minBedTemp,
            maxBedTempC: data.maxBedTemp,
            gtin: data.gtin,
            countryOfOrigin: data.countryOfOrigin,
            certifications: data.certifications ?? [],
            dryingTempC: data.dryingTemp,
            dryingTimeMinutes: data.dryingTime
        )
        return encode(dataModel: model)
    }
    
    // MARK: - Decode
    
    static func decode(from data: Data) -> FilamentTagData? {
        guard let model = decodeDataModel(from: data) else { return nil }

        let colorHex = String(format: "%02X%02X%02X", model.primaryColorRGBA[0], model.primaryColorRGBA[1], model.primaryColorRGBA[2])

        return FilamentTagData(
            id: UUID(),
            name: model.materialName,
            material: model.materialTypeName,
            subtype: nil,
            brand: model.brandName,
            colorHex: colorHex,
            minNozzleTemp: model.minPrintTempC,
            maxNozzleTemp: model.maxPrintTempC,
            minBedTemp: model.minBedTempC,
            maxBedTemp: model.maxBedTempC,
            spoolmanId: nil,
            density: model.density,
            openPrintTagMaterialTypeID: model.materialTypeID,
            transmissionDistance: model.transmissionDistance,
            gtin: model.gtin,
            manufacturedDateUnix: model.manufacturedDateUnix,
            countryOfOrigin: model.countryOfOrigin,
            preheatTemp: model.preheatTempC,
            dryingTemp: model.dryingTempC,
            dryingTime: model.dryingTimeMinutes,
            nominalNetWeight: model.nominalNetWeightGrams,
            actualNetWeight: model.actualNetWeightGrams,
            emptyContainerWeight: model.emptyContainerWeightGrams,
            materialTags: model.tags,
            certifications: model.certifications,
            tagURL: nil
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
    case float32(Float32)
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

    var doubleValue: Double? {
        switch self {
        case .float32(let f):
            return Double(f)
        case .uint(let v):
            return Double(v)
        case .negint(let v):
            guard v <= UInt64(Int.max) else { return nil }
            return Double(-1 - Int(v))
        default:
            return nil
        }
    }

    var intArrayValue: [Int]? {
        guard case .array(let items) = self else { return nil }
        return items.compactMap { $0.intValue }
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
        case .float32(let f):
            out.append(0xFA) // major type 7, float32
            let bits = f.bitPattern
            out.append(UInt8((bits >> 24) & 0xFF))
            out.append(UInt8((bits >> 16) & 0xFF))
            out.append(UInt8((bits >> 8) & 0xFF))
            out.append(UInt8(bits & 0xFF))
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
        
        if major == 7 {
            switch additional {
            case 26:
                guard offset + 3 < bytes.count else { return nil }
                let bits = UInt32(bytes[offset]) << 24
                    | UInt32(bytes[offset + 1]) << 16
                    | UInt32(bytes[offset + 2]) << 8
                    | UInt32(bytes[offset + 3])
                offset += 4
                return .float32(Float32(bitPattern: bits))
            default:
                return nil
            }
        }

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
