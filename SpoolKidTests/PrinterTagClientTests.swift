//
//  PrinterTagClientTests.swift
//  SpoolKidTests
//
//  The plugin client against a scripted transport. No printer is contacted.
//

import Testing
import Foundation
@testable import SpoolKid

/// Answers each call with the next scripted step, and records every call.
@MainActor
private final class ScriptedTransport: PrinterTransport {
    enum Step {
        case reply(Any)
        case failure(Error)
    }

    var onNotification: ((String, [Any]) -> Void)?
    var onClosed: (() -> Void)?
    private var steps: [Step]
    private(set) var calls: [(method: String, params: [String: Any])] = []
    private(set) var timeouts: [Duration?] = []

    init(steps: [Step]) {
        self.steps = steps
    }

    func call(_ method: String, params: [String: Any], timeout: Duration) async throws -> MoonrakerValue {
        timeouts.append(timeout)
        return try await call(method, params: params)
    }

    func call(_ method: String, params: [String: Any]) async throws -> MoonrakerValue {
        calls.append((method, params))
        guard !steps.isEmpty else { throw MoonrakerError.timedOut }
        switch steps.removeFirst() {
        case .reply(let value): return MoonrakerValue(value: value)
        case .failure(let error): throw error
        }
    }

    func close() {}
}

private func okWrite(pagesWritten: Int) -> ScriptedTransport.Step {
    .reply(["ok": true, "uid": "04a1b2c3d4e5f6", "pages_written": pagesWritten, "verified": true])
}

private func failedReply(code: String, pagesWritten: Int) -> ScriptedTransport.Step {
    .reply(["ok": false, "error": ["code": code, "message": "plugin says \(code)", "pages_written": pagesWritten]])
}

private func pages(_ count: Int) -> [(page: Int, data: Data)] {
    (0..<count).map { (page: 4 + $0, data: Data([0x01, 0x02, 0x03, UInt8($0 & 0xFF)])) }
}

