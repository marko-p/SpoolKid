//
//  TigerTagPayload.swift
//  SpoolKid
//
//  Purpose: Encode/decode the TigerTag NFC format (spec v2.1).
//  Normative spec: https://github.com/TigerTag-Project/TigerTag-RFID-Guide
//
//  Format: raw NFC pages (NOT NDEF) on NTAG21x, all multi-byte values
//  big-endian. 144 bytes at pages 0x04–0x27: 80 bytes of data + a 64-byte
//  optional ECDSA-P256 signature (verified by TigerTagSignature, never
//  decoded as data).
//
//  Offsets below are relative to the start of page 4, which is the spec's
//  own convention and what the read buffer hands over.
//
//  SpoolKid always writes the standard TigerTag magic with ID Product
//  0xFFFFFFFF: TigerTag+ product IDs are administered by TigerTag Corp and
//  are never invented here.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

enum TigerTagVariant: Equatable, Sendable {
    case tigerTag
    case plus(productID: UInt32)
    case initTag
}

enum TigerTagPayload {

    // MARK: - Constants

    static let bytesPerPage = 4
    static let dataByteCount = 80
    static let totalByteCount = 144
    /// The chip must have a page 39: NTAG213 (45 pages) is the smallest
    /// variant the 144-byte layout fits, per the spec's capacity note.
    static let minChipPageCount = 40
    /// READ (0x30) addresses filling pages 4–39; each READ returns four pages.
    static let readPages: [Int] = [4, 8, 12, 16, 20, 24, 28, 32, 36]
    static let signatureRangeInData: Range<Int> = 80..<144

    /// Byte offset of page 4 inside a pages-0-indexed read buffer.
    static let firstUserPageOffset = 16

    /// Magic u32 values at +0 (spec §2.1, database/id_version.json).
    private static let standardMagic: UInt32 = 0x5BF5_9264
    private static let plusMagic: UInt32 = 0xBC0F_CB97
    private static let initMagic: UInt32 = 0x6C41_A2E1

    // MARK: - Variant detection

    static func variant(of dataFromPage4: [UInt8]) -> TigerTagVariant? {
        guard dataFromPage4.count >= 4 else { return nil }
        switch u32(dataFromPage4, 0) {
        case standardMagic: return .tigerTag
        case plusMagic: return .plus(productID: u32(dataFromPage4, 4))
        case initMagic: return .initTag
        default: return nil
        }
    }

    /// Name for Tag Explorer dumps: the variant, or nil when the bytes are
    /// not TigerTag at all.
    static func dumpName(for dataFromPage4: [UInt8]) -> String? {
        switch variant(of: dataFromPage4) {
        case .tigerTag: return "TigerTag"
        case .plus: return "TigerTag+"
        case .initTag: return "TigerTag Init"
        case nil: return nil
        }
    }

    // MARK: - Decode

    /// Decodes the 80 data bytes. Refuses the Init variant (a blank marker,
    /// not data — the read path reports it separately) and short payloads.
    static func decode(from dataFromPage4: [UInt8]) -> FilamentTagData? {
        guard dataFromPage4.count >= dataByteCount,
              let variant = variant(of: dataFromPage4), variant != .initTag else { return nil }

        let materialID = UInt16(truncatingIfNeeded: u16(dataFromPage4, 8))
        let material = TigerTagRegistry.materialLabel(forID: materialID) ?? "Unknown"
        let brand = TigerTagRegistry.brandLabel(forID: UInt16(truncatingIfNeeded: u16(dataFromPage4, 14))) ?? "Unknown"
        let subtype = TigerTagRegistry.subtypeLabel(
            aspect1: dataFromPage4[10], aspect2: dataFromPage4[11]
        )
        let unit = dataFromPage4[23]
        let initial = grams(u24(dataFromPage4, 20), unit: unit, materialID: materialID)
        let available = grams(u24(dataFromPage4, 76), unit: unit, materialID: materialID)
        let secondsSince2000 = u32(dataFromPage4, 32)
        // Colors 2 and 3 are RGB at +36 and +40; three zero bytes is unused.
        let additionalColorHexes = [36, 40].compactMap { offset -> String? in
            guard dataFromPage4[offset..<offset + 3].contains(where: { $0 != 0 }) else { return nil }
            return colorHex(dataFromPage4, at: offset)
        }
        let td = u16(dataFromPage4, 44)

        return FilamentTagData(
            name: string(dataFromPage4, 48, length: 28),
            material: material,
            subtype: subtype,
            brand: brand,
            colorHex: colorHex(dataFromPage4, at: 16),
            additionalColorHexes: additionalColorHexes.isEmpty ? nil : additionalColorHexes,
            minNozzleTemp: u16(dataFromPage4, 24),
            maxNozzleTemp: u16(dataFromPage4, 26),
            minBedTemp: Int(dataFromPage4[30]),
            maxBedTemp: Int(dataFromPage4[31]),
            diameter: TigerTagRegistry.diameterMM(forID: dataFromPage4[13]),
            transmissionDistance: td == 0 ? nil : Double(td) / 10,
            manufacturedDateUnix: secondsSince2000 == 0 ? nil : Int(secondsSince2000) + 946_684_800,
            dryingTemp: Int(dataFromPage4[28]),
            // +29 is HOURS (guide v2.1); the model keeps minutes.
            dryingTime: Int(dataFromPage4[29]) * 60,
            nominalNetWeight: initial,
            actualNetWeight: available,
            colorAlpha: FilamentOpacity.stated(alpha: Int(dataFromPage4[19]))
        )
    }

