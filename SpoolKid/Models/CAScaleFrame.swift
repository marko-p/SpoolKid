//
//  CAScaleFrame.swift
//  SpoolKid
//
//  Purpose: Read grams out of the plain frames some kitchen scales notify on
//  FFF4 (a Futula Kitchen Scale 5, advertising as "Kitchen Scale3", issue #21).
//  Pure and synchronous, like `AiLinkScaleFrame`: the format was recovered
//  from one captured session and has to stay checkable against it.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// The 11-byte frame, verified on all 78 frames of the #21 capture:
///
///     CA | 00 | flag | lo | hi | 00 00 00 | unit | motion | xor
///
/// `lo`/`hi` are the weight in grams, little-endian and **unmasked**: the scale
/// zeroes itself with its own Tare button, so there is nothing to learn. It is
/// handed on as an `AiLinkScaleWeightFrame` whose mask is zero, which is what
/// `AiLinkScaleZero.selfZeroing` holds. `xor` is the XOR of the ten bytes
/// before it. `motion` is 00 once the display settles; like an AiLink scale, it
/// never calls an empty pan settled.
///
/// `unit` follows the display (04 in grams; 01, 05, 06 and 07 as the unit
/// button cycles), but the number sent does not change with it, so every unit
/// is read as grams (owner, 2026-10-22).
///
/// `flag` is set only on frames that have not settled, and what it means is
/// unknown: as a minus sign or as 256 g, the values it marks fit the frames
/// around them equally badly. Those frames are not read as weights.
///
/// An AccuWeight CK780BLE (issue #22, 2026-10-24) sends a 16-byte frame on the
/// same FFF4, verified against all four display photos of its capture:
///
///     CA | 00 00 | 01 | hi | lo | 00 × 10
///
/// Grams are big-endian and unmasked, with no checksum and no motion byte. The
/// scale notifies only when its display changes to a resting value (each one
/// twice, ~0.4 s apart), so every such frame is settled. Byte 3 was 01 on every
/// frame; any other value, or anything in the tail, is not read, because it may
/// be another display unit whose number is not grams.
nonisolated enum CAScaleFrame {

    static let start: UInt8 = 0xCA
    static let length = 11
    static let longLength = 16
    private static let settledMotion: UInt8 = 0x00
    private static let longGramsMarker: UInt8 = 0x01

    /// A weight frame, or nil for a truncated read, another protocol, a bad
    /// checksum or a frame whose flag byte is set — all "do not act on this".
    static func weightFrame(from data: Data) -> AiLinkScaleWeightFrame? {
        let bytes = [UInt8](data)
        if bytes.count == longLength { return longWeightFrame(bytes) }
        guard bytes.count == length, bytes[0] == start, bytes[2] == 0 else { return nil }
        guard bytes[0..<10].reduce(0, ^) == bytes[10] else { return nil }
        return AiLinkScaleWeightFrame(
            masked: UInt16(bytes[4]) << 8 | UInt16(bytes[3]),
            isSettled: bytes[9] == settledMotion,
            sequence: 0
        )
    }

    private static func longWeightFrame(_ bytes: [UInt8]) -> AiLinkScaleWeightFrame? {
        guard bytes[0] == start, bytes[1] == 0, bytes[2] == 0, bytes[3] == longGramsMarker,
              bytes[6...].allSatisfy({ $0 == 0 }) else { return nil }
        return AiLinkScaleWeightFrame(
            masked: UInt16(bytes[4]) << 8 | UInt16(bytes[5]),
            isSettled: true,
            sequence: 0
        )
    }
}
