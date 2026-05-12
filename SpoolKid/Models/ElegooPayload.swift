//
//  ElegooPayload.swift
//  SpoolKid
//
//  Purpose: Decode the ELEGOO RFID tag format.
//  Spec: https://github.com/ELEGOO-3D/ELEGOO-RFID-Tag-Guide
//
//  Format: Raw NFC page reads on NTAG213. NOT NDEF.
//
//  The spec describes two possible physical layouts:
//  1. Byte-striped: each EPC byte occupies byte 0 of consecutive pages
//  2. Contiguous: EPC data fills pages 4-11 sequentially (32 bytes)
//
//  This decoder attempts both layouts and uses whichever produces
//  a valid result.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
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

    // MARK: - Byte-Striped Layout
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

                logger.debug("Elegoo lenient match at page \(page)")
                return decodeEPCBytes(candidateBytes)
            }
        }

        return nil
    }

    private static func decodeCodeBasedBytes(_ bytes: [UInt8]) -> FilamentTagData? {
        guard bytes.count >= 29 else { return nil }

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

        let minNozzle = max(0, baseNozzle - AppConfig.Defaults.nozzleTempOffset)
        let maxNozzle = min(500, baseNozzle + AppConfig.Defaults.nozzleTempOffset)
        let minBed = max(0, baseBed - AppConfig.Defaults.bedTempOffset)
        let maxBed = min(200, baseBed + AppConfig.Defaults.bedTempOffset)

        return FilamentTagData(
            name: nil,
            material: material,
            subtype: nil,
            brand: "ELEGOO",
            colorHex: colorHex,
            minNozzleTemp: minNozzle,
            maxNozzleTemp: maxNozzle,
            minBedTemp: minBed,
            maxBedTemp: maxBed,
            spoolmanId: nil,
            nominalNetWeight: Double(weightRaw)
        )
    }

    private static func materialName(fromCode code: UInt32) -> String? {
        switch code {
        case 0x00807665: return "PLA"
        case 0x80698471: return "PETG"
        case 0x00656683: return "ABS"
        case 0x00848085: return "TPU"
        case 0x00008065: return "PA"
        case 0x00678069: return "CPE"
        case 0x00008067: return "PC"
        case 0x00808665: return "PVA"
        case 0x00658365: return "ASA"
        default: return nil
        }
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
            material: material.isEmpty ? "Unknown" : material,
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
