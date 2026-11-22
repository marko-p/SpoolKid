//
//  TagDumpDecodeTests.swift
//  SpoolKidTests
//
//  The explorer's "Decoded as" row said "Nothing recognised it" for a tag
//  SpoolKid had written itself, because it only ever attempted Anycubic ACE.
//  The fixture below is the real dump that exposed that (owner device pass,
//  2026-09-07): an NTAG215 carrying a SpoolKid OpenSpool tag, page for page.
//

import Testing
import Foundation
import CoreNFC
@testable import SpoolKid

struct TagDumpDecodeTests {

    // MARK: - Fixtures

    /// The first 66 pages of a real NTAG215 dump — everything up to and
    /// including the terminator TLV. Pages 0-2 are the UID and its check
    /// bytes, page 3 is the capability container `E1 10 3E 00`, and the TLV
    /// chain starts at page 4 with `03 F5` — an NDEF TLV of 245 bytes.
    static let openSpoolTagPages = [
        "048D1312", "56C92A81", "34480000", "E1103E00", "03F5D210", "E2617070", "6C696361", "74696F6E",
        "2F6A736F", "6E7B2270", "726F746F", "636F6C22", "3A226F70", "656E7370", "6F6F6C22", "2C227665",
        "7273696F", "6E223A22", "312E3022", "2C227479", "7065223A", "22504C41", "222C2273", "75627479",
        "7065223A", "2253696C", "6B222C22", "636F6C6F", "725F6865", "78223A22", "43434243", "3535222C",
        "22627261", "6E64223A", "22417A75", "72654669", "6C6D222C", "226D696E", "5F74656D", "70223A22",
        "32333022", "2C226D61", "785F7465", "6D70223A", "22323430", "222C2262", "65645F6D", "696E5F74",
        "656D7022", "3A223830", "222C2262", "65645F6D", "61785F74", "656D7022", "3A223835", "222C226E",
        "616D6522", "3A22504C", "41205369", "6C6B2047", "4F4C4420", "31384B22", "2C227370", "6F6F6C5F",
        "6964223A", "34357DFE"
    ]

    static func bytes(_ pages: [String]) -> [UInt8] {
        pages.flatMap { page in
            stride(from: 0, to: page.count, by: 2).map { offset in
                let start = page.index(page.startIndex, offsetBy: offset)
                let end = page.index(start, offsetBy: 2)
                return UInt8(page[start..<end], radix: 16)!
            }
        }
    }

    // MARK: - Finding the message

    @Test func theMessageIsFoundInARealNTAGDump() throws {
        let message = try #require(TagDumpDecode.ndefMessageBytes(in: Self.bytes(Self.openSpoolTagPages), from: 16))
        // The TLV said 0xF5 = 245 bytes, and the walk must hand back exactly
        // that many — no terminator, no trailing page padding.
        #expect(message.count == 245)
        // D2 = MB+ME+SR, TNF media. The record starts where the TLV value does.
        #expect(message.first == 0xD2)
        #expect(message.last == 0x7D)  // the JSON's closing brace
    }

    /// Type 5 tags (ISO 15693) put the capability container in the first
    /// block, so their chain starts at byte 4, not 16. The same walk has to
    /// find both without being told which family it is looking at.
    @Test func aTypeFiveLayoutIsFoundAtItsOwnOffset() throws {
        var bytes: [UInt8] = [0xE1, 0x40, 0x10, 0x00]      // 4-byte capability container
        bytes += [0x03, 0x03, 0xAA, 0xBB, 0xCC, 0xFE]       // NDEF TLV of 3 bytes, then terminator
        #expect(TagDumpDecode.ndefMessageBytes(in: bytes, from: 4) == [0xAA, 0xBB, 0xCC])
    }

