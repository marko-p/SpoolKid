//
//  BLECommand.swift
//  SpoolKid
//
//  Purpose: Turn what a tester types into bytes to send to a scale.
//
//  Sending exists because listening ran out. Four captures established that
//  this scale's notify stream does not carry the displayed weight — 1493 g and
//  2386 g produce readings two counts apart, while 0 g reproduces to the count
//  across four sessions (2026-09-08). The remaining
//  hypothesis is that the weight is answered on request, which cannot be tested
//  without a way to ask.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum BLECommand {

    /// Bytes from hex a person typed. Spaces, colons and dashes are ignored, so
    /// a frame copied out of a transcript pastes in unchanged.
    ///
    /// Returns nil rather than a partial result: half a command is not a
    /// command, and sending one to an unknown device is the one thing here
    /// worth being strict about.
    static func parse(_ text: String) -> Data? {
        let cleaned = text.filter { !" :-\n\t".contains($0) }
        guard !cleaned.isEmpty, cleaned.count % 2 == 0 else { return nil }
        var data = Data()
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    /// Wraps a payload the way this scale wraps its own frames: a header byte,
    /// the payload, a one-byte sum of the payload, and a trailer byte.
    ///
    /// Derived from the device's own traffic, not from a specification — both
    /// its streams are framed exactly this way and the checksum has held on
    /// every packet of every capture. It is offered as a convenience for
    /// building a plausible request; whether the scale ANSWERS one is the
    /// question being asked.
    static func framed(payload: Data, header: UInt8, trailer: UInt8) -> Data {
        var out = Data([header])
        out.append(payload)
        out.append(UInt8(payload.reduce(0) { $0 + Int($1) } % 256))
        out.append(trailer)
        return out
    }
}
