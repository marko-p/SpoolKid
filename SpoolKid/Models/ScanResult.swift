//
//  ScanResult.swift
//  SpoolKid
//
//  Purpose: Structured output from a single NFC scan session.
//  Emitted by NFCManager after every successful read, regardless of tag format.
//
//  `tagData` is non-nil for any format whose payload was decoded (NDEF formats + ACE + Elegoo).
//  Both `tagData` and `format` may be nil if the scan succeeded at the NFC level
//  but no payload was decoded.
//
//  The Scan Result Hub routes based on:
//    1. tagData?.spoolmanId       → authoritative fast-path (embedded spool ID)
//    2. cardUID present           → Spoolman lot_nr lookup
//    3. tagData present           → heuristic FilamentMatchService scoring
//    4. cardUID only (no tagData) → UID-only mapping UI
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

    /// Decoded filament data. Non-nil for NDEF formats (OpenSpool, OpenTag3D)
    /// and raw page formats (Anycubic ACE, ELEGOO). Nil for unknown/unreadable tags.
    let tagData: FilamentTagData?

    /// Tag format that produced `tagData`. Nil when `tagData` is nil.
    let format: DetectedFormat?

    /// Raw page bytes captured during unknown-format fallback reads.
    /// Present only for debug workflows when raw reads were attempted but no format decoded.
    let rawPageLogBytes: [UInt8]?

    init(
        cardUID: String?,
        tagData: FilamentTagData?,
        format: DetectedFormat?,
        rawPageLogBytes: [UInt8]? = nil
    ) {
        self.cardUID = cardUID
        self.tagData = tagData
        self.format = format
        self.rawPageLogBytes = rawPageLogBytes
    }

    // MARK: - Convenience

    /// True when the tag was detected but its data could not be read.
    var isUnknownFormat: Bool {
        tagData == nil && cardUID != nil
    }

    /// Human-readable description of the tag for display in the hub.
    var displayLabel: String {
        if let format = format {
            return format.displayName
        }
        if cardUID != nil {
            return "Unknown Tag"
        }
        return "Unrecognized Tag"
    }

    // MARK: - Detected format

    enum DetectedFormat: Sendable {
        case openSpool
        case openTag3D
        case anycubicACE
        case elegoo

        var displayName: String {
            switch self {
            case .openSpool:    return "OpenSpool"
            case .openTag3D:    return "OpenTag3D"
            case .anycubicACE:  return "Anycubic ACE"
            case .elegoo:       return "ELEGOO"
            }
        }
    }
}
