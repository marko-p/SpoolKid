//
//  TagSnapshotTests.swift
//  SpoolKidTests
//
//  A clone is only a clone if what goes back onto the tag is exactly what came
//  off it. These pin that a snapshot rebuilds byte-identical NDEF records, and
//  that a raw snapshot is precisely the pages a format's read covers — pages
//  0-3 belong to the chip, not to its content.
//
//  Records are built with CoreNFC's own initializers rather than SpoolKid's
//  helpers, so nothing here depends on the codecs the clone deliberately
//  bypasses.
//

import Foundation
import CoreNFC
import Testing
@testable import SpoolKid

struct TagSnapshotTests {

    // MARK: - NDEF records

    private func expectByteIdenticalRoundTrip(_ records: [NFCNDEFPayload]) throws {
        let snapshot = TagSnapshot.capturing(records)
        let rebuilt = try #require(snapshot.records())

        #expect(rebuilt.count == records.count)
        for (original, copy) in zip(records, rebuilt) {
            #expect(copy.typeNameFormat == original.typeNameFormat)
            #expect(copy.type == original.type)
            #expect(copy.identifier == original.identifier)
            #expect(copy.payload == original.payload)
        }
        #expect(NFCNDEFMessage(records: rebuilt).length == NFCNDEFMessage(records: records).length)
        #expect(TagSnapshot.capturing(rebuilt) == snapshot)
    }

    @Test func anOpenSpoolRecordRoundTripsByteForByte() throws {
        let json = #"{"protocol":"openspool","version":"1.0","type":"PLA","color_hex":"FF0000","brand":"Generic","min_temp":"200","max_temp":"220","vendor_key":"kept-by-another-app"}"#
        let record = NFCNDEFPayload(
            format: .media,
            type: Data("application/json".utf8),
            identifier: Data(),
            payload: Data(json.utf8)
        )
        try expectByteIdenticalRoundTrip([record])
    }

    /// OpenPrintTag writes a URI record before its CBOR record. Both come
    /// back, in order.
    @Test func anOpenPrintTagLinkAndCBORPairRoundTripsInOrder() throws {
        let uri = try #require(NFCNDEFPayload.wellKnownTypeURIPayload(string: "https://3dtag.org/s/abc"))
        let cbor = NFCNDEFPayload(
            format: .media,
            type: Data("application/vnd.openprinttag".utf8),
            identifier: Data(),
            payload: Data([0xA0, 0xBF, 0x08, 0x19, 0x03, 0xE8, 0x18, 0x1D, 0xF9, 0x3F, 0x9E, 0xFF])
        )
        try expectByteIdenticalRoundTrip([uri, cbor])

        let rebuilt = try #require(TagSnapshot.capturing([uri, cbor]).records())
        #expect(rebuilt.first?.wellKnownTypeURIPayload()?.absoluteString == "https://3dtag.org/s/abc")
    }

