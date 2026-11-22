//
//  PrinterTagPlugin.swift
//  SpoolKid
//
//  Purpose: The SpoolKid RFID Writer plugin on the printer: whether it is
//  there and ready, and what its errors mean to the user. Pure rules, built
//  from the plugin's Klipper object status.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// The plugin's state as the printer reports it.
nonisolated enum PrinterTagPlugin: Equatable, Sendable {
    case notInstalled
    case ready(version: String)
    case notReady(reason: String)
    /// The plugin speaks an API this app does not know.
    case needsAppUpdate(version: String)

    static let supportedAPIVersion = 1
    static let objectName = "spoolkid_rfid"
    /// The plugin is listed but has not reported yet: not absent, not known.
    static let waitingReason = "Waiting for the plugin to report."

    /// `objects` is the printer's object list; `status` is the `spoolkid_rfid`
    /// object's status.
    static func parse(objects: [String], status: [String: Any]?) -> PrinterTagPlugin {
        guard objects.contains(objectName) else { return .notInstalled }
        guard let status, !status.isEmpty else {
            return .notReady(reason: waitingReason)
        }
        let version = status["plugin_version"] as? String ?? "unknown"
        if let apiVersion = status["api_version"] as? Int, apiVersion > supportedAPIVersion {
            return .needsAppUpdate(version: version)
        }
        if status["ready"] as? Bool == true {
            return .ready(version: version)
        }
        return .notReady(reason: status["not_ready_reason"] as? String ?? "unknown reason")
    }

    var isUsable: Bool {
        if case .ready = self { return true }
        return false
    }

    /// The Printer settings row, or nil while the printer is not online: the
    /// plugin's state is unknown then, and "not installed" would be a guess.
    func settingsRow(connection: PrinterConnection) -> String? {
        guard case .online = connection else { return nil }
        return settingsText
    }

    /// The Printer settings row.
    var settingsText: String {
        switch self {
        case .notInstalled:
            "SpoolKid RFID Writer: not installed"
        case .ready(let version):
            "SpoolKid RFID Writer: ready (\(version))"
        case .notReady(let reason):
            "SpoolKid RFID Writer: not ready: \(reason)"
        case .needsAppUpdate:
            "SpoolKid RFID Writer: installed, needs a newer SpoolKid"
        }
    }
}

/// What a tag operation through the printer failed on.
nonisolated enum PrinterTagError: Error, Equatable, Sendable {
    case notReady(String)
    case busy
    case printing
    case noTag
    case uidMismatch
    case unsupportedTag(String)
    case protectedPage
    case authFailed
    case writeFailed(pagesWritten: Int)
    case verifyFailed(pagesWritten: Int)
    case badRequest(String)
    case connectionLost(pagesWritten: Int)

    /// From a reply's `error` object: `code`, `message`, `pages_written`.
    /// `unknown_tag` maps to `.noTag`. A code this app does not know is shown
    /// with the plugin's own message.
    init(reply: [String: Any]) {
        let code = reply["code"] as? String ?? ""
        let message = reply["message"] as? String ?? ""
        let pagesWritten = reply["pages_written"] as? Int ?? 0
        switch code {
        case "not_ready": self = .notReady(message)
        case "busy": self = .busy
        case "printing": self = .printing
        case "no_tag", "unknown_tag": self = .noTag
        case "uid_mismatch": self = .uidMismatch
        case "unsupported_tag": self = .unsupportedTag(message)
        case "protected_page": self = .protectedPage
        case "auth_failed": self = .authFailed
        case "write_failed": self = .writeFailed(pagesWritten: pagesWritten)
        case "verify_failed": self = .verifyFailed(pagesWritten: pagesWritten)
        default: self = .badRequest(message)
        }
    }

    /// The plugin's own error code, for logs. `unknown_tag` reads as `no_tag`;
    /// a reply this app could not use reads as `connection_lost`.
    var code: String {
        switch self {
        case .notReady: "not_ready"
        case .busy: "busy"
        case .printing: "printing"
        case .noTag: "no_tag"
        case .uidMismatch: "uid_mismatch"
        case .unsupportedTag: "unsupported_tag"
        case .protectedPage: "protected_page"
        case .authFailed: "auth_failed"
        case .writeFailed: "write_failed"
        case .verifyFailed: "verify_failed"
        case .badRequest: "bad_request"
        case .connectionLost: "connection_lost"
        }
    }

    /// The user's message. Toolheads are shown 1-based.
    func message(toolhead: Int) -> String {
        switch self {
        case .notReady(let reason), .unsupportedTag(let reason), .badRequest(let reason):
            reason
        case .busy:
            "The printer is busy with another tag. Try again."
        case .printing:
            "The printer is printing. Tags can be written when the print ends."
        case .noTag:
            "No tag answered at RFID reader \(toolhead + 1). Check the spool is seated, then try again."
        case .uidMismatch:
            "The tag at RFID reader \(toolhead + 1) changed. Scan again."
        case .protectedPage:
            "This tag is locked and can't be written."
        case .authFailed:
            "This tag is password-protected and the password was refused."
        case .writeFailed(let pages):
            "Wrote \(pages) pages, then the tag stopped answering. Read it again before trusting it."
        case .verifyFailed(let pages):
            "Wrote \(pages) pages, but the tag did not read back the same. Read it again before trusting it."
        case .connectionLost:
            "The printer stopped answering. The tag may be partly written. Read it again before trusting it."
        }
    }
}
