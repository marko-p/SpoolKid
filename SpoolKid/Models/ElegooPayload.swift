//
//  ElegooPayload.swift
//  SpoolKid
//
//  Purpose: Decode and encode the ELEGOO RFID tag format.
//  Spec: https://github.com/ELEGOO-3D/ELEGOO-RFID-Tag-Guide
//
//  Format: Raw NFC page reads on NTAG213.
//
//  Real tags ARE NDEF — pages 4-9 carry a URI record for elegoo.com — and the
//  proprietary block sits in user memory AFTER the NDEF terminator, at page 16.
//  An NDEF reader therefore sees only the URL. Everything ELEGOO puts on the
//  spool lives in that block, which is why this codec reads raw pages.
//
//  The block always opens `36 EE EE EE EE`. Three layouts are attempted:
//  1. Byte-striped: each EPC byte occupies byte 0 of consecutive pages
//  2. Contiguous:   EPC data fills pages 4-11 sequentially (32 bytes)
//  3. Lenient scan: the signature is found at any page boundary
//
//  Layouts 1 and 2 come from the published guide. Every tag captured from real
//  hardware so far (5 spools, 2026-05 and 2026-09) uses layout 3 with the block
//  at page 16, so the scan is the path that matters in practice.
//
//  Block layout (offsets from the `36` signature byte), as captured:
//    0      = 0x36 signature          8-11  = material, BCD-ASCII
//    1-4    = 0xEEEEEEEE manufacturer 12-13 = Canvas type index, subtype ID
//    16-19  = colour RGBA             20-21 = nozzle min °C
//    22-23  = nozzle max °C           28-29 = diameter ÷ 0.01 mm
//    30-31  = net weight, grams
//  Bytes 5-7, 14-15, 24-27 and 32-34 are unidentified. They are identical on
//  every tag captured (`00`s, and `00 36 C8` at 32-34), so nothing is inferred
//  from them rather than guessed. Bytes 12-13 are named by DnG-Crafts' dump and
//  `ElegooCanvasCatalog`; every factory spool captured is PLA, so both are 0.
//
//  Writing produces the factory image only: pages 4-39 with the elegoo.com
//  link and the block at page 16 (`encodePages`).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.spoolkid", category: "ElegooPayload")

struct ElegooPayload {

    // MARK: - Constants

    static let headerByte: UInt8 = 0x36
    static let manufacturerCode: UInt32 = 0xEEEEEEEE

    /// Pages to read via NTAG READ (0x30). Each read returns 16 bytes (4 pages).
    static let readPages: [Int] = [4, 8, 12, 16, 20, 24, 28, 32]

    static let bytesPerPage: Int = 4

    // MARK: - Encode

    /// The smallest chip a Canvas can read a tag from: it reads pages 0-44,
    /// which is all of an NTAG213.
    static let minChipPageCount = 45

    /// Pages 4-9 of every factory spool: a lock-control TLV and an NDEF URI
    /// record for https://www.elegoo.com, terminated. Copied byte for byte —
    /// the printer ignores it, but it is the image every Canvas has seen.
    private static let factoryLinkPages: [UInt8] = [
        0x01, 0x03, 0xA0, 0x0C, 0x34, 0x03, 0x0F, 0xD1, 0x01, 0x0B, 0x55, 0x02,
        0x65, 0x6C, 0x65, 0x67, 0x6F, 0x6F, 0x2E, 0x63, 0x6F, 0x6D, 0xFE, 0x00
    ]

