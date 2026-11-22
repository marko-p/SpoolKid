//
//  Type2NDEFTests.swift
//  SpoolKidTests
//
//  Pins the Type 2 packing the printer's reader writes with: NDEF records to
//  message bytes, the TLV and capability container laid onto NTAG pages, and
//  the geometry each NTAG size implies.
//

import Foundation
import Testing
@testable import SpoolKid

struct Type2NDEFTests {

    private static let ntag213 = Type2Geometry(versionReply: [0, 4, 4, 2, 1, 0, 0x0F, 3], capabilityContainer: [])
    private static let ntag215 = Type2Geometry(versionReply: [0, 4, 4, 2, 1, 0, 0x11, 3], capabilityContainer: [])
    private static let formattedCC: [UInt8] = [0xE1, 0x10, 0x3E, 0x00]
    private static let blankCC: [UInt8] = [0, 0, 0, 0]

    private static func textRecord(payload: Data) -> NDEFRecordSnapshot {
        NDEFRecordSnapshot(typeNameFormat: 0x01, type: Data("T".utf8), identifier: Data(), payload: payload)
    }

    /// The pages laid onto a flat user-memory buffer, the way a tag would hold them.
    private static func laidOut(_ pages: [(page: Int, data: Data)], totalPages: Int) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: totalPages * 4)
        for entry in pages {
            buffer.replaceSubrange(entry.page * 4 ..< entry.page * 4 + entry.data.count, with: entry.data)
        }
        return buffer
    }

    @Test func messageBytesRoundTripThroughRecords() {
        let short = NDEFRecordSnapshot(typeNameFormat: 0x01, type: Data("T".utf8), identifier: Data(), payload: Data([0x02, 0x65, 0x6E]))
        let long = NDEFRecordSnapshot(
            typeNameFormat: 0x02,
            type: Data("application/x-spoolkid".utf8),
            identifier: Data("id1".utf8),
            payload: Data(repeating: 0xAB, count: 300)
        )
        let bytes = Type2NDEF.messageBytes(for: [short, long])
        #expect(Type2NDEF.records(fromMessageBytes: bytes) == [short, long])
    }

    @Test func pagesStartWithTLVAndEndWithTerminator() throws {
        let message: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        let pages = try #require(Type2NDEF.pages(
            forMessageBytes: message,
            geometry: Self.ntag215,
            currentCapabilityContainer: Self.formattedCC
        ))
        #expect(pages.first?.page == 4)
        #expect(pages.first?.data == Data([0x03, 0x0A, 1, 2]))
        // TLV header (2) + message (10) puts the terminator at byte 12 of the chain: page 7, byte 0.
        let terminatorPage = try #require(pages.first { $0.page == 7 })
        #expect(terminatorPage.data.first == 0xFE)
    }

    @Test func longMessageUsesThreeByteLength() throws {
        let message = [UInt8](repeating: 0x55, count: 300)
        let pages = try #require(Type2NDEF.pages(
            forMessageBytes: message,
            geometry: Self.ntag215,
            currentCapabilityContainer: Self.formattedCC
        ))
        #expect(pages.first?.data == Data([0x03, 0xFF, 0x01, 0x2C]))
    }

    @Test func blankTagGetsCapabilityContainerPage() throws {
        let pages = try #require(Type2NDEF.pages(
            forMessageBytes: [1, 2],
            geometry: Self.ntag215,
            currentCapabilityContainer: Self.blankCC
        ))
        #expect(pages.first?.page == 3)
        #expect(pages.first?.data == Data(Self.formattedCC))
    }

    @Test func formattedTagSkipsCapabilityContainerPage() throws {
        let pages = try #require(Type2NDEF.pages(
            forMessageBytes: [1, 2],
            geometry: Self.ntag215,
            currentCapabilityContainer: Self.formattedCC
        ))
        #expect(pages.first?.page == 4)
    }

    @Test func messageThatDoesNotFitReturnsNil() {
        let oversized = [UInt8](repeating: 0x11, count: 200)
        #expect(Type2NDEF.pages(
            forMessageBytes: oversized,
            geometry: Self.ntag213,
            currentCapabilityContainer: Self.formattedCC
        ) == nil)

        // NTAG213 holds 144 bytes of user memory: a 141-byte message's TLV is exactly 144 bytes.
        let exactFit = [UInt8](repeating: 0x11, count: 141)
        #expect(Type2NDEF.pages(
            forMessageBytes: exactFit,
            geometry: Self.ntag213,
            currentCapabilityContainer: Self.formattedCC
        ) != nil)
    }

    @Test func packedPagesDecodeWithTheExistingUnpacker() throws {
        let message = Type2NDEF.messageBytes(for: [Self.textRecord(payload: Data(repeating: 0x41, count: 60))])
        let pages = try #require(Type2NDEF.pages(
            forMessageBytes: message,
            geometry: Self.ntag213,
            currentCapabilityContainer: Self.blankCC
        ))
        let buffer = Self.laidOut(pages, totalPages: Self.ntag213.totalPages)
        #expect(TagDumpDecode.ndefMessageBytes(in: buffer, from: 16) == message)
    }

    @Test func truncatedOrChunkedMessageIsNil() {
        let valid = Type2NDEF.messageBytes(for: [Self.textRecord(payload: Data([1, 2, 3]))])
        #expect(Type2NDEF.records(fromMessageBytes: Array(valid.dropLast())) == nil)

        var chunked = valid
        chunked[0] |= 0x20
        #expect(Type2NDEF.records(fromMessageBytes: chunked) == nil)
    }

    @Test func geometryForEachNTAGAndFallback() {
        let ntag213 = Self.ntag213
        #expect(ntag213.lastUserPage == 39)
        #expect(ntag213.totalPages == 45)
        #expect(ntag213.capabilityContainer == [0xE1, 0x10, 0x12, 0x00])
        #expect(ntag213.userByteCapacity == 144)

        let ntag215 = Self.ntag215
        #expect(ntag215.lastUserPage == 129)
        #expect(ntag215.totalPages == 135)
        #expect(ntag215.capabilityContainer == Self.formattedCC)

        let ntag216 = Type2Geometry(versionReply: [0, 4, 4, 2, 1, 0, 0x13, 3], capabilityContainer: [])
        #expect(ntag216.lastUserPage == 225)
        #expect(ntag216.totalPages == 231)
        #expect(ntag216.capabilityContainer == [0xE1, 0x10, 0x6D, 0x00])

        // No usable version reply: the capability container decides, as the plugin does.
        let fallback213 = Type2Geometry(versionReply: nil, capabilityContainer: [0xE1, 0x10, 0x12, 0x00])
        #expect(fallback213.lastUserPage == 39)
        #expect(fallback213.totalPages == 40)

        let unknownVersion = Type2Geometry(versionReply: [0, 4, 4, 2, 1, 0, 0x99, 3], capabilityContainer: [0xE1, 0x10, 0x12, 0x00])
        #expect(unknownVersion == fallback213)

        let zeroSize = Type2Geometry(versionReply: nil, capabilityContainer: [0xE1, 0x10, 0x00, 0x00])
        #expect(zeroSize.lastUserPage == 15)
        #expect(zeroSize.totalPages == 16)
    }

    /// The iPhone wrote this NTAG215 dump (OpenSpool, 245-byte message). Parsing its message and
    /// packing it again must reproduce every page from 4 through the terminator.
    @Test func repackingARealIPhoneWrittenDumpIsByteIdentical() throws {
        let dump = TagDumpDecodeTests.bytes(TagDumpDecodeTests.openSpoolTagPages)
        let message = try #require(TagDumpDecode.ndefMessageBytes(in: dump, from: 16))
        let records = try #require(Type2NDEF.records(fromMessageBytes: message))
        let repacked = Type2NDEF.messageBytes(for: records)
        #expect(repacked == message)

        let pages = try #require(Type2NDEF.pages(
            forMessageBytes: repacked, geometry: Self.ntag215, currentCapabilityContainer: Self.formattedCC))
        let packed = pages.flatMap { Array($0.data) }
        #expect(pages.first?.page == 4)
        #expect(pages.last?.page == TagDumpDecodeTests.openSpoolTagPages.count - 1)
        #expect(packed == Array(dump[16...]))
    }

    @Test func tlvLengthSwitchesToThreeBytesAtTwoHundredFiftyFive() throws {
        let short = try #require(Type2NDEF.pages(
            forMessageBytes: [UInt8](repeating: 0x55, count: 254),
            geometry: Self.ntag215, currentCapabilityContainer: Self.formattedCC))
        #expect(Array(short[0].data) == [0x03, 0xFE, 0x55, 0x55])
        // 2 header bytes + 254 + terminator = 257 bytes = 65 pages.
        #expect(short.count == 65)

        let long = try #require(Type2NDEF.pages(
            forMessageBytes: [UInt8](repeating: 0x55, count: 255),
            geometry: Self.ntag215, currentCapabilityContainer: Self.formattedCC))
        #expect(Array(long[0].data) == [0x03, 0xFF, 0x00, 0xFF])
        // 4 header bytes + 255 + terminator = 260 bytes = 65 pages.
        #expect(long.count == 65)
        let tail = long.flatMap { Array($0.data) }
        #expect(tail[259] == 0xFE)
    }
}
