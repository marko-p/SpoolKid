import Testing
import Foundation
@testable import SpoolKid

struct ElegooPayloadTests {
    @Test func decodesCapturedElegooDumpWithShiftedHeaderBlock() {
        let pages = makeCapturedUnknownTagPages()

        let decoded = ElegooPayload.decode(from: pages)

        #expect(decoded != nil)
        #expect(decoded?.brand == "ELEGOO")
        #expect(decoded?.material == "PLA")
        #expect(decoded?.colorHex == "FFFFFF")
        #expect(decoded?.nominalNetWeight == 1000.0)
    }

    @Test func decodesSpecExampleFromContiguousLayout() {
        let epcBytes = makeSpecExampleEPCBytes()
        let pages = makeContiguousPages(with: epcBytes)

        let decoded = ElegooPayload.decode(from: pages)

        #expect(decoded != nil)
        #expect(decoded?.material == "PLA")
        #expect(decoded?.subtype == "CF20")
        #expect(decoded?.brand == "ELEGOO")
        #expect(decoded?.colorHex == "FF3700")
        #expect(decoded?.nominalNetWeight == 1000.0)
    }

    @Test func decodesSpecExampleFromByteStripedLayout() {
        let epcBytes = makeSpecExampleEPCBytes()
        let pages = makeByteStripedPages(with: epcBytes)

        let decoded = ElegooPayload.decode(from: pages)

        #expect(decoded != nil)
        #expect(decoded?.material == "PLA")
        #expect(decoded?.subtype == "CF20")
        #expect(decoded?.brand == "ELEGOO")
        #expect(decoded?.colorHex == "FF3700")
        #expect(decoded?.nominalNetWeight == 1000.0)
    }

    @Test func rejectsWrongManufacturerCode() {
        var epcBytes = makeSpecExampleEPCBytes()
        epcBytes[1] = 0xDE
        epcBytes[2] = 0xAD
        epcBytes[3] = 0xBE
        epcBytes[4] = 0xEF

        let pages = makeContiguousPages(with: epcBytes)

        #expect(ElegooPayload.decode(from: pages) == nil)
    }

    @Test func rejectsBuffersSmallerThanRequiredNTAGWindow() {
        let undersized = Array(repeating: UInt8(0), count: (36 * ElegooPayload.bytesPerPage) - 1)
        #expect(ElegooPayload.decode(from: undersized) == nil)
    }

    // MARK: - Tags captured from the tester's spools (2026-09-10)
    //
    // Four ELEGOO PLA spools, dumped verbatim by the Tag Explorer. Every byte
    // below is the tag's own; the only difference between the four is the UID
    // and the four colour bytes at block offset 16.

    @Test func capturedTagReportsTheTemperaturesPrintedOnItsSpool() {
        let decoded = ElegooPayload.decode(from: makeTesterTagPages(neonGreenDumpHex))

        // The tag states 190-230 at block offset 20. SpoolKid used to ignore
        // those bytes and report 200-220, derived from the PLA preset.
        #expect(decoded?.minNozzleTemp == 190)
        #expect(decoded?.maxNozzleTemp == 230)
    }

    @Test func capturedTagReportsItsDiameter() {
        let decoded = ElegooPayload.decode(from: makeTesterTagPages(neonGreenDumpHex))

        #expect(decoded?.diameter == 1.75)
    }

    @Test func capturedTagReportsTheColourOnTheSpool() {
        #expect(ElegooPayload.decode(from: makeTesterTagPages(neonGreenDumpHex))?.colorHex == "29D464")
        #expect(ElegooPayload.decode(from: makeTesterTagPages(darkBlueDumpHex))?.colorHex == "106DD7")
    }

    @Test func capturedTagStillReportsItsMaterialAndWeight() {
        let decoded = ElegooPayload.decode(from: makeTesterTagPages(neonGreenDumpHex))

        #expect(decoded?.brand == "ELEGOO")
        #expect(decoded?.material == "PLA")
        #expect(decoded?.nominalNetWeight == 1000.0)
    }

