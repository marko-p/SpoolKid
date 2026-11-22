//
//  TagDump.swift
//  SpoolKid
//
//  Purpose: One raw read of a whole tag, as it leaves the phone.
//
//  Pages are hex strings rather than a base64 blob because the ACE-RFID
//  reverse-engineered spec is written page by page, and a dump is meant to be
//  read against it by a person.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct TagDump: Codable, Equatable {

    /// How the walk ended. Only `error` is a failure, and only when nothing
    /// was read at all.
    ///
    /// `endOfTag` and `wrap` were one case until 2026-09-07. They are not the
    /// same claim: `endOfTag` means the tag stated its own size and the walk
    /// read exactly that, while `wrap` means nothing stated a size and the
    /// walk inferred the end from the tag repeating itself. One is a reading,
    /// the other is a deduction, and a dump has to say which it is.
    nonisolated enum EndReason: String, Codable {
        /// A read failed. With no pages behind it, the dump is empty.
        case error
        /// The tag's own declared size was reached, or it refused the next
        /// block because there is no next block.
        case endOfTag
        /// The tag's size was never declared and the read came back showing
        /// the start of the tag again.
        case wrap
    }

    let capturedAt: Date
    let uid: String
    let tagType: String
    /// What GET_VERSION said, when the tag answered it at all.
    let chipVersion: String?
    let pagesRead: Int
    let endedBy: EndReason
    /// One uppercase 8-character hex string per 4-byte page, indexed from zero.
    let pages: [String]
    /// Which format decoded this tag, if any. A fact about the dump, not an
    /// interpretation of it.
    let decodedAs: String?
    var note: String
    let appVersion: String

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Groups raw bytes into pages. A trailing partial page is dropped rather
    /// than zero-padded — padding would put bytes in the record that the tag
    /// never returned.
    static func hexPages(from bytes: [UInt8]) -> [String] {
        stride(from: 0, to: bytes.count - (bytes.count % 4), by: 4).map { start in
            bytes[start..<(start + 4)]
                .map { String(format: "%02X", $0) }
                .joined()
        }
    }
}
