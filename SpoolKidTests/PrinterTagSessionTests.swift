//
//  PrinterTagSessionTests.swift
//  SpoolKidTests
//
//  The printer tag session against a fake gateway that holds a page buffer and
//  applies writes to it, so a write followed by a scan round-trips. No printer
//  is contacted.
//

import Testing
import Foundation
@testable import SpoolKid

@MainActor
private final class FakeGateway: PrinterTagGateway {
    var tagPlugin: PrinterTagPlugin = .ready(version: "1.0")
    var toolheads: [ToolheadState] = []
    var memory: [UInt8]
    var uid = "04A1B2C3D4E5F6"
    var versionReply: [UInt8]? = [0x00, 0x04, 0x04, 0x02, 0x01, 0x00, 0x0F, 0x03]   // NTAG213
    var writeFailure: PrinterTagError?
    var readFailure: PrinterTagError?
    private(set) var readCalls = 0
    private(set) var writes: [[(page: Int, data: Data)]] = []
    private(set) var lastExpectedUID: String?
    private(set) var lastAllowConfig: Bool?

    init(memory: [UInt8]) { self.memory = memory }

    /// A factory NTAG213: formatted, with an empty NDEF TLV.
    static func blankNTAG213() -> FakeGateway {
        var bytes = [UInt8](repeating: 0, count: 180)
        bytes[0..<8] = [0x04, 0xA1, 0xB2, 0x00, 0xC3, 0xD4, 0xE5, 0xF6]
        bytes[12..<16] = [0xE1, 0x10, 0x12, 0x00]
        bytes[16..<20] = [0x03, 0x00, 0xFE, 0x00]
        bytes[41 * 4 + 3] = 0xFF   // CFG0's AUTH0: no page is password-protected
        return FakeGateway(memory: bytes)
    }

    /// A factory NTAG215 (OpenSpool's JSON does not fit an NTAG213), formatted or never formatted.
    static func ntag215(formatted: Bool = true) -> FakeGateway {
        var bytes = [UInt8](repeating: 0, count: 540)
        bytes[0..<8] = [0x04, 0xA1, 0xB2, 0x00, 0xC3, 0xD4, 0xE5, 0xF6]
        if formatted {
            bytes[12..<16] = [0xE1, 0x10, 0x3E, 0x00]
            bytes[16..<20] = [0x03, 0x00, 0xFE, 0x00]
        }
        bytes[131 * 4 + 3] = 0xFF   // CFG0's AUTH0: no page is password-protected
        let gateway = FakeGateway(memory: bytes)
        gateway.versionReply = [0x00, 0x04, 0x04, 0x02, 0x01, 0x00, 0x11, 0x03]
        return gateway
    }

    /// Never formatted: every page zero.
    static func unformatted() -> FakeGateway { FakeGateway(memory: [UInt8](repeating: 0, count: 180)) }

    func readTag(toolhead: Int, expectedUID: String?) async -> Result<PrinterTagRead, PrinterTagError> {
        readCalls += 1
        if let readFailure { return .failure(readFailure) }
        // The plugin does not reach a MIFARE Classic (4-byte UID) tag, and refuses
        // a read that names a different tag than the one on the holder.
        if uid.count == 8 { return .failure(.unsupportedTag("Not an NFC-A Type 2 tag.")) }
        if let expectedUID, SpoolMappingService.normalizeUID(expectedUID) != SpoolMappingService.normalizeUID(uid) {
            return .failure(.uidMismatch)
        }
        let container = Array(memory[12..<16])
        return .success(PrinterTagRead(
            uid: uid, firstPage: 0, bytes: memory, versionReply: versionReply,
            geometry: Type2Geometry(versionReply: versionReply, capabilityContainer: container)))
    }

