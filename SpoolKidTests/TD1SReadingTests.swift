//
//  TD1SReadingTests.swift
//  SpoolKidTests
//
//  Purpose: Reading a TD1S scan out of the MIDI bytes it sends. The fixtures
//  are the owner's four device captures (firmware 2.0.1, 2026-11-02), each
//  checked against the TD and hex the TD1S's own screen showed.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
@testable import SpoolKid

struct TD1SReadingTests {
    private static func sysEx(_ text: String) -> [UInt8] {
        [0xF0, 0x7D] + Array(text.utf8) + [0xF7]
    }

    @Test(arguments: [
        ("cdc:20168611985,,,,2.5,FFFFFF\n", 2.5, "FFFFFF"),
        ("cdc:24748603468,,,,0.1,272A29\n", 0.1, "272A29"),
        ("cdc:35773425321,,,,5.9,FF2612\n", 5.9, "FF2612"),
        ("cdc:41286131075,,,,0.1,3B4248\n", 0.1, "3B4248"),
    ])
    func ownerCapturesDecode(text: String, td: Double, hex: String) throws {
        let reading = try #require(TD1SReading.latest(in: Self.sysEx(text)))
        #expect(reading.transmissionDistance == td)
        #expect(reading.hex == hex)
    }

    /// Bytes keep arriving while the sheet is open; the newest complete scan wins.
    @Test func latestCompleteScanWins() {
        let bytes = Self.sysEx("cdc:1,,,,2.5,FFFFFF\n") + Self.sysEx("cdc:2,,,,5.9,FF2612\n")
            + [0xF0, 0x7D] + Array("cdc:3,,,,0.1".utf8)
        #expect(TD1SReading.latest(in: bytes)?.hex == "FF2612")
    }

    @Test func lowercaseHexIsUppercased() {
        #expect(TD1SReading.latest(in: Self.sysEx("cdc:1,,,,2.5,ff2612\n"))?.hex == "FF2612")
    }

    /// A colour with no usable TD still fills the colour.
    @Test func unusableTDLeavesOnlyColour() throws {
        let reading = try #require(TD1SReading.latest(in: Self.sysEx("cdc:1,,,,0.0,272A29\n")))
        #expect(reading.transmissionDistance == nil)
        #expect(reading.hex == "272A29")
    }

    @Test func otherSysExAndMalformedLinesAreIgnored() {
        #expect(TD1SReading.latest(in: [0xF0, 0x7E, 0x00, 0xF7]) == nil)
        #expect(TD1SReading.latest(in: Self.sysEx("cdc:1,,,,2.5,FFF\n")) == nil)
        #expect(TD1SReading.latest(in: Self.sysEx("hello")) == nil)
        #expect(TD1SReading.latest(in: []) == nil)
    }

    /// A color scan fills the TD box only while it is empty (owner, 2026-11-02).
    @Test func colorScanFillsAnEmptyTDBoxOnly() {
        let reading = TD1SReading(transmissionDistance: 5.9, hex: "FF2612")
        #expect(reading.transmissionDistanceText(replacing: "") == "5.9")
        #expect(reading.transmissionDistanceText(replacing: "  ") == "5.9")
        #expect(reading.transmissionDistanceText(replacing: "2.5") == nil)
        #expect(TD1SReading(transmissionDistance: nil, hex: "FF2612").transmissionDistanceText(replacing: "") == nil)
    }
}