    /// Pages 4-39 of a factory spool carrying `data`: the elegoo.com link, the
    /// block at page 16, and zeroes over everything else in user memory so a
    /// previous format leaves nothing behind. Empty when the Canvas has no
    /// entry for the material and subtype, or the colour does not parse —
    /// nothing is written that the printer would read as something else.
    static func encodePages(from data: FilamentTagData) -> [(page: Int, data: Data)] {
        guard let entry = ElegooCanvasCatalog.entry(forTagMaterial: data.material, subtype: data.subtype),
              let materialCode = materialCode(for: entry.material),
              let rgb = ColorMatching.parseHex(data.colorHex) else {
            logger.error("ELEGOO encode refused: no Canvas entry or colour for material=\(data.material, privacy: .public)")
            return []
        }

        var block = [UInt8](repeating: 0, count: 36)
        block[0] = headerByte
        putU32(manufacturerCode, at: 1, into: &block)
        putU32(materialCode, at: 8, into: &block)
        block[12] = entry.typeIndex
        block[13] = entry.subtypeID
        block[16] = UInt8((rgb.r * 255).rounded())
        block[17] = UInt8((rgb.g * 255).rounded())
        block[18] = UInt8((rgb.b * 255).rounded())
        block[19] = 0xFF
        putU16(data.minNozzleTemp, at: 20, into: &block)
        putU16(data.maxNozzleTemp, at: 22, into: &block)
        let diameter = data.diameter ?? AppConfig.Defaults.diameter
        putU16(Int((diameter * 100).rounded()), at: 28, into: &block)
        let grams = FilamentTagData.statedMeasurement(data.nominalNetWeight) ?? AppConfig.Defaults.nominalNetWeight
        putU16(Int(grams.rounded()), at: 30, into: &block)
        // Identical on every captured tag; its meaning is unknown.
        block[33] = 0x36
        block[34] = 0xC8

        var image = [UInt8](repeating: 0, count: 36 * bytesPerPage)   // pages 4-39
        image.replaceSubrange(0..<factoryLinkPages.count, with: factoryLinkPages)
        image.replaceSubrange(48..<48 + block.count, with: block)       // page 16
        return (4...39).map { page in
            let start = (page - 4) * bytesPerPage
            return (page, Data(image[start..<start + bytesPerPage]))
        }
    }

    /// The inverse of `materialName(fromCode:)`: each character's decimal code
    /// as two BCD digits, right-aligned in four bytes.
    static func materialCode(for name: String) -> UInt32? {
        let scalars = Array(name.unicodeScalars)
        guard (1...4).contains(scalars.count) else { return nil }
        var code: UInt32 = 0
        for scalar in scalars {
            guard scalar.value < 100 else { return nil }
            code = code << 8 | (scalar.value / 10) << 4 | scalar.value % 10
        }
        guard materialName(fromCode: code) == name else { return nil }
        return code
    }

    private static func putU16(_ value: Int, at offset: Int, into bytes: inout [UInt8]) {
        let clamped = UInt16(min(max(value, 0), Int(UInt16.max)))
        bytes[offset] = UInt8(clamped >> 8)
        bytes[offset + 1] = UInt8(clamped & 0xFF)
    }

    private static func putU32(_ value: UInt32, at offset: Int, into bytes: inout [UInt8]) {
        for index in 0..<4 {
            bytes[offset + index] = UInt8((value >> UInt32(24 - index * 8)) & 0xFF)
        }
    }

    // MARK: - Decode

    /// Decodes from a flat byte array of raw NFC page data starting from page 0.
    /// Expects at least enough bytes to cover pages 0-35 (144 bytes for NTAG213).
    static func decode(from pages: [UInt8]) -> FilamentTagData? {
        guard pages.count >= 36 * bytesPerPage else {
            logger.debug("Buffer too small: \(pages.count) bytes, need 144")
            return nil
        }

        // Log the first 48 bytes of raw page data for debugging
        let preview = pages.prefix(48).map { String(format: "%02X", $0) }.joined(separator: " ")
        logger.debug("Elegoo raw page data [0..<48]: \(preview)")

        // Try byte-striped layout first (spec's most literal interpretation)
        if let result = decodeByteStriped(pages: pages) {
            logger.debug("Elegoo decode succeeded (byte-striped)")
            return result
        }

        // Fall back to contiguous layout
        if let result = decodeContiguous(pages: pages) {
            logger.debug("Elegoo decode succeeded (contiguous)")
            return result
        }

        // Lenient fallback: just look for the header byte anywhere in page 4-11
        if let result = decodeLenient(pages: pages) {
            logger.debug("Elegoo decode succeeded (lenient)")
            return result
        }

        logger.debug("Elegoo decode failed: no layout matched")
        return nil
    }

