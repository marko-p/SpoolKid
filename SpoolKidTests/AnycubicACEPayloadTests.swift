//
//  AnycubicACEPayloadTests.swift
//  SpoolKidTests
//
//  The first tests the ACE codec has had. The fixture is a factory Anycubic
//  PLA tag dumped by a tester with ACE hardware (issue #5, 2026-09-12) — the
//  only ground truth SpoolKid has for this format, which is otherwise
//  reverse-engineered from a third-party spec.
//

import Testing
import Foundation
@testable import SpoolKid

struct AnycubicACEPayloadTests {

    // MARK: - A factory tag

    @Test func decodesEveryFieldOfAFactoryTag() throws {
        let decoded = try #require(AnycubicACEPayload.decode(from: factoryTagPages()))

        #expect(decoded.name == "AHPLVO-107")
        #expect(decoded.brand == "AC")
        #expect(decoded.material == "PLA")
        #expect(decoded.colorHex == "FF7F32")
        #expect(decoded.minNozzleTemp == 190)
        #expect(decoded.maxNozzleTemp == 230)
        #expect(decoded.minBedTemp == 55)
        #expect(decoded.maxBedTemp == 65)
        #expect(decoded.spoolmanId == nil)
    }

    /// Page 30 opens `AF 00` on the factory tag: 175, so the diameter is in
    /// hundredths of a millimetre. SpoolKid used to write tenths (17).
    @Test func readsTheDiameterInHundredthsOfAMillimetre() throws {
        let decoded = try #require(AnycubicACEPayload.decode(from: factoryTagPages()))
        #expect(decoded.diameter == 1.75)
    }

    /// Page 31 is `E8 03 00 00` on the factory tag: 1000 g.
    @Test func readsTheNetWeightFromPage31() throws {
        let decoded = try #require(AnycubicACEPayload.decode(from: factoryTagPages()))
        #expect(decoded.nominalNetWeight == 1000)
    }

    @Test func refusesATagWithoutTheMagicByte() {
        var pages = factoryTagPages()
        pages[16] = 0x00
        #expect(AnycubicACEPayload.decode(from: pages) == nil)
    }

    // MARK: - What SpoolKid writes

    /// Page 4 is `7B 00 65 00` on the factory tag. An ACE Pro saw a tag
    /// written with `7B 00 00 00` as a spool with no RFID data, and read it
    /// once byte 2 alone was changed to `65` (issue #16).
    @Test func writesTheHeaderTheWayTheFactoryTagCarriesIt() {
        #expect(encodedPage(4, from: sample) == Array(factoryTagPages()[16..<20]))
    }

    @Test func writesTheDiameterTheWayTheFactoryTagCarriesIt() {
        #expect(encodedPage(30, from: sample) == [0xAF, 0x00, 0x4A, 0x01])
    }

    @Test func writesTheDefaultDiameterWhenNoneIsStated() {
        var data = sample
        data.diameter = nil
        #expect(encodedPage(30, from: data) == [0xAF, 0x00, 0x4A, 0x01])
    }

    @Test func writesTheNetWeightTheWayTheFactoryTagCarriesIt() {
        #expect(encodedPage(31, from: sample) == [0xE8, 0x03, 0x00, 0x00])
    }

    /// An unknown weight is written as zero rather than a guessed 1000 g, and
    /// written at all so a rewrite does not leave the previous spool's weight
    /// behind on the tag.
    @Test(arguments: [nil, 0.0] as [Double?])
    func clearsPage31WhenTheWeightIsUnknown(_ weight: Double?) {
        var data = sample
        data.nominalNetWeight = weight
        #expect(encodedPage(31, from: data) == [0x00, 0x00, 0x00, 0x00])
    }

    @Test func roundTripsEveryFieldItWrites() throws {
        let decoded = try #require(AnycubicACEPayload.decode(from: pagesWritten(from: sample)))

        #expect(decoded.name == "White PETG Basic")
        #expect(decoded.brand == "Polar Filament")
        #expect(decoded.material == "PETG")
        #expect(decoded.colorHex == "1A2B3C")
        #expect(decoded.minNozzleTemp == 250)
        #expect(decoded.maxNozzleTemp == 260)
        #expect(decoded.minBedTemp == 70)
        #expect(decoded.maxBedTemp == 75)
        #expect(decoded.diameter == 1.75)
        #expect(decoded.nominalNetWeight == 1000)
    }

