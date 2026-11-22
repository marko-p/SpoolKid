//
//  TagDumpDecode.swift
//  SpoolKid
//
//  Purpose: Say what a raw dump actually is.
//
//  The explorer's "Decoded as" row used to attempt exactly one format —
//  Anycubic ACE — and report "Nothing recognised it" for everything else. A
//  SpoolKid-written OpenSpool tag that the Scan Hub reads perfectly therefore
//  came back unrecognised (owner device pass, 2026-09-07). The row promises a
//  general answer, so it has to try what SpoolKid can actually read.
//
//  NDEF tags keep their message inside a TLV chain in user memory, so getting
//  from raw pages to a decodable payload means walking that chain. That walk
//  is pure arithmetic over bytes and lives here, where it can be tested
//  against a real dump instead of a tag.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import CoreNFC

nonisolated enum TagDumpDecode {

    /// What the explorer says when a tag carries a readable NDEF message in a
    /// format SpoolKid has no decoder for. Distinct from recognising nothing:
    /// the tag IS an NDEF tag, which is the useful half of the answer.
    static let unrecognisedNDEF = "NDEF, but no format SpoolKid knows"

    static let locationTag = "SpoolKid location tag"

    /// Where a TLV chain can begin, by tag family.
    ///
    /// Type 2 (NTAG, Ultralight): pages 0-3 are UID, lock bytes and the
    /// capability container, so user memory starts at page 4 — byte 16.
    /// Type 5 (ISO 15693): the capability container occupies the first block
    /// and is 4 or 8 bytes wide, so the chain starts at one of those.
    ///
    /// Tried in order, and each one verified before the next is abandoned —
    /// see `nameForNDEF(in:)`. The walk rejects most wrong guesses on its own
    /// (the byte at a wrong offset is rarely a valid TLV type), but not all
    /// of them: a Type 5 tag's message content can contain a `0x03` and a
    /// plausible length at byte 16, which parses and means nothing.
    static let tlvStartOffsets = [16, 4, 8]

    /// Walks the TLV chain from one candidate offset.
    ///
    /// Returns nil rather than guessing whenever the chain stops making
    /// sense — a partial match at the wrong offset must fail so the next
    /// offset gets its turn.
    static func ndefMessageBytes(in bytes: [UInt8], from start: Int) -> [UInt8]? {
        guard case .message(let message) = walkTLVChain(in: bytes, from: start) else { return nil }
        return message
    }

    /// True when a tag's user memory holds nothing: never formatted (all
    /// padding), formatted and never written (a terminator, or a zero-length
    /// NDEF TLV), or emptied — a message whose records are all TNF empty,
    /// which is what "Empty This Tag…" writes.
    ///
    /// NDEF semantics, not all-zero: an NDEF write leaves the old message's
    /// tail past its terminator, and no reader looks there. Bytes that are
    /// not a TLV chain are unreadable, not absent, so they are never blank.
    static func isBlank(in bytes: [UInt8], from start: Int) -> Bool {
        switch walkTLVChain(in: bytes, from: start) {
        case .noMessage:
            return true
        case .notTLV:
            return false
        case .message(let messageBytes):
            return isOnlyEmptyRecords(messageBytes)
        }
    }

    /// True when `bytes` are NDEF records of TNF empty and nothing else —
    /// type, ID and payload all zero-length.
    ///
    /// Read from the bytes, not through `NFCNDEFMessage(data:)`: that parse
    /// hands back one TNF-empty record for arbitrary input (`DE AD`, `41 41`
    /// — Simulator probe, 2026-09-30), so it cannot tell an erased tag from
    /// noise.
    private static func isOnlyEmptyRecords(_ bytes: [UInt8]) -> Bool {
        var index = 0
        while index < bytes.count {
            let header = bytes[index]
            // Type length, then a 1- or 4-byte payload length, then an ID length if IL is set.
            let fieldCount = 1 + (header & 0x10 != 0 ? 1 : 4) + (header & 0x08 != 0 ? 1 : 0)
            guard header & 0x27 == 0,                        // not chunked, TNF empty
                  index + fieldCount < bytes.count,
                  bytes[(index + 1)...(index + fieldCount)].allSatisfy({ $0 == 0 }) else { return false }
            index += 1 + fieldCount
            if header & 0x40 != 0 { return index == bytes.count }   // ME: the last record
        }
        return false
    }

    /// Where a TLV walk from one offset ends.
    private enum TLVWalkEnd {
        /// The value of the first NDEF TLV with content.
        case message([UInt8])
        /// Padding, a terminator or a zero-length NDEF TLV, and no message.
        case noMessage
        /// The bytes stopped being a TLV chain.
        case notTLV
    }

    private static func walkTLVChain(in bytes: [UInt8], from start: Int) -> TLVWalkEnd {
        var index = start
        while index < bytes.count {
            switch bytes[index] {
            case 0x00:
                // NULL TLV: one byte of padding, no length field.
                index += 1
            case 0xFE:
                // Terminator TLV. Nothing follows it, so there is no message.
                return .noMessage
            case 0x03, 0xFD:
                // NDEF and proprietary TLVs are both type-length-value.
                let isNDEF = bytes[index] == 0x03
                guard let field = lengthField(in: bytes, at: index + 1) else { return .notTLV }
                let valueStart = index + 1 + field.byteCount
                let valueEnd = valueStart + field.length
                guard valueEnd <= bytes.count else { return .notTLV }
                if isNDEF {
                    // A zero-length NDEF TLV is a formatted but empty tag.
                    return field.length == 0 ? .noMessage : .message(Array(bytes[valueStart..<valueEnd]))
                }
                index = valueEnd
            default:
                return .notTLV
            }
        }
        return .noMessage
    }

    /// A TLV length field: one byte, or `0xFF` followed by two big-endian bytes.
    private static func lengthField(in bytes: [UInt8], at index: Int) -> (length: Int, byteCount: Int)? {
        guard index < bytes.count else { return nil }
        guard bytes[index] == 0xFF else { return (Int(bytes[index]), 1) }
        guard index + 2 < bytes.count else { return nil }
        return (Int(bytes[index + 1]) << 8 | Int(bytes[index + 2]), 3)
    }

    /// Names the format of one NDEF record, or nil when nothing identifies it.
    ///
    /// The names are `TagFormat.displayName`'s, spelled out rather than read
    /// from it: this type is `nonisolated` so it can run on CoreNFC's callback
    /// queue, and `TagFormat` is not.
    static func name(forMIMEType mimeType: String?, payload: Data) -> String? {
        if let mimeType = mimeType?.lowercased() {
            if mimeType.contains("opentag3d") { return "OpenTag3D" }
            if mimeType.contains("openprinttag") { return "OpenPrintTag" }
        }

        // A shelf label is not filament data, and reporting it as unrecognised
        // would be the same lie in a different place.
        if LocationTagPayload.decode(payload: payload, mimeType: mimeType) != nil {
            return locationTag
        }

        if let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
           json["protocol"] as? String == "openspool" {
            return "OpenSpool"
        }

        return nil
    }

    /// The first record in a message that names a format, or nil when none
    /// of them does. Deciding that a nameless message is still worth calling
    /// NDEF belongs to the caller, which can see the other offsets.
    static func name(forNDEFMessage message: NFCNDEFMessage) -> String? {
        for record in message.records {
            let mimeType = record.typeNameFormat == .media
                ? String(data: record.type, encoding: .utf8)
                : nil
            if let name = name(forMIMEType: mimeType, payload: record.payload) {
                return name
            }
        }
        return nil
    }

    /// The whole answer for a dump's NDEF half: nil when the bytes carry no
    /// NDEF message at all, so the caller can fall through to its raw-format
    /// decoders and then to "nothing recognised it".
    ///
    /// An offset wins only by producing a record that names a format. Two
    /// weaker rules were tried and both fail on a real tag:
    ///
    /// - Taking the first offset that *parses as TLV* lets a coincidence
    ///   inside a Type 5 tag's content mask the real chain a few bytes away.
    /// - Taking the first offset that also *builds an `NFCNDEFMessage`* is no
    ///   better, because `NFCNDEFMessage(data:)` accepts two arbitrary bytes
    ///   and hands back a message holding one TNF-empty record — the same
    ///   message it builds from a genuinely empty record (Simulator probe,
    ///   2026-09-30).
    ///
    /// So a nameless message never ends the search; it is only remembered, so
    /// that a tag whose message genuinely is in an unknown format still gets
    /// the more useful of the two negative answers. A message of nothing but
    /// empty records is not remembered: it is noise or an emptied tag, and
    /// neither holds a format to not know.
    static func nameForNDEF(in bytes: [UInt8]) -> String? {
        var sawRecords = false
        for start in tlvStartOffsets {
            guard let messageBytes = ndefMessageBytes(in: bytes, from: start),
                  let message = NFCNDEFMessage(data: Data(messageBytes)),
                  message.records.contains(where: {
                      $0.typeNameFormat != .empty
                          || !$0.type.isEmpty || !$0.identifier.isEmpty || !$0.payload.isEmpty
                  }) else { continue }
            if let named = name(forNDEFMessage: message) { return named }
            sawRecords = true
        }
        return sawRecords ? unrecognisedNDEF : nil
    }
}