    // MARK: - Byte-Striped Layoute
    // Each EPC byte occupies byte 0 of consecutive pages starting from page 4.

    private static func decodeByteStriped(pages: [UInt8]) -> FilamentTagData? {
        // Extract EPC bytes: byte 0 of each page from 4 through 35
        var epcBytes = [UInt8]()
        for page in 4..<36 {
            let offset = page * bytesPerPage
            guard offset < pages.count else { break }
            epcBytes.append(pages[offset])
        }

        guard epcBytes.count >= 24 else { return nil }

        let preview = epcBytes.prefix(24).map { String(format: "%02X", $0) }.joined(separator: " ")
        logger.debug("Elegoo byte-striped EPC bytes: \(preview)")

        guard epcBytes[0] == headerByte else {
            logger.debug("Elegoo byte-striped header mismatch: got 0x\(String(format: "%02X", epcBytes[0]))")
            return nil
        }

        let mfrCode = (UInt32(epcBytes[1]) << 24)
            | (UInt32(epcBytes[2]) << 16)
            | (UInt32(epcBytes[3]) << 8)
            | UInt32(epcBytes[4])
        guard mfrCode == manufacturerCode else {
            logger.debug("Elegoo byte-striped manufacturer mismatch: got 0x\(String(format: "%08X", mfrCode))")
            return nil
        }

        return decodeEPCBytes(epcBytes)
    }

    // MARK: - Contiguous Layout
    // EPC data fills pages 4-11 sequentially (32 bytes contiguous).

    private static func decodeContiguous(pages: [UInt8]) -> FilamentTagData? {
        // Pages 4-11 = 8 pages × 4 bytes = 32 bytes
        let startOffset = 4 * bytesPerPage // byte 16
        let endOffset = 12 * bytesPerPage    // byte 48
        guard endOffset <= pages.count else { return nil }

        let epcBytes = Array(pages[startOffset..<endOffset])

        let preview = epcBytes.prefix(24).map { String(format: "%02X", $0) }.joined(separator: " ")
        logger.debug("Elegoo contiguous EPC bytes: \(preview)")

        guard epcBytes[0] == headerByte else {
            logger.debug("Elegoo contiguous header mismatch: got 0x\(String(format: "%02X", epcBytes[0]))")
            return nil
        }

        let mfrCode = (UInt32(epcBytes[1]) << 24)
            | (UInt32(epcBytes[2]) << 16)
            | (UInt32(epcBytes[3]) << 8)
            | UInt32(epcBytes[4])
        guard mfrCode == manufacturerCode else {
            logger.debug("Elegoo contiguous manufacturer mismatch: got 0x\(String(format: "%08X", mfrCode))")
            return nil
        }

        return decodeEPCBytes(epcBytes)
    }

    // MARK: - Lenient Fallback
    // Scans page byte 0s for header, then tries additional decode layouts.

    private static func decodeLenient(pages: [UInt8]) -> FilamentTagData? {
        let totalPages = pages.count / bytesPerPage

        // Search for header byte 0x36 at byte 0 from page 4 onward
        for page in 4..<totalPages {
            let offset = page * bytesPerPage
            guard offset < pages.count else { break }
            guard pages[offset] == headerByte else { continue }

            let candidateBytes = Array(pages[offset..<pages.count])
            guard candidateBytes.count >= 32 else { continue }

            let mfrCode = (UInt32(candidateBytes[1]) << 24)
                | (UInt32(candidateBytes[2]) << 16)
                | (UInt32(candidateBytes[3]) << 8)
                | UInt32(candidateBytes[4])

            if mfrCode == manufacturerCode {
                if let result = decodeCodeBasedBytes(candidateBytes) {
                    logger.debug("Elegoo lenient code-based match at page \(page)")
                    return result
                }

                if let result = decodeEPCBytes(candidateBytes) {
                    logger.debug("Elegoo lenient match at page \(page)")
                    return result
                }

                // A signature with nothing readable behind it is not a decode.
                logger.debug("Elegoo signature at page \(page) carried no readable block")
            }
        }

        return nil
    }

