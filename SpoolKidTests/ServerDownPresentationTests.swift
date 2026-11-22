//
//  ServerDownPresentationTests.swift
//  SpoolKidTests
//
//  The 2026-11-07 server-down lockout: what Home and Library show.
//

import Testing
@testable import SpoolKid

struct ServerDownPresentationTests {
    @Test func aDownServerWithRowsShowsTheStaleList() {
        #expect(ServerDownPresentation.decide(isDown: true, hasLoadedRows: true) == .staleList)
    }

    @Test func aDownServerWithNothingLoadedShowsNotConnected() {
        #expect(ServerDownPresentation.decide(isDown: true, hasLoadedRows: false) == .notConnected)
    }

    @Test(arguments: [true, false])
    func upOrUnknownIsNormal(hasLoadedRows: Bool) {
        #expect(ServerDownPresentation.decide(isDown: false, hasLoadedRows: hasLoadedRows) == .normal)
    }

    @Test func theDefaultStateLocksNothing() {
        #expect(!ServerLinkState().isDown)
    }
}
