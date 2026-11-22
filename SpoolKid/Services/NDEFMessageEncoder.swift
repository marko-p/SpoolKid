//
//  NDEFMessageEncoder.swift
//  SpoolKid
//
//  Purpose: The bytes of an NDEF message, from its records. CoreNFC offers no
//  serializer; spec 3 sends a tag's message to Spoolman as `payload_b64`.
//  Pure. Layout: NFC Forum NDEF 1.0, §3.2.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum NDEFMessageEncoder {
    /// MB on the first record and ME on the last; SR when a payload fits one
    /// length byte, else a 4-byte big-endian length; IL when a record has an
    /// ID. Header, type length, payload length, ID length, type, ID, payload.
    static func encode(_ records: [NDEFRecordSnapshot]) -> [UInt8] {
        var bytes: [UInt8] = []
        for (index, record) in records.enumerated() {
            let isShort = record.payload.count <= 255
            let hasID = !record.identifier.isEmpty
            var header = record.typeNameFormat & 0x07
            if index == 0 { header |= 0x80 }
            if index == records.count - 1 { header |= 0x40 }
            if isShort { header |= 0x10 }
            if hasID { header |= 0x08 }
            bytes.append(header)
            bytes.append(UInt8(record.type.count))
            if isShort {
                bytes.append(UInt8(record.payload.count))
            } else {
                let length = UInt32(record.payload.count)
                bytes += [UInt8((length >> 24) & 0xFF), UInt8((length >> 16) & 0xFF), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]
            }
            if hasID { bytes.append(UInt8(record.identifier.count)) }
            bytes += record.type
            if hasID { bytes += record.identifier }
            bytes += record.payload
        }
        return bytes
    }
}
