//
//  OpenPrintTagFirmwareRulesTests.swift
//  SpoolKidTests
//
//  Every layout `OpenPrintTagLayout` produces is one the Prusa Core One L's
//  firmware accepts. The region rules below are Prusa-Firmware-Buddy
//  `1ce23f33`'s `OPTReader` (src/module/nfc/openprinttag/openprinttag/
//  opt_reader.cpp); the tracking precondition is its filament usage tracker.
//  `referenceImageIsPinned` fixes the bytes that Prusa's own reference parser
//  (OpenPrintTag/openprinttag-specification, utils/rec_info.py --opt-check)
//  accepted when it was run on them.
//

import CoreNFC
import Foundation
import Testing
@testable import SpoolKid

struct OpenPrintTagFirmwareRulesTests {

    private static let mime = "application/vnd.openprinttag"

    // MARK: - OPTReader's region rules

    private nonisolated struct Rejected: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// What the reader works out from a payload. Throws where the firmware
    /// calls the tag invalid.
    private struct Regions {
        let meta: Range<Int>
        let main: Range<Int>
        /// Where main's CBOR actually ends, which may be short of its region.
        let mainCBOREnd: Int
        let mainFields: [Int: CBORReader.Value]
        let aux: Range<Int>?
    }

    private static func regions(of payload: Data) throws -> Regions {
        var reader = CBORReader(payload)
        guard let metaMap = reader.readMap() else { throw Rejected("meta is not a map") }
        let metaEnd = reader.offset

        func offset(_ key: Int) throws -> Int? {
            guard let value = metaMap[key] else { return nil }
            guard let n = value.intValue, n >= 0 else { throw Rejected("meta key \(key) is not an offset") }
            return n
        }
        let mainStart = try offset(0) ?? metaEnd
        let auxStart = try offset(2)
        let auxSize = try offset(3)
        if auxSize != nil && auxStart == nil { throw Rejected("aux size without an aux offset") }

        func region(_ name: String, _ start: Int, _ end: Int) throws -> Range<Int> {
            guard start >= 0, start <= end, end <= payload.count else {
                throw Rejected("\(name) region \(start)..<\(end) lies outside the \(payload.count)-byte payload")
            }
            return start..<end
        }

        // An unset main size runs to the aux offset if aux is after main,
        // else to the payload end.
        let mainSize: Int
        if let size = try offset(1) {
            mainSize = size
        } else if let auxStart, auxStart > mainStart {
            mainSize = auxStart - mainStart
        } else {
            mainSize = payload.count - mainStart
        }
        let main = try region("main", mainStart, mainStart + mainSize)

        var aux: Range<Int>?
        if let auxStart {
            // An unset aux size runs to the next region or the payload end.
            let next = mainStart > auxStart ? mainStart : payload.count
            aux = try region("aux", auxStart, auxStart + (auxSize ?? (next - auxStart)))
        }
        let meta = try region("meta", 0, metaEnd)

        guard mainStart < payload.count else { throw Rejected("main starts outside the payload") }
        var mainReader = CBORReader(payload, start: mainStart)
        guard let fields = mainReader.readMap() else { throw Rejected("main is not a map") }
        return Regions(meta: meta, main: main, mainCBOREnd: mainReader.offset, mainFields: fields, aux: aux)
    }

    // MARK: - The tag as the printer's reader sees it

    /// The MIME record of `message`, found wherever it sits behind a URI
    /// record, and whether its header marks it chunked (CF), which the
    /// reader rejects.
    private static func openPrintTagRecord(in message: [UInt8]) -> (payload: Data, chunked: Bool)? {
        var index = 0
        while index + 2 <= message.count {
            let header = message[index]
            let typeLength = Int(message[index + 1])
            var cursor = index + 2
            let payloadLength: Int
            if header & 0x10 != 0 {
                guard cursor < message.count else { return nil }
                payloadLength = Int(message[cursor])
                cursor += 1
            } else {
                guard cursor + 4 <= message.count else { return nil }
                payloadLength = message[cursor..<cursor + 4].reduce(0) { $0 << 8 | Int($1) }
                cursor += 4
            }
            var idLength = 0
            if header & 0x08 != 0 {
                guard cursor < message.count else { return nil }
                idLength = Int(message[cursor])
                cursor += 1
            }
            guard cursor + typeLength + idLength + payloadLength <= message.count else { return nil }
            let type = Array(message[cursor..<cursor + typeLength])
            cursor += typeLength + idLength
            if header & 0x07 == 0x02, type == Array(mime.utf8) {
                return (Data(message[cursor..<cursor + payloadLength]), header & 0x20 != 0)
            }
            index = cursor + payloadLength
        }
        return nil
    }

    private static func message(for payload: Data, url: String?) -> [UInt8] {
        let records = NFCManager.ndefRecords(mimePayload: payload, mimeType: mime, urlString: url)
        return NDEFMessageEncoder.encode(records.map(NDEFRecordSnapshot.init(record:)))
    }