    func writeTag(toolhead: Int, expectedUID: String, pages: [(page: Int, data: Data)],
                  password: Data?, allowConfig: Bool) async -> Result<Int, PrinterTagError> {
        writes.append(pages)
        lastExpectedUID = expectedUID
        lastAllowConfig = allowConfig
        if let writeFailure { return .failure(writeFailure) }
        if SpoolMappingService.normalizeUID(expectedUID) != SpoolMappingService.normalizeUID(uid) {
            return .failure(.uidMismatch)
        }
        var written = 0
        for entry in pages {
            let range = entry.page * 4..<entry.page * 4 + 4
            // The plugin skips a capability-container page that already holds the bytes.
            if entry.page == 3, Array(memory[range]) == Array(entry.data) { continue }
            memory.replaceSubrange(range, with: entry.data)
            written += 1
        }
        return .success(written)
    }
}

private func bytes(hex: String) -> [UInt8] {
    let characters = Array(hex)
    return stride(from: 0, to: characters.count, by: 2).map { UInt8(String(characters[$0...$0 + 1]), radix: 16)! }
}

private let sample = FilamentTagData(
    material: "PLA", brand: "ELEGOO", colorHex: "29D464",
    minNozzleTemp: 190, maxNozzleTemp: 230, minBedTemp: 50, maxBedTemp: 60,
    diameter: 1.75, nominalNetWeight: 1000)

@MainActor
private func scanResult(_ gateway: FakeGateway, rejecting: Bool = false) async -> PrinterScanOutcome {
    await PrinterTagSession(gateway: gateway, toolhead: 1).scan(rejectingLocationTags: rejecting)
}

@MainActor
private func perform(_ write: NFCManager.PendingWrite, on gateway: FakeGateway,
                     blocked: Set<String> = []) async -> PrinterWriteOutcome {
    await PrinterTagSession(gateway: gateway, toolhead: 1).perform(write, blockedUIDs: blocked)
}

/// Lays an NDEF message onto a gateway's memory the way a write would.
@MainActor
private func install(_ records: [NDEFRecordSnapshot], on gateway: FakeGateway) {
    let message = Type2NDEF.messageBytes(for: records)
    let container = Array(gateway.memory[12..<16])
    let geometry = Type2Geometry(versionReply: gateway.versionReply, capabilityContainer: container)
    for entry in Type2NDEF.pages(forMessageBytes: message, geometry: geometry,
                                 currentCapabilityContainer: geometry.capabilityContainer)! {
        gateway.memory.replaceSubrange(entry.page * 4..<entry.page * 4 + 4, with: entry.data)
    }
}

@Suite @MainActor struct PrinterTagSessionTests {

    // MARK: - Reads

    @Test func scanDecodesOpenSpoolFromPages() async throws {
        let gateway = FakeGateway.ntag215()
        let payload = try #require(TagFormatService.shared.encode(data: sample, format: .openSpool))
        install(NFCManager.ndefRecords(mimePayload: payload, mimeType: "application/json", urlString: nil)
            .map(NDEFRecordSnapshot.init(record:)), on: gateway)

        guard case .result(let result) = await scanResult(gateway) else { Issue.record("expected a result"); return }
        #expect(result.format == .openSpool)
        #expect(result.tagData?.material == "PLA")
        #expect(result.cardUID == "04a1b2c3d4e5f6")
        #expect(result.tagSnapshot != nil)
        #expect(result.inspection?.chip?.getVersion == gateway.versionReply)
    }

