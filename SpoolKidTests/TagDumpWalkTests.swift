//
//  TagDumpWalkTests.swift
//  SpoolKidTests
//
//  A walk that does not terminate is not a slow walk, it is a hung scan
//  session the tester has to force-quit. NTAG READ wraps instead of failing,
//  so termination is arithmetic, not error handling.
//

import Testing
import Foundation
@testable import SpoolKid

struct TagDumpWalkTests {

    private let pageZero: [UInt8] = [0x04, 0xA1, 0xB2, 0xC3]

    private func block(_ pages: [[UInt8]]) -> [UInt8] { pages.flatMap { $0 } }

    @Test func aBlockThatDoesNotWrapIsFourRealPages() {
        let full = block([pageZero, [0xD4, 0xE5, 0x80, 0x00], [0x11, 0x22, 0x33, 0x44], [0x55, 0x66, 0x77, 0x88]])
        #expect(TagDumpWalk.realPageCount(in: full, firstPage: [0xFF, 0xFF, 0xFF, 0xFF], atPage: 4) == 4)
    }

    /// An NTAG213 has 45 pages, so the read at page 44 returns page 44 and then
    /// pages 0, 1 and 2 of the same tag. Only the first page is real.
    @Test func aPartialWrapReportsOnlyThePagesBeforeIt() {
        let full = block([[0x99, 0x99, 0x99, 0x99], pageZero, [0xD4, 0xE5, 0x80, 0x00], [0x11, 0x22, 0x33, 0x44]])
        #expect(TagDumpWalk.realPageCount(in: full, firstPage: pageZero, atPage: 44) == 1)
    }

    /// Page 0 is itself. Counting that as a wrap would end every walk before it
    /// read anything.
    @Test func theFirstBlockIsNeverAWrap() {
        let full = block([pageZero, [0xD4, 0xE5, 0x80, 0x00], [0x11, 0x22, 0x33, 0x44], [0x55, 0x66, 0x77, 0x88]])
        #expect(TagDumpWalk.realPageCount(in: full, firstPage: pageZero, atPage: 0) == 4)
    }

    @Test func aWrapAtTheStartOfABlockReportsNoRealPages() {
        let full = block([pageZero, [0xD4, 0xE5, 0x80, 0x00], [0x11, 0x22, 0x33, 0x44], [0x55, 0x66, 0x77, 0x88]])
        #expect(TagDumpWalk.realPageCount(in: full, firstPage: pageZero, atPage: 132) == 0)
    }

    @Test func aMalformedBlockIsNoRealPages() {
        #expect(TagDumpWalk.realPageCount(in: [0x01, 0x02], firstPage: pageZero, atPage: 8) == 0)
        #expect(TagDumpWalk.realPageCount(in: Array(repeating: 0, count: 16), firstPage: [0x01], atPage: 8) == 0)
    }

    @Test func chipCapacityIsReadFromTheVersionResponse() {
        // GET_VERSION returns 8 bytes; byte 6 is the storage size code.
        #expect(TagDumpWalk.pageCount(forVersionResponse: [0x00, 0x04, 0x04, 0x02, 0x01, 0x00, 0x0F, 0x03]) == 45)
        #expect(TagDumpWalk.pageCount(forVersionResponse: [0x00, 0x04, 0x04, 0x02, 0x01, 0x00, 0x11, 0x03]) == 135)
        #expect(TagDumpWalk.pageCount(forVersionResponse: [0x00, 0x04, 0x04, 0x02, 0x01, 0x00, 0x13, 0x03]) == 231)
    }

    /// Not every Ultralight-compatible tag answers GET_VERSION, and an
    /// unrecognised storage code is not a reason to refuse the dump.
    @Test func anUnusableVersionResponseYieldsNoCapacity() {
        #expect(TagDumpWalk.pageCount(forVersionResponse: []) == nil)
        #expect(TagDumpWalk.pageCount(forVersionResponse: [0x00, 0x04]) == nil)
        #expect(TagDumpWalk.pageCount(forVersionResponse: [0x00, 0x04, 0x04, 0x02, 0x01, 0x00, 0x99, 0x03]) == nil)
    }

    /// The Tag Explorer and the Inspect Tag screen name the chip from the same
    /// page count, so the two cannot disagree.
    @Test func chipNamesForKnownPageCounts() {
        #expect(TagDumpWalk.chipName(forPageCount: 45) == "NTAG213")
        #expect(TagDumpWalk.chipName(forPageCount: 135) == "NTAG215")
        #expect(TagDumpWalk.chipName(forPageCount: 231) == "NTAG216")
        #expect(TagDumpWalk.chipName(forPageCount: 41) == nil)
    }

    /// The owner's two tags (2026-10-17): a Prusament SLIX2 of 80 blocks and
    /// a SLIX of 28. Both report IC reference 0x01; only the UID tells them apart.
    @Test func icodeNamesFromTheUID() {
        #expect(TagDumpWalk.icodeName(forUID: [0xE0, 0x04, 0x01, 0x09, 0x18, 0xED, 0xD6, 0xBD]) == "ICODE SLIX2")
        #expect(TagDumpWalk.icodeName(forUID: [0xE0, 0x04, 0x01, 0x53, 0x09, 0xB8, 0x60, 0x31]) == "ICODE SLIX")
    }

    /// Only the SLIX2 UID names the chip whose block 79 is a counter.
    @Test func isSLIX2MatchesTheName() {
        #expect(TagDumpWalk.isSLIX2(uid: [0xE0, 0x04, 0x01, 0x09, 0x18, 0xED, 0xD6, 0xBD]))
        #expect(!TagDumpWalk.isSLIX2(uid: [0xE0, 0x04, 0x01, 0x53, 0x09, 0xB8, 0x60, 0x31]))
        #expect(!TagDumpWalk.isSLIX2(uid: []))
    }

    /// Type bits 00 are ICODE SLI or ICODE 3 and 11 are ICODE DNA or NTAG 5,
    /// so neither is named; nor is another maker or IC type.
    @Test func ambiguousOrForeignUIDsAreNotNamed() {
        #expect(TagDumpWalk.icodeName(forUID: [0xE0, 0x04, 0x01, 0x00, 0, 0, 0, 0]) == nil)
        #expect(TagDumpWalk.icodeName(forUID: [0xE0, 0x04, 0x01, 0x18, 0, 0, 0, 0]) == nil)
        #expect(TagDumpWalk.icodeName(forUID: [0xE0, 0x07, 0x01, 0x08, 0, 0, 0, 0]) == nil)
        #expect(TagDumpWalk.icodeName(forUID: [0xE0, 0x04, 0x02, 0x10, 0, 0, 0, 0]) == nil)
        #expect(TagDumpWalk.icodeName(forUID: [0xE0, 0x04, 0x01]) == nil)
    }
}
