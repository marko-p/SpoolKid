//
//  Type2NDEF.swift
//  SpoolKid
//
//  Purpose: Lay an NDEF message onto NFC Forum Type 2 tag pages, the way the
//  U1's tag reader writes it.
//
//  iPhone writes leave this wrapping to iOS. A write through the printer's
//  reader goes page by page, so the capability container and the TLV chain
//  are built here, and the tag's size comes from the same plugin plan the
//  reader uses. Pure byte arithmetic, so it can be tested without a tag.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// Where NTAG user memory sits on a tag, and the capability container that
/// describes it.
nonisolated struct Type2Geometry: Equatable, Sendable {
    let lastUserPage: Int
    let totalPages: Int
    /// Byte 2 of the capability container: the data area size, in 8-byte units.
    private let sizeByte: UInt8

    /// From the plugin's read reply when it names a known NTAG, otherwise from
    /// the capability container, as the plugin does.
    ///
    /// The GET_VERSION reply carries the storage size in byte 6.
    init(versionReply: [UInt8]?, capabilityContainer: [UInt8]) {
        if let reply = versionReply, reply.count > 6, let known = Self.known(storageByte: reply[6]) {
            self.sizeByte = known.sizeByte
            self.lastUserPage = known.lastUserPage
            self.totalPages = known.totalPages
        } else {
            let size = capabilityContainer.count > 2 ? capabilityContainer[2] : 0
            self.sizeByte = size
            self.lastUserPage = size == 0 ? 15 : 3 + Int(size) * 2
            self.totalPages = self.lastUserPage + 1
        }
    }

    /// Usable bytes between the capability container and the terminator's page.
    var userByteCapacity: Int { (lastUserPage - 3) * 4 }

    /// `E1 10 <size> 00` for this tag's size.
    var capabilityContainer: [UInt8] { [0xE1, 0x10, sizeByte, 0x00] }

    private static func known(storageByte: UInt8) -> (sizeByte: UInt8, lastUserPage: Int, totalPages: Int)? {
        switch storageByte {
        case 0x0F: return (0x12, 39, 45)    // NTAG213
        case 0x11: return (0x3E, 129, 135)  // NTAG215
        case 0x13: return (0x6D, 225, 231)  // NTAG216
        default: return nil
        }
    }
}

nonisolated enum Type2NDEF {

    /// NDEF records as message bytes. Each record gets the short form when its
    /// payload is under 256 bytes, and the first and last records carry MB and
    /// ME. Nothing is chunked. Type and identifier are at most 255 bytes by NDEF.
    static func messageBytes(for records: [NDEFRecordSnapshot]) -> [UInt8] {
        var bytes: [UInt8] = []
        for (index, record) in records.enumerated() {
            let isShort = record.payload.count < 256
            let hasIdentifier = !record.identifier.isEmpty

            var flags = record.typeNameFormat & 0x07
            if index == 0 { flags |= 0x80 }
            if index == records.count - 1 { flags |= 0x40 }
            if isShort { flags |= 0x10 }
            if hasIdentifier { flags |= 0x08 }

            bytes.append(flags)
            bytes.append(UInt8(record.type.count))
            if isShort {
                bytes.append(UInt8(record.payload.count))
            } else {
                let length = UInt32(record.payload.count)
                bytes += [UInt8(length >> 24), UInt8((length >> 16) & 0xFF), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]
            }
            if hasIdentifier { bytes.append(UInt8(record.identifier.count)) }
            bytes += record.type
            bytes += record.identifier
            bytes += record.payload
        }
        return bytes
    }

    /// The records of an NDEF message read from raw bytes, through the record
    /// marked ME. Nil when a record is truncated, chunked (CF), or the bytes
    /// end before ME.
    static func records(fromMessageBytes bytes: [UInt8]) -> [NDEFRecordSnapshot]? {
        var records: [NDEFRecordSnapshot] = []
        var index = 0
        while true {
            guard let parsed = parseRecord(in: bytes, at: index) else { return nil }
            records.append(parsed.record)
            if parsed.isLast { return records }
            index = parsed.end
        }
    }

    /// Pages to write, in order: the capability container on page 3 when the
    /// tag's current one differs from the geometry's, then the TLV (0x03,
    /// length, message, 0xFE) from page 4, zero padded to whole pages. Nil when
    /// it does not fit the tag's user memory.
    static func pages(forMessageBytes bytes: [UInt8], geometry: Type2Geometry,
                      currentCapabilityContainer: [UInt8]) -> [(page: Int, data: Data)]? {
        let tlv = tlvHeader(forLength: bytes.count) + bytes + [0xFE]
        let tlvPageCount = (tlv.count + 3) / 4
        guard tlvPageCount <= geometry.lastUserPage - 3 else { return nil }

        var entries: [(page: Int, data: Data)] = []
        if currentCapabilityContainer != geometry.capabilityContainer {
            entries.append((3, Data(geometry.capabilityContainer)))
        }
        let padded = tlv + [UInt8](repeating: 0, count: tlvPageCount * 4 - tlv.count)
        for pageIndex in 0..<tlvPageCount {
            let start = pageIndex * 4
            entries.append((4 + pageIndex, Data(padded[start..<start + 4])))
        }
        return entries
    }

    /// 0x03 and a one-byte length, or 0x03 0xFF and a two-byte big-endian length
    /// from 255 bytes on.
    private static func tlvHeader(forLength length: Int) -> [UInt8] {
        guard length >= 255 else { return [0x03, UInt8(length)] }
        return [0x03, 0xFF, UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]
    }

    /// One record starting at `start`, and where the next one begins. Nil on
    /// truncation or a chunked record.
    private static func parseRecord(in bytes: [UInt8], at start: Int)
        -> (record: NDEFRecordSnapshot, end: Int, isLast: Bool)? {
        guard start < bytes.count else { return nil }
        let flags = bytes[start]
        guard flags & 0x20 == 0 else { return nil }

        let isShort = flags & 0x10 != 0
        let hasIdentifier = flags & 0x08 != 0
        var cursor = start + 1

        func take(_ count: Int) -> [UInt8]? {
            guard count >= 0, cursor + count <= bytes.count else { return nil }
            defer { cursor += count }
            return Array(bytes[cursor..<cursor + count])
        }

        guard let typeLength = take(1)?.first else { return nil }
        let payloadLength: Int
        if isShort {
            guard let value = take(1)?.first else { return nil }
            payloadLength = Int(value)
        } else {
            guard let value = take(4) else { return nil }
            payloadLength = value.reduce(0) { $0 << 8 | Int($1) }
        }
        var identifierLength = 0
        if hasIdentifier {
            guard let value = take(1)?.first else { return nil }
            identifierLength = Int(value)
        }
        guard let type = take(Int(typeLength)),
              let identifier = take(identifierLength),
              let payload = take(payloadLength) else { return nil }

        let record = NDEFRecordSnapshot(
            typeNameFormat: flags & 0x07,
            type: Data(type),
            identifier: Data(identifier),
            payload: Data(payload)
        )
        return (record, cursor, flags & 0x40 != 0)
    }
}
