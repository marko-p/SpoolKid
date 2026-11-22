//
//  OpenPrintTagLayout.swift
//  SpoolKid
//
//  Purpose: Lays an OpenPrintTag record out the way Prusa's reference
//  initializer (`utils/nfc_initialize.py`) does: meta -> main -> zero padding
//  -> aux, the message filling the tag's capacity less the terminator byte.
//  The aux region holds the spool's consumed weight, and the main section
//  gains a filament length, so a Prusa printer can count the spool down.
//
//  Constraints, each with the printer behaviour that makes it one:
//  - A length is written only together with an aux region. The firmware
//    writes its countdown into aux and treats a tag without one as
//    unreachable (`bsod_unreachable()`), so a length alone crashes it.
//  - No region lies outside the payload, and main never runs into aux
//    (the reader rejects the tag).
//  - The message never exceeds the ceiling, and on a SLIX2 never reaches
//    block 79, the chip's counter, which cannot hold user data.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import CoreNFC

nonisolated enum OpenPrintTagLayout {

    /// The aux region is at least this long: the printer's own write (a
    /// consumed weight plus a workgroup of up to 8 characters) must fit.
    static let auxRegionSize = 32
    /// A SLIX2's NDEF message, whatever capacity CoreNFC reports (an older
    /// SpoolKid declared the counter block as user memory, which reports 312).
    static let slix2MessageCeiling = 303
    /// A Type 5 block and an NTAG page.
    static let blockSize = 4

    private static let mimeType = "application/vnd.openprinttag"
    /// Type 5 capability container, ahead of the NDEF TLV.
    private static let capabilityContainerSize = 4
    private static let auxRegionOffsetKey = 2    // meta-section key 2
    private static let nominalFullLengthKey = 53 // main-section key 53, mm

    struct Result: Equatable {
        /// The MIME record's payload, zero-padded to fill the message.
        let payload: Data
        /// Meta plus main CBOR bytes: the part that says something.
        let sectionsLength: Int
        /// Payload-relative start of the aux region; nil when there is none.
        let auxOffset: Int?
        /// Whether main carries `nominal_full_length`. Never true without aux.
        let writesLength: Bool
        /// The whole NDEF message, URI record and headers included.
        let messageLength: Int
    }

    /// The longest NDEF message to write: one byte short of the capacity,
    /// for the terminator, and on a SLIX2 never past its counter block.
    static func messageCeiling(capacity: Int, isSLIX2: Bool) -> Int {
        let ceiling = capacity - 1
        return isSLIX2 ? min(ceiling, slix2MessageCeiling) : ceiling
    }

    /// Filament length in mm for `netWeight` g of `density` g/cm3 at
    /// `diameter` mm. Nil unless all three are stated: no default density or
    /// diameter is ever assumed.
    static func fullLength(netWeight: Double?, density: Double?, diameter: Double?) -> Int? {
        guard let net = FilamentTagData.statedMeasurement(netWeight),
              let density = FilamentTagData.statedMeasurement(density),
              let diameter = FilamentTagData.statedMeasurement(diameter) else { return nil }
        let radius = diameter / 2
        let millimetres = (net / density * 1000 / (Double.pi * radius * radius)).rounded()
        guard millimetres >= 1, millimetres < 1e9 else { return nil }
        return Int(millimetres)
    }

    /// The aux map: empty (`A0`, as Prusa's initializer writes it), or the
    /// consumed weight as the firmware encodes it, an indefinite map
    /// `BF 00 FA <float32> FF`.
    static func auxSection(consumedWeight: Double?) -> Data {
        guard let grams = FilamentTagData.statedMeasurement(consumedWeight),
              Float(grams).isFinite else { return Data([0xA0]) }
        var out = Data([0xBF, 0x00, 0xFA])
        let pattern = Float(grams).bitPattern
        for shift in [24, 16, 8, 0] { out.append(UInt8((pattern >> UInt32(shift)) & 0xFF)) }
        out.append(0xFF)
        return out
    }

    /// Lays `data` out for a tag reporting `capacity`. Nil when the capacity
    /// is unknown (<= 0; the caller writes the unpadded `encode(from:)`) or
    /// too small for the material data.
    static func layout(for data: FilamentTagData, urlString: String?, capacity: Int, isSLIX2: Bool) -> Result? {
        guard capacity > 0 else { return nil }

        let ceiling = messageCeiling(capacity: capacity, isSLIX2: isSLIX2)
        let shortOverhead = headerOverhead(payloadSize: 1, urlString: urlString)
        let longOverhead = headerOverhead(payloadSize: 256, urlString: urlString)

        // The payload fills the ceiling. The record header grows from short to
        // long at 256 bytes, so at that boundary the message is a few bytes
        // under the ceiling rather than over it.
        var size = ceiling - shortOverhead
        if size > 255 {
            size = ceiling - longOverhead
            if size <= 255 { size = 255 }
        }
        guard size > 0 else { return nil }
        let overhead = size > 255 ? longOverhead : shortOverhead
        let message = size + overhead

        // Aux starts on a block boundary of the tag's memory, at least
        // `auxRegionSize` bytes before the payload's end.
        let tlvHeader = message > 254 ? 4 : 2
        let payloadStart = capabilityContainerSize + tlvHeader + overhead
        let auxStart = size - auxRegionSize
        let auxOffset = auxStart - ((payloadStart + auxStart) % blockSize)

        let length = fullLength(netWeight: data.nominalNetWeight, density: data.density, diameter: data.diameter)

        if auxOffset > 0 {
            var main = OpenPrintTagPayload.mainMap(from: data)
            if let length { main.append((nominalFullLengthKey, .uint(UInt64(length)))) }
            let meta = CBORWriter.encodeMap([(auxRegionOffsetKey, .uint(UInt64(auxOffset)))])
            let mainBytes = CBORWriter.encodeMap(main)
            let sections = meta.count + mainBytes.count
            if sections <= auxOffset {
                var payload = meta
                payload.append(mainBytes)
                payload.append(Data(count: auxOffset - sections))
                payload.append(auxSection(consumedWeight: data.consumedWeight))
                payload.append(Data(count: size - payload.count))
                return result(payload: payload, sectionsLength: sections, auxOffset: auxOffset,
                              writesLength: length != nil, urlString: urlString, ceiling: ceiling)
            }
        }

        // No room for aux: material data only, and no length.
        var payload = Data([0xA0])
        payload.append(CBORWriter.encodeMap(OpenPrintTagPayload.mainMap(from: data)))
        guard payload.count <= size else { return nil }
        let sections = payload.count
        payload.append(Data(count: size - sections))
        return result(payload: payload, sectionsLength: sections, auxOffset: nil,
                      writesLength: false, urlString: urlString, ceiling: ceiling)
    }

    // MARK: - Private

    /// Message bytes around a payload of `payloadSize`: the URI record and the
    /// MIME record's header, measured on the write's own assembly.
    private static func headerOverhead(payloadSize: Int, urlString: String?) -> Int {
        messageLength(payload: Data(count: payloadSize), urlString: urlString) - payloadSize
    }

    private static func messageLength(payload: Data, urlString: String?) -> Int {
        NFCNDEFMessage(records: NFCManager.ndefRecords(
            mimePayload: payload, mimeType: mimeType, urlString: urlString)).length
    }

    private static func result(payload: Data, sectionsLength: Int, auxOffset: Int?,
                               writesLength: Bool, urlString: String?, ceiling: Int) -> Result? {
        let length = messageLength(payload: payload, urlString: urlString)
        guard length <= ceiling else { return nil }
        return Result(payload: payload, sectionsLength: sectionsLength, auxOffset: auxOffset,
                      writesLength: writesLength, messageLength: length)
    }
}