    @Test func scanDecodesEachRawFormat() async throws {
        // ELEGOO: the tester's real dump.
        let elegoo = FakeGateway(memory: bytes(hex: "53CC7A6D0530000431480000E11012000103A00C34030FD1010B5502656C65676F6F2E636F6DFE0000000000000000000000000000000000000000000000000036EEEEEEEE0000000080766500000000106DD7FF00BE00E60000000000AF03E80036C800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000BD040000FF000500000000000000000000"))
        guard case .result(let elegooResult) = await scanResult(elegoo) else { Issue.record("elegoo"); return }
        #expect(elegooResult.format == .elegoo)
        #expect(elegooResult.tagData?.material == "PLA")

        // TigerTag: the golden vector from page 4.
        let tiger = FakeGateway.blankNTAG213()
        let rosa = bytes(hex: "5bf59264ffffffff954b68008e384df9ff0000ff0003e81500c300e63205323c2d94cc80000000000000000000e60000537461727465722052656400000000000000000000000000000000000003e800")
        tiger.memory.replaceSubrange(16..<16 + rosa.count, with: rosa)
        guard case .result(let tigerResult) = await scanResult(tiger) else { Issue.record("tiger"); return }
        #expect(tigerResult.format == .tigerTag)
        #expect(tigerResult.tigerTagInfo != nil)

        // Anycubic ACE: pages as the encoder writes them.
        let ace = FakeGateway.blankNTAG213()
        for entry in AnycubicACEPayload.encodePages(from: sample) {
            ace.memory.replaceSubrange(entry.page * 4..<entry.page * 4 + 4, with: entry.data)
        }
        guard case .result(let aceResult) = await scanResult(ace) else { Issue.record("ace"); return }
        #expect(aceResult.format == .anycubicACE)
        #expect(aceResult.tagData?.material == "PLA")
    }

    @Test func scanOfBlankTagReportsBlank() async {
        guard case .result(let result) = await scanResult(.blankNTAG213()) else { Issue.record("expected a result"); return }
        #expect(result.tagData == nil)
        #expect(result.isBlankTag)
        #expect(result.undecodedTagNote == "Empty tag")
    }