    /// NDEF TLV length field: one byte, or `FF` and two.
    private static func tlvHeader(forMessageLength length: Int) -> [UInt8] {
        length > 254 ? [0x03, 0xFF, UInt8(length >> 8), UInt8(length & 0xFF)] : [0x03, UInt8(length)]
    }

    // MARK: - The sweep

    @Test func everyLayoutIsOneThePrinterAccepts() throws {
        var accepted = 0
        var sawAux = false
        var sawNoAux = false

        for capacity in [106, 136, 200, 254, 255, 256, 260, 304, 312, 492] {
            for url in [OpenPrintTagLayoutTests.url, nil] {
                for density in [1.24, nil] {
                    for slix2 in [true, false] {
                        let label = "capacity \(capacity), url \(url != nil), density \(density.map { "\($0)" } ?? "nil"), slix2 \(slix2)"
                        guard let result = OpenPrintTagLayoutTests.prusa(url: url, capacity: capacity, slix2: slix2, density: density) else { continue }
                        accepted += 1

                        // Every region is inside the payload, as the reader derives them.
                        let regions: Regions
                        do { regions = try Self.regions(of: result.payload) } catch {
                            Issue.record("the reader rejects \(label): \(error)")
                            continue
                        }
                        #expect(regions.meta.upperBound <= regions.main.lowerBound, "\(label)")
                        #expect(regions.main.upperBound <= result.payload.count, "\(label)")

                        // Main's CBOR ends within its region and at or before aux.
                        #expect(regions.mainCBOREnd <= regions.main.upperBound, "\(label)")
                        if let aux = regions.aux {
                            sawAux = true
                            #expect(regions.mainCBOREnd <= aux.lowerBound, "\(label)")
                            #expect(aux.lowerBound == result.auxOffset, "\(label)")
                            #expect(aux.upperBound == result.payload.count, "\(label)")
                            // The printer's own write: a consumed weight and a workgroup.
                            #expect(aux.count >= 32, "\(label)")
                        } else {
                            sawNoAux = true
                            #expect(result.auxOffset == nil, "\(label)")
                        }

                        // A length goes with an aux region: the firmware's write
                        // into a tag without one is `bsod_unreachable()`.
                        let carriesLength = regions.mainFields[53] != nil
                        #expect(carriesLength == result.writesLength, "\(label)")
                        if result.writesLength { #expect(result.auxOffset != nil, "\(label)") }
                        if carriesLength { #expect(regions.aux != nil, "\(label)") }

                        // The record the reader looks for is there, whole, and the
                        // length the layout reports is the real message's.
                        let message = Self.message(for: result.payload, url: url)
                        #expect(message.count == result.messageLength, "\(label)")
                        let record = Self.openPrintTagRecord(in: message)
                        #expect(record?.payload == result.payload, "\(label)")
                        #expect(record?.chunked == false, "\(label)")

                        // A SLIX2 never has its counter block (79, bytes 316...) written:
                        // CC, TLV header, message and the terminator end by byte 312.
                        if slix2 {
                            let tlv = Self.tlvHeader(forMessageLength: result.messageLength).count
                            #expect(4 + tlv + result.messageLength + 1 <= 316, "\(label)")
                        }
                    }
                }
            }
        }

        // The sweep reaches both kinds of tag; a rule that no case exercises proves nothing.
        #expect(accepted > 0)
        #expect(sawAux)
        #expect(sawNoAux)
    }

    // MARK: - Prusa's reference parser

    /// The image `matchesThePrusamentLayout` describes, as it sits on a
    /// 312-byte SLIX2: CC `E1 40 27 01`, the long TLV, the message, `FE`.
    /// `rec_info.py --show-all --opt-check` accepted these bytes: regions meta,
    /// main and aux, `consumed_weight` 388 in aux, no errors (nfc-formats.md,
    /// "Write layout").
    private static let referenceImageHex = """
    E140270103FF012F910117550433647461672E6F72672F732F34636533643337
    663162521CF56170706C69636174696F6E2F766E642E6F70656E7072696E7474
    6167A10218D2AD080009000A70504C412047616C61787920426C61636B0B6950
    727573616D656E7413433D3E3D182218CD182318E1182518281826183C101903
    E8181DFA3F9EB852181EFA3FE0000018351A00051DB400000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000BF00FA43C20000FF00000000
    0000000000000000000000000000000000000000000000FE
    """

    @Test func referenceImageIsPinned() throws {
        let result = try #require(OpenPrintTagLayoutTests.prusa())
        let message = Self.message(for: result.payload, url: OpenPrintTagLayoutTests.url)
        #expect(message.count == 303)

        let capabilityContainer: [UInt8] = [0xE1, 0x40, 0x27, 0x01]
        let image = capabilityContainer + Self.tlvHeader(forMessageLength: message.count) + message + [0xFE]
        #expect(image.count == 312)

        let hex = image.map { String(format: "%02X", $0) }.joined()
        let pinned = Self.referenceImageHex.filter { !$0.isWhitespace }
        #expect(hex == pinned, "The layout's bytes changed. Prusa's rec_info.py --opt-check accepted the pinned ones: run it on the new image and update the hex. Actual: \(hex)")
    }
}
