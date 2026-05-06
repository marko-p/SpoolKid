//
//  BambuTagProbe.swift
//  SpoolKid
//
//  Purpose: Heuristic detection of Bambu Lab NFC tags based on MIFARE identifier bytes.
//
//  iOS CoreNFC cannot authenticate MIFARE Classic sectors, so all data blocks
//  are inaccessible. Only the UID (NFCMiFareTag.identifier) is readable.
//
//  Detection heuristic:
//  - 7-byte identifier (standard NXP MIFARE Classic 1K/4K identifier length)
//  - First byte == 0x04 (NXP manufacturer code in ISO 14443-3A cascade tag UIDs)
//
//  This is a probabilistic heuristic, not a cryptographic proof.
//  The display label "Bambu Lab (encrypted)" is only used when both conditions match.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import Foundation

// MARK: - Result

struct BambuTagProbeResult: Sendable {
    /// Whether this tag matches the Bambu Lab MIFARE heuristic.
    let couldBeBambu: Bool
    /// Always true: iOS CoreNFC cannot read MIFARE Classic data sectors.
    let dataEncrypted: Bool
    /// Normalized lowercase hex UID (no separators).
    let normalizedUID: String
    /// Human-readable label for display in the scan result UI.
    let displayLabel: String
}

// MARK: - Probe

enum BambuTagProbe {

    private static let bambuIdentifierLength = 7
    private static let nxpManufacturerByte: UInt8 = 0x04

    // MARK: Public API

    /// Probe an NFC tag using its raw identifier bytes.
    /// - Parameters:
    ///   - identifierBytes: Raw bytes from `NFCMiFareTag.identifier`.
    ///   - ndefPayload: Optional NDEF payload data (reserved for future use).
    static func probe(identifierBytes: [UInt8], ndefPayload: Data?) -> BambuTagProbeResult {
        let uid = normalizeUID(bytes: identifierBytes)
        let isBambu = couldBeBambuTag(identifierBytes: identifierBytes)
        return BambuTagProbeResult(
            couldBeBambu: isBambu,
            dataEncrypted: true,
            normalizedUID: uid,
            displayLabel: isBambu ? "Bambu Lab (encrypted)" : "Encrypted MIFARE Classic"
        )
    }

    /// Convert raw identifier bytes to a lowercase hex string without separators.
    static func normalizeUID(bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Private helpers

    private static func couldBeBambuTag(identifierBytes: [UInt8]) -> Bool {
        guard identifierBytes.count == bambuIdentifierLength else { return false }
        return identifierBytes[0] == nxpManufacturerByte
    }
}