    private static func decodeCodeBasedBytes(_ bytes: [UInt8]) -> FilamentTagData? {
        // Indexes through 31 are read below; the old guard of 29 was three
        // short of the weight field it goes on to read.
        guard bytes.count >= 32 else { return nil }

        // Variant observed in real-world ELEGOO tags where material is stored as a code,
        // and diameter/weight appear later in the block.
        let materialCode = (UInt32(bytes[8]) << 24)
            | (UInt32(bytes[9]) << 16)
            | (UInt32(bytes[10]) << 8)
            | UInt32(bytes[11])
        guard let material = materialName(fromCode: materialCode) else { return nil }

        let colorHex = String(format: "%02X%02X%02X", bytes[16], bytes[17], bytes[18])

        let diameterRaw = (UInt16(bytes[28]) << 8) | UInt16(bytes[29])
        let weightRaw = (UInt16(bytes[30]) << 8) | UInt16(bytes[31])

        // Basic sanity checks to avoid false positives when scanning for header blocks.
        guard diameterRaw >= 50, diameterRaw <= 300 else { return nil }
        guard weightRaw >= 50, weightRaw <= 5000 else { return nil }

        let preset = AppConfig.materialPresets[material]
        let baseNozzle = preset?.extruder ?? AppConfig.Defaults.extruderTemp
        let baseBed = preset?.bed ?? AppConfig.Defaults.bedTemp

        // Bytes 20-23 are the nozzle range ELEGOO prints on the spool. Zero is
        // the tag declining to say rather than a temperature, so it falls back
        // to the preset. Bytes 24-27 sit where a bed range would, but they are
        // zero on every tag captured, so nothing is read from them: a guess
        // that happens to be unobservable today is still a guess.
        let minNozzle = statedTemperature(bytes, at: 20)
            ?? max(0, baseNozzle - AppConfig.Defaults.nozzleTempOffset)
        let maxNozzle = statedTemperature(bytes, at: 22)
            ?? min(500, baseNozzle + AppConfig.Defaults.nozzleTempOffset)
        let minBed = max(0, baseBed - AppConfig.Defaults.bedTempOffset)
        let maxBed = min(200, baseBed + AppConfig.Defaults.bedTempOffset)

        // Bytes 12-13 are the Canvas type index and subtype ID. An ID the
        // catalog does not hold, or a type that contradicts the material, is
        // left unread rather than refused: the block is still a spool.
        var subtype: String?
        if let entry = ElegooCanvasCatalog.entry(typeIndex: bytes[12], subtypeID: bytes[13]),
           entry.material == material {
            subtype = ElegooCanvasCatalog.tagFields(for: entry).subtype
        }

        return FilamentTagData(
            name: nil,
            material: material,
            subtype: subtype,
            brand: "ELEGOO",
            colorHex: colorHex,
            minNozzleTemp: minNozzle,
            maxNozzleTemp: maxNozzle,
            minBedTemp: minBed,
            maxBedTemp: maxBed,
            spoolmanId: nil,
            diameter: Double(diameterRaw) / 100,
            nominalNetWeight: Double(weightRaw)
        )
    }

    /// A temperature the tag states, in °C. Zero means the field is unset —
    /// no filament prints at 0 °C, so the two are not ambiguous here.
    private static func statedTemperature(_ bytes: [UInt8], at offset: Int) -> Int? {
        let value = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        return value == 0 ? nil : value
    }