    /// The tag is silent about the bed, so the preset still supplies that range.
    @Test func theBedRangeStillComesFromThePresetWhenTheTagIsSilent() {
        let decoded = ElegooPayload.decode(from: makeTesterTagPages(neonGreenDumpHex))

        #expect(decoded?.minBedTemp == 45)
        #expect(decoded?.maxBedTemp == 55)
    }

    @Test func theNozzleRangeFallsBackToThePresetWhenTheTagIsSilent() {
        var pages = makeTesterTagPages(neonGreenDumpHex)
        for offset in 84..<88 { pages[offset] = 0 }   // block offset 20-23

        let decoded = ElegooPayload.decode(from: pages)

        #expect(decoded?.minNozzleTemp == 200)
        #expect(decoded?.maxNozzleTemp == 220)
    }

    // MARK: - Material names

    /// The material field is ASCII stored as BCD of each character's decimal
    /// code, so it decodes arithmetically. It used to be a nine-entry lookup
    /// table, and anything ELEGOO shipped that was not in the table fell
    /// through to a layout that read the colour three bytes early.
    @Test func materialIsDecodedArithmeticallyNotLookedUpInATable() {
        var pages = makeTesterTagPages(neonGreenDumpHex)
        // "HIPS" = 72, 73, 80, 83 — a material the old table did not list.
        pages[72] = 0x72; pages[73] = 0x73; pages[74] = 0x80; pages[75] = 0x83

        let decoded = ElegooPayload.decode(from: pages)

        #expect(decoded?.material == "HIPS")
        #expect(decoded?.colorHex == "29D464")
    }

    @Test(arguments: [
        (UInt32(0x00807665), "PLA"), (UInt32(0x80698471), "PETG"),
        (UInt32(0x00656683), "ABS"),  (UInt32(0x00848085), "TPU"),
        (UInt32(0x00008065), "PA"),   (UInt32(0x00678069), "CPE"),
        (UInt32(0x00008067), "PC"),   (UInt32(0x00808665), "PVA"),
        (UInt32(0x00658365), "ASA")
    ])
    func everyMaterialCodeInTheGuidesTableDecodesToItsName(code: UInt32, name: String) {
        #expect(ElegooPayload.materialName(fromCode: code) == name)
    }

    @Test(arguments: [UInt32(0x00000000), UInt32(0x4C412043), UInt32(0x000000FF)])
    func aFieldThatIsNotBCDIsNotAMaterialName(code: UInt32) {
        #expect(ElegooPayload.materialName(fromCode: code) == nil)
    }

    /// A block that carries the signature but nothing readable behind it is
    /// refused. It used to be reported as material "Unknown" with the colour
    /// read three bytes early and the nozzle minimum served up as a weight.
    @Test func aBlockWithNoReadableMaterialIsRefusedRatherThanMisread() {
        var pages = makeTesterTagPages(neonGreenDumpHex)
        for offset in 72..<76 { pages[offset] = 0xFF }   // block offset 8-11

        #expect(ElegooPayload.decode(from: pages) == nil)
    }

    /// Issue #4: the format carries no name, so the decode honestly reports
    /// nil and the scan hub must label the spool from what IS on the tag.
    /// Pinning both halves of that path against a real captured dump.
    @Test func capturedTagDecodesToTheConstructedDisplayLabel() {
        let decoded = ElegooPayload.decode(from: makeTesterTagPages(darkBlueDumpHex))

        #expect(decoded?.name == nil)
        #expect(decoded?.displayName == "ELEGOO PLA")
    }
}

/// Elegoo PLA neon green, UID 53555F0A300004, captured 2026-09-10.
private let neonGreenDumpHex = "53555FD10A3000043E480000E11012000103A00C34030FD1010B5502656C65676F6F2E636F6DFE0000000000000000000000000000000000000000000000000036EEEEEEEE000000008076650000000029D464FF00BE00E60000000000AF03E80036C800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000BD040000FF000500000000000000000000"

