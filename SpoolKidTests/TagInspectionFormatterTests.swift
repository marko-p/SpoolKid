//
//  TagInspectionFormatterTests.swift
//  SpoolKidTests
//
//  The Inspect Tag screen shows a tester what is on the tag, so these pin the
//  strings it derives from the raw facts: a chip or maker named only where the
//  mapping is verified, record text shown exactly as stored, and the dumps
//  laid out the way the screen and the share text promise.
//

import Testing
import Foundation
import CoreNFC
@testable import SpoolKid

struct TagInspectionFormatterTests {

    // MARK: - Fixtures

    private let ntag215 = TagInspection(
        capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
        family: .mifareUltralight,
        uid: [0x04, 0xA2, 0x3F, 0x1A, 0xB2, 0x5C, 0x80],
        icManufacturerCode: nil,
        ndef: .init(access: .readWrite, capacity: 496, messageLength: 212),
        chip: .init(getVersion: [0x00, 0x04, 0x04, 0x02, 0x01, 0x00, 0x11, 0x03])
    )

    private let slix = TagInspection(
        capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
        family: .iso15693,
        uid: [0xE0, 0x04, 0x01, 0x08, 0x12, 0xA9, 0xC3, 0xF1],
        icManufacturerCode: 0x04,
        chip: .init(icReference: 0x01, blockSize: 4, totalBlocks: 80)
    )

    private func record(tnf: UInt8, type: String, payload: [UInt8], id: [UInt8] = []) -> NDEFRecordSnapshot {
        NDEFRecordSnapshot(
            typeNameFormat: tnf,
            type: Data(type.utf8),
            identifier: Data(id),
            payload: Data(payload)
        )
    }

    private func snapshot(of payload: NFCNDEFPayload) -> NDEFRecordSnapshot {
        NDEFRecordSnapshot(record: payload)
    }

    private func value(_ rows: [InspectorRow], _ label: String) -> String? {
        rows.first { $0.label == label }?.value
    }

    private func labels(_ rows: [InspectorRow]) -> [String] { rows.map(\.label) }

    private func firstRecord(_ snap: NDEFRecordSnapshot) throws -> InspectorRecord {
        try #require(TagInspectionFormatter.records(inspection(ntag215, records: [snap])).first)
    }

    /// A well-known `U` record: the prefix code, then the rest as UTF-8.
    private func uriRecord(prefix: UInt8, _ rest: String) -> NDEFRecordSnapshot {
        record(tnf: 1, type: "U", payload: [prefix] + Array(rest.utf8))
    }

    private func inspection(_ base: TagInspection, records: [NDEFRecordSnapshot]) -> TagInspection {
        var copy = base
        copy.ndef = .init(access: .readWrite, capacity: 496, messageLength: 212, records: records)
        return copy
    }

    // MARK: - Chip

