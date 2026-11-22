//
//  OpenPrintTagPayload.swift
//  SpoolKid
//
//  Purpose: Decode the OpenPrintTag (Prusa / "nfcv") NFC format into FilamentTagData.
//  Spec: https://github.com/OpenPrintTag/openprinttag-specification
//
//  On-tag layout (NDEF media record, MIME "application/vnd.openprinttag"):
//    [meta CBOR map][main CBOR map][optional aux CBOR map]
//  The meta map (integer keys 0..3) declares region offsets; the main map holds the
//  material fields. Real tags use indefinite-length maps/arrays (0xbf/0x9f .. 0xff)
//  and half-precision floats (0xf9), so the reader supports both.
//
//  Writing: `encode(from:)` is the unpadded record; `mainMap(from:)` is the main
//  section that `OpenPrintTagLayout` builds the tag's write layout around.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

enum OpenPrintTagPayload {

    // MARK: - Main-section integer keys (OpenPrintTag spec)
    private nonisolated enum Key {
        static let gtin = 4
        static let materialClass = 8
        static let materialType = 9
        static let materialName = 10
        static let brandName = 11
        static let manufacturedDate = 14
        static let nominalNetWeight = 16
        static let actualNetWeight = 17
        static let emptyContainerWeight = 18
        static let primaryColor = 19
        /// secondary_color_0..4: the colors after the primary, in order.
        static let secondaryColorKeys = [20, 21, 22, 23, 24]
        static let transmissionDistance = 27
        static let tags = 28
        static let density = 29
        static let filamentDiameter = 30
        static let minPrintTemp = 34
        static let maxPrintTemp = 35
        static let preheatTemp = 36
        static let minBedTemp = 37
        static let maxBedTemp = 38
        static let countryOfOrigin = 55
        static let certifications = 56
        static let dryingTemp = 57
        static let dryingTime = 58
    }

    private static let mainRegionOffsetKey = 0  // meta-section key 0
    private static let auxRegionOffsetKey = 2    // meta-section key 2
    private static let auxConsumedWeightKey = 0  // aux-section key 0, grams

    /// material_type enum (key 9) → human abbreviation.
    nonisolated static let materialTypeAbbreviations: [Int: String] = [
        0: "PLA", 1: "PETG", 2: "TPU", 3: "ABS", 4: "ASA", 5: "PC", 6: "PCTG",
        7: "PP", 8: "PA6", 9: "PA11", 10: "PA12", 11: "PA66", 12: "CPE", 13: "TPE",
        14: "HIPS", 15: "PHA", 16: "PET", 17: "PEI", 18: "PBT", 19: "PVB", 20: "PVA",
        21: "PEKK", 22: "PEEK", 23: "BVOH", 24: "TPC", 25: "PPS", 26: "PPSU",
        27: "PVC", 28: "PEBA", 29: "PVDF", 30: "PPA", 31: "PCL", 32: "PES",
        33: "PMMA", 34: "POM", 35: "PPE", 36: "PS", 37: "PSU", 38: "TPI", 42: "PA612"
    ]

    // MARK: - Public

    /// Decode the full application/vnd.openprinttag NDEF record payload into FilamentTagData.
    /// Returns nil if the bytes are not a valid OpenPrintTag container with a material main section.
    static func decode(from payload: Data) -> FilamentTagData? {
        var reader = CBORReader(payload)
        guard let firstMap = reader.readMap() else { return nil }
        let afterFirst = reader.offset

        let mainMap: [Int: CBORReader.Value]
        var consumedWeight: Double?
        if isMainSection(firstMap) {
            mainMap = firstMap                       // No meta wrapper, so no aux region.
        } else {
            let mainOffset = firstMap[mainRegionOffsetKey]?.intValue ?? afterFirst
            guard mainOffset >= 0, mainOffset <= payload.count else { return nil }
            var mainReader = CBORReader(payload, start: mainOffset)
            guard let m = mainReader.readMap() else { return nil }
            mainMap = m
            consumedWeight = auxConsumedWeight(in: payload, meta: firstMap)
        }
        return mapToFilament(mainMap, consumedWeight: consumedWeight)
    }

    // MARK: - Private

    private static func isMainSection(_ map: [Int: CBORReader.Value]) -> Bool {
        map[Key.materialType] != nil || map[Key.materialName] != nil
            || map[Key.materialClass] != nil || map[Key.brandName] != nil
    }

