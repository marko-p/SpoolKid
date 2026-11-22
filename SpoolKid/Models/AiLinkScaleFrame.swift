//
//  AiLinkScaleFrame.swift
//  SpoolKid
//
//  Purpose: Read grams out of an AiLink/Elink scale's notification frames.
//  Pure and synchronous: the whole protocol was recovered from captured bytes,
//  so it has to stay checkable against those bytes without a scale on the desk.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// A weight frame as it arrived: the masked value, and what the scale says
/// about it. The value is not a weight until a zero mask is known.
nonisolated struct AiLinkScaleWeightFrame: Equatable {
    let masked: UInt16
    let isSettled: Bool
    let sequence: UInt8
}

/// One weight notification from the scale.
nonisolated struct AiLinkScaleReading: Equatable {
    let grams: Int
    /// The scale has stopped moving and this is the number on its display.
    /// A weigh session should record only these.
    let isSettled: Bool
    /// The frame counter, kept because packet loss is normal on this link and
    /// two readings with the same counter are the same reading arriving twice.
    let sequence: UInt8
}

/// The frame format an AiLink module notifies on its FFE2 characteristic.
///
///     A7 | type(2) | len | payload(len) | sum | 7A
///
/// `sum` is the low byte of the sum of everything between the A7 and itself.
/// Verified on 343 frames across eight capture sessions (owner, 2026-09-08).
///
/// The weight frame carries `len == 9`:
///
///     EB | seq | unit | hi | lo | 6D EA 42 | motion
///
/// `hi`/`lo` are the weight in grams **XORed with a per-device mask**, which is
/// why four sessions of arithmetic on the raw bytes found no scale factor that
/// worked: there isn't one, the field is masked. The mask is a device constant,
/// not a session key — the same two bytes decode captures taken hours apart,
/// through two different apps, with and without the vendor handshake.
///
/// Recovering it needs no cryptography and no handshake: **an empty pan reads
/// zero, so whatever the scale sends with nothing on it IS the mask.** That is
/// what `zeroMask(from:)` is for, and it is why this works on any scale in the
/// family rather than only on the one that was captured.
nonisolated enum AiLinkScaleFrame {

    static let start: UInt8 = 0xA7
    static let end: UInt8 = 0x7A
    /// The only device type seen. Kept as a value rather than a check: a
    /// different model in the same family is not a reason to refuse a frame
    /// whose checksum is good.
    static let observedDeviceType: UInt16 = 0x006C
    /// The unit code the scale sends while its display is in grams. Any other
    /// code means the number is in some other unit, and reporting it as grams
    /// would be worse than reporting nothing.
    static let gramsUnit: UInt8 = 0x03
    static let weightPayloadLength = 9
    private static let settledMotion: UInt8 = 0x01

    /// The payload of a well-formed frame, or nil. Nil covers a truncated read,
    /// a frame that is not this protocol, and a frame whose checksum disagrees
    /// with its contents — all three are "do not act on this".
    static func payload(of data: Data) -> [UInt8]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 6, bytes[0] == start, bytes[bytes.count - 1] == end else { return nil }
        let length = Int(bytes[3])
        guard bytes.count == length + 6 else { return nil }
        let checked = bytes[1...(3 + length)]
        let sum = checked.reduce(0, { $0 + Int($1) }) & 0xFF
        guard sum == Int(bytes[4 + length]) else { return nil }
        return Array(bytes[4..<(4 + length)])
    }

    /// A weight frame's raw fields, before the mask is applied. Separated
    /// because two callers need the masked value itself: the decoder, and the
    /// zero-learning that has no mask yet.
    static func weightFrame(from data: Data) -> AiLinkScaleWeightFrame? {
        guard let payload = payload(of: data),
              payload.count == weightPayloadLength,
              payload[2] == gramsUnit
        else { return nil }
        return AiLinkScaleWeightFrame(
            masked: UInt16(payload[3]) << 8 | UInt16(payload[4]),
            isSettled: payload[8] == settledMotion,
            sequence: payload[1]
        )
    }

    /// The two masked weight bytes, whatever they currently mean. Read this
    /// with an empty pan and it is the device's mask; that is the whole
    /// calibration step.
    static func zeroMask(from data: Data) -> UInt16? {
        weightFrame(from: data)?.masked
    }

    /// The weight this frame reports, given the device's mask.
    ///
    /// Returns nil for anything that is not a grams weight frame — including a
    /// frame in another unit, which is refused rather than converted, because
    /// no capture has yet shown what the other unit codes are.
    static func reading(from data: Data, zeroMask: UInt16) -> AiLinkScaleReading? {
        guard let frame = weightFrame(from: data) else { return nil }
        return AiLinkScaleReading(
            grams: Int(frame.masked ^ zeroMask),
            isSettled: frame.isSettled,
            sequence: frame.sequence
        )
    }
}