    /// The material name is ASCII stored as BCD of each character's decimal
    /// code: `80 76 65` is 80, 76, 65 — "PLA". Names are right-aligned in the
    /// four-byte field and zero-padded.
    ///
    /// This replaced a nine-entry lookup table, which every code in the
    /// guide's material list decodes to arithmetically (pinned by
    /// `ElegooPayloadTests`). The table was a transcription, and a material
    /// ELEGOO shipped but nobody had listed fell through to a layout that read
    /// the colour three bytes early and the nozzle minimum as a weight.
    static func materialName(fromCode code: UInt32) -> String? {
        var name = ""
        for shift in stride(from: 24, through: 0, by: -8) {
            let byte = UInt8((code >> UInt32(shift)) & 0xFF)
            guard byte != 0 else { continue }   // leading pad
            let tens = byte >> 4
            let units = byte & 0x0F
            guard tens <= 9, units <= 9 else { return nil }
            let value = Int(tens) * 10 + Int(units)
            // Uppercase letters, digits, and the +/- that name blends.
            let isName = (65...90).contains(value)
                || (48...57).contains(value)
                || value == 43 || value == 45
            guard isName else { return nil }
            name.append(Character(UnicodeScalar(UInt8(value))))
        }
        return name.isEmpty ? nil : name
    }

    // MARK: - EPC Decoding (common)

    private static func decodeEPCBytes(_ epcBytes: [UInt8]) -> FilamentTagData? {
        guard epcBytes.count >= 24 else { return nil }

        // Material fields are ASCII, null/space padded
        let materialName = readASCIIString(epcBytes, start: 7, length: 4)
        let materialSupplement = readASCIIString(epcBytes, start: 11, length: 4)

        let colorHex = String(format: "%02X%02X%02X", epcBytes[15], epcBytes[16], epcBytes[17])

        let weightRaw = (UInt16(epcBytes[20]) << 8) | UInt16(epcBytes[21])

        let material = materialName.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtype = materialSupplement.trimmingCharacters(in: .whitespacesAndNewlines)

        // Without a material this is not an ELEGOO block, whatever sits at the
        // signature bytes. It used to be reported as material "Unknown" with
        // every other field read at the wrong offset.
        guard !material.isEmpty else { return nil }

        // Derive sensible temperature defaults from material preset if known
        let preset = AppConfig.materialPresets[material]
        let baseNozzle = preset?.extruder ?? AppConfig.Defaults.extruderTemp
        let baseBed = preset?.bed ?? AppConfig.Defaults.bedTemp

        let minNozzle = max(0, baseNozzle - AppConfig.Defaults.nozzleTempOffset)
        let maxNozzle = min(500, baseNozzle + AppConfig.Defaults.nozzleTempOffset)
        let minBed = max(0, baseBed - AppConfig.Defaults.bedTempOffset)
        let maxBed = min(200, baseBed + AppConfig.Defaults.bedTempOffset)

        return FilamentTagData(
            name: nil,
            material: material,
            subtype: subtype.isEmpty ? nil : subtype,
            brand: "ELEGOO",
            colorHex: colorHex,
            minNozzleTemp: minNozzle,
            maxNozzleTemp: maxNozzle,
            minBedTemp: minBed,
            maxBedTemp: maxBed,
            spoolmanId: nil,
            nominalNetWeight: weightRaw > 0 ? Double(weightRaw) : nil
        )
    }

    // MARK: - Helpers

    private static func readASCIIString(_ bytes: [UInt8], start: Int, length: Int) -> String {
        guard start + length <= bytes.count else { return "" }
        let slice = bytes[start..<start + length]
        // Trim trailing nulls and spaces
        let trimmed = slice.reversed().drop(while: { $0 == 0 || $0 == 0x20 }).reversed()
        return String(bytes: trimmed, encoding: .ascii) ?? ""
    }
}