    @Test func scanOfLocationTagIsRefusedWhenRejecting() async throws {
        let gateway = FakeGateway.blankNTAG213()
        let location = LocationTagPayload(uuid: UUID(), name: "Shelf A")
        let record = NDEFRecordSnapshot(
            typeNameFormat: 2, type: Data(LocationTagPayload.mimeType.utf8), identifier: Data(),
            payload: try #require(location.encoded()))
        install([record], on: gateway)

        guard case .refused(let message, let result) = await scanResult(gateway, rejecting: true) else {
            Issue.record("expected a refusal"); return
        }
        #expect(message == "This tag labels Shelf A.")
        #expect(result?.locationTag == location)

        guard case .result(let accepted) = await scanResult(gateway) else { Issue.record("expected a result"); return }
        #expect(accepted.locationTag == location)
    }

    @Test func scanOfSnapmakerToolheadReturnsWhatThePrinterReports() async {
        let gateway = FakeGateway.blankNTAG213()
        gateway.toolheads = [ToolheadState(
            index: 1, material: "PLA", vendor: "Snapmaker", colorHexes: ["FF0000"], alpha: 255,
            isLoaded: true, isOfficial: true, tagUID: "A1B2C3D4",
            tag: ToolheadTagData(vendor: "Snapmaker", material: "PLA", colorHexes: ["FF0000"], alpha: 255))]

        guard case .result(let result) = await scanResult(gateway) else { Issue.record("expected a result"); return }
        #expect(gateway.readCalls == 0)
        #expect(result.cardUID == "a1b2c3d4")
        #expect(result.tagData?.material == "PLA")
        #expect(result.tagData?.brand == "Snapmaker")
        #expect(result.tagSnapshot == nil)
        #expect(result.isReportedByPrinter)
    }

    @Test func aTagReadThroughThePluginIsNotMarkedAsReportedByThePrinter() async {
        guard case .result(let result) = await scanResult(FakeGateway.blankNTAG213()) else { Issue.record("expected a result"); return }
        #expect(!result.isReportedByPrinter)
    }

    @Test func aPluginThatIsNotReadyFailsTheScan() async {
        let gateway = FakeGateway.blankNTAG213()
        gateway.tagPlugin = .notReady(reason: "Reader is starting.")
        guard case .failed(let error) = await scanResult(gateway) else { Issue.record("expected a failure"); return }
        #expect(error == .notReady("Reader is starting."))
        #expect(gateway.readCalls == 0)
    }

    @Test func aSevenByteUIDOnAnOfficialToolheadIsReadThroughThePlugin() async {
        let gateway = FakeGateway.blankNTAG213()
        gateway.toolheads = [ToolheadState(
            index: 1, material: "PLA", colorHexes: ["FF0000"], alpha: 255, isLoaded: true, isOfficial: true,
            tagUID: "04A1B2C3D4E5F6",
            tag: ToolheadTagData(vendor: "Snapmaker", material: "PLA", colorHexes: ["FF0000"], alpha: 255))]
        guard case .result(let result) = await scanResult(gateway) else { Issue.record("expected a result"); return }
        #expect(gateway.readCalls == 1)
        #expect(!result.isReportedByPrinter)
        #expect(result.cardUID == "04a1b2c3d4e5f6")
    }

    @Test func aFourByteUIDOnANonOfficialToolheadIsReportedNotRead() async {
        let gateway = FakeGateway.blankNTAG213()
        gateway.toolheads = [ToolheadState(
            index: 1, material: "PLA", colorHexes: ["0000FF"], alpha: 255, isLoaded: true, isOfficial: false,
            tagUID: "A1B2C3D4",
            tag: ToolheadTagData(vendor: "Bambu Lab", material: "PLA", colorHexes: ["0000FF"], alpha: 255))]
        guard case .result(let result) = await scanResult(gateway) else { Issue.record("expected a result"); return }
        #expect(gateway.readCalls == 0)
        #expect(result.cardUID == "a1b2c3d4")
        #expect(result.tagData?.brand == "Bambu Lab")
    }

    @Test func aLocationWriteIsRefusedBeforeTheUIDCheck() async {
        let gateway = FakeGateway.ntag215()
        gateway.uid = "A1B2C3D4"
        gateway.toolheads = [ToolheadState(
            index: 1, material: "PLA", colorHexes: ["FF0000"], alpha: 255, isLoaded: true, isOfficial: false,
            tagUID: "A1B2C3D4")]
        let outcome = await perform(.location(LocationTagPayload(uuid: UUID(), name: "Shelf")), on: gateway)
        #expect(outcome == .refused(message: "Location tags are written with the iPhone."))
        #expect(gateway.writes.isEmpty)
    }

    @Test func anUnsupportedTagFallsBackToWhatThePrinterReports() async {
        let gateway = FakeGateway.blankNTAG213()
        gateway.readFailure = .unsupportedTag("Not an NFC-A tag.")
        gateway.toolheads = [ToolheadState(
            index: 1, material: "PETG", colorHexes: ["00FF00"], alpha: 255, isLoaded: true, isOfficial: false,
            tagUID: "04A1B2C3D4E5F6",
            tag: ToolheadTagData(vendor: "Acme", material: "PETG", colorHexes: ["00FF00"], alpha: 255))]
        guard case .result(let result) = await scanResult(gateway) else { Issue.record("expected a result"); return }
        #expect(gateway.readCalls == 1)
        #expect(result.cardUID == "04a1b2c3d4e5f6")
        #expect(result.tagData?.material == "PETG")
        #expect(result.tagSnapshot == nil)

        gateway.toolheads = []
        guard case .failed(let error) = await scanResult(gateway) else { Issue.record("expected a failure"); return }
        #expect(error == .unsupportedTag("Not an NFC-A tag."))
    }

    @Test func dumpReportsEveryPageAndTheFormat() async throws {
        let gateway = FakeGateway.blankNTAG213()
        let dump = try await PrinterTagSession(gateway: gateway, toolhead: 1).dump().get()
        #expect(dump.pagesRead == 45)
        #expect(dump.chipVersion == "NTAG213")
        #expect(dump.endedBy == .endOfTag)
        #expect(dump.uid == "04a1b2c3d4e5f6")
    }

    // MARK: - Writes

    @Test func writeOpenSpoolProducesPagesTheUnpackerReadsBack() async {
        let gateway = FakeGateway.ntag215()
        let outcome = await perform(.filament(sample, .openSpool, cardUID: nil), on: gateway)
        #expect(outcome == .written(uid: "04a1b2c3d4e5f6"))
        #expect(gateway.lastExpectedUID == "04a1b2c3d4e5f6")
        #expect(gateway.lastAllowConfig == false)

        guard case .result(let result) = await scanResult(gateway) else { Issue.record("expected a result"); return }
        #expect(result.format == .openSpool)
        #expect(result.tagData?.brand == "ELEGOO")
    }

    @Test func writeToBlankTagIncludesCapabilityContainer() async {
        let gateway = FakeGateway.ntag215(formatted: false)
        _ = await perform(.filament(sample, .openSpool, cardUID: nil), on: gateway)
        let pages = gateway.writes.first ?? []
        #expect(pages.first?.page == 3)
        #expect(pages.first?.data == Data([0xE1, 0x10, 0x3E, 0x00]))
    }

    @Test func aFormattedTagKeepsItsCapabilityContainer() async {
        let gateway = FakeGateway.ntag215()
        _ = await perform(.filament(sample, .openSpool, cardUID: nil), on: gateway)
        #expect(gateway.writes.first?.contains { $0.page == 3 } == false)
    }

    @Test func aBlankTagOfUnknownTypeIsNotFormatted() async {
        // Page 3 is one-time programmable: with no GET_VERSION answer the geometry
        // would be a zero-size container, so nothing may be sent.
        let gateway = FakeGateway.unformatted()
        gateway.versionReply = nil
        let outcome = await perform(.filament(sample, .openSpool, cardUID: nil), on: gateway)
        #expect(outcome == .refused(message: PrinterTagSession.unidentifiedBlankTagMessage))
        #expect(gateway.writes.isEmpty)

        // With the chip identified the same blank tag is formatted, capability container first.
        let identified = FakeGateway.ntag215(formatted: false)
        _ = await perform(.filament(sample, .openSpool, cardUID: nil), on: identified)
        #expect(identified.writes.first?.first?.page == 3)
    }

    @Test func theFakeGatewayRefusesAWrongExpectedUIDLikeThePlugin() async {
        let gateway = FakeGateway.ntag215()
        let pages = [(page: 4, data: Data([1, 2, 3, 4]))]
        #expect(await gateway.writeTag(toolhead: 1, expectedUID: "AABBCCDDEEFF00", pages: pages,
                                       password: nil, allowConfig: false) == .failure(.uidMismatch))
        #expect(await gateway.readTag(toolhead: 1, expectedUID: "AABBCCDDEEFF00") == .failure(.uidMismatch))
        gateway.uid = "A1B2C3D4"
        guard case .failure(.unsupportedTag) = await gateway.readTag(toolhead: 1, expectedUID: nil) else {
            Issue.record("a 4-byte tag must be unsupported"); return
        }
    }

    @Test func aSkippedCapabilityContainerPageIsNotCounted() async {
        let gateway = FakeGateway.ntag215()
        let held = Data(gateway.memory[12..<16])
        let result = await gateway.writeTag(
            toolhead: 1, expectedUID: gateway.uid,
            pages: [(page: 3, data: held), (page: 4, data: Data([1, 2, 3, 4]))], password: nil, allowConfig: false)
        #expect(result == .success(1))
    }

    @Test func writeThatDoesNotFitIsRefusedAndWritesNothing() async {
        let gateway = FakeGateway.unformatted()
        gateway.versionReply = nil
        gateway.memory[12..<16] = [0xE1, 0x10, 0x06, 0x00]   // 48 bytes of user memory
        let outcome = await perform(.filament(sample, .openSpool, cardUID: nil), on: gateway)
        guard case .refused(let message) = outcome else { Issue.record("expected a refusal"); return }
        #expect(message.hasPrefix("Tag is too small. Needs "))
        #expect(gateway.writes.isEmpty)
    }

    @Test func writeToBlockedUIDIsRefused() async {
        let gateway = FakeGateway.ntag215()
        let outcome = await perform(.filament(sample, .openSpool, cardUID: nil), on: gateway, blocked: ["04a1b2c3d4e5f6"])
        #expect(outcome == .blocked(uid: "04A1B2C3D4E5F6"))
        #expect(gateway.writes.isEmpty)
    }

    @Test func aRawFormatWritesItsPagesHighestFirst() async {
        let gateway = FakeGateway.blankNTAG213()
        let outcome = await perform(.filament(sample, .anycubicACE, cardUID: nil), on: gateway)
        #expect(outcome == .written(uid: "04a1b2c3d4e5f6"))
        #expect(gateway.writes.first?.map(\.page) == Array((4...31).reversed()))
    }

    @Test func aFactoryPasswordProtectedTagIsRefusedForACE() async {
        let gateway = FakeGateway.blankNTAG213()
        gateway.memory[41 * 4 + 3] = 0x04   // AUTH0 = 4
        let outcome = await perform(.filament(sample, .anycubicACE, cardUID: nil), on: gateway)
        guard case .refused(let message) = outcome else { Issue.record("expected a refusal"); return }
        #expect(message.hasPrefix("This tag is password-protected, as factory Anycubic tags are."))
        #expect(gateway.writes.isEmpty)
    }

    @Test func aFourByteUIDIsRefusedForEveryWriteKind() async {
        let snapshot = TagSnapshot.rawPages(firstPage: 4, bytes: [1, 2, 3, 4])
        let writes: [NFCManager.PendingWrite] = [
            .filament(sample, .openSpool, cardUID: nil),
            .clear(expectedUID: nil),
            .clone(snapshot, sourceUID: "AABBCCDD", blockedUIDs: [], allowedUID: nil),
        ]
        for write in writes {
            // The printer reports the tag's UID; the plugin would refuse to read it.
            let gateway = FakeGateway.ntag215()
            gateway.uid = "A1B2C3D4"
            gateway.toolheads = [ToolheadState(
                index: 1, material: "PLA", colorHexes: ["FF0000"], alpha: 255, isLoaded: true, isOfficial: false,
                tagUID: "A1B2C3D4")]
            #expect(await perform(write, on: gateway) == .refused(message: "This tag type can't be written by the printer."))
            #expect(gateway.writes.isEmpty)
        }

        let official = FakeGateway.ntag215()
        official.uid = "A1B2C3D4"
        official.toolheads = [ToolheadState(
            index: 1, material: "PLA", colorHexes: ["FF0000"], alpha: 255, isLoaded: true, isOfficial: true,
            tagUID: "A1B2C3D4")]
        #expect(await perform(.clear(expectedUID: nil), on: official) == .refused(message: "Snapmaker tags can't be rewritten."))
        #expect(official.writes.isEmpty)
    }

    @Test func clearWritesWhatTheIPhonePathWouldWrite() async {
        // NDEF: one empty record, TLV-wrapped.
        let ndef = FakeGateway.blankNTAG213()
        let outcome = await perform(.clear(expectedUID: "04A1B2C3D4E5F6"), on: ndef)
        #expect(outcome == .written(uid: "04a1b2c3d4e5f6"))
        #expect(ndef.writes.first?.map(\.page) == [4, 5])
        #expect(ndef.writes.first?.map(\.data) == [Data([0x03, 0x03, 0xD0, 0x00]), Data([0x00, 0xFE, 0x00, 0x00])])

        // Raw: the scan's pages zeroed, highest first.
        let raw = FakeGateway.blankNTAG213()
        _ = await perform(.clear(expectedUID: nil, zeroPages: [4, 5, 6]), on: raw)
        #expect(raw.writes.first?.map(\.page) == [6, 5, 4])
        #expect(raw.writes.first?.allSatisfy { $0.data == Data(repeating: 0, count: 4) } == true)

        // A different tag is refused, nothing written.
        let other = FakeGateway.blankNTAG213()
        #expect(await perform(.clear(expectedUID: "AABBCCDD"), on: other) == .wrongTag(uid: "04a1b2c3d4e5f6"))
        #expect(other.writes.isEmpty)
    }

    @Test func cloneOfRawSnapshotWritesItsPagesInOrder() async {
        let gateway = FakeGateway.blankNTAG213()
        let snapshot = TagSnapshot.rawPages(firstPage: 4, bytes: [
            0x7B, 0x00, 0x65, 0x00, 0x41, 0x48, 0x50, 0x4C, 0x56, 0x4F, 0x2D, 0x31])
        let outcome = await perform(
            .clone(snapshot, sourceUID: "AABBCCDD", blockedUIDs: [], allowedUID: nil), on: gateway)
        #expect(outcome == .written(uid: "04a1b2c3d4e5f6"))
        #expect(gateway.writes.first?.map(\.page) == [6, 5, 4])
        #expect(gateway.writes.first?.first?.data == Data([0x56, 0x4F, 0x2D, 0x31]))
    }

    @Test func cloneRefusesTheSourceTagAndABlockedOne() async {
        let snapshot = TagSnapshot.rawPages(firstPage: 4, bytes: [1, 2, 3, 4])
        let same = FakeGateway.blankNTAG213()
        #expect(await perform(.clone(snapshot, sourceUID: "04A1B2C3D4E5F6", blockedUIDs: [], allowedUID: nil), on: same) == .sameTag)
        let blocked = FakeGateway.blankNTAG213()
        #expect(await perform(.clone(snapshot, sourceUID: "AABBCCDD", blockedUIDs: ["04A1B2C3D4E5F6"], allowedUID: nil), on: blocked)
                == .blocked(uid: "04A1B2C3D4E5F6"))
        #expect(same.writes.isEmpty && blocked.writes.isEmpty)
    }

    @Test func partialWriteUsesTheExistingFailureWording() async {
        let gateway = FakeGateway.blankNTAG213()
        gateway.writeFailure = .writeFailed(pagesWritten: 5)
        let outcome = await perform(.filament(sample, .anycubicACE, cardUID: nil), on: gateway)
        let total = gateway.writes.first?.count ?? 0
        #expect(total == 28)
        #expect(outcome == .failed(message: NFCManager.rawWriteFailureMessage(
            pagesWritten: 5, totalPages: total, cause: PrinterTagError.writeFailed(pagesWritten: 5).message(toolhead: 1))))
        #expect(outcome == .failed(message: "The write was cut short after 5 of 28 pages, so the tag is only partly written. Write it again."))
    }

    @Test func aToolheadOperationLeavesFlowEventsWithThePluginsCodeAndNoTagContent() async {
        let gateway = FakeGateway.ntag215()
        gateway.writeFailure = .writeFailed(pagesWritten: 3)
        _ = await PrinterTagSession(gateway: gateway, toolhead: 7)
            .perform(.filament(sample, .openSpool, cardUID: nil), blockedUIDs: [])

        let events = WorkflowTraceStore.shared.exportEvents()
            .filter { $0.path == "printer-nfc" && $0.details["toolhead"] == "7" }
        #expect(events.map(\.step) == ["write-openspool.start", "write.error", "write-openspool.end"])
        #expect(events[1].details["code"] == "write_failed")
        #expect(events[1].details["pagesWritten"] == "3")
        #expect(events[2].details["outcome"] == "failed")
        let everything = events.flatMap { $0.details.values }.joined()
        #expect(!everything.contains("ELEGOO") && !everything.contains("04A1B2"))
    }

    @Test func connectionLostNamesAPossiblyPartialTag() async {
        let gateway = FakeGateway.ntag215()
        gateway.writeFailure = .connectionLost(pagesWritten: 3)
        let outcome = await perform(.filament(sample, .openSpool, cardUID: nil), on: gateway)
        #expect(outcome == .failed(message: "The printer stopped answering. The tag may be partly written. Read it again before trusting it."))
    }
}