    /// The printer's `consumed_weight` (grams) from the aux region the meta
    /// map points at. A missing, unreadable, non-finite or negative value is
    /// nil, never a failed decode (a half-float NaN would otherwise reach the
    /// hub's text, and a negative one would put the remaining above the full).
    private static func auxConsumedWeight(in payload: Data, meta: [Int: CBORReader.Value]) -> Double? {
        guard let auxOffset = meta[auxRegionOffsetKey]?.intValue,
              auxOffset >= 0, auxOffset < payload.count else { return nil }
        var auxReader = CBORReader(payload, start: auxOffset)
        guard let grams = auxReader.readMap()?[auxConsumedWeightKey]?.doubleValue,
              grams.isFinite, grams >= 0 else { return nil }
        return grams
    }

    private static func mapToFilament(_ m: [Int: CBORReader.Value], consumedWeight: Double?) -> FilamentTagData? {
        let typeID = m[Key.materialType]?.intValue
        let materialName = m[Key.materialName]?.stringValue
        let brand = m[Key.brandName]?.stringValue ?? ""

        let material: String
        if let typeID, let abbr = materialTypeAbbreviations[typeID] {
            material = abbr
        } else if let materialName {
            material = materialName
        } else {
            return nil  // No usable material identity.
        }

        func hex(_ rgb: [UInt8]) -> String { String(format: "%02X%02X%02X", rgb[0], rgb[1], rgb[2]) }
        var colorHexes: [String] = []
        // Three bytes are opaque, a fourth is alpha (spec). The first color's speaks for all.
        var colorAlpha: Int?
        func read(_ rgb: [UInt8]) {
            if colorHexes.isEmpty, rgb.count >= 4 { colorAlpha = FilamentOpacity.stated(alpha: Int(rgb[3])) }
            colorHexes.append(hex(rgb))
        }
        if let rgb = m[Key.primaryColor]?.bytesValue, rgb.count >= 3 { read(rgb) }
        for key in Key.secondaryColorKeys {
            if let rgb = m[key]?.bytesValue, rgb.count >= 3 { read(rgb) }
        }
        // With no primary, the first secondary stands in for it.
        let colorHex = colorHexes.first ?? "808080"
        let additional = colorHexes.count > 1 ? Array(colorHexes.dropFirst()) : nil

        return FilamentTagData(
            id: UUID(),
            name: materialName,
            material: material,
            subtype: nil,
            brand: brand,
            colorHex: colorHex,
            additionalColorHexes: additional,
            minNozzleTemp: m[Key.minPrintTemp]?.intValue ?? 0,
            maxNozzleTemp: m[Key.maxPrintTemp]?.intValue ?? 0,
            minBedTemp: m[Key.minBedTemp]?.intValue ?? 0,
            maxBedTemp: m[Key.maxBedTemp]?.intValue ?? 0,
            spoolmanId: nil,
            density: m[Key.density]?.doubleValue,
            diameter: m[Key.filamentDiameter]?.doubleValue,
            transmissionDistance: m[Key.transmissionDistance]?.doubleValue,
            gtin: m[Key.gtin]?.uint64Value.map { String($0) },
            manufacturedDateUnix: m[Key.manufacturedDate]?.intValue,
            countryOfOrigin: m[Key.countryOfOrigin]?.stringValue,
            preheatTemp: m[Key.preheatTemp]?.intValue,
            dryingTemp: m[Key.dryingTemp]?.intValue,
            dryingTime: m[Key.dryingTime]?.intValue,
            nominalNetWeight: m[Key.nominalNetWeight]?.doubleValue,
            actualNetWeight: m[Key.actualNetWeight]?.doubleValue,
            emptyContainerWeight: m[Key.emptyContainerWeight]?.doubleValue,
            materialTags: m[Key.tags]?.intArrayValue,
            certifications: m[Key.certifications]?.intArrayValue,
            tagURL: nil,
            consumedWeight: consumedWeight,
            colorAlpha: colorAlpha
        )
    }

    // MARK: - Encode (write)

    /// Reverse of materialTypeAbbreviations: uppercased abbreviation -> enum id.
    private nonisolated static let materialTypeIDByAbbreviation: [String: Int] =
        Dictionary(uniqueKeysWithValues: materialTypeAbbreviations.map { ($1.uppercased(), $0) })

    nonisolated static func materialTypeID(for material: String) -> Int? {
        materialTypeIDByAbbreviation[material.trimmingCharacters(in: .whitespaces).uppercased()]
    }

