//
//  MIDICaptureTests.swift
//  SpoolKidTests
//
//  Purpose: The pure half of the TD1S capture: CoreMIDI hands over Universal
//  MIDI Packet words, and a capture also records them as the MIDI 1.0 bytes a
//  decoder (or a person) reads. Plus the capture's round trip through its
//  archive and the Diagnostics list.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
import Foundation
@testable import SpoolKid

struct UMPDecoderTests {
    @Test func channelVoiceNoteOn() {
        #expect(UMPDecoder.midi1Bytes(fromWords: [0x2090_3C64]) == [0x90, 0x3C, 0x64])
    }

    @Test func programChangeHasOneDataByte() {
        #expect(UMPDecoder.midi1Bytes(fromWords: [0x20C0_0500]) == [0xC0, 0x05])
    }

    @Test func realtimeClockHasNoData() {
        #expect(UMPDecoder.midi1Bytes(fromWords: [0x10F8_0000]) == [0xF8])
    }

    @Test func completeSysExInOnePacket() {
        #expect(UMPDecoder.midi1Bytes(fromWords: [0x3003_7D01, 0x0200_0000]) == [0xF0, 0x7D, 0x01, 0x02, 0xF7])
    }

    @Test func sysExSplitAcrossStartContinueEnd() {
        let words: [UInt32] = [
            0x3016_0102, 0x0304_0506,   // start, 6 bytes
            0x3026_0708, 0x090A_0B0C,   // continue, 6 bytes
            0x3031_0D00, 0x0000_0000,   // end, 1 byte
        ]
        #expect(UMPDecoder.midi1Bytes(fromWords: words)
                == [0xF0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 0xF7])
    }

    /// A 128-bit message type is skipped whole, never misread as four 32-bit ones.
    @Test func unknownWideMessagesAreSkippedWhole() {
        #expect(UMPDecoder.midi1Bytes(fromWords: [0x5000_0000, 0x2090_3C64, 0, 0, 0x2080_3C00])
                == [0x80, 0x3C, 0x00])
    }

    @Test func hexIsSpacedUppercasePairs() {
        #expect(UMPDecoder.hex([0xF0, 0x7D, 0x0A]) == "F0 7D 0A")
    }
}

/// An extension of `DiagnosticCaptureStoreTests` so it shares that suite's
/// serialization: those tests clear the whole capture folder.
extension DiagnosticCaptureStoreTests {
    @Test func keptCaptureIsListedWithItsNote() throws {
        let capture = MIDICapture(
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            sources: [.init(name: "TD1S", manufacturer: "AJAX", model: "TD1S", uniqueID: 42)],
            packets: [.init(offsetMs: 12, source: "TD1S", words: [0x3003_7D01, 0x0200_0000])],
            note: "Bambu PLA Basic white",
            displayedTD: "4.2",
            displayedHex: "F5F5F5"
        )
        let directory = try MIDICaptureArchiveBuilder.build(capture)
        defer { try? FileManager.default.removeItem(at: directory) }

        let listed = try #require(DiagnosticCaptureStore.list(kind: .td1sCapture).first { $0.directory == directory })
        #expect(listed.summary == "Bambu PLA Basic white")

        let saved = try MIDICapture.decoder.decode(
            MIDICapture.self,
            from: Data(contentsOf: directory.appendingPathComponent(DiagnosticCaptureKind.td1sCapture.manifestFilename))
        )
        #expect(saved.packets.first?.midi1Hex == "F0 7D 01 02 F7")
        #expect(saved.displayedTD == "4.2")
    }

    @Test func unannotatedCaptureIsSummarisedByWhatItHolds() {
        #expect(DiagnosticCaptureStore.describeTD1SCapture(note: " ", td: "", hex: "", packets: 3)
                == "3 packets")
        #expect(DiagnosticCaptureStore.describeTD1SCapture(note: "", td: "4.2", hex: "F5F5F5", packets: 1)
                == "TD 4.2 · F5F5F5 · 1 packet")
    }
}