    @Test func ntag215ChipRows() {
        let rows = TagInspectionFormatter.chipRows(ntag215)
        #expect(rows == [
            InspectorRow(label: "Chip", value: "NTAG215"),
            InspectorRow(label: "Made by", value: "NXP Semiconductors"),
            InspectorRow(label: "Technology", value: "NFC-A (ISO 14443-3A)"),
            InspectorRow(label: "NFC Forum type", value: "Type 2"),
            InspectorRow(label: "UID", value: "04A23F1AB25C80"),
            InspectorRow(label: "Memory size", value: "135 pages × 4 bytes"),
        ])
    }

    @Test func unknownVersionShowsRawBytes() {
        var tag = ntag215
        tag.chip = .init(getVersion: [0x00, 0x04, 0x03, 0x01, 0x01, 0x00, 0x0B, 0x03])
        let rows = TagInspectionFormatter.chipRows(tag)
        #expect(value(rows, "Chip") == "MIFARE Ultralight family (version 00 04 03 01 01 00 0B 03)")
        #expect(value(rows, "Memory size") == nil)
    }

    @Test func noChipReplyFallsBackToFamily() {
        var tag = ntag215
        tag.chip = nil
        let rows = TagInspectionFormatter.chipRows(tag)
        #expect(value(rows, "Chip") == "MIFARE Ultralight family")
        #expect(value(rows, "Memory size") == nil)
    }

    @Test func slixChipRows() {
        let rows = TagInspectionFormatter.chipRows(slix)
        #expect(rows == [
            InspectorRow(label: "Chip", value: "ICODE SLIX2"),
            InspectorRow(label: "Made by", value: "NXP Semiconductors"),
            InspectorRow(label: "Technology", value: "NFC-V (ISO 15693)"),
            InspectorRow(label: "NFC Forum type", value: "Type 5"),
            InspectorRow(label: "UID", value: "E004010812A9C3F1"),
            InspectorRow(label: "Memory size", value: "80 blocks × 4 bytes"),
        ])
    }

    /// The ICODE type is in the UID, so it is named even when Get System Info
    /// was not answered.
    @Test func anICODEIsNamedWithoutSystemInfo() {
        var tag = slix
        tag.chip = nil
        #expect(value(TagInspectionFormatter.chipRows(tag), "Chip") == "ICODE SLIX2")
    }

    @Test func anUnnamedISO15693ChipShowsItsICReference() {
        let tag = TagInspection(
            capturedAt: Date(), family: .iso15693,
            uid: [0xE0, 0x04, 0x01, 0x18, 0x12, 0xA9, 0xC3, 0xF1], icManufacturerCode: 0x04,
            chip: .init(icReference: 0x01, blockSize: 4, totalBlocks: 64)
        )
        #expect(value(TagInspectionFormatter.chipRows(tag), "Chip") == "ISO 15693, IC 0x01")
    }

    @Test func aFourByteUIDHasNoManufacturer() {
        let tag = TagInspection(
            capturedAt: Date(), family: .mifareOther,
            uid: [0x08, 0x11, 0x22, 0x33], icManufacturerCode: nil
        )
        let rows = TagInspectionFormatter.chipRows(tag)
        #expect(value(rows, "Made by") == nil)
        #expect(value(rows, "NFC Forum type") == nil)
        #expect(value(rows, "Chip") == "ISO 14443-A tag")
    }

    @Test func unknownManufacturerShowsCode() {
        #expect(TagInspectionFormatter.manufacturerName(code: 0x99) == "Code 0x99")
    }

    @Test func manufacturerTable() {
        #expect(TagInspectionFormatter.manufacturerName(code: 0x02) == "STMicroelectronics")
        #expect(TagInspectionFormatter.manufacturerName(code: 0x04) == "NXP Semiconductors")
        #expect(TagInspectionFormatter.manufacturerName(code: 0x05) == "Infineon Technologies")
        #expect(TagInspectionFormatter.manufacturerName(code: 0x07) == "Texas Instruments")
        #expect(TagInspectionFormatter.manufacturerName(code: 0x16) == "EM Microelectronic-Marin")
    }

    /// A ten-byte NFC-A UID also starts with the manufacturer code; the
    /// ISO 15693 code comes from the tag, not from `uid[0]`.
    @Test func manufacturerSourceFollowsTheFamily() {
        let tenBytes = TagInspection(
            capturedAt: Date(), family: .mifarePlus,
            uid: [0x02, 1, 2, 3, 4, 5, 6, 7, 8, 9], icManufacturerCode: nil
        )
        #expect(value(TagInspectionFormatter.chipRows(tenBytes), "Made by") == "STMicroelectronics")

        let noCode = TagInspection(
            capturedAt: Date(), family: .iso15693,
            uid: [0xE0, 0x04, 0x01, 0x08, 0x12, 0xA9, 0xC3, 0xF1], icManufacturerCode: nil
        )
        #expect(value(TagInspectionFormatter.chipRows(noCode), "Made by") == nil)
    }

    @Test func familyFallbacks() {
        func chip(_ family: TagInspection.Family) -> String? {
            let tag = TagInspection(capturedAt: Date(), family: family, uid: [1, 2, 3, 4], icManufacturerCode: nil)
            return value(TagInspectionFormatter.chipRows(tag), "Chip")
        }
        #expect(chip(.mifareDESFire) == "MIFARE DESFire")
        #expect(chip(.mifarePlus) == "MIFARE Plus")
        #expect(chip(.mifareOther) == "ISO 14443-A tag")
        #expect(chip(.iso15693) == "ISO 15693 tag")
        #expect(chip(.iso7816) == "ISO 7816 smart card")
        #expect(chip(.feliCa) == "FeliCa")
    }

    // MARK: - Memory

    @Test func memoryRowsForAMessage() {
        let rows = TagInspectionFormatter.memoryRows(ntag215)
        #expect(rows == [
            InspectorRow(label: "Used", value: "212 of 496 bytes"),
            InspectorRow(label: "Free", value: "284 bytes"),
            InspectorRow(label: "Write access", value: "Writable"),
        ])
        let usage = TagInspectionFormatter.memoryUsage(ntag215)
        #expect(usage?.used == 212)
        #expect(usage?.capacity == 496)
    }

    @Test func memoryRowsWithoutAMessage() {
        var tag = ntag215
        tag.ndef = .init(access: .readOnly, capacity: 496)
        #expect(TagInspectionFormatter.memoryRows(tag) == [
            InspectorRow(label: "Capacity", value: "496 bytes"),
            InspectorRow(label: "Write access", value: "Read-only"),
        ])
        #expect(TagInspectionFormatter.memoryUsage(tag) == nil)
    }

    @Test func freeSpaceIsNeverNegative() {
        var tag = ntag215
        tag.ndef = .init(access: .readWrite, capacity: 100, messageLength: 130)
        #expect(value(TagInspectionFormatter.memoryRows(tag), "Free") == "0 bytes")
    }

    @Test func notFormattedShowsOnlyAccess() {
        var tag = ntag215
        tag.ndef = .init(access: .notSupported, capacity: 0)
        #expect(TagInspectionFormatter.memoryRows(tag) == [
            InspectorRow(label: "Write access", value: "Not NDEF-formatted"),
        ])
        #expect(TagInspectionFormatter.memoryUsage(tag) == nil)
    }

    /// The status probe can be inconclusive and the read still return a
    /// message. The tag then has records, so it must not be called
    /// unformatted, and a capacity of 0 is not a capacity to gauge against.
    @Test func inconclusiveProbeWithAMessageShowsOnlyUsed() {
        var tag = ntag215
        tag.ndef = .init(access: .notSupported, capacity: 0, messageLength: 212)
        #expect(TagInspectionFormatter.memoryRows(tag) == [
            InspectorRow(label: "Used", value: "212 bytes"),
        ])
        #expect(TagInspectionFormatter.memoryUsage(tag) == nil)

        tag.ndef = .init(access: .notSupported, capacity: 0, messageLength: 1)
        #expect(TagInspectionFormatter.memoryRows(tag) == [
            InspectorRow(label: "Used", value: "1 byte"),
        ])
    }

    @Test func noNDEFStatusMeansNoMemoryRows() {
        var tag = ntag215
        tag.ndef = nil
        #expect(TagInspectionFormatter.memoryRows(tag).isEmpty)
        #expect(TagInspectionFormatter.memoryUsage(tag) == nil)
    }

    // MARK: - Content

    @Test func layoutForElegoo() {
        var tag = inspection(ntag215, records: [record(tnf: 1, type: "U", payload: [0x04] + Array("example.com".utf8))])
        tag.rawMemory = .init(firstUnit: 4, unitSize: 4, bytes: Array(repeating: 0, count: 128))
        let rows = TagInspectionFormatter.contentRows(tag, formatName: "ELEGOO")
        #expect(rows == [
            InspectorRow(label: "Format", value: "ELEGOO"),
            InspectorRow(label: "Layout", value: "NDEF, 1 record + raw pages 4–35"),
        ])
    }

    @Test func layoutForIso15693Raw() {
        var tag = slix
        tag.rawMemory = .init(firstUnit: 0, unitSize: 4, bytes: Array(repeating: 0, count: 320))
        #expect(value(TagInspectionFormatter.contentRows(tag, formatName: "Unknown tag format"), "Layout") == "Raw blocks 0–79")
        #expect(TagInspectionFormatter.rawSectionTitle(tag) == "Raw Blocks")
        #expect(TagInspectionFormatter.rawSectionTitle(ntag215) == "Raw Pages")
    }

    @Test func layoutForNDEFAndForRawPagesAlone() {
        let two = inspection(ntag215, records: [
            record(tnf: 2, type: "text/plain", payload: [0x61]),
            record(tnf: 2, type: "text/plain", payload: [0x62]),
        ])
        #expect(value(TagInspectionFormatter.contentRows(two, formatName: "x"), "Layout") == "NDEF, 2 records")

        var raw = ntag215
        raw.ndef = nil
        raw.rawMemory = .init(firstUnit: 4, unitSize: 4, bytes: Array(repeating: 0, count: 144))
        #expect(value(TagInspectionFormatter.contentRows(raw, formatName: "x"), "Layout") == "Raw pages 4–39")
    }

    @Test func noRecordsAndNoRawMemoryHasNoLayout() {
        let rows = TagInspectionFormatter.contentRows(ntag215, formatName: "Empty tag")
        #expect(rows == [InspectorRow(label: "Format", value: "Empty tag")])
    }

    @Test func formatNames() {
        #expect(TagInspectionFormatter.formatName(format: .openSpool, isLocationTag: false, undecodedNote: nil) == "OpenSpool")
        #expect(TagInspectionFormatter.formatName(format: nil, isLocationTag: true, undecodedNote: nil) == "SpoolKid location")
        #expect(TagInspectionFormatter.formatName(format: .webUrl, isLocationTag: false, undecodedNote: nil) == "Web link")
        #expect(TagInspectionFormatter.formatName(format: nil, isLocationTag: false, undecodedNote: "Empty tag") == "Empty tag")
        #expect(TagInspectionFormatter.formatName(format: nil, isLocationTag: false, undecodedNote: nil) == "Unknown tag format")
    }

    // MARK: - Records

    private func openSpoolRecord() throws -> (record: NDEFRecordSnapshot, encoded: Data) {
        let tagData = FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "D32F2F",
            minNozzleTemp: 190, maxNozzleTemp: 220, minBedTemp: 50, maxBedTemp: 60
        )
        let encoded = try #require(TagFormatService.shared.encode(data: tagData, format: .openSpool))
        return (record(tnf: 2, type: "application/json", payload: [UInt8](encoded)), encoded)
    }

    @Test func openSpoolJSONShowsExactlyAsEncoded() throws {
        let (json, encoded) = try openSpoolRecord()
        let records = TagInspectionFormatter.records(inspection(ntag215, records: [json]))
        let first = try #require(records.first)
        #expect(first.text == String(decoding: encoded, as: UTF8.self))
        #expect(first.title == "Record 1 · application/json")
        #expect(value(first.rows, "Size") == "\(encoded.count) bytes · UTF-8 text")
        #expect(value(first.rows, "Kind") == "MIME type")
    }

    @Test func textRecordDecodesLanguageAndText() throws {
        let payload = try #require(NFCNDEFPayload.wellKnownTypeTextPayload(string: "Hello", locale: Locale(identifier: "en")))
        let snap = snapshot(of: payload)
        let first = try #require(TagInspectionFormatter.records(inspection(ntag215, records: [snap])).first)
        #expect(first.title == "Record 1 · Text")
        #expect(first.text == "Hello")
        #expect(value(first.rows, "Language") == "en")
        #expect(value(first.rows, "Size") == "\(snap.payload.count) bytes · text")
        #expect(labels(first.rows) == ["Kind", "Language", "Size"])
    }

    @Test func uriRecordExpandsPrefix() throws {
        let payload = try #require(NFCNDEFPayload.wellKnownTypeURIPayload(string: "https://spoolman.local/spool/show/42"))
        let snap = snapshot(of: payload)
        let first = try #require(TagInspectionFormatter.records(inspection(ntag215, records: [snap])).first)
        #expect(first.text == "https://spoolman.local/spool/show/42")
        #expect(first.title == "Record 1 · Link")
        #expect(value(first.rows, "Size") == "\(snap.payload.count) bytes · link")
        #expect(value(first.rows, "Kind") == "Well-known")
    }

    @Test func recordsForAnUnrecognisedMIMEType() throws {
        let snap = record(tnf: 2, type: "application/vnd.openprinttag", payload: [0xA2, 0x08, 0x1A, 0x00])
        let first = try #require(TagInspectionFormatter.records(inspection(ntag215, records: [snap])).first)
        #expect(first.text == nil)
        #expect(value(first.rows, "Size") == "4 bytes · binary")
        // Offset, two spaces, the hex padded to 23 characters, two spaces, ASCII.
        #expect(first.hex == "0000  A2 08 1A 00" + String(repeating: " ", count: 12) + "  ....")
    }

    @Test func controlCharactersMakeAPayloadBinary() throws {
        let snap = record(tnf: 2, type: "text/plain", payload: Array("ab".utf8) + [0x00])
        let first = try #require(TagInspectionFormatter.records(inspection(ntag215, records: [snap])).first)
        #expect(first.text == nil)
    }

    @Test func newlinesAndTabsStayText() throws {
        let raw = "a\tb\r\nc"
        let snap = record(tnf: 2, type: "text/plain", payload: Array(raw.utf8))
        let first = try #require(TagInspectionFormatter.records(inspection(ntag215, records: [snap])).first)
        #expect(first.text == raw)
    }

    /// `String(data:encoding:)` drops a leading byte-order mark. A third-party
    /// writer's `EF BB BF 7B ...` JSON is rejected by parsers because of that
    /// mark, so the screen must keep it rather than show clean-looking JSON.
    @Test func aByteOrderMarkIsKeptInTextAndID() throws {
        let bytes: [UInt8] = [0xEF, 0xBB, 0xBF] + Array("{\"a\":1}".utf8)
        let snap = record(tnf: 2, type: "application/json", payload: bytes, id: [0xEF, 0xBB, 0xBF, 0x61])
        let first = try #require(TagInspectionFormatter.records(inspection(ntag215, records: [snap])).first)
        let text = try #require(first.text)
        #expect(text.unicodeScalars.first == "\u{FEFF}")
        #expect(Array(text.utf8) == bytes)
        #expect(value(first.rows, "ID") == "\u{FEFF}a")
    }

    /// Invalid UTF-8 is binary; the repair that keeps the byte-order mark must
    /// not turn a bad byte into U+FFFD text.
    @Test func invalidUTF8StaysBinary() throws {
        let snap = record(tnf: 2, type: "text/plain", payload: [0x61, 0xFF, 0x62], id: [0xFF, 0x01])
        let first = try #require(TagInspectionFormatter.records(inspection(ntag215, records: [snap])).first)
        #expect(first.text == nil)
        #expect(value(first.rows, "Size") == "3 bytes · binary")
        #expect(value(first.rows, "ID") == "FF 01")
    }

    // MARK: - Links shown exactly as stored

    /// `URL.absoluteString` percent-encodes a space and non-ASCII text, which
    /// would show a link the tag does not hold. The prefix is expanded by hand.
    @Test func aLinkShowsExactlyAsStored() throws {
        let spaced = uriRecord(prefix: 0x04, "a b")
        let first = try firstRecord(spaced)
        #expect(first.text == "https://a b")
        #expect(first.title == "Record 1 · Link")
        #expect(value(first.rows, "Size") == "4 bytes · link")

        let accented = uriRecord(prefix: 0x00, "grün|x")
        let second = try firstRecord(accented)
        #expect(second.text == "grün|x")
        #expect(value(second.rows, "Size") == "\(accented.payload.count) bytes · link")
    }

    @Test func everyURIPrefixCodeExpands() throws {
        let prefixes = [
            "", "http://www.", "https://www.", "http://", "https://", "tel:", "mailto:",
            "ftp://anonymous:anonymous@", "ftp://ftp.", "ftps://", "sftp://", "smb://", "nfs://",
            "ftp://", "dav://", "news:", "telnet://", "imap:", "rtsp://", "urn:", "pop:", "sip:",
            "sips:", "tftp:", "btspp://", "btl2cap://", "btgoep://", "tcpobex://", "irdaobex://",
            "file://", "urn:epc:id:", "urn:epc:tag:", "urn:epc:pat:", "urn:epc:raw:", "urn:epc:",
            "urn:nfc:",
        ]
        #expect(prefixes.count == 0x24)
        for (code, prefix) in prefixes.enumerated() {
            let first = try firstRecord(uriRecord(prefix: UInt8(code), "x"))
            #expect(first.text == prefix + "x", "code \(code)")
        }
    }

    /// A prefix code past the table, or a remainder that is not UTF-8, is not
    /// a link CoreNFC or this screen can expand: the payload is judged as plain
    /// bytes, the way an undecodable `T` record is.
    @Test func anUnexpandableLinkFallsThroughToTheGenericRule() throws {
        // 0x24 is past the table but the bytes are printable UTF-8: shown as is.
        let printable = try firstRecord(uriRecord(prefix: 0x24, "abc"))
        #expect(printable.text == "$abc")
        #expect(value(printable.rows, "Size") == "4 bytes · UTF-8 text")

        // 0x99 alone is not valid UTF-8.
        let badPrefix = try firstRecord(record(tnf: 1, type: "U", payload: [0x99, 0x61]))
        #expect(badPrefix.text == nil)
        #expect(value(badPrefix.rows, "Size") == "2 bytes · binary")

        // A known prefix, but the rest is not UTF-8.
        let badRest = try firstRecord(record(tnf: 1, type: "U", payload: [0x04, 0xFF, 0x61]))
        #expect(badRest.text == nil)
        #expect(value(badRest.rows, "Size") == "3 bytes · binary")
    }

    // MARK: - Control characters

    /// U+0085 is UTF-8 `C2 85`: above 0x20 by scalar value, but a control
    /// character all the same.
    @Test func aC1ControlCharacterMakesAPayloadBinary() throws {
        let first = try firstRecord(record(tnf: 2, type: "text/plain", payload: [0x61, 0xC2, 0x85]))
        #expect(first.text == nil)
        #expect(value(first.rows, "Size") == "3 bytes · binary")
    }

    @Test func aControlCharacterInTheIDShowsHex() throws {
        func id(_ bytes: [UInt8]) throws -> String? {
            value(try firstRecord(record(tnf: 2, type: "text/plain", payload: [0x61], id: bytes)).rows, "ID")
        }
        #expect(try id([0x61, 0x00]) == "61 00")
        #expect(try id([0x61, 0x7F]) == "61 7F")
        #expect(try id([0x61, 0xC2, 0x85]) == "61 C2 85")
        // Tab, CR and LF are allowed, as in the payload rule.
        #expect(try id([0x61, 0x09, 0x0D, 0x0A]) == "a\t\r\n")
    }

    /// A well-known "T" record CoreNFC cannot decode (a language code longer
    /// than the payload) is not labelled "text": it takes the generic rule, so
    /// its status byte makes it binary, and it has no Language row.
    @Test func anUndecodableTextRecordIsBinary() throws {
        let snap = record(tnf: 1, type: "T", payload: [0x3F, 0x00, 0x01])
        #expect(snap.record().wellKnownTypeTextPayload().0 == nil)
        let first = try #require(TagInspectionFormatter.records(inspection(ntag215, records: [snap])).first)
        #expect(first.title == "Record 1 · Text")
        #expect(value(first.rows, "Size") == "3 bytes · binary")
        #expect(value(first.rows, "Language") == nil)
        #expect(first.text == nil)
    }

    @Test func emptyPayload() throws {
        let snap = record(tnf: 0, type: "", payload: [])
        let first = try #require(TagInspectionFormatter.records(inspection(ntag215, records: [snap])).first)
        #expect(first.title == "Record 1 · Empty")
        #expect(value(first.rows, "Size") == "0 bytes")
        #expect(first.text == nil)
        #expect(first.hex == "")
    }

    @Test func oneByteIsSingular() throws {
        let snap = record(tnf: 2, type: "application/octet-stream", payload: [0xFF])
        let first = try #require(TagInspectionFormatter.records(inspection(ntag215, records: [snap])).first)
        #expect(value(first.rows, "Size") == "1 byte · binary")
    }

    @Test func recordTitlesAndKinds() {
        func describe(tnf: UInt8, type: String) -> (title: String, kind: String?) {
            let snap = record(tnf: tnf, type: type, payload: [0x61])
            let first = TagInspectionFormatter.records(inspection(ntag215, records: [snap]))[0]
            return (first.title, value(first.rows, "Kind"))
        }
        #expect(describe(tnf: 1, type: "Sp").title == "Record 1 · Well-known “Sp”")
        #expect(describe(tnf: 3, type: "https://example.com/x").title == "Record 1 · https://example.com/x")
        #expect(describe(tnf: 3, type: "x").kind == "Absolute URI")
        #expect(describe(tnf: 4, type: "example.com:thing").title == "Record 1 · example.com:thing")
        #expect(describe(tnf: 4, type: "x").kind == "External")
        #expect(describe(tnf: 5, type: "").title == "Record 1 · Unknown")
        #expect(describe(tnf: 5, type: "").kind == "Unknown")
        #expect(describe(tnf: 6, type: "").title == "Record 1 · Unchanged")
        #expect(describe(tnf: 7, type: "").title == "Record 1 · Reserved")
        #expect(describe(tnf: 7, type: "").kind == "Reserved")
        #expect(describe(tnf: 0, type: "").kind == "Empty")
    }

    @Test func identifierShowsAsTextOrHex() throws {
        let asText = record(tnf: 2, type: "text/plain", payload: [0x61], id: Array("spool-1".utf8))
        let asHex = record(tnf: 2, type: "text/plain", payload: [0x61], id: [0xFF, 0x01])
        let none = record(tnf: 2, type: "text/plain", payload: [0x61])
        let records = TagInspectionFormatter.records(inspection(ntag215, records: [asText, asHex, none]))
        #expect(value(records[0].rows, "ID") == "spool-1")
        #expect(value(records[1].rows, "ID") == "FF 01")
        #expect(value(records[2].rows, "ID") == nil)
        #expect(records.map(\.title) == [
            "Record 1 · text/plain", "Record 2 · text/plain", "Record 3 · text/plain",
        ])
    }

    @Test func noRecordsWithoutNDEF() {
        var tag = ntag215
        tag.ndef = nil
        #expect(TagInspectionFormatter.records(tag).isEmpty)
    }

    // MARK: - Dumps

    @Test func hexDumpWrapsAtEight() {
        let bytes = [UInt8]("{\"protocol".utf8)
        let rows = TagInspectionFormatter.hexDump(bytes).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(rows.count == 2)
        #expect(rows[0] == "0000  7B 22 70 72 6F 74 6F 63  {\"protoc")
        #expect(rows[1].hasPrefix("0008  6F 6C"))
        #expect(rows[1].hasSuffix("  ol"))
    }

    @Test func hexDumpOfNothingIsEmpty() {
        #expect(TagInspectionFormatter.hexDump([]) == "")
    }

    @Test func bareHexIsSpaceSeparatedUppercase() {
        #expect(TagInspectionFormatter.bareHex([0xA2, 0x08, 0x1A, 0x00]) == "A2 08 1A 00")
        #expect(TagInspectionFormatter.bareHex([0xFF]) == "FF")
        #expect(TagInspectionFormatter.bareHex([]) == "")
    }

    /// Copy Hex copies this, not the dump: offsets and a readable column would
    /// have to be stripped by hand before the bytes could be pasted anywhere.
    @Test func aRecordsBareHexIsItsPayloadBareHex() throws {
        let binary = try firstRecord(record(tnf: 2, type: "application/vnd.openprinttag", payload: [0xA2, 0x08, 0x1A, 0x00]))
        #expect(binary.bareHex == "A2 08 1A 00")
        #expect(binary.bareHex == TagInspectionFormatter.bareHex([0xA2, 0x08, 0x1A, 0x00]))

        let (json, encoded) = try openSpoolRecord()
        let text = try firstRecord(json)
        #expect(text.bareHex == TagInspectionFormatter.bareHex([UInt8](encoded)))
        #expect(text.hex != text.bareHex)

        #expect(try firstRecord(record(tnf: 0, type: "", payload: [])).bareHex == "")
    }

    @Test func rawDumpRows() {
        let memory = TagInspection.RawMemory(
            firstUnit: 4, unitSize: 4,
            bytes: [0x7B, 0x00, 0x65, 0x00, 0x41, 0x42, 0x43, 0x44]
        )
        #expect(TagInspectionFormatter.rawDump(memory) == "  4  7B 00 65 00  {.e.\n  5  41 42 43 44  ABCD")
    }

    @Test func rawMemoryFromSnapshot() {
        let raw = TagInspection.RawMemory(snapshot: .rawPages(firstPage: 4, bytes: [1, 2, 3, 4]))
        #expect(raw?.firstUnit == 4)
        #expect(raw?.unitSize == 4)
        #expect(raw?.bytes == [1, 2, 3, 4])
        #expect(TagInspection.RawMemory(snapshot: .ndef([])) == nil)
        #expect(TagInspection.RawMemory(snapshot: nil) == nil)
    }

    // MARK: - Caption and share

    @Test func captionCopy() {
        let changed = TagInspectionFormatter.caption(capturedAt: Date(), changedSinceScan: true)
        #expect(changed == "This tag was changed after this scan. Scan it again to see what's on it now.")
        let current = TagInspectionFormatter.caption(capturedAt: Date(), changedSinceScan: false)
        #expect(current.hasPrefix("As read at "))
    }

    @Test func shareTextCoversEverything() throws {
        let (json, encoded) = try openSpoolRecord()
        var tag = inspection(ntag215, records: [json])
        tag.rawMemory = .init(firstUnit: 4, unitSize: 4, bytes: [0x7B, 0x00, 0x65, 0x00])
        let text = TagInspectionFormatter.shareText(tag, formatName: "OpenSpool", appVersion: "0.25 (1)")
        let record = try #require(TagInspectionFormatter.records(tag).first)
        let firstHexRow = try #require(record.hex.split(separator: "\n").first)

        #expect(text.hasPrefix("Inspect Tag — SpoolKid 0.25 (1)"))
        #expect(text.contains("Chip: NTAG215"))
        #expect(text.contains("Used: 212 of 496 bytes"))
        #expect(text.contains("Format: OpenSpool"))
        #expect(text.contains("Record 1 · application/json"))
        #expect(text.contains(String(decoding: encoded, as: UTF8.self)))
        #expect(text.contains(String(firstHexRow)))
        #expect(text.contains("Raw Pages"))
        #expect(text.contains("  4  7B 00 65 00  {.e."))
    }
}