@Suite struct PrinterTagClientTests {

@Test @MainActor func readDecodesPagesVersionAndGeometry() async {
    let version = "0004040201001103"
    let transport = ScriptedTransport(steps: [.reply([
        "ok": true,
        "uid": "04a1b2c3d4e5f6",
        "first_page": 0,
        "pages": "04a1b2c3" + "d4e5f600" + "00000000" + "e1100f00" + "00000000",
        "version": version,
        "last_user_page": 129,
        "total_pages": 135,
    ])])

    let result = await PrinterTagClient.read(transport: transport, toolhead: 2, expectedUID: nil)

    let versionBytes: [UInt8] = [0x00, 0x04, 0x04, 0x02, 0x01, 0x00, 0x11, 0x03]
    let expected = PrinterTagRead(
        uid: "04A1B2C3D4E5F6",
        firstPage: 0,
        bytes: [0x04, 0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6, 0x00, 0, 0, 0, 0, 0xE1, 0x10, 0x0F, 0x00, 0, 0, 0, 0],
        versionReply: versionBytes,
        geometry: Type2Geometry(versionReply: versionBytes, capabilityContainer: [0xE1, 0x10, 0x0F, 0x00])
    )
    #expect(result == .success(expected))
    #expect(transport.calls.count == 1)
    #expect(transport.calls.first?.method == "printer.spoolkid_rfid.read")
    #expect(transport.calls.first?.params["toolhead"] as? Int == 2)
    #expect(transport.calls.first?.params["expected_uid"] == nil)
}

@Test @MainActor func readFailureCarriesThePluginsCode() async {
    let transport = ScriptedTransport(steps: [failedReply(code: "no_tag", pagesWritten: 0)])

    let result = await PrinterTagClient.read(transport: transport, toolhead: 0, expectedUID: nil)

    #expect(result == .failure(.noTag))
}

@Test @MainActor func shortWriteIsOneCall() async {
    let transport = ScriptedTransport(steps: [okWrite(pagesWritten: 3)])

    let result = await PrinterTagClient.write(
        transport: transport, toolhead: 1, expectedUID: "04:A1:B2:C3:D4:E5:F6",
        pages: [(page: 4, data: Data([0x01, 0x02, 0x03, 0x04])), (page: 5, data: Data([0xAA, 0xBB, 0xCC, 0xDD])), (page: 6, data: Data([0, 0, 0, 0]))],
        password: nil, allowConfig: false
    )

    #expect(result == .success(3))
    #expect(transport.calls.count == 1)
    let params = transport.calls.first?.params ?? [:]
    #expect(transport.calls.first?.method == "printer.spoolkid_rfid.write")
    #expect(params["toolhead"] as? Int == 1)
    #expect(params["expected_uid"] as? String == "04a1b2c3d4e5f6")
    let sent = params["pages"] as? [[String: Any]] ?? []
    #expect(sent.count == 3)
    #expect(sent.first?["page"] as? Int == 4)
    #expect(sent.first?["data"] as? String == "01020304")
    #expect(sent[1]["data"] as? String == "aabbccdd")
}

@Test @MainActor func longWriteIsSplitIntoChunksOf64InOrder() async {
    let transport = ScriptedTransport(steps: [okWrite(pagesWritten: 64), okWrite(pagesWritten: 64), okWrite(pagesWritten: 22)])

    let result = await PrinterTagClient.write(
        transport: transport, toolhead: 0, expectedUID: "04a1b2c3d4e5f6",
        pages: pages(150), password: nil, allowConfig: false
    )

    #expect(result == .success(150))
    #expect(transport.calls.map { ($0.params["pages"] as? [[String: Any]])?.count } == [64, 64, 22])
    let sentPages = transport.calls.flatMap { ($0.params["pages"] as? [[String: Any]] ?? []).compactMap { $0["page"] as? Int } }
    #expect(sentPages == Array(4..<154))
}

@Test @MainActor func secondChunkFailureStopsAndReportsTotalPagesWritten() async {
    let transport = ScriptedTransport(steps: [okWrite(pagesWritten: 64), failedReply(code: "write_failed", pagesWritten: 10)])

    let result = await PrinterTagClient.write(
        transport: transport, toolhead: 0, expectedUID: "04a1b2c3d4e5f6",
        pages: pages(150), password: nil, allowConfig: false
    )

    #expect(result == .failure(.writeFailed(pagesWritten: 74)))
    #expect(transport.calls.count == 2)
}

@Test @MainActor func transportErrorMidWriteIsConnectionLost() async {
    let transport = ScriptedTransport(steps: [okWrite(pagesWritten: 64), .failure(MoonrakerError.timedOut)])

    let result = await PrinterTagClient.write(
        transport: transport, toolhead: 0, expectedUID: "04a1b2c3d4e5f6",
        pages: pages(150), password: nil, allowConfig: false
    )

    #expect(result == .failure(.connectionLost(pagesWritten: 64)))
    #expect(transport.calls.count == 2)
}

@Test @MainActor func unverifiedOkReplyIsNotSuccess() async {
    let transport = ScriptedTransport(steps: [.reply(["ok": true, "uid": "04a1b2c3d4e5f6", "pages_written": 3])])

    let result = await PrinterTagClient.write(
        transport: transport, toolhead: 0, expectedUID: "04a1b2c3d4e5f6",
        pages: pages(3), password: nil, allowConfig: false
    )

    #expect(result == .failure(.verifyFailed(pagesWritten: 0)))
}

@Test @MainActor func unverifiedSecondChunkCountsOnlyTheVerifiedFirstChunk() async {
    let transport = ScriptedTransport(steps: [okWrite(pagesWritten: 64), .reply(["ok": true, "pages_written": 10])])

    let result = await PrinterTagClient.write(
        transport: transport, toolhead: 0, expectedUID: "04a1b2c3d4e5f6",
        pages: pages(150), password: nil, allowConfig: false
    )

    #expect(result == .failure(.verifyFailed(pagesWritten: 64)))
    #expect(transport.calls.count == 2)
}

@Test @MainActor func successCountsWhatThePluginReports() async {
    let transport = ScriptedTransport(steps: [okWrite(pagesWritten: 63)])

    let result = await PrinterTagClient.write(
        transport: transport, toolhead: 0, expectedUID: "04a1b2c3d4e5f6",
        pages: pages(64), password: nil, allowConfig: false
    )

    #expect(result == .success(63))
}

@Test @MainActor func okReplyWithoutAPageCountIsNotSuccess() async {
    let transport = ScriptedTransport(steps: [.reply(["ok": true, "uid": "04a1b2c3d4e5f6", "verified": true])])

    let result = await PrinterTagClient.write(
        transport: transport, toolhead: 0, expectedUID: "04a1b2c3d4e5f6",
        pages: pages(3), password: nil, allowConfig: false
    )

    #expect(result == .failure(.verifyFailed(pagesWritten: 0)))
}

@Test @MainActor func okReplyClaimingMorePagesThanSentIsNotSuccess() async {
    let transport = ScriptedTransport(steps: [okWrite(pagesWritten: 5)])

    let result = await PrinterTagClient.write(
        transport: transport, toolhead: 0, expectedUID: "04a1b2c3d4e5f6",
        pages: pages(3), password: nil, allowConfig: false
    )

    #expect(result == .failure(.verifyFailed(pagesWritten: 0)))
}

@Test @MainActor func pluginErrorOnSecondChunkKeepsItsOwnCode() async {
    let transport = ScriptedTransport(steps: [okWrite(pagesWritten: 64), failedReply(code: "protected_page", pagesWritten: 0)])

    let result = await PrinterTagClient.write(
        transport: transport, toolhead: 0, expectedUID: "04a1b2c3d4e5f6",
        pages: pages(150), password: nil, allowConfig: false
    )

    #expect(result == .failure(.protectedPage))
    #expect(transport.calls.count == 2)
}

@Test @MainActor func emptyWriteIsRefusedWithoutACall() async {
    let transport = ScriptedTransport(steps: [])

    let result = await PrinterTagClient.write(
        transport: transport, toolhead: 0, expectedUID: "04a1b2c3d4e5f6",
        pages: [], password: nil, allowConfig: false
    )

    #expect(result == .failure(.badRequest("Nothing to write.")))
    #expect(transport.calls.isEmpty)
}

@Test @MainActor func passwordAndAllowConfigAreSentOnlyWhenSet() async {
    let unset = ScriptedTransport(steps: [okWrite(pagesWritten: 1)])
    _ = await PrinterTagClient.write(
        transport: unset, toolhead: 0, expectedUID: "04a1b2c3d4e5f6",
        pages: pages(1), password: nil, allowConfig: false
    )
    #expect(unset.calls.first?.params["password"] == nil)
    #expect(unset.calls.first?.params["allow_config"] == nil)

    let set = ScriptedTransport(steps: [okWrite(pagesWritten: 1)])
    _ = await PrinterTagClient.write(
        transport: set, toolhead: 0, expectedUID: "04a1b2c3d4e5f6",
        pages: pages(1), password: Data([0xAB, 0xCD, 0xEF, 0x01]), allowConfig: true
    )
    #expect(set.calls.first?.params["password"] as? String == "abcdef01")
    #expect(set.calls.first?.params["allow_config"] as? Bool == true)
}

@Test @MainActor func notConnectedIsConnectionLostBeforeAnyCall() async {
    let read = await PrinterTagClient.read(transport: nil, toolhead: 0, expectedUID: nil)
    let write = await PrinterTagClient.write(
        transport: nil, toolhead: 0, expectedUID: "04a1b2c3d4e5f6",
        pages: pages(1), password: nil, allowConfig: false
    )

    #expect(read == .failure(.connectionLost(pagesWritten: 0)))
    #expect(write == .failure(.connectionLost(pagesWritten: 0)))
}

@Test @MainActor func aRejectionBeforeAnyChunkIsTheMoonrakerTextNotALostConnection() async {
    let read = ScriptedTransport(steps: [.failure(MoonrakerError.rejected("Method not found"))])
    #expect(await PrinterTagClient.read(transport: read, toolhead: 0, expectedUID: nil)
            == .failure(.badRequest("Method not found")))

