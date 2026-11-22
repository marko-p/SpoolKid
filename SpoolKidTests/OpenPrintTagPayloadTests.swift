//
//  OpenPrintTagPayloadTests.swift
//  SpoolKidTests
//
//  Decoder tests for OpenPrintTag read support, validated against the real
//  spec vector (tests/encode_decode/01_data.bin, bytes 66..311 = the
//  application/vnd.openprinttag NDEF record payload) and decoded breakdown
//  (01_info.yaml) from github.com/OpenPrintTag/openprinttag-specification.
//

import Testing
import Foundation
import CoreNFC
@testable import SpoolKid

struct OpenPrintTagPayloadTests {

    /// Real OpenPrintTag NDEF media-record payload (meta + main + aux), 245 bytes.
    private static let vector01 =
        "a10218d2bf041b000007d0fcab45f9056a33333463353466303838080009000a76504c4120507275" +
        "73612047616c61787920426c61636b0b6950727573616d656e740e1a68d3c7d7101903e8111903f4" +
        "1219011813443d3e3dff181c9f17ff181df93cf6182218cd182318e1182418aa182518281826183c" +
        "18271218281828182914182a1840182b18c8182c1864182d183418389f0001ff183b831832fa4134" +
        "cccdfa43014ccd183c69323730203330203230ff0000000000000000000000000000000000000000" +
        "00000000000000000000a00000000000000000000000000000000000000000000000000000000000" +
        "0000000000"

