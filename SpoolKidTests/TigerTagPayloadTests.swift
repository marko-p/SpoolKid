//
//  TigerTagPayloadTests.swift
//  SpoolKidTests
//
//  Fixtures are the TigerTag-SDK-Python repository's own 80-byte vectors —
//  the closest thing to ground truth without hardware. The rosa3d vector is
//  the golden one: decode → re-encode with the tag's own timestamp must
//  reproduce its bytes exactly (pinned in the encode tests).
//

import Testing
import Foundation
@testable import SpoolKid

struct TigerTagPayloadTests {

    // Fixtures are single-line hex — Array(hex:) joins across whitespace,
    // and Swift multiline strings have no line continuation to lean on.

    /// tigertag_pla_rosa3d — the golden vector (see plan header).
    static let rosa3d: [UInt8] = Array(hex: "5bf59264ffffffff954b68008e384df9ff0000ff0003e81500c300e63205323c2d94cc80000000000000000000e60000537461727465722052656400000000000000000000000000000000000003e800")

    static let plusBambu: [UInt8] = Array(hex: "bc0fcb9700001234957068008e388933ffffffff0003e81500e601044108465a2e933e0000000000000000000000000042616d627520504554472048462057686974650000000000000000000003e800")

    static let lowStock: [UInt8] = Array(hex: "5bf59264ffffffff954bf7008e38bb3a22aa44ff0003e81500c800e63204323c2ced5e00000000000000000000a500006553756e20504c412b20477265656e0000000000000000000000000000009600")

    static let resinGeneric: [UInt8] = Array(hex: "5bf59264ffffffff20ca0000ad00ffffccccffcc0001f43000000000000019232d3732000000000000000000000000004361737461626c6520526573696e203530306d6c00000000000000000001f400")

    static let bicolor: [UInt8] = Array(hex: "5bf59264ffffffff954b68fc8e38c5acff8000ff0003e81500be00dc2d06193c2e666b001a1a1a000000000000c30000506f6c795477696e204f72616e67652d426c61636b000000000000000003e800")

    static let initTag: [UInt8] = Array(hex: "6c41a2e100000000000000000000000000000000000000150000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")

    // MARK: - Encode fixtures (shared with the encode extension below)

    private let sampleData = FilamentTagData(
        name: "Bench", material: "PLA", brand: "eSun", colorHex: "FF0000",
        minNozzleTemp: 200, maxNozzleTemp: 220, minBedTemp: 50, maxBedTemp: 60
    )
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Variant detection

    @Test func detectsAllThreeVariants() {
        #expect(TigerTagPayload.variant(of: Self.rosa3d) == .tigerTag)
        #expect(TigerTagPayload.variant(of: Self.plusBambu) == .plus(productID: 0x1234))
        #expect(TigerTagPayload.variant(of: Self.initTag) == .initTag)
    }

    @Test func refusesNonTigerTagBytes() {
        #expect(TigerTagPayload.variant(of: []) == nil)
        #expect(TigerTagPayload.variant(of: [0x7B, 0, 0, 0]) == nil) // ACE magic
    }

    // MARK: - Decode: golden vector

    @Test func decodesEveryFieldOfTheGoldenVector() throws {
        let decoded = try #require(TigerTagPayload.decode(from: Self.rosa3d))
        #expect(decoded.material == "PLA")
        #expect(decoded.brand == "Rosa3D")
        #expect(decoded.subtype == "Basic")
        #expect(decoded.colorHex == "FF0000")
        #expect(decoded.minNozzleTemp == 195)
        #expect(decoded.maxNozzleTemp == 230)
        #expect(decoded.minBedTemp == 50)
        #expect(decoded.maxBedTemp == 60)
        #expect(decoded.dryingTemp == 50)
        // The tag says 5 HOURS (guide v2.1: "Dry Time … Drying duration
        // (hours)"); the model keeps drying time in minutes, OpenPrintTag's
        // unit and the write form's. Was `== 5` until 2026-09-24 — same data,
        // the model's unit, not a spec change.
        #expect(decoded.dryingTime == 300)
        #expect(decoded.diameter == 1.75)
        #expect(decoded.transmissionDistance == 23.0)
        #expect(decoded.nominalNetWeight == 1000)
        #expect(decoded.actualNetWeight == 1000)
        #expect(decoded.name == "Starter Red")
        // Tag timestamp 0x2D94CC80 = 764726400 s after 2000-01-01 GMT.
        #expect(decoded.manufacturedDateUnix == 764726400 + 946_684_800)
    }