/// Elegoo PLA dark blue, UID 53CC7A05300004, captured 2026-09-10.
private let darkBlueDumpHex = "53CC7A6D0530000431480000E11012000103A00C34030FD1010B5502656C65676F6F2E636F6DFE0000000000000000000000000000000000000000000000000036EEEEEEEE0000000080766500000000106DD7FF00BE00E60000000000AF03E80036C800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000BD040000FF000500000000000000000000"

private func makeTesterTagPages(_ hex: String) -> [UInt8] {
    var bytes: [UInt8] = []
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
        index = next
    }
    return bytes
}

private func makeSpecExampleEPCBytes() -> [UInt8] {
    var bytes: [UInt8] = [
        0x36,
        0xEE, 0xEE, 0xEE, 0xEE,
        0x00, 0x01,
        0x50, 0x4C, 0x41, 0x20,
        0x43, 0x46, 0x32, 0x30,
        0xFF, 0x37, 0x00,
        0x00, 0xAF,
        0x03, 0xE8,
        0x09, 0xC6
    ]

    bytes.append(contentsOf: Array(repeating: 0x00, count: 8))
    return bytes
}

private func makeContiguousPages(with epcBytes: [UInt8]) -> [UInt8] {
    var pages = Array(repeating: UInt8(0), count: 36 * ElegooPayload.bytesPerPage)
    let start = 4 * ElegooPayload.bytesPerPage

    for (index, value) in epcBytes.enumerated() {
        pages[start + index] = value
    }

    return pages
}

private func makeByteStripedPages(with epcBytes: [UInt8]) -> [UInt8] {
    var pages = Array(repeating: UInt8(0), count: 36 * ElegooPayload.bytesPerPage)

    for (index, value) in epcBytes.enumerated() {
        let page = 4 + index
        pages[page * ElegooPayload.bytesPerPage] = value
    }

    return pages
}

private func makeCapturedUnknownTagPages() -> [UInt8] {
    let rawHex = "534F01950730000433480000E11012000103A00C34030FD1010B5502656C65676F6F2E636F6DFE0000000000000000000000000000000000000000000000000036EEEEEEEE0000000080766500000000FFFFFFFF00BE00E60000000000AF03E80036C8"
    var pages = Array(repeating: UInt8(0), count: 36 * ElegooPayload.bytesPerPage)

    var bytes: [UInt8] = []
    var index = rawHex.startIndex
    while index < rawHex.endIndex {
        let next = rawHex.index(index, offsetBy: 2)
        let byteString = String(rawHex[index..<next])
        bytes.append(UInt8(byteString, radix: 16) ?? 0)
        index = next
    }

    for (offset, byte) in bytes.enumerated() where offset < pages.count {
        pages[offset] = byte
    }

    return pages
}

// MARK: - Encode (ELEGOO write, issue #14)
//
// The oracle is the factory tag itself: two spools that differ only in colour
// differ only at page 20, so encoding PLA in each colour must reproduce each
// dump's pages 4-39 byte for byte.

extension ElegooPayloadTests {

    @Test(arguments: [(neonGreenDumpHex, "29D464"), (darkBlueDumpHex, "106DD7")])
    func encodingAFactorySpoolReproducesItsTagByteForByte(dumpHex: String, colorHex: String) {
        let factory = makeTesterTagPages(dumpHex)
        let data = factoryPLA(colorHex: colorHex)

        let pages = ElegooPayload.encodePages(from: data)

        #expect(pages.map(\.page) == Array(4...39))
        #expect(pages.flatMap { [UInt8]($0.data) } == Array(factory[16..<160]))
    }

    @Test(arguments: ElegooCanvasCatalog.entries)
    func everyCanvasFilamentSurvivesAWriteAndARead(entry: ElegooCanvasCatalog.Entry) throws {
        let fields = ElegooCanvasCatalog.tagFields(for: entry)
        let data = FilamentTagData(
            material: fields.material, subtype: fields.subtype, brand: "ELEGOO", colorHex: "A1B2C3",
            minNozzleTemp: 205, maxNozzleTemp: 235, minBedTemp: 0, maxBedTemp: 0,
            diameter: 2.85, nominalNetWeight: 750
        )

        let decoded = try #require(ElegooPayload.decode(from: tagImage(writing: data)))

        #expect(decoded.material == fields.material)
        #expect(decoded.subtype == fields.subtype)
        #expect(decoded.colorHex == "A1B2C3")
        #expect(decoded.minNozzleTemp == 205)
        #expect(decoded.maxNozzleTemp == 235)
        #expect(decoded.diameter == 2.85)
        #expect(decoded.nominalNetWeight == 750)
    }

