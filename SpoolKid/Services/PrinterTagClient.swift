//
//  PrinterTagClient.swift
//  SpoolKid
//
//  Purpose: The client for the SpoolKid RFID Writer plugin's read and write
//  endpoints, over the printer's Moonraker transport. Requests and replies are
//  built and decoded here; writes go in chunks of 64 pages and count only the
//  pages the plugin confirmed.
//
//  Copyright (c) 2026 Marko Praprotnik. All rights reserved.
//  Licensed under the MIT License.
//  See LICENSE in the project root for details.
//

import Foundation

/// A tag as the plugin read it.
nonisolated struct PrinterTagRead: Equatable, Sendable {
    let uid: String
    let firstPage: Int
    let bytes: [UInt8]
    let versionReply: [UInt8]?
    let geometry: Type2Geometry
}

/// What the printer-backed tag operations need from a printer. `PrinterService`
/// conforms; tests can stand in for it.
@MainActor
protocol PrinterTagGateway: AnyObject {
    var tagPlugin: PrinterTagPlugin { get }
    var toolheads: [ToolheadState] { get }
    func readTag(toolhead: Int, expectedUID: String?) async -> Result<PrinterTagRead, PrinterTagError>
    /// `.success(n)` means every requested page now holds its requested bytes and was
    /// verified. `n` can be smaller than `pages.count`, because the plugin skips a
    /// capability-container page that already held the right bytes, so never compare
    /// `n` with the page count to decide success.
    func writeTag(toolhead: Int, expectedUID: String, pages: [(page: Int, data: Data)],
                  password: Data?, allowConfig: Bool) async -> Result<Int, PrinterTagError>
}