    // MARK: - Decode: variants and shapes

    @Test func decodesTigerTagPlus() throws {
        // The product ID is TigerTag Corp–allocated; SpoolKid reads the tag
        // as its on-chip data and never invents one on write.
        let decoded = try #require(TigerTagPayload.decode(from: Self.plusBambu))
        #expect(decoded.material == "PETG")
        #expect(decoded.brand == "Bambu Lab")
        #expect(decoded.name == "Bambu PETG HF White")
    }

    @Test func refusesTheInitVariant() {
        #expect(TigerTagPayload.decode(from: Self.initTag) == nil)
    }

    @Test func refusesTooShortPayload() {
        #expect(TigerTagPayload.decode(from: Array(Self.rosa3d.prefix(79))) == nil)
    }

    /// Measure Available rides the unit at +23. 150 g out of 1000 g.
    @Test func decodesMeasureAvailableInTheSameUnit() throws {
        let decoded = try #require(TigerTagPayload.decode(from: Self.lowStock))
        #expect(decoded.nominalNetWeight == 1000)
        #expect(decoded.actualNetWeight == 150)
        #expect(decoded.name == "eSun PLA+ Green")
    }

    /// Resin in ml converts to grams via the material's registry density
    /// (Castable Resin 1.05): 500 ml → 525 g.
    @Test func convertsVolumeMeasuresThroughMaterialDensity() throws {
        let decoded = try #require(TigerTagPayload.decode(from: Self.resinGeneric))
        #expect(decoded.material == "Castable Resin")
        #expect(decoded.brand == "Generic")
        #expect(decoded.nominalNetWeight == 525)
    }

    /// kg measures convert ×1000. Unit IDs are decimal registry values:
    /// kg is 35 (spec hex 0x23) — 0x35 would be an unknown unit.
    @Test func convertsKilogramMeasures() throws {
        var bytes = Self.rosa3d
        bytes[20] = 0x00; bytes[21] = 0x00; bytes[22] = 0x01 // u24 = 1
        bytes[23] = 35 // kg
        let decoded = try #require(TigerTagPayload.decode(from: bytes))
        #expect(decoded.nominalNetWeight == 1000)
    }

    /// Aspect 2 carries the color-composition mode; decode joins both labels.
    @Test func decodesAspect2IntoSubtype() throws {
        let decoded = try #require(TigerTagPayload.decode(from: Self.bicolor))
        #expect(decoded.subtype == "Basic Bicolor")
        #expect(decoded.material == "PLA")
        #expect(decoded.brand == "Polymaker")
    }

    @Test func unknownMaterialIDReadsAsUnknown() throws {
        var bytes = Self.rosa3d
        bytes[8] = 0xFF; bytes[9] = 0xFE // not in the registry
        let decoded = try #require(TigerTagPayload.decode(from: bytes))
        #expect(decoded.material == "Unknown")
    }

    /// The other raw decoders must not claim these bytes — the scan tries
    /// ELEGOO and ACE before TigerTag.
    @Test func otherRawDecodersRefuseTigerTagBytes() {
        let wholeChip = Array(repeating: UInt8(0), count: 16) + Self.rosa3d
        #expect(ElegooPayload.decode(from: wholeChip) == nil)
        #expect(AnycubicACEPayload.decode(from: wholeChip) == nil)
    }
}

extension Array where Element == UInt8 {
    /// Hex-string initializer for fixtures. Accepts whitespace anywhere.
    init(hex: String) {
        let clean = hex.split(whereSeparator: \.isWhitespace).joined()
        var result: [UInt8] = []
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            result.append(UInt8(clean[index..<next], radix: 16)!)
            index = next
        }
        self = result
    }
}

// MARK: - Encode

extension TigerTagPayloadTests {

    /// The SDK fixture IS the golden encode vector: decode → re-encode with
    /// the tag's own timestamp must reproduce the bytes exactly.
    @Test func reEncodingTheGoldenVectorReproducesItsBytes() throws {
        let decoded = try #require(TigerTagPayload.decode(from: Self.rosa3d))
        let date = try #require(WriteTagFormAssembler.date(fromUnixSeconds: decoded.manufacturedDateUnix!))
        let pages = TigerTagPayload.encodePages(from: decoded, date: date)
        let bytes = pages.flatMap { [UInt8]($0.data) }
        #expect(bytes == Self.rosa3d)
    }

