//
//  TD1SReading.swift
//  SpoolKid
//
//  Purpose: One Biqu TD1S scan, read out of the MIDI bytes the device sends
//  over USB (firmware 2.0.1+). Each scan is one SysEx message, F0 7D … F7,
//  whose body is the same CSV line the TD1S prints on its serial port with a
//  "cdc:" prefix: field 4 is the TD (mm), field 5 the hex color. Decoded from
//  the owner's device captures, 2026-11-02.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct TD1SReading: Equatable, Sendable {
    /// Nil when the TD1S sent none SpoolKid can store (see `TransmissionDistance`).
    let transmissionDistance: Double?
    /// Six uppercase hex digits, no "#", as the color fields hold it.
    let hex: String

    /// The newest complete scan in `bytes`, or nil when there is none yet.
    static func latest(in bytes: [UInt8]) -> TD1SReading? {
        guard let end = bytes.lastIndex(of: 0xF7) else { return nil }
        // A later scan that has not finished arriving is ignored; an earlier
        // complete one is not a fallback either — what the screen shows is
        // the newest scan or nothing.
        guard let start = bytes[..<end].lastIndex(of: 0xF0),
              bytes.index(after: start) < end, bytes[bytes.index(after: start)] == 0x7D,
              let text = String(bytes: bytes[(start + 2)..<end], encoding: .ascii)
        else { return nil }
        return parse(line: text)
    }

    /// What a color scan writes into the TD box holding `current`: the scan's
    /// TD, rounded as the form enters it, but only into an empty box — a TD
    /// already there is never overwritten by a color reading. Nil = leave it.
    func transmissionDistanceText(replacing current: String) -> String? {
        guard current.trimmingCharacters(in: .whitespaces).isEmpty,
              let transmissionDistance else { return nil }
        return String(TransmissionDistance.rounded(transmissionDistance))
    }

    private static func parse(line: String) -> TD1SReading? {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("cdc:") { text.removeFirst(4) }
        let fields = text.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count >= 6 else { return nil }
        let hex = fields[5].trimmingCharacters(in: .whitespaces).uppercased()
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
        return TD1SReading(transmissionDistance: TransmissionDistance.decode(String(fields[4])), hex: hex)
    }
}
