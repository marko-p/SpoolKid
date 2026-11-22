//
//  TagDumpTests.swift
//  SpoolKidTests
//
//  A dump is evidence. If it does not round-trip byte-for-byte it is a story
//  about a tag, which is worth nothing to whoever reads it later.
//

import Testing
import Foundation
@testable import SpoolKid

struct TagDumpTests {

    private func sample(note: String = "Anycubic PLA+ black, factory, unused") -> TagDump {
        TagDump(
            capturedAt: Date(timeIntervalSince1970: 1_788_739_200),
            uid: "04A1B2C3D4E580",
            tagType: "MIFARE Ultralight",
            chipVersion: "NTAG215",
            pagesRead: 135,
            endedBy: .wrap,
            pages: ["04A1B2C3", "D4E58000"],
            decodedAs: "anycubicACE",
            note: note,
            appVersion: "0.18 (42)"
        )
    }

    @Test func aDumpRoundTripsThroughJSON() throws {
        let original = sample()
        let data = try TagDump.encoder.encode(original)
        let restored = try TagDump.decoder.decode(TagDump.self, from: data)
        #expect(restored == original)
    }

    /// A tag no decoder claims is the most interesting kind of tag there is.
    @Test func anUndecodedDumpRoundTripsWithNullFields() throws {
        var dump = sample(note: "")
        dump = TagDump(
            capturedAt: dump.capturedAt, uid: dump.uid, tagType: dump.tagType,
            chipVersion: nil, pagesRead: dump.pagesRead, endedBy: .error,
            pages: dump.pages, decodedAs: nil, note: "", appVersion: dump.appVersion
        )
        let restored = try TagDump.decoder.decode(TagDump.self, from: TagDump.encoder.encode(dump))
        #expect(restored.decodedAs == nil)
        #expect(restored.chipVersion == nil)
        #expect(restored.note.isEmpty)
        #expect(restored.endedBy == .error)
    }

    @Test func datesAreISO8601SoTheFileReadsAsText() throws {
        let json = String(data: try TagDump.encoder.encode(sample()), encoding: .utf8) ?? ""
        #expect(json.contains("2026-09-07T"))
    }

    /// Pages are the unit the ACE-RFID spec is written in, so a dump can be
    /// read straight against it.
    @Test func bytesBecomeUppercaseFourByteHexPages() {
        let pages = TagDump.hexPages(from: [0x04, 0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0x80, 0x00])
        #expect(pages == ["04A1B2C3", "D4E58000"])
    }

    /// A tag whose last read returned a partial block must not silently lose
    /// the tail or invent zeroes for it.
    @Test func aTrailingPartialPageIsDroppedRatherThanPadded() {
        let pages = TagDump.hexPages(from: [0x04, 0xA1, 0xB2, 0xC3, 0xD4, 0xE5])
        #expect(pages == ["04A1B2C3"])
    }
}