    @Test func aProprietaryTLVIsSteppedOverRatherThanStoppingTheWalk() throws {
        var bytes = [UInt8](repeating: 0x00, count: 16)
        bytes += [0xFD, 0x02, 0x11, 0x22]                   // proprietary TLV, 2 bytes
        bytes += [0x03, 0x02, 0xDE, 0xAD, 0xFE]             // then the NDEF TLV
        #expect(TagDumpDecode.ndefMessageBytes(in: bytes, from: 16) == [0xDE, 0xAD])
    }

    @Test func theThreeByteLengthFormIsRead() throws {
        var bytes = [UInt8](repeating: 0x00, count: 16)
        bytes += [0x03, 0xFF, 0x01, 0x00]                   // 0xFF escape, then 256 big-endian
        bytes += [UInt8](repeating: 0x5A, count: 256)
        let message = try #require(TagDumpDecode.ndefMessageBytes(in: bytes, from: 16))
        #expect(message.count == 256)
        #expect(message.allSatisfy { $0 == 0x5A })
    }

    /// A tag that has been formatted but never written carries a TLV of zero
    /// length. That is not a message, and reporting it as one would put an
    /// empty record in front of a tester as if it decoded.
    @Test func anEmptyNDEFTLVIsNotAMessage() {
        var bytes = [UInt8](repeating: 0x00, count: 16)
        bytes += [0x03, 0x00, 0xFE]
        #expect(TagDumpDecode.ndefMessageBytes(in: bytes, from: 16) == nil)
    }

    @Test func aTerminatorBeforeAnyMessageEndsTheWalk() {
        var bytes = [UInt8](repeating: 0x00, count: 16)
        bytes += [0xFE, 0x03, 0x02, 0xDE, 0xAD]
        #expect(TagDumpDecode.ndefMessageBytes(in: bytes, from: 16) == nil)
    }

    /// A raw-format tag — an Anycubic ACE page dump — has no TLV chain at all.
    /// The walk must decline it rather than find a message in arbitrary bytes.
    @Test func rawPagesWithNoTLVChainYieldNothing() {
        let bytes = [UInt8](repeating: 0x41, count: 128)
        #expect(TagDumpDecode.ndefMessageBytes(in: bytes, from: 16) == nil)
    }

    @Test func aLengthRunningPastTheDumpIsRefused() {
        var bytes = [UInt8](repeating: 0x00, count: 16)
        bytes += [0x03, 0x40, 0xAA, 0xBB]                   // claims 64 bytes, has 2
        #expect(TagDumpDecode.ndefMessageBytes(in: bytes, from: 16) == nil)
    }

    // MARK: - Naming what was found

    @Test func aSpoolKidOpenSpoolTagIsNamed() throws {
        let name = try #require(TagDumpDecode.nameForNDEF(in: Self.bytes(Self.openSpoolTagPages)))
        #expect(name == "OpenSpool")
    }

    @Test func mimeTypesNameTheirFormats() {
        #expect(TagDumpDecode.name(forMIMEType: "application/opentag3d", payload: Data()) == "OpenTag3D")
        #expect(TagDumpDecode.name(forMIMEType: "application/vnd.openprinttag", payload: Data()) == "OpenPrintTag")
    }

    @Test func openSpoolIsRecognisedByItsProtocolFieldNotItsMIMEType() {
        // OpenSpool rides on "application/json", which names nothing.
        let payload = Data(#"{"protocol":"openspool","version":"1.0","type":"PLA"}"#.utf8)
        #expect(TagDumpDecode.name(forMIMEType: "application/json", payload: payload) == "OpenSpool")
    }

    @Test func someOtherJSONIsNotOpenSpool() {
        let payload = Data(#"{"protocol":"something-else"}"#.utf8)
        #expect(TagDumpDecode.name(forMIMEType: "application/json", payload: payload) == nil)
    }

    /// A shelf label is not filament data, but it is something SpoolKid wrote
    /// and must not come back as unrecognised.
    @Test func aLocationTagIsNamed() throws {
        let payload = try #require(
            LocationTagPayload(uuid: UUID(), name: "Shelf A").encoded()
        )
        #expect(
            TagDumpDecode.name(forMIMEType: LocationTagPayload.mimeType, payload: payload)
                == TagDumpDecode.locationTag
        )
    }