    /// +29 is whole hours; the model's minutes convert at this boundary, and a
    /// stated time never rounds to 0 ("this tag does not say").
    @Test func writesDryTimeInWholeHoursFromTheModelsMinutes() {
        var data = sampleData
        data.dryingTime = 360
        #expect(encodeBytes(data)[29] == 6)
        data.dryingTime = 20
        #expect(encodeBytes(data)[29] == 1)
        data.dryingTime = nil
        #expect(encodeBytes(data)[29] == 0)
    }

    @Test func emitsOnlyDataPagesFourThroughTwentyThree() {
        let pages = TigerTagPayload.encodePages(from: sampleData, date: fixedDate)
        #expect(pages.map(\.page) == Array(4..<24))
        // Signature pages are the write path's job (it zeroes them so a
        // reused signed chip reads unsigned, never invalid).
        #expect(!pages.contains { $0.page >= 24 })
    }

    @Test func writesStandardMagicAndMakerProductID() {
        let bytes = encodeBytes(sampleData)
        #expect(Array(bytes[0..<4]) == [0x5B, 0xF5, 0x92, 0x64])
        #expect(Array(bytes[4..<8]) == [0xFF, 0xFF, 0xFF, 0xFF])
        #expect(bytes[12] == 0x8E) // Filament
        #expect(bytes[23] == 21)   // grams
    }

    @Test func resolvesMaterialAndBrandThroughTheRegistry() {
        var data = sampleData
        data.material = "PLA+/Pro"   // alias → PLA+
        data.brand = "Protopasta"    // alias → Proto-Pasta
        let bytes = encodeBytes(data)
        #expect(Array(bytes[8..<10]) == bigEndian(TigerTagRegistry.materialID(for: "PLA+").id))
        #expect(Array(bytes[14..<16]) == bigEndian(TigerTagRegistry.brandID(for: "Proto-Pasta").id))
    }

    @Test func outOfRegistryNamesWriteUndefinedIDs() {
        var data = sampleData
        data.material = "Unobtainium"
        data.brand = "Mike's Filaments"
        let bytes = encodeBytes(data)
        #expect(Array(bytes[8..<10]) == [0xFF, 0xFF])
        #expect(Array(bytes[14..<16]) == [0xFF, 0xFF])
    }

    @Test func subtypeBecomesTwoAspectBytes() {
        var data = sampleData
        data.subtype = "Silk Bicolor"
        let bytes = encodeBytes(data)
        let aspects = TigerTagRegistry.aspects(forSubtype: "Silk Bicolor")
        #expect(bytes[10] == aspects.aspect1)
        #expect(bytes[11] == aspects.aspect2)
    }

    @Test func diameterWritesTheNearestRegistryValue() {
        var data = sampleData
        data.diameter = 2.85
        #expect(encodeByte(13, data) == 221)
        data.diameter = 1.75
        #expect(encodeByte(13, data) == 56)
        data.diameter = nil   // AppConfig default (1.75) applies
        #expect(encodeByte(13, data) == 56)
        data.diameter = 3.0   // no such TigerTag diameter — nearest
        #expect(encodeByte(13, data) == 221)
    }

    /// On-chip color order is R,G,B,A — opaque red is FF 00 00 FF.
    @Test func colorWritesAsRGBOpaque() {
        let bytes = encodeBytes(sampleData) // FF0000
        #expect(Array(bytes[16..<20]) == [0xFF, 0x00, 0x00, 0xFF])
    }

    @Test func colorsTwoAndThreeStayZero() {
        let bytes = encodeBytes(sampleData)
        #expect(Array(bytes[36..<44]) == [UInt8](repeating: 0, count: 8))
    }

    @Test func nameTruncatesAtUTF8BoundariesUnder28Bytes() {
        var data = sampleData
        data.name = String(repeating: "é", count: 20) // 40 bytes UTF-8 → 14 chars
        let bytes = encodeBytes(data)
        let field = Array(bytes[48..<76])
        let written = field.prefix(while: { $0 != 0 })
        #expect(written.count <= 28)
        #expect(String(bytes: written, encoding: .utf8)?.contains("é") == true)
    }

    @Test func timestampConvertsUnixToSecondsSince2000() {
        let bytes = encodeBytes(sampleData)
        let seconds = Int(bytes[32]) << 24 | Int(bytes[33]) << 16 | Int(bytes[34]) << 8 | Int(bytes[35])
        #expect(seconds == 1_700_000_000 - 946_684_800)
    }

