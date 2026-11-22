//
//  MIDICapture.swift
//  SpoolKid
//
//  Purpose: A recording of what a USB MIDI device — the Biqu TD1S, firmware
//  2.0.1+ — sent while plugged into the iPhone, with what its own screen
//  showed, so its unpublished scan format can be decoded offline. Plus the
//  Universal MIDI Packet → MIDI 1.0 conversion the recording is read through.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct MIDICapture: Codable, Equatable, Sendable {
    struct Source: Codable, Equatable, Sendable, Identifiable {
        let name: String
        let manufacturer: String?
        let model: String?
        let uniqueID: Int32
        var id: Int32 { uniqueID }
    }

    /// One CoreMIDI event packet. `words` are the raw Universal MIDI Packet
    /// words exactly as received; `midi1Hex` is the same message as MIDI 1.0
    /// bytes, which is how the firmware author describes the output.
    struct Packet: Codable, Equatable, Sendable {
        /// Milliseconds since recording started.
        let offsetMs: Int
        let source: String
        let words: [UInt32]
        let wordsHex: String
        let midi1Hex: String

        init(offsetMs: Int, source: String, words: [UInt32]) {
            self.offsetMs = offsetMs
            self.source = source
            self.words = words
            self.wordsHex = words.map { String(format: "%08X", $0) }.joined(separator: " ")
            self.midi1Hex = UMPDecoder.hex(UMPDecoder.midi1Bytes(fromWords: words))
        }
    }

    let capturedAt: Date
    let sources: [Source]
    let packets: [Packet]
    /// What the tester says the filament is.
    var note: String
    /// What the TD1S's own screen showed for this scan — the answer the bytes
    /// are decoded against.
    var displayedTD: String
    var displayedHex: String

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Universal MIDI Packet (UMP) words → MIDI 1.0 bytes. CoreMIDI's current
/// input API delivers UMP only; MIDI 1.0 traffic arrives as message types 1
/// (system), 2 (channel voice) and 3 (7-bit SysEx, six bytes per packet).
nonisolated enum UMPDecoder {
    static func midi1Bytes(fromWords words: [UInt32]) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            let type = word >> 28
            let size = wordCount(ofType: type)
            defer { index += size }
            switch type {
            case 0x1:
                let status = UInt8((word >> 16) & 0xFF)
                bytes.append(status)
                let dataCount = switch status {
                case 0xF1, 0xF3: 1
                case 0xF2: 2
                default: 0
                }
                bytes.append(contentsOf: [UInt8((word >> 8) & 0xFF), UInt8(word & 0xFF)].prefix(dataCount))
            case 0x2:
                let status = UInt8((word >> 16) & 0xFF)
                let dataCount = (status & 0xF0 == 0xC0 || status & 0xF0 == 0xD0) ? 1 : 2
                bytes.append(status)
                bytes.append(contentsOf: [UInt8((word >> 8) & 0xFF), UInt8(word & 0xFF)].prefix(dataCount))
            case 0x3 where index + 1 < words.count:
                let second = words[index + 1]
                let form = (word >> 20) & 0xF
                let count = min(Int((word >> 16) & 0xF), 6)
                let payload: [UInt8] = [
                    UInt8((word >> 8) & 0xFF), UInt8(word & 0xFF),
                    UInt8(second >> 24), UInt8((second >> 16) & 0xFF),
                    UInt8((second >> 8) & 0xFF), UInt8(second & 0xFF),
                ]
                // 0 complete, 1 start, 2 continue, 3 end.
                if form == 0 || form == 1 { bytes.append(0xF0) }
                bytes.append(contentsOf: payload.prefix(count))
                if form == 0 || form == 3 { bytes.append(0xF7) }
            default:
                break
            }
        }
        return bytes
    }

    /// UMP message sizes by type (UMP spec, table 4).
    private static func wordCount(ofType type: UInt32) -> Int {
        switch type {
        case 0x0, 0x1, 0x2, 0x6, 0x7: 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: 2
        case 0xB, 0xC: 3
        default: 4
        }
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

nonisolated enum MIDICaptureArchiveBuilder {
    @discardableResult
    static func build(_ capture: MIDICapture, at now: Date = Date()) throws -> URL {
        let kind = DiagnosticCaptureKind.td1sCapture
        let workDir = try DiagnosticBundle.makeWorkDirectory(kind: kind.rawValue, at: now)
        try MIDICapture.encoder.encode(capture).write(to: workDir.appendingPathComponent(kind.manifestFilename))
        return try DiagnosticCaptureStore.keep(workDir)
    }
}