nonisolated enum PrinterTagClient {
    static let readMethod = "printer.spoolkid_rfid.read"
    static let writeMethod = "printer.spoolkid_rfid.write"
    /// Pages sent per write call. A write stops at the first call that fails.
    static let pagesPerWriteCall = 64
    /// Longer than the socket's default: a claimed write can take about 30 s on the plugin.
    static let callTimeout: Duration = .seconds(35)

    @MainActor
    static func read(transport: PrinterTransport?, toolhead: Int, expectedUID: String?) async -> Result<PrinterTagRead, PrinterTagError> {
        guard let transport else { return .failure(.connectionLost(pagesWritten: 0)) }
        do {
            let reply = try await transport.call(
                readMethod, params: readParams(toolhead: toolhead, expectedUID: expectedUID), timeout: callTimeout)
            return decodeRead(reply: reply.value)
        } catch {
            return .failure(callFailure(error, confirmed: 0))
        }
    }

    @MainActor
    static func write(transport: PrinterTransport?, toolhead: Int, expectedUID: String,
                      pages: [(page: Int, data: Data)], password: Data?, allowConfig: Bool) async -> Result<Int, PrinterTagError> {
        guard !pages.isEmpty else { return .failure(.badRequest("Nothing to write.")) }
        guard let transport else { return .failure(.connectionLost(pagesWritten: 0)) }
        var confirmed = 0
        for start in stride(from: 0, to: pages.count, by: pagesPerWriteCall) {
            let chunk = Array(pages[start..<min(start + pagesPerWriteCall, pages.count)])
            let params = writeParams(toolhead: toolhead, expectedUID: expectedUID, pages: chunk,
                                     password: password, allowConfig: allowConfig)
            let reply: MoonrakerValue
            do {
                reply = try await transport.call(writeMethod, params: params, timeout: callTimeout)
            } catch {
                return .failure(callFailure(error, confirmed: confirmed))
            }
            guard let object = reply.value as? [String: Any] else {
                return .failure(.connectionLost(pagesWritten: confirmed))
            }
            if object["ok"] as? Bool != true {
                let error = object["error"] as? [String: Any] ?? [:]
                return .failure(total(PrinterTagError(reply: error), confirmedBefore: confirmed))
            }
            // The plugin may write fewer pages than sent (it skips a capability
            // container page that already holds the bytes), never more.
            guard object["verified"] as? Bool == true,
                  let reported = object["pages_written"] as? Int,
                  (0...chunk.count).contains(reported) else {
                return .failure(.verifyFailed(pagesWritten: confirmed))
            }
            confirmed += reported
        }
        return .success(confirmed)
    }

    // MARK: Requests

    static func readParams(toolhead: Int, expectedUID: String?) -> [String: Any] {
        var params: [String: Any] = ["toolhead": toolhead]
        if let expectedUID { params["expected_uid"] = normalizedUIDForPlugin(expectedUID) }
        return params
    }

    static func writeParams(toolhead: Int, expectedUID: String, pages: [(page: Int, data: Data)],
                            password: Data?, allowConfig: Bool) -> [String: Any] {
        var params: [String: Any] = [
            "toolhead": toolhead,
            "expected_uid": normalizedUIDForPlugin(expectedUID),
            "pages": pages.map { ["page": $0.page, "data": hexString($0.data)] as [String: Any] },
        ]
        if let password { params["password"] = hexString(password) }
        if allowConfig { params["allow_config"] = true }
        return params
    }

    // MARK: Replies

    /// `reply` is the call's result value. Anything that is not a usable read
    /// reply is treated as a lost connection, with nothing confirmed.
    static func decodeRead(reply: Any) -> Result<PrinterTagRead, PrinterTagError> {
        guard let object = reply as? [String: Any] else { return .failure(.connectionLost(pagesWritten: 0)) }
        guard object["ok"] as? Bool == true else {
            return .failure(PrinterTagError(reply: object["error"] as? [String: Any] ?? [:]))
        }
        guard let uid = object["uid"] as? String, let firstPage = object["first_page"] as? Int,
              let pagesHex = object["pages"] as? String, let pageBytes = bytes(fromHex: pagesHex) else {
            return .failure(.connectionLost(pagesWritten: 0))
        }
        let versionReply = (object["version"] as? String).flatMap { bytes(fromHex: $0) }
        let geometry = Type2Geometry(versionReply: versionReply,
                                     capabilityContainer: capabilityContainer(in: pageBytes, firstPage: firstPage))
        return .success(PrinterTagRead(uid: SpoolMappingService.normalizeUID(uid), firstPage: firstPage,
                                       bytes: pageBytes, versionReply: versionReply, geometry: geometry))
    }

    // MARK: Helpers

    /// Page 3 when the read covers it, otherwise four zero bytes.
    private static func capabilityContainer(in bytes: [UInt8], firstPage: Int) -> [UInt8] {
        let offset = (3 - firstPage) * 4
        guard firstPage <= 3, offset >= 0, offset + 4 <= bytes.count else { return [0, 0, 0, 0] }
        return Array(bytes[offset..<offset + 4])
    }

    /// A call that threw. Moonraker refusing it (a rejection, a sign-in wanted)
    /// means it never reached the plugin: that is the printer's own text, or a
    /// partial write once a chunk was confirmed. Anything else is a lost connection.
    private static func callFailure(_ error: Error, confirmed: Int) -> PrinterTagError {
        switch error as? MoonrakerError {
        case .rejected(let message), .unauthorized(let message):
            confirmed == 0 ? .badRequest(message) : .writeFailed(pagesWritten: confirmed)
        default:
            .connectionLost(pagesWritten: confirmed)
        }
    }

    /// Adds what the confirmed chunks wrote to a write-failed count. The other
    /// codes carry no page count.
    private static func total(_ error: PrinterTagError, confirmedBefore confirmed: Int) -> PrinterTagError {
        switch error {
        case .writeFailed(let pages): .writeFailed(pagesWritten: confirmed + pages)
        case .verifyFailed(let pages): .verifyFailed(pagesWritten: confirmed + pages)
        default: error
        }
    }

    /// The plugin takes lowercase hex with no separators.
    private static func normalizedUIDForPlugin(_ uid: String) -> String {
        SpoolMappingService.normalizeUID(uid).lowercased()
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func bytes(fromHex hex: String) -> [UInt8]? {
        let characters = Array(hex)
        guard characters.count.isMultiple(of: 2) else { return nil }
        var result: [UInt8] = []
        result.reserveCapacity(characters.count / 2)
        for index in stride(from: 0, to: characters.count, by: 2) {
            guard let byte = UInt8(String(characters[index...index + 1]), radix: 16) else { return nil }
            result.append(byte)
        }
        return result
    }
}
