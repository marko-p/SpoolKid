//
//  TagDumpWalk.swift
//  SpoolKid
//
//  Purpose: Decide when a raw page walk has reached the end of a tag.
//
//  NTAG READ (0x30) returns four pages and, on the last pages of the tag,
//  wraps around to page 0 rather than returning an error. A walk that watches
//  only for errors therefore never ends — it re-reads the start of the tag
//  until the session times out. Termination is arithmetic, and lives here so
//  it can be tested without a tag in hand.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum TagDumpWalk {

    /// One NTAG READ returns 16 bytes — four pages.
    static let pagesPerRead = 4

    /// How many ISO 15693 blocks to ask for at once. Read Multiple Blocks is
    /// optional in the standard and tags vary in how many they will return,
    /// so this is deliberately small; the walk falls back to one block at a
    /// time when a range read is refused.
    static let blocksPerRead = 4

    /// ISO 15693 block addresses are a single byte outside extended mode, so
    /// a walk that neither errors nor runs out still has to stop here.
    static let blockCeiling = 256

    /// What an ISO 15693 tag says about itself, as a fact rather than a guess.
    ///
    /// The IC reference identifies the part, but SpoolKid has no verified map
    /// from reference byte to part name — and inventing one would put a guess
    /// in the record where the tester expects a reading. So the byte is
    /// reported as itself.
    static func describeICReference(_ reference: Int) -> String {
        String(format: "ISO 15693, IC 0x%02X", reference)
    }

    /// The NXP ICODE part an ISO 15693 UID (MSB first) names, or nil. SLIX and
    /// SLIX2 both report IC reference 0x01; after `E0 04 01` the type indicator
    /// bits 37 and 36 (NXP numbers them from LSB 1), `uid[3] & 0x18`, tell them
    /// apart: 0x10 SLIX, 0x08 SLIX2 (SL2S2602 data sheet Rev. 4.1, Table 8;
    /// Proxmark3 `cmdhf15.c`; the owner's SLIX2 and SLIX, 80 and 28 blocks).
    /// 0x00 is SLI or ICODE 3 and 0x18 is ICODE DNA or NTAG 5, so neither is named.
    static func icodeName(forUID uid: [UInt8]) -> String? {
        guard uid.count == 8, uid[0] == 0xE0, uid[1] == 0x04, uid[2] == 0x01 else { return nil }
        switch uid[3] & 0x18 {
        case 0x10: return "ICODE SLIX"
        case 0x08: return "ICODE SLIX2"
        default: return nil
        }
    }

    /// Whether an ISO 15693 UID names an ICODE SLIX2, whose block 79 is a
    /// 16-bit counter that cannot hold user data (SL2S2602 §9.2).
    static func isSLIX2(uid: [UInt8]) -> Bool {
        icodeName(forUID: uid) == "ICODE SLIX2"
    }

    /// How many of the four pages in `block` are real, given `firstPage` (the
    /// four bytes of page 0) and the absolute page number the block was read at.
    ///
    /// Returns 4 when the block does not wrap. NTAG page counts are not
    /// multiples of four, so the last read of a tag returns one to three real
    /// pages followed by the start of the tag coming round again — a partial
    /// wrap is the normal case, not the exception.
    static func realPageCount(in block: [UInt8], firstPage: [UInt8], atPage page: Int) -> Int {
        guard block.count == pagesPerRead * 4, firstPage.count == 4 else { return 0 }
        for offset in 0..<pagesPerRead {
            let absolutePage = page + offset
            guard absolutePage != 0 else { continue }
            let start = offset * 4
            if Array(block[start..<(start + 4)]) == firstPage { return offset }
        }
        return pagesPerRead
    }

    /// Total pages the chip claims, from an 8-byte GET_VERSION (0x60) reply.
    ///
    /// Byte 6 is the storage-size code. Only the three NTAG parts SpoolKid
    /// meets are mapped; anything else returns nil, because a guess here would
    /// be recorded as fact in the dump.
    static func pageCount(forVersionResponse bytes: [UInt8]) -> Int? {
        guard bytes.count >= 7 else { return nil }
        switch bytes[6] {
        case 0x0F: return 45   // NTAG213
        case 0x11: return 135  // NTAG215
        case 0x13: return 231  // NTAG216
        default: return nil
        }
    }

    /// The part name for a page count from `pageCount(forVersionResponse:)`.
    /// The one place the three NTAG parts are named, shared by the Tag Explorer
    /// and the Inspect Tag screen. Any other count returns nil, not a guess.
    static func chipName(forPageCount pages: Int) -> String? {
        switch pages {
        case 45: return "NTAG213"
        case 135: return "NTAG215"
        case 231: return "NTAG216"
        default: return nil
        }
    }
}
