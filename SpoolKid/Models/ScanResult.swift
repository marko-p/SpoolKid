//
//  ScanResult.swift
//  SpoolKid
//
//  Purpose: Structured output from a single NFC scan session.
//  Emitted by NFCManager after every successful read, regardless of tag format.
//
//  `tagData` is non-nil for any format whose payload was decoded — the NDEF
//  formats (OpenSpool, OpenPrintTag, OpenTag3D) and the raw-page formats
//  (Anycubic ACE, ELEGOO, TigerTag). Both `tagData` and `format` may be nil
//  if the scan succeeded at the NFC level but no payload was decoded.
//
//  The Scan Result Hub routes based on:
//    0. locationTag present       → location tag; not filament data at all
//    1. tagData?.spoolmanId       → authoritative fast-path (embedded spool ID)
//    2. cardUID present           → tag link lookup (Spoolman Tags, card_uids)
//    3. tagData present           → heuristic FilamentMatchService scoring
//    4. cardUID only (no tagData) → UID-only mapping UI
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
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

    /// A SpoolKid location record read from the tag. When this is non-nil the
    /// tag is a location tag and `tagData` is nil — an NDEF write replaces the
    /// whole message, so the two never coexist.
    let locationTag: LocationTagPayload?

    /// Raw page bytes captured during unknown-format fallback reads.
    /// Present only for debug workflows when raw reads were attempted but no format decoded.
    let rawPageLogBytes: [UInt8]?

    /// Nothing decoded because there is nothing on the tag — see
    /// `TagDumpDecode.isBlank(in:from:)`. False for every decoded read.
    let isBlankTag: Bool

    /// What the scan read, byte for byte, for Clone Tag. Nil for a read with
    /// nothing to copy: a UID-only result, OCR, a QR code.
    let tagSnapshot: TagSnapshot?

    /// TigerTag variant and signature verdict. Nil for every other format.
    let tigerTagInfo: TigerTagInfo?

    /// Web URL found on the tag (e.g. from an NDEF URI record)
    let url: URL?

    /// The Spoolman or FilaMan label a camera QR scan read; nil otherwise.
    var backendLabel: BackendLabel? = nil

    /// OCR-extracted serial number carried through review when routing to scan hub.
    let ocrSerialNumber: String?

    /// OCR-extracted filament diameter in millimeters carried through review when routing to scan hub.
    let ocrDiameterMM: Double?

    /// OCR-extracted filament name carried through review when routing to scan hub.
    let ocrFilamentName: String?

    /// OCR-extracted filament subtype carried through review when routing to scan hub.
    let ocrSubtype: String?

    /// OCR-extracted nominal net weight in grams carried through review when routing to scan hub.
    let ocrNominalNetWeightG: Double?

    /// Full OCR parsed candidate for review/editing when tapping on filament card.
    let ocrCandidate: OCRParsedCandidate?

    /// JPEG image of the label captured during OCR scanning. Non-nil only when the alpha archive toggle is ON.
    var ocrCapturedImageData: Data? = nil

    /// What the scan learned about the tag itself, for Inspect Tag. Non-nil
    /// for every NFC read, nil for OCR and QR results. Attached by
    /// `NFCManager.attaching`; nothing that routes the result reads it.
    var inspection: TagInspection? = nil

    /// True when a toolhead's reader could not reach the tag (a Snapmaker or
    /// MIFARE Classic tag) and this is the printer's own report of it, not a
    /// read of the tag. Always false on the iPhone path.
    var isReportedByPrinter = false

    init(
        cardUID: String?,
        tagData: FilamentTagData?,
        format: DetectedFormat?,
        locationTag: LocationTagPayload? = nil,
        rawPageLogBytes: [UInt8]? = nil,
        isBlankTag: Bool = false,
        url: URL? = nil,
        ocrSerialNumber: String? = nil,
        ocrDiameterMM: Double? = nil,
        ocrFilamentName: String? = nil,
        ocrSubtype: String? = nil,
        ocrNominalNetWeightG: Double? = nil,
        ocrCandidate: OCRParsedCandidate? = nil,
        tagSnapshot: TagSnapshot? = nil,
        tigerTagInfo: TigerTagInfo? = nil
    ) {
        self.cardUID = cardUID
        self.tagData = tagData
        self.format = format
        self.locationTag = locationTag
        self.rawPageLogBytes = rawPageLogBytes
        self.isBlankTag = isBlankTag
        self.url = url
        self.ocrSerialNumber = ocrSerialNumber
        self.ocrDiameterMM = ocrDiameterMM
        self.ocrFilamentName = ocrFilamentName
        self.ocrSubtype = ocrSubtype
        self.ocrNominalNetWeightG = ocrNominalNetWeightG
        self.ocrCandidate = ocrCandidate
        self.tagSnapshot = tagSnapshot
        self.tigerTagInfo = tigerTagInfo
    }

    // MARK: - Convenience

    /// True when the tag was detected but its data could not be read.
    var isUnknownFormat: Bool {
        tagData == nil && cardUID != nil
    }

    /// The hub's note on a tag nothing decoded, or nil when something did.
    var undecodedTagNote: String? {
        guard isUnknownFormat else { return nil }
        return isBlankTag ? "Empty tag" : "Unknown tag format"
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

    nonisolated enum DetectedFormat: Sendable {
        case openSpool
        case openPrintTag
        case openTag3D
        case anycubicACE
        case elegoo
        case tigerTag
        case webUrl
        case backendLabel
        case ocr

        var displayName: String {
            switch self {
            case .openSpool:    return "OpenSpool"
            case .openPrintTag: return "OpenPrintTag"
            case .openTag3D:    return "OpenTag3D"
            case .anycubicACE:  return "Anycubic ACE"
            case .elegoo:       return "ELEGOO"
            case .tigerTag:     return "TigerTag"
            case .webUrl:       return "Web URL"
            case .backendLabel: return "Label QR"
            case .ocr:          return "OCR Scan"
            }
        }

        /// The format SpoolKid writes for a tag read in this one; nil for the
        /// read-only sources.
        @MainActor var tagFormat: TagFormat? {
            switch self {
            case .openSpool: .openSpool
            case .openPrintTag: .openPrintTag
            case .openTag3D: .openTag3D
            case .anycubicACE: .anycubicACE
            case .elegoo: .elegoo
            case .tigerTag: .tigerTag
            case .webUrl, .backendLabel, .ocr: nil
            }
        }
    }
}