    private func hexData(_ hex: String) -> Data {
        var d = Data()
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            d.append(UInt8(hex[i..<j], radix: 16)!)
            i = j
        }
        return d
    }

    // MARK: - Decoder (Task 1)

    @Test func decodesRealPrusamentVector() throws {
        let tag = try #require(OpenPrintTagPayload.decode(from: hexData(Self.vector01)))
        #expect(tag.material == "PLA")
        #expect(tag.name == "PLA Prusa Galaxy Black")
        #expect(tag.brand == "Prusament")
        #expect(tag.colorHex == "3D3E3D")
        #expect(tag.minNozzleTemp == 205)
        #expect(tag.maxNozzleTemp == 225)
        #expect(tag.minBedTemp == 40)
        #expect(tag.maxBedTemp == 60)
        #expect(tag.preheatTemp == 170)
        #expect(tag.nominalNetWeight == 1000)
        #expect(tag.actualNetWeight == 1012)
        #expect(tag.emptyContainerWeight == 280)
        #expect(tag.gtin == "8594173675001")
        #expect(tag.manufacturedDateUnix == 1758709719)
        #expect(tag.materialTags == [23])
        let density = try #require(tag.density)
        #expect(abs(density - 1.24) < 0.01)
    }

    @Test func honorsExplicitMainRegionOffset() throws {
        // meta {0:6} = "a10006" (3B); pad "000000" to offset 6; main at 6:
        // {9:0, 11:"X", 34:200} = "a309000b6158182218c8"
        let hex = "a10006" + "000000" + "a309000b6158182218c8"
        let tag = try #require(OpenPrintTagPayload.decode(from: hexData(hex)))
        #expect(tag.material == "PLA")
        #expect(tag.brand == "X")
        #expect(tag.minNozzleTemp == 200)
        #expect(tag.name == nil)
    }

    @Test func returnsNilForNonOpenPrintTagBytes() {
        #expect(OpenPrintTagPayload.decode(from: Data([0x01, 0x02, 0x03])) == nil)
    }

    @Test func halfFloatDecodesDensity() {
        #expect(abs(CBORReader.halfToDouble(0x3cf6) - 1.24) < 0.01)
    }

    // MARK: - TagFormatService wiring (Task 2)

    @Test func tagFormatServiceDecodesOpenPrintTagByMime() throws {
        let tag = try #require(
            TagFormatService.shared.decode(
                payload: hexData(Self.vector01),
                mimeType: "application/vnd.openprinttag"
            )
        )
        #expect(tag.material == "PLA")
        #expect(tag.brand == "Prusament")
    }

    // MARK: - Detected format (Task 3)

    @Test func openPrintTagDetectedFormatDisplayName() {
        #expect(ScanResult.DetectedFormat.openPrintTag.displayName == "OpenPrintTag")
    }

    // MARK: - Provenance caption (Task 5)

    @Test func provenanceCaptionForTag() {
        #expect(ScanResultHubView.provenanceCaption(
            format: .openPrintTag, hasParsedWebData: false, webHost: nil)
            == "Read from tag · OpenPrintTag")
    }

    @Test func provenanceCaptionForWeb() {
        #expect(ScanResultHubView.provenanceCaption(
            format: .webUrl, hasParsedWebData: true, webHost: "3dtag.org")
            == "Parsed from web · 3dtag.org")
    }

    @Test func provenanceCaptionNoneForUIDOnly() {
        #expect(ScanResultHubView.provenanceCaption(
            format: nil, hasParsedWebData: false, webHost: nil) == nil)
    }

    // MARK: - Encoder (Task 1)

    @Test func encodeRoundTripsCoreAndRichFields() throws {
        let original = FilamentTagData(
            id: UUID(), name: "PLA Galaxy Black", material: "PLA", subtype: nil,
            brand: "Prusament", colorHex: "3D3E3D",
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 40, maxBedTemp: 60,
            spoolmanId: nil, density: 1.24, transmissionDistance: nil,
            gtin: "8594173675001", manufacturedDateUnix: 1758709719, countryOfOrigin: "CZ",
            preheatTemp: 170, dryingTemp: 55, dryingTime: 480,
            nominalNetWeight: 1000, actualNetWeight: 1012, emptyContainerWeight: 280,
            materialTags: [23], certifications: nil, tagURL: nil
        )
        let bytes = try #require(OpenPrintTagPayload.encode(from: original))
        #expect(bytes.first == 0xa0)
        let decoded = try #require(OpenPrintTagPayload.decode(from: bytes))
        #expect(decoded.material == "PLA")
        #expect(decoded.name == "PLA Galaxy Black")
        #expect(decoded.brand == "Prusament")
        #expect(decoded.colorHex == "3D3E3D")
        #expect(decoded.minNozzleTemp == 205)
        #expect(decoded.maxNozzleTemp == 225)
        #expect(decoded.minBedTemp == 40)
        #expect(decoded.maxBedTemp == 60)
        #expect(decoded.preheatTemp == 170)
        #expect(decoded.nominalNetWeight == 1000)
        #expect(decoded.actualNetWeight == 1012)
        #expect(decoded.emptyContainerWeight == 280)
        #expect(decoded.gtin == "8594173675001")
        #expect(decoded.manufacturedDateUnix == 1758709719)
        #expect(decoded.countryOfOrigin == "CZ")
        #expect(decoded.dryingTemp == 55)
        #expect(decoded.dryingTime == 480)
        #expect(decoded.materialTags == [23])
        let density = try #require(decoded.density)
        #expect(abs(density - 1.24) < 0.001)
    }

    @Test func encodeReadableViaTagFormatServiceMime() throws {
        let data = FilamentTagData(material: "PETG", brand: "Generic", colorHex: "112233",
                                   minNozzleTemp: 230, maxNozzleTemp: 250, minBedTemp: 70, maxBedTemp: 80)
        let bytes = try #require(OpenPrintTagPayload.encode(from: data))
        let decoded = try #require(TagFormatService.shared.decode(payload: bytes, mimeType: "application/vnd.openprinttag"))
        #expect(decoded.material == "PETG")
    }

    @Test func encodeOmitsMaterialTypeForUnknownMaterial() throws {
        let data = FilamentTagData(name: "Weird Blend", material: "ZZZ", brand: "X", colorHex: "000000",
                                   minNozzleTemp: 200, maxNozzleTemp: 210, minBedTemp: 50, maxBedTemp: 60)
        let bytes = try #require(OpenPrintTagPayload.encode(from: data))
        let decoded = try #require(OpenPrintTagPayload.decode(from: bytes))
        #expect(decoded.material == "Weird Blend")
    }

    // MARK: - TagFormat registration (Task 2)

    @Test func tagFormatOpenPrintTagMetadata() {
        #expect(TagFormat.openPrintTag.displayName == "OpenPrintTag")
        #expect(TagFormat.openPrintTag.isNDEF == true)
        #expect(TagFormat.openPrintTag.mimeType == "application/vnd.openprinttag")
    }

    @Test func tagFormatServiceEncodesOpenPrintTag() throws {
        let data = FilamentTagData(material: "PLA", brand: "Prusament", colorHex: "3D3E3D",
                                   minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 40, maxBedTemp: 60)
        let bytes = try #require(TagFormatService.shared.encode(data: data, format: .openPrintTag))
        #expect(bytes.first == 0xa0)
    }

    // MARK: - Field catalog + visibility (Task 3)

    @Test func openPrintTagCatalogHasRichFields() {
        let ids = Set(NFCFieldCatalog.fields(for: .openPrintTag).map(\.id))
        #expect(ids.isSuperset(of: ["material", "brand", "color_hex", "temp_range",
                                    "name", "preheat_temp", "nominal_weight", "empty_weight",
                                    "density", "drying_temp", "drying_time", "gtin",
                                    "country", "manufactured_date", "url"]))
    }

    @Test func openPrintTagNonEssentialFieldsHaveVisibilityKeys() {
        let store = NFCFieldVisibilityStore()
        for field in NFCFieldCatalog.fields(for: .openPrintTag) where !field.isEssential {
            #expect(store.visibilityKey(for: .openPrintTag, fieldID: field.id) != nil,
                    "missing visibility key for \(field.id)")
        }
    }

    // MARK: - URL record helpers (Task 6)

    @Test func ndefRecordsIncludeURIWhenURLPresent() {
        let mime = Data([0xa0])
        let withURL = NFCManager.ndefRecords(mimePayload: mime, mimeType: "application/vnd.openprinttag",
                                             urlString: "https://3dtag.org/s/abc")
        #expect(withURL.count == 2)
        #expect(NFCManager.firstURL(in: withURL)?.absoluteString == "https://3dtag.org/s/abc")

        let noURL = NFCManager.ndefRecords(mimePayload: mime, mimeType: "application/vnd.openprinttag", urlString: nil)
        #expect(noURL.count == 1)
        #expect(NFCManager.firstURL(in: noURL) == nil)
    }

    // MARK: - Secondary colors

    private static func mainKeys(_ data: FilamentTagData) -> [Int] {
        OpenPrintTagPayload.mainMap(from: data).map(\.0)
    }

    private static func bytesValue(_ key: Int, in data: FilamentTagData) -> [UInt8]? {
        guard let value = OpenPrintTagPayload.mainMap(from: data).first(where: { $0.0 == key })?.1,
              case .bytes(let rgb) = value else { return nil }
        return rgb
    }

    /// A main section with the given keys, read back through `decode(from:)`.
    private static func decodeMain(_ pairs: [(Int, CBORWriter.Value)]) -> FilamentTagData? {
        let base: [(Int, CBORWriter.Value)] = [(9, .uint(0)), (10, .text("PLA")), (11, .text("Test"))]
        return OpenPrintTagPayload.decode(from: Data([0xa0]) + CBORWriter.encodeMap(base + pairs))
    }

    @Test func multiOmitsPrimaryWritesSecondaries() {
        let multi = FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "2D39C9", additionalColorHexes: ["A51A52"],
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60
        )
        #expect(!Self.mainKeys(multi).contains(19))
        #expect(Self.bytesValue(20, in: multi) == [0x2D, 0x39, 0xC9])
        #expect(Self.bytesValue(21, in: multi) == [0xA5, 0x1A, 0x52])
        #expect(!Self.mainKeys(multi).contains(22))
    }

    @Test func multiColorRoundTrips() throws {
        let multi = FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "2D39C9", additionalColorHexes: ["A51A52", "112233"],
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60
        )
        let bytes = try #require(OpenPrintTagPayload.encode(from: multi))
        let decoded = try #require(OpenPrintTagPayload.decode(from: bytes))
        #expect(decoded.colors.hexes == ["2D39C9", "A51A52", "112233"])
        #expect(decoded.colors.isMulti)
    }

    @Test func singleColorKeepsThePrimaryAndNoSecondaries() {
        let single = FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "3D3E3D",
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60
        )
        #expect(Self.bytesValue(19, in: single) == [0x3D, 0x3E, 0x3D])
        #expect(!Self.mainKeys(single).contains { (20...24).contains($0) })
    }

    @Test func readsPrimaryPlusSecondaries() throws {
        let data = try #require(Self.decodeMain([
            (19, .bytes([0xFF, 0x00, 0x00])), (20, .bytes([0x00, 0xFF, 0x00])), (21, .bytes([0x00, 0x00, 0xFF])),
        ]))
        #expect(data.colors.hexes == ["FF0000", "00FF00", "0000FF"])
        #expect(data.colorHex == "FF0000")
    }

    @Test func primaryAbsentReadsFirstSecondaryAsThePrimary() throws {
        let data = try #require(Self.decodeMain([
            (20, .bytes([0xFF, 0x00, 0x00])), (21, .bytes([0x00, 0xFF, 0x00])),
        ]))
        #expect(data.colorHex == "FF0000")
        #expect(data.additionalColorHexes == ["00FF00"])
    }

    @Test func noColorKeysReadsGrey() throws {
        let data = try #require(Self.decodeMain([]))
        #expect(data.colorHex == "808080")
        #expect(data.additionalColorHexes == nil)
    }

    @Test func capsAtFiveColors() throws {
        let six = FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "111111",
            additionalColorHexes: ["222222", "333333", "444444", "555555", "666666"],
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60
        )
        #expect(Self.mainKeys(six).filter { (20...24).contains($0) } == [20, 21, 22, 23, 24])
        #expect(!Self.mainKeys(six).contains(25))
        let bytes = try #require(OpenPrintTagPayload.encode(from: six))
        let decoded = try #require(OpenPrintTagPayload.decode(from: bytes))
        #expect(decoded.colors.hexes.count == 5)
    }
}
