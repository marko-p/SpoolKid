//
//  TagCapacityEstimator.swift
//  SpoolKid
//
//  Purpose: Decomposes an OpenPrintTag NDEF message into byte segments
//  (NFC-V overhead / Material / URL / Printer countdown) against a nominal
//  ICODE SLIX2 budget, for the Write Tag capacity gauge. Advisory only — the
//  authoritative capacity check stays in NFCManager.handleNDEFWrite.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import CoreNFC

enum TagCapacityEstimator {
    /// What CoreNFC reports for a 312 B ICODE SLIX2 (Prusament Type 5) tag, in
    /// bytes. A planning guide only — not a hard gate.
    static let slix2Capacity = 304

    struct Breakdown: Equatable {
        let material: Int
        let url: Int
        let overhead: Int
        let capacity: Int
        /// The aux region, where a Prusa printer keeps its countdown.
        var aux: Int = 0
        /// Whether the layout also wrote a filament length, the one thing that
        /// lets a Prusa printer count the spool down in the aux region.
        var countsDown: Bool = false

        var total: Int { material + url + overhead + aux }
        var free: Int  { max(0, capacity - total) }
        var over: Int  { max(0, total - capacity) }
        var fits: Bool { total <= capacity }
    }

    /// Breaks the encoded NDEF message into NFC-V / Material / URL / Printer
    /// countdown segments against the SLIX2 budget. OpenPrintTag is measured in
    /// Prusa's layout, so the padding between main and aux is left out of
    /// `total` and counts as free; when that layout does not fit it is the
    /// unpadded record. Returns nil when the data can't be encoded for `format`
    /// or the format has no NDEF MIME type.
    static func breakdown(for data: FilamentTagData,
                          format: TagFormat,
                          urlString: String?) -> Breakdown? {
        guard let mime = format.mimeType,
              let cbor = TagFormatService.shared.encode(data: data, format: format) else {
            return nil
        }
        if format == .openPrintTag,
           let laid = OpenPrintTagLayout.layout(for: data, urlString: urlString,
                                                capacity: slix2Capacity, isSLIX2: true) {
            let withoutURL = NFCNDEFMessage(records:
                NFCManager.ndefRecords(mimePayload: laid.payload, mimeType: mime, urlString: nil)).length
            let url = max(0, laid.messageLength - withoutURL)
            let aux = laid.auxOffset.map { laid.payload.count - $0 } ?? 0
            return Breakdown(material: laid.sectionsLength, url: url,
                             overhead: laid.messageLength - laid.payload.count - url,
                             capacity: slix2Capacity, aux: aux, countsDown: laid.writesLength)
        }
        // No layout fits, which for an OpenPrintTag means the write refuses it.
        // Judge the unpadded record against the room the layout may use (a
        // byte short of CoreNFC's figure), so one the write would refuse never
        // shows as fitting.
        let withoutURL = NFCNDEFMessage(records:
            NFCManager.ndefRecords(mimePayload: cbor, mimeType: mime, urlString: nil)).length
        let withURL = NFCNDEFMessage(records:
            NFCManager.ndefRecords(mimePayload: cbor, mimeType: mime, urlString: urlString)).length
        let material = cbor.count
        let url = max(0, withURL - withoutURL)
        let overhead = max(0, withoutURL - material)
        return Breakdown(material: material, url: url, overhead: overhead,
                         capacity: OpenPrintTagLayout.messageCeiling(capacity: slix2Capacity, isSLIX2: true))
    }
}