    /// An NDEF tag in a format nobody here decodes is still an NDEF tag. That
    /// is a different answer from "nothing recognised it", and the more useful
    /// one for a tester holding an unknown spool.
    @Test func anUnknownNDEFRecordSaysItIsStillNDEF() throws {
        var bytes = [UInt8](repeating: 0x00, count: 16)
        // One media record, type "application/octet-stream", payload "hi".
        let type = Array("application/octet-stream".utf8)
        let payload = Array("hi".utf8)
        let record: [UInt8] = [0xD2, UInt8(type.count), UInt8(payload.count)] + type + payload
        bytes += [0x03, UInt8(record.count)] + record + [0xFE]
        #expect(TagDumpDecode.nameForNDEF(in: bytes) == TagDumpDecode.unrecognisedNDEF)
    }

    /// A Type 5 tag's chain starts at byte 4, but byte 16 is inside its
    /// content — and content can hold a `0x03` followed by a length that
    /// parses. Taking the first offset that merely parses as TLV would hand
    /// back those bytes, fail to build a message from them, and report the
    /// tag as unrecognised with its real message twelve bytes away in the
    /// same dump.
    @Test func aCoincidenceAtTheType2OffsetDoesNotMaskTheType5Chain() throws {
        let type = Array("application/opentag3d".utf8)
        let record: [UInt8] = [0xD2, UInt8(type.count), 0x04] + type + [0x00, 0x00, 0x00, 0x00]

        var bytes: [UInt8] = [0xE1, 0x40, 0x10, 0x00]       // capability container, bytes 0-3
        // A proprietary TLV whose value happens to span byte 16. Its content
        // is opaque to the walk, which is exactly how a coincidence gets in.
        var proprietary = [UInt8](repeating: 0x00, count: 12)
        proprietary[10] = 0x03                               // lands at byte 16
        proprietary[11] = 0x02                               // ...and reads as a 2-byte length
        bytes += [0xFD, UInt8(proprietary.count)] + proprietary
        bytes += [0x03, UInt8(record.count)] + record + [0xFE]

        // The decoy is really there, and really does parse from byte 16.
        #expect(bytes[16] == 0x03)
        #expect(TagDumpDecode.ndefMessageBytes(in: bytes, from: 16) != nil)
        // But those bytes are not a message, so byte 16 must not be the
        // answer — the real chain at byte 4 is.
        #expect(TagDumpDecode.nameForNDEF(in: bytes) == "OpenTag3D")
    }

    @Test func bytesWithNoNDEFAtAllAreNotNamed() {
        #expect(TagDumpDecode.nameForNDEF(in: [UInt8](repeating: 0x41, count: 128)) == nil)
    }

    /// `NFCNDEFMessage(data:)` turns `DE AD` into one TNF-empty record
    /// (Simulator probe, 2026-09-30), so a TLV holding no records still
    /// builds a message with a record in it. That record says nothing, and
    /// must not make the tag "NDEF, but no format SpoolKid knows".
    @Test func anNDEFTLVHoldingNoRecordsIsNotNamed() {
        var bytes = [UInt8](repeating: 0x00, count: 16)
        bytes += [0x03, 0x02, 0xDE, 0xAD, 0xFE]
        #expect(TagDumpDecode.nameForNDEF(in: bytes) == nil)
    }

    // MARK: - Recognising a blank tag
    //
    // A new user scanned an empty NTAG215 and was told "Unknown tag format"
    // (test-user report, 2026-09-30). The buffers below are shaped like the
    // TigerTag read's: pages 0-39, with page 4 at byte 16.