    @Test func transmissionDistanceScalesTimesTen() {
        var data = sampleData
        data.transmissionDistance = 23.0
        var bytes = encodeBytes(data)
        #expect(Array(bytes[44..<46]) == [0x00, 0xE6])
        data.transmissionDistance = nil
        bytes = encodeBytes(data)
        #expect(Array(bytes[44..<46]) == [0x00, 0x00])
    }

    @Test func unstatedWeightWritesZeroAndGrams() {
        var data = sampleData
        data.nominalNetWeight = nil
        data.actualNetWeight = nil
        let bytes = encodeBytes(data)
        #expect(Array(bytes[20..<23]) == [0x00, 0x00, 0x00]) // clears a previous spool's weight
        #expect(Array(bytes[76..<79]) == [0x00, 0x00, 0x00])
    }

    /// Weight out of the weigh session — actualNetWeight rides Measure
    /// Available, in the same grams unit.
    @Test func actualNetWeightWritesToMeasureAvailable() {
        var data = sampleData
        data.nominalNetWeight = 1000
        data.actualNetWeight = 340
        let bytes = encodeBytes(data)
        #expect(Array(bytes[20..<23]) == [0x00, 0x03, 0xE8]) // 1000 g
        #expect(Array(bytes[76..<79]) == [0x00, 0x01, 0x54]) // 340 = 0x154
    }

    // MARK: - Assembler wiring

    @Test func assemblerCarriesMessageAndAspectsForTigerTag() throws {
        let data = WriteTagFormAssembler.buildTagData(
            format: .tigerTag,
            name: "Bench Spool",
            material: "PLA",
            subtype: "Silk",
            brand: "eSun",
            colorHex: "00FF00",
            minNozzleTemp: 200, maxNozzleTemp: 220,
            minBedTemp: 50, maxBedTemp: 60,
            spoolmanId: 75,
            writeSpoolID: true
        )
        #expect(data.name == "Bench Spool")     // the custom message
        #expect(data.subtype == "Silk")          // aspects ride on it
        #expect(data.spoolmanId == nil)          // mapping is card_uids' job
    }

    // MARK: - Helpers

    private func encodeBytes(_ data: FilamentTagData) -> [UInt8] {
        TigerTagPayload.encodePages(from: data, date: fixedDate).flatMap { [UInt8]($0.data) }
    }

    private func encodeByte(_ offset: Int, _ data: FilamentTagData) -> UInt8 {
        encodeBytes(data)[offset]
    }

    private func bigEndian(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }

    // MARK: - Colors 2 and 3

    private static let multiSample = FilamentTagData(
        material: "PLA", brand: "Prusament", colorHex: "2D39C9", additionalColorHexes: ["A51A52", "112233"],
        minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60
    )

    @Test func multiColorRoundTrips() throws {
        let decoded = try #require(TigerTagPayload.decode(from: encodeBytes(Self.multiSample)))
        #expect(decoded.colors.hexes == ["2D39C9", "A51A52", "112233"])
    }

    @Test func colorTwoAndThreeAreRGBAtTheirOffsets() {
        let bytes = encodeBytes(Self.multiSample)
        #expect(Array(bytes[36..<39]) == [0xA5, 0x1A, 0x52])
        #expect(Array(bytes[40..<43]) == [0x11, 0x22, 0x33])
    }

    /// +39 is the tag index byte and +43 is reserved. A color never writes
    /// them, so they hold the zeros the encoder has always written.
    @Test func colorsLeaveIndexAndReservedBytesZero() {
        let bytes = encodeBytes(Self.multiSample)
        #expect(bytes[39] == 0)
        #expect(bytes[43] == 0)
    }

    @Test func singleColorLeavesColorTwoAndThreeUnset() throws {
        let single = FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "2D39C9",
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60
        )
        #expect(encodeBytes(single)[36..<44].allSatisfy { $0 == 0 })
        let decoded = try #require(TigerTagPayload.decode(from: encodeBytes(single)))
        #expect(decoded.additionalColorHexes == nil)
    }

    @Test func capsAtThreeColors() throws {
        let four = FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "111111",
            additionalColorHexes: ["222222", "333333", "444444"],
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60
        )
        let decoded = try #require(TigerTagPayload.decode(from: encodeBytes(four)))
        #expect(decoded.colors.hexes == ["111111", "222222", "333333"])
    }

    @Test func aStoredAlphaExtraIsWrittenAsRGB() {
        let data = FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "2D39C9", additionalColorHexes: ["A51A52FF"],
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60
        )
        let bytes = encodeBytes(data)
        #expect(Array(bytes[36..<39]) == [0xA5, 0x1A, 0x52])
        #expect(bytes[39] == 0)
    }
}