    /// Page 19 is the Canvas type index and subtype ID: `00 04` is PLA-CF on
    /// DnG-Crafts' dump.
    @Test func theSubtypeIsReadFromPage19() {
        var pages = makeTesterTagPages(neonGreenDumpHex)
        pages[77] = 0x04   // page 19, byte 1

        #expect(ElegooPayload.decode(from: pages)?.subtype == "PLA-CF")
    }

    /// A factory spool with an ID nobody catalogued must keep reading.
    @Test func aSubtypeIDNobodyCataloguedStillReads() {
        var pages = makeTesterTagPages(neonGreenDumpHex)
        pages[77] = 0x07   // PLA has no subtype 7 in the catalog

        let decoded = ElegooPayload.decode(from: pages)

        #expect(decoded?.material == "PLA")
        #expect(decoded?.subtype == nil)
    }

    @Test func aTypeIndexThatContradictsTheMaterialIsNotTrusted() {
        var pages = makeTesterTagPages(neonGreenDumpHex)
        pages[76] = 0x01   // PETG's type index on a PLA block
        pages[77] = 0x01

        let decoded = ElegooPayload.decode(from: pages)

        #expect(decoded?.material == "PLA")
        #expect(decoded?.subtype == nil)
    }

    @Test(arguments: [("Nylon", nil), ("PLA", "Glow")] as [(String, String?)])
    func encodingRefusesAFilamentTheCanvasHasNoEntryFor(material: String, subtype: String?) {
        var data = factoryPLA(colorHex: "29D464")
        data.material = material
        data.subtype = subtype

        #expect(ElegooPayload.encodePages(from: data).isEmpty)
    }

    @Test func encodingRefusesAColourItCannotParse() {
        #expect(ElegooPayload.encodePages(from: factoryPLA(colorHex: "XYZ")).isEmpty)
    }

    @Test func anUnstatedDiameterAndWeightWriteTheAppDefaults() throws {
        var data = factoryPLA(colorHex: "29D464")
        data.diameter = nil
        data.nominalNetWeight = nil

        let page23 = try #require(ElegooPayload.encodePages(from: data).first { $0.page == 23 })

        #expect([UInt8](page23.data) == [0x00, 0xAF, 0x03, 0xE8])
    }

    @Test func aWeightBeyondTheFieldIsClampedRatherThanWrapped() throws {
        var data = factoryPLA(colorHex: "29D464")
        data.nominalNetWeight = 70_000

        let page23 = try #require(ElegooPayload.encodePages(from: data).first { $0.page == 23 })

        #expect([UInt8](page23.data) == [0x00, 0xAF, 0xFF, 0xFF])
    }
}

private func factoryPLA(colorHex: String) -> FilamentTagData {
    FilamentTagData(
        material: "PLA", brand: "ELEGOO", colorHex: colorHex,
        minNozzleTemp: 190, maxNozzleTemp: 230, minBedTemp: 45, maxBedTemp: 55,
        diameter: 1.75, nominalNetWeight: 1000
    )
}

/// A factory tag's pages 0-3 and 40-44 around what the encoder writes, so the
/// decoder reads it exactly as it would read the chip.
private func tagImage(writing data: FilamentTagData) -> [UInt8] {
    var image = makeTesterTagPages(neonGreenDumpHex)
    for page in ElegooPayload.encodePages(from: data) {
        let start = page.page * ElegooPayload.bytesPerPage
        image.replaceSubrange(start..<start + ElegooPayload.bytesPerPage, with: [UInt8](page.data))
    }
    return image
}
