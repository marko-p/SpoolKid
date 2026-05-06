//
//  ScanResult.swift
//  SpoolKid
//
//  Purpose: Structured output from a single NFC scan session.
//  Emitted by NFCManager after every successful read, regardless of tag format.
//
//  `tagData` is non-nil for any format whose payload was decoded (NDEF formats + ACE).
//  `bambuProbe` is non-nil only for MIFARE tags (encrypted or plaintext NXP tags).
//  Both may be nil if the scan succeeded at the NFC level but no payload was decoded.
//
//  The Scan Result Hub (Phase 3) routes based on:
//    1. tagData?.spoolmanId       → authoritative fast-path (embedded spool ID)
//    2. cardUID present           → Spoolman lot_nr lookup
//    3. tagData present           → heuristic FilamentMatchService scoring
//    4. bambuProbe present        → encrypted-tag UI with UID copy affordance
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import Foundation

struct ScanResult: Sendable {

    // MARK: - Tag identity

    /// Normalized lowercase hex UID (no separators), if available.
    /// Populated for all MIFARE tags (both classic and NTAG/Ultralight families).
    /// May be nil for ISO 15693 tags — not currently supported.
    let cardUID: String?

    // MARK: - Decoded payload

    /// Decoded filament data. Non-nil for NDEF formats (OpenSpool, OpenPrintTag,
    /// OpenTag3D) and Anycubic ACE raw pages. Nil for encrypted/unreadable tags.
    let tagData: FilamentTagData?

    /// Tag format that produced `tagData`. Nil when `tagData` is nil.
    let format: DetectedFormat?

    // MARK: - Bambu / MIFARE Classic probe

    /// Non-nil when the scanned tag is a MIFARE-family tag.
    /// Always present alongside `cardUID` for such tags.
    let bambuProbe: BambuTagProbeResult?

    // MARK: - Convenience

    /// True when the tag was detected but its data could not be read (encrypted).
    var isEncrypted: Bool {
        bambuProbe?.dataEncrypted == true && tagData == nil
    }

    /// Human-readable description of the tag for display in the hub.
    var displayLabel: String {
        if let probe = bambuProbe {
            return probe.displayLabel
        }
        if let format = format {
            return format.displayName
        }
        return "Unknown Tag"
    }

    // MARK: - Detected format

    enum DetectedFormat: Sendable {
        case openSpool
        case openPrintTag
        case openTag3D
        case anycubicACE

        var displayName: String {
            switch self {
            case .openSpool:    return "OpenSpool"
            case .openPrintTag: return "OpenPrintTag"
            case .openTag3D:    return "OpenTag3D"
            case .anycubicACE:  return "Anycubic ACE"
            }
        }
    }
}