    /// "White PETG Basic" fills pages 5-8 of the SKU. The ACE's own reader
    /// accepted exactly this tag (issue #5), so SpoolKid must read it back
    /// whole rather than refuse or truncate it.
    @Test func aSixteenCharacterSKUNeedsNoTerminator() {
        #expect(Array("White PETG Basic".utf8).count == 16)
        #expect(Array(encodedPage(8, from: sample) ?? []) == Array("asic".utf8))
    }

    /// The SKU is five pages, 5–9, as the reference writer lays it out. A
    /// 17-character ReSpool SKU puts its last character on page 9 (issue #23).
    @Test func readsASKUThatRunsOntoPage9() throws {
        var bytes = pagesWritten(from: sample)
        let sku = Array("AHPLCG-103-A1B2C3".utf8)
        bytes.replaceSubrange(20..<40, with: sku + [UInt8](repeating: 0, count: 20 - sku.count))
        let decoded = try #require(AnycubicACEPayload.decode(from: bytes))
        #expect(decoded.name == "AHPLCG-103-A1B2C3")
    }

    @Test func writesASeventeenCharacterSKUWhole() throws {
        var data = sample
        data.name = "AHPLCG-103-A1B2C3"
        #expect(encodedPage(9, from: data) == Array("3".utf8) + [0, 0, 0])
        let decoded = try #require(AnycubicACEPayload.decode(from: pagesWritten(from: data)))
        #expect(decoded.name == "AHPLCG-103-A1B2C3")
    }

    @Test func aTwentyCharacterSKUFillsPage9AndNeedsNoTerminator() throws {
        var data = sample
        data.name = "ABCDEFGHIJKLMNOPQRST"
        #expect(encodedPage(9, from: data) == Array("QRST".utf8))
        let decoded = try #require(AnycubicACEPayload.decode(from: pagesWritten(from: data)))
        #expect(decoded.name == "ABCDEFGHIJKLMNOPQRST")
    }

    // MARK: - Fixtures

    private let sample = FilamentTagData(
        name: "White PETG Basic",
        material: "PETG",
        subtype: nil,
        brand: "Polar Filament",
        colorHex: "1A2B3C",
        minNozzleTemp: 250,
        maxNozzleTemp: 260,
        minBedTemp: 70,
        maxBedTemp: 75,
        diameter: 1.75,
        nominalNetWeight: 1000
    )

    private func encodedPage(_ page: Int, from data: FilamentTagData) -> [UInt8]? {
        AnycubicACEPayload.encodePages(from: data).first { $0.page == page }.map { Array($0.data) }
    }

    /// A blank NTAG213 with SpoolKid's pages written over it.
    private func pagesWritten(from data: FilamentTagData) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 45 * AnycubicACEPayload.bytesPerPage)
        for page in AnycubicACEPayload.encodePages(from: data) {
            let offset = page.page * AnycubicACEPayload.bytesPerPage
            bytes.replaceSubrange(offset..<(offset + 4), with: page.data)
        }
        return bytes
    }
}

/// Factory Anycubic PLA, orange, UID 53440707740001 — all 45 pages, captured
/// 2026-09-12 after one print. Byte-identical to the unused capture across
/// every user page: the ACE writes nothing back.
private let factoryTagHex = "534407980774000172480000E11012007B0065004148504C564F2D313037000000000000000000004143000000000000000000000000000000000000504C410000000000000000000000000000000000FF327FFF00000000000000003200C800BE00E6000000000000000000000000000000000037004100AF004A01E80300000000000000000000000000000000000000000000000000000000000000000000000000BD04000004470000000000000000000000"

private func factoryTagPages() -> [UInt8] {
    var bytes: [UInt8] = []
    var index = factoryTagHex.startIndex
    while index < factoryTagHex.endIndex {
        let next = factoryTagHex.index(index, offsetBy: 2)
        bytes.append(UInt8(factoryTagHex[index..<next], radix: 16) ?? 0)
        index = next
    }
    return bytes
}