    /// Pages 0-39 with `user` laid over user memory from page 4.
    static func tagPages(user: [UInt8]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0x00, count: 160)
        bytes.replaceSubrange(16..<(16 + user.count), with: user)
        return bytes
    }

    /// NXP ships NTAG21x formatted: a zero-length NDEF TLV, then a terminator.
    @Test func aFactoryFormattedTagIsBlank() {
        #expect(TagDumpDecode.isBlank(in: Self.tagPages(user: [0x03, 0x00, 0xFE]), from: 16))
    }

    @Test func aNeverFormattedTagIsBlank() {
        #expect(TagDumpDecode.isBlank(in: Self.tagPages(user: []), from: 16))
    }

    @Test func aTerminatorAtPageFourIsBlank() {
        #expect(TagDumpDecode.isBlank(in: Self.tagPages(user: [0xFE]), from: 16))
    }

    /// "Empty This Tag…" writes one record of TNF empty (`D0 00 00`), and
    /// the NDEF write leaves the old message's tail behind the terminator.
    /// No reader looks past the terminator, so the tail does not count.
    @Test func aTagEmptiedBySpoolKidIsBlankDespiteTheOldTail() {
        var bytes = Self.bytes(Self.openSpoolTagPages)
        bytes.replaceSubrange(16..<22, with: [0x03, 0x03, 0xD0, 0x00, 0x00, 0xFE])
        #expect(TagDumpDecode.isBlank(in: bytes, from: 16))
    }

    @Test func aWrittenOpenSpoolTagIsNotBlank() {
        #expect(!TagDumpDecode.isBlank(in: Self.bytes(Self.openSpoolTagPages), from: 16))
    }

    @Test func aMessageInAnUnknownFormatIsNotBlank() {
        let type = Array("application/octet-stream".utf8)
        let payload = Array("hi".utf8)
        let record: [UInt8] = [0xD2, UInt8(type.count), UInt8(payload.count)] + type + payload
        #expect(!TagDumpDecode.isBlank(in: Self.tagPages(user: [0x03, UInt8(record.count)] + record + [0xFE]), from: 16))
    }

    /// `NFCNDEFMessage(data:)` turns `DE AD` into one TNF-empty record — the
    /// same answer it gives for a real erased tag — so the check reads the
    /// record header itself. Content that is not records is still content.
    @Test func anNDEFTLVHoldingNoRecordsIsNotBlank() {
        #expect(!TagDumpDecode.isBlank(in: Self.tagPages(user: [0x03, 0x02, 0xDE, 0xAD, 0xFE]), from: 16))
    }

    /// The same empty record in the long form: a 4-byte payload length.
    @Test func aLongFormEmptyRecordIsBlank() {
        let record: [UInt8] = [0xC0, 0x00, 0x00, 0x00, 0x00, 0x00]
        #expect(TagDumpDecode.isBlank(in: Self.tagPages(user: [0x03, UInt8(record.count)] + record + [0xFE]), from: 16))
    }

    @Test func anEmptyRecordFollowedByMoreBytesIsNotBlank() {
        let record: [UInt8] = [0xD0, 0x00, 0x00, 0x41]      // ME set, then a stray byte inside the TLV
        #expect(!TagDumpDecode.isBlank(in: Self.tagPages(user: [0x03, UInt8(record.count)] + record + [0xFE]), from: 16))
    }

    @Test func rawFormatPagesAreNotBlank() {
        #expect(!TagDumpDecode.isBlank(in: [UInt8](repeating: 0x41, count: 160), from: 16))
    }

    /// A raw erase zeroes only the pages its format owns, and a stale tail
    /// from an earlier write can sit past them. Those bytes are unreadable,
    /// not absent, so the tag stays "unknown" rather than "empty".
    @Test func zeroedPagesFollowedByStaleBytesAreNotBlank() {
        var user = [UInt8](repeating: 0x00, count: 112)     // pages 4-31 zeroed
        user += Array(#""spool_id":45}"#.utf8)              // pages 32+ still hold JSON
        #expect(!TagDumpDecode.isBlank(in: Self.tagPages(user: user), from: 16))
    }
}