    /// Three bytes when opaque, as the spec allows and every earlier tag has.
    private nonisolated static func colorBytes(fromHex hex: String, alpha: UInt8) -> [UInt8]? {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        guard clean.count >= 6 else { return nil }
        let s = Array(clean)
        func byte(_ i: Int) -> UInt8? { UInt8(String(s[i...i + 1]), radix: 16) }
        guard let r = byte(0), let g = byte(2), let b = byte(4) else { return nil }
        return alpha == 0xFF ? [r, g, b] : [r, g, b, alpha]
    }

    /// Encode a FilamentTagData into a spec-valid application/vnd.openprinttag payload:
    /// 0xa0 (empty meta) + definite-length main map. Fields are written only when present.
    static func encode(from data: FilamentTagData) -> Data? {
        var out = Data([0xa0])                                    // empty meta map
        out.append(CBORWriter.encodeMap(mainMap(from: data)))     // main map
        return out
    }

    /// The main section's keys and values, in the order `encode(from:)` writes
    /// them; `OpenPrintTagLayout` adds its own keys to this list.
    nonisolated static func mainMap(from data: FilamentTagData) -> [(Int, CBORWriter.Value)] {
        var main: [(Int, CBORWriter.Value)] = []
        main.append((Key.materialClass, .uint(0)))                       // FFF
        if let id = materialTypeID(for: data.material) {
            main.append((Key.materialType, .uint(UInt64(id))))
        }
        if let name = data.name, !name.isEmpty { main.append((Key.materialName, .text(name))) }
        if !data.brand.isEmpty { main.append((Key.brandName, .text(data.brand))) }
        let colors = data.trimmedColors(max: TagFormat.openPrintTag.maxColors)
        if colors.count >= 2 {
            // A multi-color filament has no single primary_color (the spec says
            // to omit it), so every color goes to secondary_color_0..4.
            for (key, hex) in zip(Key.secondaryColorKeys, colors) {
                if let rgb = colorBytes(fromHex: hex, alpha: data.writtenAlphaByte) { main.append((key, .bytes(rgb))) }
            }
        } else if let rgb = colorBytes(fromHex: data.colorHex, alpha: data.writtenAlphaByte) {
            main.append((Key.primaryColor, .bytes(rgb)))
        }
        main.append((Key.minPrintTemp, .uint(UInt64(max(0, data.minNozzleTemp)))))
        main.append((Key.maxPrintTemp, .uint(UInt64(max(0, data.maxNozzleTemp)))))
        // A 0 below is "this tag does not say", as on every other codec; the
        // write form shows 0 in each field left untouched.
        if let p = data.preheatTemp, p > 0 { main.append((Key.preheatTemp, .uint(UInt64(p)))) }
        main.append((Key.minBedTemp, .uint(UInt64(max(0, data.minBedTemp)))))
        main.append((Key.maxBedTemp, .uint(UInt64(max(0, data.maxBedTemp)))))
        if let w = FilamentTagData.statedMeasurement(data.nominalNetWeight) { main.append((Key.nominalNetWeight, .uint(UInt64(w.rounded())))) }
        if let w = FilamentTagData.statedMeasurement(data.actualNetWeight) { main.append((Key.actualNetWeight, .uint(UInt64(w.rounded())))) }
        if let w = FilamentTagData.statedMeasurement(data.emptyContainerWeight) { main.append((Key.emptyContainerWeight, .uint(UInt64(w.rounded())))) }
        if let d = data.density { main.append((Key.density, .float(d))) }
        if let d = FilamentTagData.statedMeasurement(data.diameter) { main.append((Key.filamentDiameter, .float(d))) }
        if let t = data.transmissionDistance { main.append((Key.transmissionDistance, .float(t))) }
        if let g = data.gtin, let gv = UInt64(g.filter(\.isNumber)) { main.append((Key.gtin, .uint(gv))) }
        if let md = data.manufacturedDateUnix, md >= 0 { main.append((Key.manufacturedDate, .uint(UInt64(md)))) }
        if let c = data.countryOfOrigin, !c.isEmpty { main.append((Key.countryOfOrigin, .text(c.uppercased()))) }
        if let dt = data.dryingTemp, dt > 0 { main.append((Key.dryingTemp, .uint(UInt64(dt)))) }
        if let dti = data.dryingTime, dti > 0 { main.append((Key.dryingTime, .uint(UInt64(dti)))) }
        if let tags = data.materialTags, !tags.isEmpty {
            main.append((Key.tags, .array(tags.map { .uint(UInt64(max(0, $0))) })))
        }
        if let certs = data.certifications, !certs.isEmpty {
            main.append((Key.certifications, .array(certs.map { .uint(UInt64(max(0, $0))) })))
        }

        return main
    }
}

