//
//  ServerWriteLockTests.swift
//  SpoolKidTests
//
//  The 2026-11-07 server-down lockout: what a form says.
//

import Testing
@testable import SpoolKid

struct ServerWriteLockTests {
    @Test func downKeepsTheTyping() {
        #expect(SaveNote.text(isDown: true, backendName: "Spoolman")
                == "Can't reach Spoolman. What you typed is kept; Save comes back when it does.")
    }

    @Test func upSaysNothing() {
        #expect(SaveNote.text(isDown: false, backendName: "Spoolman") == nil)
    }

    @Test func anUnknownSaveSaysSo() {
        #expect(SaveNote.failure(WriteOutcome<Void>.unknown, otherwise: "Refused")
                == "This may not have saved. Check once the server is back.")
    }

    @Test func aFailedSaveKeepsItsOwnMessage() {
        #expect(SaveNote.failure(WriteOutcome<Void>.failed, otherwise: "Refused") == "Refused")
    }

    @Test func anUnsureCreateHoldsSaveUntilAcknowledged() {
        #expect(SaveNote.holdsResave(after: .unknown, isCreate: true))
        #expect(!SaveNote.holdsResave(after: .unknown, isCreate: false))
        #expect(!SaveNote.holdsResave(after: .failed, isCreate: true))
        #expect(SaveNote.unsureCreate == "This may already have saved. Check the list before you save again.")
    }

    @MainActor @Test func theDefaultOutcomeIsSavedOrFailed() async {
        let state = ServerLinkState()
        #expect(await state.outcome { true }.isFailed == false)
        #expect(await state.outcome { false }.isFailed)
    }
}