/// `NFCManager`'s reader parameter: the printer path publishes through the same properties.
/// Serialized: the tests share the static `NFCManager.printerTagGateway`.
@Suite(.serialized) @MainActor struct NFCToolheadReaderTests {

    private func waitUntilIdle(_ manager: NFCManager) async {
        for _ in 0..<300 where manager.isScanning {
            try? await Task.sleep(for: .milliseconds(10))
        }
        await Task.yield()
    }

    /// A filament write that succeeds records in the host app's tag ledger
    /// (`TagAssociationStore.shared`, no seam), so the published properties are
    /// checked here through the paths that never reach it: clear, clone, and a
    /// failed filament write. The success outcome itself is pinned in the session tests.
    @Test func toolheadReaderPublishesThroughTheSameProperties() async {
        let gateway = FakeGateway.ntag215()
        NFCManager.printerTagGateway = gateway
        defer { NFCManager.printerTagGateway = nil }
        let manager = NFCManager()

        manager.clearTag(expectedUID: "04A1B2C3D4E5F6", reader: .toolhead(1))
        #expect(manager.isScanning)
        await waitUntilIdle(manager)
        #expect(manager.lastTagClear == .cleared(uid: "04a1b2c3d4e5f6"))
        #expect(!manager.isScanning)

        manager.cloneTag(TagSnapshot.rawPages(firstPage: 4, bytes: [1, 2, 3, 4]), sourceUID: "AABBCCDD",
                         blockedUIDs: [], allowedUID: nil, reader: .toolhead(1))
        await waitUntilIdle(manager)
        #expect(manager.lastClone == .written(uid: "04A1B2C3D4E5F6"))

        gateway.writeFailure = .connectionLost(pagesWritten: 0)
        manager.writeTag(data: sample, format: .openSpool, reader: .toolhead(1))
        await waitUntilIdle(manager)
        #expect(!manager.lastWriteSucceeded)
        #expect(manager.lastWrittenTagUID == nil)
        #expect(manager.alertMessage == PrinterTagError.connectionLost(pagesWritten: 0).message(toolhead: 1))
    }