    let write = ScriptedTransport(steps: [.failure(MoonrakerError.unauthorized("Unauthorized"))])
    let result = await PrinterTagClient.write(
        transport: write, toolhead: 0, expectedUID: "04a1b2c3d4e5f6", pages: pages(3), password: nil, allowConfig: false)
    #expect(result == .failure(.badRequest("Unauthorized")))
}

@Test @MainActor func aRejectionAfterAConfirmedChunkIsAPartialWrite() async {
    let transport = ScriptedTransport(steps: [okWrite(pagesWritten: 64), .failure(MoonrakerError.rejected("nope"))])
    let result = await PrinterTagClient.write(
        transport: transport, toolhead: 0, expectedUID: "04a1b2c3d4e5f6", pages: pages(150), password: nil, allowConfig: false)
    #expect(result == .failure(.writeFailed(pagesWritten: 64)))
}

@Test @MainActor func aClosedSocketIsStillConnectionLost() async {
    let transport = ScriptedTransport(steps: [.failure(MoonrakerError.notConnected)])
    #expect(await PrinterTagClient.read(transport: transport, toolhead: 0, expectedUID: nil)
            == .failure(.connectionLost(pagesWritten: 0)))
}

@Test @MainActor func bothPluginCallsAskForTheLongerTimeout() async {
    let transport = ScriptedTransport(steps: [
        failedReply(code: "no_tag", pagesWritten: 0), okWrite(pagesWritten: 1), okWrite(pagesWritten: 1)])
    _ = await PrinterTagClient.read(transport: transport, toolhead: 0, expectedUID: nil)
    _ = await PrinterTagClient.write(
        transport: transport, toolhead: 0, expectedUID: "04a1b2c3d4e5f6", pages: pages(65), password: nil, allowConfig: false)
    #expect(transport.timeouts == [.seconds(35), .seconds(35), .seconds(35)])
}
}