    // MARK: - Byte helpers (big-endian per spec §2)

    private static func u16(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) << 8 | Int(b[o + 1]) }

    private static func u24(_ b: [UInt8], _ o: Int) -> Int {
        Int(b[o]) << 16 | Int(b[o + 1]) << 8 | Int(b[o + 2])
    }

    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) << 24 | UInt32(b[o + 1]) << 16 | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3])
    }

    private static func colorHex(_ b: [UInt8], at o: Int) -> String {
        // On-chip order is R,G,B,A; the primary's alpha is read separately.
        String(format: "%02X%02X%02X", b[o], b[o + 1], b[o + 2])
    }

    private static func string(_ b: [UInt8], _ o: Int, length: Int) -> String? {
        let slice = b[o..<o + length].prefix(while: { $0 != 0 })
        return slice.isEmpty ? nil : String(bytes: slice, encoding: .utf8)
    }

    /// Weights convert exactly (mg/g/kg); volumes convert through the
    /// material's registry density, assuming 1.0 g/ml when the registry has
    /// none. Zero means the tag declines to say.
    private static func grams(_ value: Int, unit: UInt8, materialID: UInt16) -> Double? {
        guard value > 0 else { return nil }
        switch unit {
        case 10: return Double(value) * 0.001            // mg
        case 21: return Double(value)                    // g
        case 35: return Double(value) * 1000             // kg
        case 48, 62, 79:                                 // ml, cl, L
            let ml = Double(value) * (unit == 48 ? 1 : unit == 62 ? 10 : 1000)
            return ml * (TigerTagRegistry.materialDensity(forID: materialID) ?? 1.0)
        default: return Double(value)                    // unknown unit: read as grams
        }
    }

    // MARK: - Encode (writes standard TigerTag, ID Product 0xFFFFFFFF)

    /// Emits the 20 data pages 4–23. Signature pages are NOT written here:
    /// the write path zeroes 24–39 so a reused signed chip reads unsigned,
    /// never invalid (its old signature covered the old identity bytes and
    /// would fail verification anyway).
    static func encodePages(from data: FilamentTagData, date: Date = .now) -> [(page: Int, data: Data)] {
        var b = [UInt8](repeating: 0, count: dataByteCount)

        putU32(standardMagic, at: 0, into: &b)
        putU32(0xFFFF_FFFF, at: 4, into: &b)                       // maker / offline product

        let material = TigerTagRegistry.materialID(for: data.material)
        putU16(Int(material.id), at: 8, into: &b)
        let aspects = TigerTagRegistry.aspects(forSubtype: data.subtype ?? "")
        b[10] = aspects.aspect1
        b[11] = aspects.aspect2
        b[12] = 0x8E                                               // Filament (resin is read-only)
        b[13] = nearestDiameterID(data.diameter)
        putU16(Int(TigerTagRegistry.brandID(for: data.brand).id), at: 14, into: &b)

        // On-chip order is R,G,B,A (fixture ff 00 00 ff = opaque red) —
        // NOT alpha-first as the ACE page was.
        let rgb = ColorMatching.parseHex(data.colorHex) ?? (r: 1.0, g: 0.0, b: 0.0)
        b[16] = UInt8((rgb.r * 255).rounded())
        b[17] = UInt8((rgb.g * 255).rounded())
        b[18] = UInt8((rgb.b * 255).rounded())
        b[19] = data.writtenAlphaByte

        // Measure + unit. Zero when unstated — a rewrite must clear the
        // previous spool's weight, and 0 reads as "tag does not say".
        let gramsWritten = Int((FilamentTagData.statedMeasurement(data.nominalNetWeight) ?? 0).rounded())
        putU24(min(gramsWritten, 0xFF_FFFF), at: 20, into: &b)
        b[23] = 21                                                 // g

        putU16(clamped(data.minNozzleTemp, 0...0xFFFF), at: 24, into: &b)
        putU16(clamped(data.maxNozzleTemp, 0...0xFFFF), at: 26, into: &b)
        b[28] = UInt8(clamped(data.dryingTemp ?? 0, 0...255))
        b[29] = UInt8(clamped(FilamentTagData.wholeDryingHours(fromMinutes: data.dryingTime) ?? 0, 0...255))
        b[30] = UInt8(clamped(data.minBedTemp, 0...255))
        b[31] = UInt8(clamped(data.maxBedTemp, 0...255))

        let unix = Int(date.timeIntervalSince1970.rounded())
        putU32(UInt32(clamped(unix - 946_684_800, 0...Int(UInt32.max))), at: 32, into: &b)

        // Colors 2 and 3 are RGB at +36 and +40, with no alpha: +39 (the tag
        // index) and +43 (reserved) are never written by a color.
        for (offset, hex) in zip([36, 40], data.extraColorsRGB(maxTotal: TagFormat.tigerTag.maxColors)) {
            if let rgb = ColorMatching.parseHex(hex) {
                b[offset] = UInt8((rgb.r * 255).rounded())
                b[offset + 1] = UInt8((rgb.g * 255).rounded())
                b[offset + 2] = UInt8((rgb.b * 255).rounded())
            }
        }
        if let td = data.transmissionDistance, td > 0 {
            putU16(clamped(Int((td * 10).rounded()), 10...1000), at: 44, into: &b)
        }

        if let name = data.name, !name.isEmpty {
            writeTruncatedUTF8(name, maxLength: 28, at: 48, into: &b)
        }

        let available = Int((FilamentTagData.statedMeasurement(data.actualNetWeight) ?? 0).rounded())
        putU24(min(available, 0xFF_FFFF), at: 76, into: &b)

        return (4..<24).map { page in
            let start = (page - 4) * bytesPerPage
            return (page, Data(b[start..<start + bytesPerPage]))
        }
    }

    /// 1.75 and 2.85 are the registry's only diameters; write the nearest,
    /// defaulting to the app standard when the form leaves it blank.
    private static func nearestDiameterID(_ diameter: Double?) -> UInt8 {
        let value = diameter ?? AppConfig.Defaults.diameter
        return abs(value - 1.75) <= abs(value - 2.85) ? 56 : 221
    }

    /// Truncates at a UTF-8 character boundary — the same rule the ACE codec
    /// applies to its string fields, so an emoji never lands split.
    private static func writeTruncatedUTF8(_ string: String, maxLength: Int, at offset: Int, into b: inout [UInt8]) {
        var truncated = string
        while truncated.utf8.count > maxLength { truncated = String(truncated.dropLast()) }
        let bytes = Array(truncated.utf8)
        b.replaceSubrange(offset..<offset + bytes.count, with: bytes)
    }

    private static func clamped(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        max(range.lowerBound, min(range.upperBound, value))
    }

    private static func putU16(_ v: Int, at o: Int, into b: inout [UInt8]) {
        b[o] = UInt8((v >> 8) & 0xFF); b[o + 1] = UInt8(v & 0xFF)
    }

    private static func putU24(_ v: Int, at o: Int, into b: inout [UInt8]) {
        b[o] = UInt8((v >> 16) & 0xFF); b[o + 1] = UInt8((v >> 8) & 0xFF); b[o + 2] = UInt8(v & 0xFF)
    }

    private static func putU32(_ v: UInt32, at o: Int, into b: inout [UInt8]) {
        b[o] = UInt8((v >> 24) & 0xFF); b[o + 1] = UInt8((v >> 16) & 0xFF)
        b[o + 2] = UInt8((v >> 8) & 0xFF); b[o + 3] = UInt8(v & 0xFF)
    }
}