    @Test func aRejectedLocationTagCarriesItsResultAndMessage() async throws {
        let gateway = FakeGateway.ntag215()
        let location = LocationTagPayload(uuid: UUID(), name: "Shelf A")
        install([NDEFRecordSnapshot(
            typeNameFormat: 2, type: Data(LocationTagPayload.mimeType.utf8), identifier: Data(),
            payload: try #require(location.encoded()))], on: gateway)
        NFCManager.printerTagGateway = gateway
        defer { NFCManager.printerTagGateway = nil }
        let manager = NFCManager()

        manager.startScanning(rejectingLocationTags: true, reader: .toolhead(1))
        await waitUntilIdle(manager)

        #expect(manager.scanResult?.locationTag == location)
        #expect(manager.alertMessage == "This tag labels Shelf A.")
    }

    @Test func aSecondOperationWhileOneRunsIsIgnored() async {
        let gateway = FakeGateway.ntag215()
        NFCManager.printerTagGateway = gateway
        defer { NFCManager.printerTagGateway = nil }
        let manager = NFCManager()

        manager.startScanning(reader: .toolhead(1))
        manager.writeTag(data: sample, format: .openSpool, reader: .toolhead(1))
        manager.startScanning(reader: .toolhead(2))
        await waitUntilIdle(manager)

        #expect(gateway.readCalls == 1)
        #expect(gateway.writes.isEmpty)
        #expect(!manager.lastWriteSucceeded)
        #expect(manager.scanResult != nil)
    }

    @Test func aToolheadWithNoPrinterNeverFallsBackToTheIPhone() async {
        NFCManager.printerTagGateway = nil
        let manager = NFCManager()
        manager.startScanning(reader: .toolhead(0))
        #expect(manager.alertMessage == "No printer is connected.")
        #expect(!manager.isScanning)
    }

    @Test func defaultReaderIsIPhone() {
        let gateway = FakeGateway.blankNTAG213()
        NFCManager.printerTagGateway = gateway
        defer { NFCManager.printerTagGateway = nil }
        let manager = NFCManager()

        manager.startScanning()
        manager.writeTag(data: sample, format: .openSpool)

        #expect(gateway.readCalls == 0)
        #expect(gateway.writes.isEmpty)
    }
}
