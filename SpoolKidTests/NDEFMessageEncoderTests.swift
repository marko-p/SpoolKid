//
//  NDEFMessageEncoderTests.swift
//  SpoolKidTests
//
//  Spec 3 sends a tag's NDEF message to Spoolman as `payload_b64`. CoreNFC
//  offers no serializer, so the record layout is the NFC Forum one, checked
//  byte for byte here.
//

import Foundation
import Testing
@testable import SpoolKid

struct NDEFMessageEncoderTests {
    private func record(tnf: UInt8, type: [UInt8], id: [UInt8] = [], payload: [UInt8]) -> NDEFRecordSnapshot {
        NDEFRecordSnapshot(typeNameFormat: tnf, type: Data(type), identifier: Data(id), payload: Data(payload))
    }

    /// One short well-known record: MB, ME and SR set, TNF 1.
    @Test func oneShortRecord() {
        let bytes = NDEFMessageEncoder.encode([record(tnf: 0x01, type: [0x54], payload: [0x02, 0x65, 0x6E, 0x48, 0x69])])
        #expect(bytes == [0xD1, 0x01, 0x05, 0x54, 0x02, 0x65, 0x6E, 0x48, 0x69])
    }

    /// MB on the first record only, ME on the last only.
    @Test func twoRecordsSetBeginAndEndOnce() {
        let bytes = NDEFMessageEncoder.encode([
            record(tnf: 0x02, type: [0x61, 0x2F, 0x62], payload: [0x01]),
            record(tnf: 0x01, type: [0x55], payload: [0x04, 0x61]),
        ])
        #expect(bytes == [0x92, 0x03, 0x01, 0x61, 0x2F, 0x62, 0x01, 0x51, 0x01, 0x02, 0x55, 0x04, 0x61])
    }

    /// A payload over 255 bytes drops SR and takes a 4-byte length.
    @Test func aLongPayloadUsesAFourByteLength() {
        let payload = [UInt8](repeating: 0xAB, count: 300)
        let bytes = NDEFMessageEncoder.encode([record(tnf: 0x02, type: [0x78], payload: payload)])
        #expect(Array(bytes.prefix(7)) == [0xC2, 0x01, 0x00, 0x00, 0x01, 0x2C, 0x78])
        #expect(bytes.count == 307)
    }

    /// IL set, the ID length after the payload length, the ID after the type.
    @Test func aRecordWithAnID() {
        let bytes = NDEFMessageEncoder.encode([record(tnf: 0x01, type: [0x54], id: [0x41], payload: [0x00])])
        #expect(bytes == [0xD9, 0x01, 0x01, 0x01, 0x54, 0x41, 0x00])
    }

    @Test func noRecordsIsNoBytes() {
        #expect(NDEFMessageEncoder.encode([]).isEmpty)
    }
}
