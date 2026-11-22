//
//  ServerLinkTests.swift
//  SpoolKidTests
//
//  The 2026-11-07 server-down lockout: what counts as down.
//

import Testing
import Foundation
@testable import SpoolKid

struct ServerLinkTests {
    @Test(arguments: [
        URLError.Code.cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet,
        .internationalRoamingOff, .dataNotAllowed, .callIsActive,
    ])
    func unreachableCodesAreNotSent(code: URLError.Code) {
        #expect(ServerFailure.classify(URLError(code)) == .notSent)
    }

    @Test(arguments: [URLError.Code.timedOut, .networkConnectionLost])
    func timeoutsMayHaveArrived(code: URLError.Code) {
        #expect(ServerFailure.classify(URLError(code)) == .mayHaveArrived)
    }

    @Test(arguments: [
        URLError.Code.secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
        .clientCertificateRejected,
    ])
    func tlsFailuresAreNotDown(code: URLError.Code) {
        #expect(ServerFailure.classify(URLError(code)) == nil)
    }

    @Test func cancellingIsNotDown() {
        #expect(ServerFailure.classify(URLError(.cancelled)) == nil)
        #expect(ServerFailure.classify(NSError(domain: "FilaManError", code: 401)) == nil)
    }

    @Test func aProbeDecides() {
        #expect(ServerLink.unknown.after(probe: .unreachable) == .down)
        #expect(ServerLink.down.after(probe: .reachable) == .up)
    }

    @Test func theLibraryIsNeverDown() {
        #expect(ServerLink.down.after(probe: .alwaysAvailable) == .up)
    }

    @Test func anyAnswerBringsItBackUp() {
        #expect(ServerLink.down.after(.answered) == .up)
    }

    @Test func aFailureTakesItDown() {
        #expect(ServerLink.up.after(.failed(.mayHaveArrived)) == .down)
    }

    @Test func unknownActsAsUp() {
        #expect(!ServerLink.unknown.isDown)
    }

    @Test func aBackendChangeForgetsTheOldState() {
        #expect(ServerLink.initial == .unknown && !ServerLink.initial.isDown)
    }
}
