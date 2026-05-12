import Testing
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
