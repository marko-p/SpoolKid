//
//  PrinterTagSession.swift
//  SpoolKid
//
//  Purpose: A scan, dump, write, clear or clone of a tag through a U1
//  toolhead's reader. The printer's plugin moves raw pages; everything that
//  decides what those pages mean or whether a write may go ahead is the
//  iPhone path's own pure code (decoders, encoders, `NFCManager`'s guards and
//  messages), reused here so both readers give the same answer for the same tag.
//
//  Read side: PrinterTagSession+Read.swift. Write side: PrinterTagSession+Write.swift.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import os

private let logger = Logger(subsystem: "com.spoolkid", category: "PrinterTagSession")

nonisolated enum PrinterScanOutcome: Sendable {
    case result(ScanResult)
    /// A rejected location tag still carries its result.
    case refused(message: String, result: ScanResult?)
    case failed(PrinterTagError)
}

nonisolated enum PrinterWriteOutcome: Equatable, Sendable {
    case written(uid: String)
    case refused(message: String)
    case failed(message: String)
    /// A clear met a different tag than the one it was meant for.
    case wrongTag(uid: String)
    /// The tag belongs to something else (a clone's, or a write's, blocked UIDs).
    case blocked(uid: String)
    /// A clone met the tag it was scanned from.
    case sameTag
}

extension PrinterScanOutcome {
    /// For flow telemetry: no tag content, only what kind of ending it was.
    nonisolated var traceName: String {
        switch self {
        case .result(let result): result.isReportedByPrinter ? "ok-reported" : "ok"
        case .refused: "refused"
        case .failed: "failed"
        }
    }
}

extension PrinterWriteOutcome {
    nonisolated var traceName: String {
        switch self {
        case .written: "written"
        case .refused: "refused"
        case .failed: "failed"
        case .wrongTag: "wrong-tag"
        case .blocked: "blocked"
        case .sameTag: "same-tag"
        }
    }
}

@MainActor
final class PrinterTagSession {
    let gateway: PrinterTagGateway
    let toolhead: Int
    /// Used only for its pure helpers (record and dump naming); it opens no session.
    let nfc = NFCManager()

    /// What the printer reports for the toolhead is read from `gateway.toolheads`.
    init(gateway: PrinterTagGateway, toolhead: Int) {
        self.gateway = gateway
        self.toolhead = toolhead
    }

    // MARK: - Telemetry

    /// A flow event for this toolhead. Never carries tag content, UIDs or secrets.
    func trace(_ step: String, _ details: [String: String] = [:]) {
        var all = details
        all["toolhead"] = String(toolhead)
        WorkflowTraceStore.log(path: "printer-nfc", step: step, details: all)
    }

    /// Reads the tag through the gateway, recording a failure's plugin code.
    func fetch() async -> Result<PrinterTagRead, PrinterTagError> {
        let result = await gateway.readTag(toolhead: toolhead, expectedUID: nil)
        if case .failure(let error) = result { traceFailure("read", error) }
        return result
    }

    func traceFailure(_ operation: String, _ error: PrinterTagError, pagesTotal: Int? = nil) {
        var details = ["code": error.code]
        if let pagesTotal { details["pagesTotal"] = String(pagesTotal) }
        switch error {
        case .writeFailed(let pages), .verifyFailed(let pages), .connectionLost(let pages):
            details["pagesWritten"] = String(pages)
        default: break
        }
        trace("\(operation).error", details)
        logger.error("Toolhead \(self.toolhead) \(operation) failed: \(error.code, privacy: .public)")
    }

    // MARK: - Shared

    /// Why the plugin cannot be used right now, nil when it can.
    static func notReadyError(for plugin: PrinterTagPlugin) -> PrinterTagError? {
        switch plugin {
        case .ready: nil
        case .notReady(let reason): .notReady(reason)
        case .notInstalled: .notReady("The SpoolKid RFID Writer plugin is not installed on the printer.")
        case .needsAppUpdate: .notReady("The printer's SpoolKid RFID Writer needs a newer SpoolKid.")
        }
    }

    var notReadyError: PrinterTagError? { Self.notReadyError(for: gateway.tagPlugin) }

    var reportedToolhead: ToolheadState? { gateway.toolheads.first { $0.index == toolhead } }

    /// The tag's memory from page 0, padded with zeros when the read began later.
    func memory(of read: PrinterTagRead) -> [UInt8] {
        [UInt8](repeating: 0, count: read.firstPage * 4) + read.bytes
    }

    /// The hardware UID as the iPhone path reports it: lowercase hex.
    func hardwareUID(of read: PrinterTagRead) -> String { read.uid.lowercased() }

    /// The chip's page count when GET_VERSION named a known NTAG.
    func knownPageCount(of read: PrinterTagRead) -> Int? {
        read.versionReply.flatMap { TagDumpWalk.pageCount(forVersionResponse: $0) }
    }

    /// Pages 0-3, the iPhone path's `readHeaderAllowsWrite` input.
    func header(of memory: [UInt8]) -> Data? {
        memory.count >= 16 ? Data(memory[0..<16]) : nil
    }

    /// CFG0, CFG1, PWD and PACK: they sit four pages before the chip's end,
    /// which is six past the last user page on NTAG213, 215 and 216.
    func configRead(of memory: [UInt8], geometry: Type2Geometry) -> Data? {
        let start = (geometry.lastUserPage + 2) * 4
        return start + 16 <= memory.count ? Data(memory[start..<start + 16]) : nil
    }

    /// What the iPhone path's pre-write reads decide, from the printer's read:
    /// static locks, then a password. Nil when the write may go ahead; a read
    /// that does not answer clearly lets the write proceed, as on the iPhone.
    func writeBlock(read: PrinterTagRead, memory: [UInt8], throughPage lastPage: Int) -> NFCManager.RawWriteRefusal? {
        if let header = header(of: memory), NFCManager.rawWriteHeaderAllowsWrite(header) == false {
            return .locked
        }
        if let config = configRead(of: memory, geometry: read.geometry),
           NFCManager.writeNeedsPassword(configRead: config, throughPage: lastPage) == true {
            return .passwordProtected
        }
        return nil
    }

    /// The message budget for an NDEF message on this tag, after the TLV's
    /// header and terminator.
    func ndefCapacity(_ geometry: Type2Geometry) -> Int {
        let room = geometry.userByteCapacity
        return room - 3 < 255 ? room - 3 : room - 5
    }

    func uidBytes(_ hex: String) -> [UInt8] {
        let characters = Array(hex)
        return stride(from: 0, to: characters.count - 1, by: 2).compactMap {
            UInt8(String(characters[$0...$0 + 1]), radix: 16)
        }
    }
}
