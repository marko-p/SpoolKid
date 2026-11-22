//
//  PrinterTagPluginTests.swift
//  SpoolKidTests
//
//  Purpose: The SpoolKid RFID Writer plugin's state, the reader choice and the
//  plugin's error codes, as the printer reports them.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
@testable import SpoolKid

struct PrinterTagPluginTests {
    private let object = "spoolkid_rfid"

    private func status(
        ready: Bool = true, reason: String = "", apiVersion: Int = 1, pluginVersion: String = "0.1.0"
    ) -> [String: Any] {
        [
            "api_version": apiVersion, "plugin_version": pluginVersion, "ready": ready,
            "not_ready_reason": reason, "busy": false
        ]
    }

    @Test func notInstalledWithoutTheObject() {
        #expect(PrinterTagPlugin.parse(objects: ["print_task_config"], status: nil) == .notInstalled)
        #expect(PrinterTagPlugin.parse(objects: [], status: status()) == .notInstalled)
    }

    @Test func readyWithVersion() {
        #expect(PrinterTagPlugin.parse(objects: [object], status: status()) == .ready(version: "0.1.0"))
    }

    @Test func notReadyCarriesTheReason() {
        let parsed = PrinterTagPlugin.parse(objects: [object], status: status(ready: false, reason: "Toolhead 2 has no reader."))
        #expect(parsed == .notReady(reason: "Toolhead 2 has no reader."))
    }

    @Test func presentWithoutStatusWaitsForThePlugin() {
        #expect(PrinterTagPlugin.parse(objects: [object], status: nil) == .notReady(reason: "Waiting for the plugin to report."))
    }

    @Test func higherAPIVersionNeedsAppUpdate() {
        let parsed = PrinterTagPlugin.parse(objects: [object], status: status(apiVersion: 2, pluginVersion: "0.2.0"))
        #expect(parsed == .needsAppUpdate(version: "0.2.0"))
    }

    @Test func onlyAReadyPluginIsUsable() {
        #expect(PrinterTagPlugin.ready(version: "0.1.0").isUsable)
        #expect(!PrinterTagPlugin.notInstalled.isUsable)
        #expect(!PrinterTagPlugin.notReady(reason: "x").isUsable)
        #expect(!PrinterTagPlugin.needsAppUpdate(version: "0.2.0").isUsable)
    }

    @Test func settingsTextNamesTheState() {
        #expect(PrinterTagPlugin.notInstalled.settingsText == "SpoolKid RFID Writer: not installed")
        #expect(PrinterTagPlugin.ready(version: "0.1.0").settingsText == "SpoolKid RFID Writer: ready (0.1.0)")
        #expect(PrinterTagPlugin.notReady(reason: "Busy.").settingsText == "SpoolKid RFID Writer: not ready: Busy.")
        #expect(PrinterTagPlugin.needsAppUpdate(version: "0.2.0").settingsText == "SpoolKid RFID Writer: installed, needs a newer SpoolKid")
    }

    @Test func errorFromReplyMapsEveryCode() {
        #expect(PrinterTagError(reply: ["code": "not_ready", "message": "Waiting.", "pages_written": 0]) == .notReady("Waiting."))
        #expect(PrinterTagError(reply: ["code": "busy", "message": "x", "pages_written": 0]) == .busy)
        #expect(PrinterTagError(reply: ["code": "printing", "message": "x", "pages_written": 0]) == .printing)
        #expect(PrinterTagError(reply: ["code": "no_tag", "message": "x", "pages_written": 0]) == .noTag)
        #expect(PrinterTagError(reply: ["code": "unknown_tag", "message": "x", "pages_written": 0]) == .noTag)
        #expect(PrinterTagError(reply: ["code": "uid_mismatch", "message": "x", "pages_written": 0]) == .uidMismatch)
        #expect(PrinterTagError(reply: ["code": "unsupported_tag", "message": "Not an NTAG.", "pages_written": 0]) == .unsupportedTag("Not an NTAG."))
        #expect(PrinterTagError(reply: ["code": "protected_page", "message": "x", "pages_written": 0]) == .protectedPage)
        #expect(PrinterTagError(reply: ["code": "auth_failed", "message": "x", "pages_written": 0]) == .authFailed)
        #expect(PrinterTagError(reply: ["code": "write_failed", "message": "x", "pages_written": 3]) == .writeFailed(pagesWritten: 3))
        #expect(PrinterTagError(reply: ["code": "verify_failed", "message": "x", "pages_written": 5]) == .verifyFailed(pagesWritten: 5))
        #expect(PrinterTagError(reply: ["code": "bad_request", "message": "Page out of range.", "pages_written": 0]) == .badRequest("Page out of range."))
    }

    @Test func messagesMatchTheSpecTable() {
        #expect(PrinterTagError.notReady("Waiting for the tag reader.").message(toolhead: 0) == "Waiting for the tag reader.")
        #expect(PrinterTagError.busy.message(toolhead: 0) == "The printer is busy with another tag. Try again.")
        #expect(PrinterTagError.printing.message(toolhead: 0) == "The printer is printing. Tags can be written when the print ends.")
        #expect(PrinterTagError.noTag.message(toolhead: 0) == "No tag answered at RFID reader 1. Check the spool is seated, then try again.")
        #expect(PrinterTagError.noTag.message(toolhead: 3) == "No tag answered at RFID reader 4. Check the spool is seated, then try again.")
        #expect(PrinterTagError.uidMismatch.message(toolhead: 1) == "The tag at RFID reader 2 changed. Scan again.")
        #expect(PrinterTagError.unsupportedTag("Not an NTAG.").message(toolhead: 0) == "Not an NTAG.")
        #expect(PrinterTagError.protectedPage.message(toolhead: 0) == "This tag is locked and can't be written.")
        #expect(PrinterTagError.authFailed.message(toolhead: 0) == "This tag is password-protected and the password was refused.")
        #expect(PrinterTagError.writeFailed(pagesWritten: 4).message(toolhead: 0)
            == "Wrote 4 pages, then the tag stopped answering. Read it again before trusting it.")
        #expect(PrinterTagError.verifyFailed(pagesWritten: 4).message(toolhead: 0)
            == "Wrote 4 pages, but the tag did not read back the same. Read it again before trusting it.")
        #expect(PrinterTagError.badRequest("Page out of range.").message(toolhead: 0) == "Page out of range.")
        #expect(PrinterTagError.connectionLost(pagesWritten: 0).message(toolhead: 0)
            == "The printer stopped answering. The tag may be partly written. Read it again before trusting it.")
    }

    @Test func theIPhoneIsAReaderAndEachToolheadIsOne() {
        #expect(TagReader.iPhone != TagReader.toolhead(0))
        #expect(TagReader.toolhead(2) == TagReader.toolhead(2))
    }

    @Test func everyErrorHasItsPluginCode() {
        let errors: [(PrinterTagError, String)] = [
            (.notReady("x"), "not_ready"), (.busy, "busy"), (.printing, "printing"), (.noTag, "no_tag"),
            (.uidMismatch, "uid_mismatch"), (.unsupportedTag("x"), "unsupported_tag"),
            (.protectedPage, "protected_page"), (.authFailed, "auth_failed"),
            (.writeFailed(pagesWritten: 1), "write_failed"), (.verifyFailed(pagesWritten: 1), "verify_failed"),
            (.badRequest("x"), "bad_request"), (.connectionLost(pagesWritten: 0), "connection_lost"),
        ]
        for (error, code) in errors { #expect(error.code == code) }
    }
}
