//
//  TagSnapshot.swift
//  SpoolKid
//
//  Purpose: What a scan read off a tag, kept byte for byte so Clone Tag can
//  write it onto another tag. The codecs decode what SpoolKid understands and
//  drop the rest, so a copy written from their output is not a copy.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import CoreNFC

/// `nonisolated`: `NFCManager` builds this on CoreNFC's callback queue and
/// reads it there again when writing a copy.
nonisolated enum TagSnapshot: Equatable, Sendable {
    /// Every record of the tag's NDEF message, in order.
    ///
    /// Exact at the record level: TNF, type, ID and payload, in order. CoreNFC
    /// writes record headers canonically, so a chunked record comes back whole.
    /// The capability container, lock bytes and TLV placement belong to the
    /// tag the copy lands on, and differ between tag families — an NTAG's
    /// layout written onto an ICODE SLIX2 would not be a readable tag.
    case ndef([NDEFRecordSnapshot])

    /// Raw NTAG pages from `firstPage`, four bytes each. Never pages 0-3: the
    /// UID, lock bytes and capability container are the chip's, not content.
    case rawPages(firstPage: Int, bytes: [UInt8])

    static let bytesPerPage = 4

    /// The first page past the UID, lock bytes and capability container.
    static let firstUserPage = 4

    /// The records of a message just read. Named apart from the `ndef` case so
    /// the two cannot be confused at a call site.
    static func capturing(_ records: [NFCNDEFPayload]) -> TagSnapshot {
        .ndef(records.map(NDEFRecordSnapshot.init(record:)))
    }

    /// Pages `firstPage...lastPage` of a raw read buffer indexed from page 0.
    /// Nil when the buffer stops short: a copy missing its last pages is not a
    /// copy, and the raw formats read fixed offsets, so a short one would still
    /// look plausible on the printer.
    static func capturingPages(_ buffer: [UInt8], firstPage: Int, lastPage: Int) -> TagSnapshot? {
        guard firstPage >= 0, lastPage >= firstPage else { return nil }
        let start = firstPage * bytesPerPage
        let end = (lastPage + 1) * bytesPerPage
        guard buffer.count >= end else { return nil }
        return .rawPages(firstPage: firstPage, bytes: Array(buffer[start..<end]))
    }

    /// The records to write back. Nil for a raw snapshot, which has none.
    func records() -> [NFCNDEFPayload]? {
        guard case .ndef(let snapshots) = self else { return nil }
        return snapshots.map { $0.record() }
    }

    /// Whether there is anything to write. A message with no records, or a raw
    /// buffer that is not whole pages, is not a copy of anything.
    var isCopyable: Bool {
        switch self {
        case .ndef(let records):
            return !records.isEmpty
        case .rawPages(_, let bytes):
            return !bytes.isEmpty && bytes.count % Self.bytesPerPage == 0
        }
    }

    /// One WRITE (0xA2) per page, in order. Empty for an NDEF snapshot.
    var pageWrites: [(page: Int, data: Data)] {
        guard case .rawPages(let firstPage, let bytes) = self else { return [] }
        return (0..<(bytes.count / Self.bytesPerPage)).map { index in
            let start = index * Self.bytesPerPage
            return (page: firstPage + index, data: Data(bytes[start..<start + Self.bytesPerPage]))
        }
    }
}

/// One NDEF record as plain bytes. `NFCNDEFPayload` is a class and not
/// `Sendable`, so it cannot ride on `ScanResult` across queues.
nonisolated struct NDEFRecordSnapshot: Equatable, Sendable {
    /// `NFCTypeNameFormat.rawValue`.
    let typeNameFormat: UInt8
    let type: Data
    let identifier: Data
    let payload: Data
}

nonisolated extension NDEFRecordSnapshot {
    init(record: NFCNDEFPayload) {
        self.init(
            typeNameFormat: record.typeNameFormat.rawValue,
            type: record.type,
            identifier: record.identifier,
            payload: record.payload
        )
    }

    /// `NFCTypeNameFormat` is an Objective-C enum, so any byte converts; the
    /// fallback only exists because the initializer is spelled failable.
    func record() -> NFCNDEFPayload {
        NFCNDEFPayload(
            format: NFCTypeNameFormat(rawValue: typeNameFormat) ?? .unknown,
            type: type,
            identifier: identifier,
            payload: payload
        )
    }
}