    @Test func aLocationTextAndMIMEPairRoundTrips() throws {
        let text = try #require(NFCNDEFPayload.wellKnownTypeTextPayload(
            string: "SpoolKid location: Shelf A", locale: Locale(identifier: "en")
        ))
        let json = #"{"protocol":"spoolkid-location","version":1,"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Shelf A"}"#
        let mime = NFCNDEFPayload(
            format: .media,
            type: Data("application/vnd.spoolkid.location".utf8),
            identifier: Data(),
            payload: Data(json.utf8)
        )
        try expectByteIdenticalRoundTrip([text, mime])
    }

    /// Nothing SpoolKid writes carries a record identifier, but another app's
    /// tag may, and an exact copy keeps it.
    @Test func aRecordIdentifierSurvives() throws {
        let record = NFCNDEFPayload(
            format: .nfcExternal,
            type: Data("example.com:spool".utf8),
            identifier: Data([0x01, 0x02, 0x03]),
            payload: Data([0xDE, 0xAD, 0xBE, 0xEF])
        )
        try expectByteIdenticalRoundTrip([record])
    }

    /// Records parsed from a tag's own bytes rebuild to the same length, so a
    /// canonically encoded message copies as the same bytes. The record is the
    /// one on every real ELEGOO tag (a short URI record).
    @Test func aShortRecordParsedFromWireBytesRebuildsToTheSameLength() throws {
        let wire: [UInt8] = [0xD1, 0x01, 0x0B, 0x55, 0x02] + Array("elegoo.com".utf8)
        let parsed = try #require(NFCNDEFMessage(data: Data(wire)))
        let rebuilt = try #require(TagSnapshot.capturing(parsed.records).records())
        #expect(NFCNDEFMessage(records: rebuilt).length == wire.count)
    }

    /// A payload over 255 bytes needs the long record form; it survives too.
    @Test func aLongRecordParsedFromWireBytesRebuildsToTheSameLength() throws {
        // MB|ME|TNF media, long form: type length, 4-byte payload length, type, payload.
        let wire: [UInt8] = [0xC2, 0x0A, 0x00, 0x00, 0x01, 0x2C]
            + Array("text/plain".utf8)
            + [UInt8](repeating: 0x41, count: 300)
        let parsed = try #require(NFCNDEFMessage(data: Data(wire)))
        let rebuilt = try #require(TagSnapshot.capturing(parsed.records).records())
        #expect(NFCNDEFMessage(records: rebuilt).length == wire.count)
    }

    @Test func aRawSnapshotHasNoRecords() {
        #expect(TagSnapshot.rawPages(firstPage: 4, bytes: [1, 2, 3, 4]).records() == nil)
    }

    // MARK: - Raw pages

    /// Every byte is its own index, so a wrong offset shows up as wrong values.
    private func indexedBuffer(count: Int) -> [UInt8] {
        (0..<count).map { UInt8($0) }
    }

    /// Anycubic ACE reads pages 0-31; the copy is pages 4-31.
    @Test func theACERangeIsPagesFourThroughThirtyOne() throws {
        let snapshot = try #require(TagSnapshot.capturingPages(indexedBuffer(count: 128), firstPage: 4, lastPage: 31))
        #expect(snapshot == .rawPages(firstPage: 4, bytes: (16..<128).map { UInt8($0) }))
    }

    /// ELEGOO reads pages 4-35 into a buffer indexed from page 0.
    @Test func theElegooRangeIsPagesFourThroughThirtyFive() throws {
        let snapshot = try #require(TagSnapshot.capturingPages(indexedBuffer(count: 144), firstPage: 4, lastPage: 35))
        #expect(snapshot == .rawPages(firstPage: 4, bytes: (16..<144).map { UInt8($0) }))
    }

    @Test func aBufferThatStopsShortOfTheLastPageCapturesNothing() {
        #expect(TagSnapshot.capturingPages(indexedBuffer(count: 143), firstPage: 4, lastPage: 35) == nil)
    }

    @Test func aLastPageBeforeTheFirstCapturesNothing() {
        #expect(TagSnapshot.capturingPages(indexedBuffer(count: 144), firstPage: 8, lastPage: 7) == nil)
    }

    /// The ranges above are the ones `NFCManager` passes. Pinned against the
    /// payload types' own constants so a change to a read buffer cannot
    /// silently shorten a copy.
    @MainActor
    @Test func theCapturedRangesMatchTheReadBuffers() {
        #expect(TagSnapshot.firstUserPage == 4)
        #expect(AnycubicACEPayload.totalPages - 1 == 31)
        #expect((ElegooPayload.readPages.max() ?? 0) + 3 == 35)
    }

    /// Read buffers start zero-filled, so a READ list with a gap would put
    /// never-read zeros into a copy without anything failing. Each READ covers
    /// four pages; together they must cover every captured page.
    @MainActor
    @Test func theReadListsCoverEveryCapturedPage() {
        func covered(_ readPages: [Int]) -> Set<Int> {
            Set(readPages.flatMap { $0..<($0 + 4) })
        }
        #expect(covered(AnycubicACEPayload.readPages).isSuperset(of: 4...31))
        #expect(covered(ElegooPayload.readPages).isSuperset(of: 4...35))
    }
}
