//
//  TagInspection.swift
//  SpoolKid
//
//  Purpose: What a scan learned about the tag itself, kept as raw facts for the
//  Inspect Tag screen. No display strings live here: `TagInspectionFormatter`
//  turns these facts into rows, so what a tester reads is derived from the
//  bytes in one place and an unknown stays an unknown instead of becoming a
//  guess.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// `nonisolated`: `NFCManager` builds this on CoreNFC's callback queue.
nonisolated struct TagInspection: Equatable, Sendable {

    /// The tag family CoreNFC reported, which decides the technology, the
    /// NFC Forum type and the fallback chip name shown for it.
    enum Family: Equatable, Sendable {
        case mifareUltralight, mifareDESFire, mifarePlus, mifareOther
        case iso15693, iso7816, feliCa
    }

    /// What `queryNDEFStatus` said the tag allows.
    enum NDEFAccess: Equatable, Sendable {
        case readWrite, readOnly, notSupported
    }

    struct NDEF: Equatable, Sendable {
        var access: NDEFAccess
        /// `queryNDEFStatus` capacity, in bytes.
        var capacity: Int
        /// `NFCNDEFMessage.length`; nil until a message was read.
        var messageLength: Int? = nil
        var records: [NDEFRecordSnapshot] = []
    }

    /// Raw memory as read: pages on a Type 2 tag, blocks on a Type 5 tag.
    struct RawMemory: Equatable, Sendable {
        /// The first page or block held in `bytes`.
        let firstUnit: Int
        /// Bytes per page or block.
        var unitSize: Int
        let bytes: [UInt8]

        init(firstUnit: Int, unitSize: Int, bytes: [UInt8]) {
            self.firstUnit = firstUnit
            self.unitSize = unitSize
            self.bytes = bytes
        }

        /// The pages of a raw snapshot. Nil for an NDEF snapshot or none.
        init?(snapshot: TagSnapshot?) {
            guard case .rawPages(let firstPage, let bytes)? = snapshot else { return nil }
            self.init(firstUnit: firstPage, unitSize: TagSnapshot.bytesPerPage, bytes: bytes)
        }
    }

    /// What the chip said about itself when asked.
    struct Chip: Equatable, Sendable {
        /// The raw GET_VERSION reply.
        var getVersion: [UInt8]? = nil
        /// ISO 15693 Get System Info: the IC reference.
        var icReference: Int? = nil
        var blockSize: Int? = nil
        var totalBlocks: Int? = nil
    }

    let capturedAt: Date
    let family: Family
    let uid: [UInt8]
    /// ISO 15693 only: the manufacturer code from the tag's UID.
    let icManufacturerCode: Int?
    var ndef: NDEF? = nil
    var rawMemory: RawMemory? = nil
    var chip: Chip? = nil
}
