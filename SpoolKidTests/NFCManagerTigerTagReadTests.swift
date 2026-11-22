//
//  NFCManagerTigerTagReadTests.swift
//  SpoolKidTests
//
//  CoreNFC itself is untestable off hardware; what is testable is the pure
//  arithmetic the read path leans on — the page-walk bounds and the slicing
//  that turns a raw buffer into codec input — plus the dump namer.
//

import Testing
import Foundation
@testable import SpoolKid

struct NFCManagerTigerTagReadTests {

    /// Page arithmetic for the TigerTag read: 9 READs at [4,8,…,36] fill
    /// pages 4–39 of the buffer, and the codec consumes buffer[16...] —
    /// 144 bytes starting at page 4. A wrong bound here truncates the tag
    /// silently, which is how the ACE once lost page 31.
    @Test func readPagesCoverTheWholePayload() {
        #expect(TigerTagPayload.readPages == [4, 8, 12, 16, 20, 24, 28, 32, 36])
        let bufferBytes = (TigerTagPayload.readPages.max()! + 4) * TigerTagPayload.bytesPerPage
        #expect(bufferBytes == 160)
        let fromPage4 = bufferBytes - TigerTagPayload.firstUserPageOffset
        #expect(fromPage4 == TigerTagPayload.totalByteCount)
    }

    @Test func slicingTheReadBufferYieldsDecodableBytes() throws {
        let buffer = [UInt8](repeating: 0, count: TigerTagPayload.firstUserPageOffset)
            + TigerTagPayloadTests.rosa3d
        let decoded = try #require(TagFormatService.shared.decodeTigerTag(
            dataFromPage4: Array(buffer[TigerTagPayload.firstUserPageOffset...])
        ))
        #expect(decoded.material == "PLA")
    }

    @Test func dumpNamerRecognizesAllThreeVariants() {
        #expect(TigerTagPayload.dumpName(for: TigerTagPayloadTests.rosa3d) == "TigerTag")
        #expect(TigerTagPayload.dumpName(for: TigerTagPayloadTests.plusBambu) == "TigerTag+")
        #expect(TigerTagPayload.dumpName(for: TigerTagPayloadTests.initTag) == "TigerTag Init")
        #expect(TigerTagPayload.dumpName(for: [0x00, 0x01, 0x02]) == nil)
    }

    /// The write appends zeroed signature pages (24–39) after the 20 data
    /// pages: a reused signed chip must read *unsigned*, never *invalid*
    /// (the old signature covered the old identity bytes and would fail).
    @Test func tigerTagWritePageListCoversDataAndSignature() {
        let sample = FilamentTagData(
            name: "Bench", material: "PLA", brand: "eSun", colorHex: "FF0000",
            minNozzleTemp: 200, maxNozzleTemp: 220, minBedTemp: 50, maxBedTemp: 60
        )
        let dataPages = TigerTagPayload.encodePages(from: sample, date: .now)
        let zero = Data(repeating: 0, count: TigerTagPayload.bytesPerPage)
        let pages = dataPages + (24...39).map { ($0, zero) }
        #expect(pages.count == 36)
        #expect(pages.map(\.page) == Array(4..<40))
        // Highest first — the shared rawWriteOrder protects chips whose
        // configuration sits at pages 16–19.
        let ordered = NFCManager.rawWriteOrder(pages)
        #expect(ordered.first!.page == 39)
        #expect(ordered.last!.page == 4)
    }
}