// MARK: - Minimal CBOR reader (decode only)

struct CBORReader {
    private let bytes: [UInt8]
    private(set) var offset: Int

    init(_ data: Data, start: Int = 0) {
        self.bytes = [UInt8](data)
        self.offset = start
    }

    enum Value {
        case uint(UInt64)
        case negint(Int64)
        case bytes([UInt8])
        case text(String)
        case array([Value])
        case map([(Int, Value)])
        case float(Double)
        case bool(Bool)
        case null

        var intValue: Int? {
            switch self {
            case .uint(let u): return Int(exactly: u)
            case .negint(let n): return Int(exactly: n)
            case .float(let d): return Int(exactly: d.rounded())
            default: return nil
            }
        }
        var uint64Value: UInt64? {
            if case .uint(let u) = self { return u }; return nil
        }
        var doubleValue: Double? {
            switch self {
            case .uint(let u): return Double(u)
            case .negint(let n): return Double(n)
            case .float(let d): return d
            default: return nil
            }
        }
        var stringValue: String? {
            if case .text(let s) = self { return s }; return nil
        }
        var bytesValue: [UInt8]? {
            if case .bytes(let b) = self { return b }; return nil
        }
        var intArrayValue: [Int]? {
            if case .array(let a) = self { return a.compactMap { $0.intValue } }; return nil
        }
    }

    /// Reads a CBOR map (definite or indefinite) at the current offset. nil if next item isn't a map.
    mutating func readMap() -> [Int: Value]? {
        guard let value = readValue(), case .map(let pairs) = value else { return nil }
        var dict = [Int: Value]()
        for (k, v) in pairs { dict[k] = v }
        return dict
    }

    /// Reads one CBOR data item, advancing offset. nil on malformed/EOF.
    mutating func readValue() -> Value? {
        guard offset < bytes.count else { return nil }
        let initial = bytes[offset]; offset += 1
        let major = initial >> 5
        let additional = initial & 0x1f

        switch major {
        case 0:
            guard let arg = readArgument(additional) else { return nil }
            return .uint(arg)
        case 1:
            guard let arg = readArgument(additional), let n = Int64(exactly: arg) else { return nil }
            return .negint(-1 - n)
        case 2:
            if additional == 31 {
                var out = [UInt8]()
                while true {
                    guard offset < bytes.count else { return nil }
                    if bytes[offset] == 0xff { offset += 1; break }
                    guard case .bytes(let chunk)? = readValue() else { return nil }
                    out.append(contentsOf: chunk)
                }
                return .bytes(out)
            }
            guard let len = readArgument(additional),
                  offset + Int(len) <= bytes.count else { return nil }
            let slice = Array(bytes[offset..<offset + Int(len)]); offset += Int(len)
            return .bytes(slice)
        case 3:
            guard let len = readArgument(additional),
                  offset + Int(len) <= bytes.count else { return nil }
            let slice = bytes[offset..<offset + Int(len)]; offset += Int(len)
            return .text(String(decoding: slice, as: UTF8.self))
        case 4:
            if additional == 31 {
                var items = [Value]()
                while true {
                    guard offset < bytes.count else { return nil }
                    if bytes[offset] == 0xff { offset += 1; break }
                    guard let v = readValue() else { return nil }
                    items.append(v)
                }
                return .array(items)
            }
            guard let count = readArgument(additional),
                  count <= UInt64(bytes.count) else { return nil }
            var items = [Value]()
            for _ in 0..<count { guard let v = readValue() else { return nil }; items.append(v) }
            return .array(items)
        case 5:
            if additional == 31 {
                var pairs = [(Int, Value)]()
                while true {
                    guard offset < bytes.count else { return nil }
                    if bytes[offset] == 0xff { offset += 1; break }
                    guard let k = readValue()?.intValue, let v = readValue() else { return nil }
                    pairs.append((k, v))
                }
                return .map(pairs)
            }
            guard let count = readArgument(additional),
                  count <= UInt64(bytes.count) else { return nil }
            var pairs = [(Int, Value)]()
            for _ in 0..<count {
                guard let k = readValue()?.intValue, let v = readValue() else { return nil }
                pairs.append((k, v))
            }
            return .map(pairs)
        case 7:
            switch additional {
            case 20: return .bool(false)
            case 21: return .bool(true)
            case 22, 23: return .null
            case 25:
                guard offset + 2 <= bytes.count else { return nil }
                let raw = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1]); offset += 2
                return .float(Self.halfToDouble(raw))
            case 26:
                guard offset + 4 <= bytes.count else { return nil }
                var u: UInt32 = 0; for i in 0..<4 { u = (u << 8) | UInt32(bytes[offset + i]) }
                offset += 4
                return .float(Double(Float(bitPattern: u)))
            case 27:
                guard offset + 8 <= bytes.count else { return nil }
                var u: UInt64 = 0; for i in 0..<8 { u = (u << 8) | UInt64(bytes[offset + i]) }
                offset += 8
                return .float(Double(bitPattern: u))
            default:
                return .null
            }
        default:
            return nil
        }
    }

    private mutating func readArgument(_ additional: UInt8) -> UInt64? {
        switch additional {
        case 0...23: return UInt64(additional)
        case 24:
            guard offset + 1 <= bytes.count else { return nil }
            let v = UInt64(bytes[offset]); offset += 1; return v
        case 25:
            guard offset + 2 <= bytes.count else { return nil }
            var v: UInt64 = 0; for i in 0..<2 { v = (v << 8) | UInt64(bytes[offset + i]) }; offset += 2; return v
        case 26:
            guard offset + 4 <= bytes.count else { return nil }
            var v: UInt64 = 0; for i in 0..<4 { v = (v << 8) | UInt64(bytes[offset + i]) }; offset += 4; return v
        case 27:
            guard offset + 8 <= bytes.count else { return nil }
            var v: UInt64 = 0; for i in 0..<8 { v = (v << 8) | UInt64(bytes[offset + i]) }; offset += 8; return v
        default:
            return nil
        }
    }

    static func halfToDouble(_ half: UInt16) -> Double {
        let sign = (half & 0x8000) != 0 ? -1.0 : 1.0
        let exp = Int((half >> 10) & 0x1f)
        let mant = Double(half & 0x03ff)
        if exp == 0 { return sign * (mant / 1024.0) * pow(2.0, -14.0) }
        if exp == 0x1f { return mant == 0 ? sign * Double.infinity : Double.nan }
        return sign * (1.0 + mant / 1024.0) * pow(2.0, Double(exp - 15))
    }
}

