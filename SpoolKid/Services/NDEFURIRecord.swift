//
//  NDEFURIRecord.swift
//  SpoolKid
//
//  Purpose: The NFC Forum URI record (well-known type `U`): a one-byte
//  abbreviation code, then the rest of the URI as UTF-8. Pure. Layout: NFC
//  Forum URI Record Type Definition.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum NDEFURIRecord {
    /// The URI RTD's abbreviations, indexed by the payload's first byte
    /// (codes 0x00–0x23).
    private static let prefixes = [
        "", "http://www.", "https://www.", "http://", "https://", "tel:", "mailto:",
        "ftp://anonymous:anonymous@", "ftp://ftp.", "ftps://", "sftp://", "smb://", "nfs://",
        "ftp://", "dav://", "news:", "telnet://", "imap:", "rtsp://", "urn:", "pop:", "sip:",
        "sips:", "tftp:", "btspp://", "btl2cap://", "btgoep://", "tcpobex://", "irdaobex://",
        "file://", "urn:epc:id:", "urn:epc:tag:", "urn:epc:pat:", "urn:epc:raw:", "urn:epc:",
        "urn:nfc:",
    ]

    /// The text a code abbreviates. Nil for a code the NFC Forum reserves
    /// (0x24–0xFF).
    static func prefix(forCode code: UInt8) -> String? {
        Int(code) < prefixes.count ? prefixes[Int(code)] : nil
    }

    /// The payload's URI, read the way CoreNFC's `wellKnownTypeURIPayload()`
    /// reads it: a reserved code as no prefix, nothing after the code as no
    /// URI, and the text through `URL(string:)`. That call is not used because
    /// on a remainder that is not UTF-8 it raises an Objective-C exception,
    /// which aborts the app; this returns nil instead.
    static func url(from payload: Data) -> URL? {
        guard let code = payload.first, payload.count > 1,
              let rest = String(data: payload.dropFirst(), encoding: .utf8) else { return nil }
        return URL(string: (prefix(forCode: code) ?? "") + rest)
    }
}