// MARK: - Minimal CBOR writer (encode only)

nonisolated enum CBORWriter {
    enum Value {
        case uint(UInt64)
        case text(String)
        case bytes([UInt8])
        case float(Double)   // emitted as single-precision (0xfa)
        case array([Value])
    }

    static func encodeMap(_ pairs: [(Int, Value)]) -> Data {
        var out = Data()
        writeHead(&out, major: 5, count: UInt64(pairs.count))
        for (key, value) in pairs {
            writeHead(&out, major: 0, count: UInt64(key))
            encodeValue(&out, value)
        }
        return out
    }

    private static func encodeValue(_ out: inout Data, _ value: Value) {
        switch value {
        case .uint(let u):
            writeHead(&out, major: 0, count: u)
        case .text(let s):
            let bytes = Array(s.utf8)
            writeHead(&out, major: 3, count: UInt64(bytes.count)); out.append(contentsOf: bytes)
        case .bytes(let b):
            writeHead(&out, major: 2, count: UInt64(b.count)); out.append(contentsOf: b)
        case .float(let d):
            out.append(0xfa)
            let bits = Float(d).bitPattern
            out.append(UInt8((bits >> 24) & 0xff)); out.append(UInt8((bits >> 16) & 0xff))
            out.append(UInt8((bits >> 8) & 0xff)); out.append(UInt8(bits & 0xff))
        case .array(let items):
            writeHead(&out, major: 4, count: UInt64(items.count))
            for item in items { encodeValue(&out, item) }
        }
    }

    private static func writeHead(_ out: inout Data, major: UInt8, count: UInt64) {
        let m = major << 5
        switch count {
        case 0...23:
            out.append(m | UInt8(count))
        case 24...0xff:
            out.append(m | 24); out.append(UInt8(count))
        case 0x100...0xffff:
            out.append(m | 25); out.append(UInt8((count >> 8) & 0xff)); out.append(UInt8(count & 0xff))
        case 0x10000...0xffff_ffff:
            out.append(m | 26)
            for shift in [24, 16, 8, 0] { out.append(UInt8((count >> UInt64(shift)) & 0xff)) }
        default:
            out.append(m | 27)
            for shift in [56, 48, 40, 32, 24, 16, 8, 0] { out.append(UInt8((count >> UInt64(shift)) & 0xff)) }
        }
    }
}
