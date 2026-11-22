//
//  FilaManErrorExtractionTests.swift
//  SpoolKidTests
//

import Testing
import Foundation
@testable import SpoolKid

struct FilaManErrorExtractionTests {
    @Test func extractsStringDetail() {
        let data = Data(#"{"detail":"Spool not found"}"#.utf8)

        #expect(FilaManService.extractErrorMessage(from: data, statusCode: 404) == "Spool not found")
    }

    @Test func extractsFirstMessageFromValidationDetailList() {
        let data = Data("""
        {"detail":[{"loc":["body","filament_id"],"msg":"Field required","type":"missing"}]}
        """.utf8)

        #expect(FilaManService.extractErrorMessage(from: data, statusCode: 422) == "Field required")
    }

    @Test func joinsMultipleValidationMessages() {
        let data = Data("""
        {"detail":[{"msg":"Field required"},{"msg":"Value too large"}]}
        """.utf8)

        #expect(FilaManService.extractErrorMessage(from: data, statusCode: 422)
                == "Field required, Value too large")
    }

    /// FilaMan's own HTTPExceptions carry an object, not a string — the 409
    /// refusing a manufacturer or filament delete is one.
    @Test func extractsMessageFromObjectDetail() {
        let data = Data(#"{"detail":{"code":"conflict","message":"Manufacturer has filaments, cannot delete without force flag"}}"#.utf8)

        #expect(FilaManService.extractErrorMessage(from: data, statusCode: 409)
                == "Manufacturer has filaments, cannot delete without force flag")
    }

    @Test func unauthorizedGetsACredentialSpecificMessage() {
        let data = Data(#"{"detail":"Not authenticated"}"#.utf8)
        let message = FilaManService.extractErrorMessage(from: data, statusCode: 401)

        #expect(message.contains("API key"))
    }

    @Test func fallsBackToStatusAndBodyForUnknownShapes() {
        let data = Data("upstream exploded".utf8)
        let message = FilaManService.extractErrorMessage(from: data, statusCode: 502)

        #expect(message.contains("502"))
        #expect(message.contains("upstream exploded"))
    }
}

struct FilaManProbeResultTests {
    @Test func okStatusIsConfirmed() {
        #expect(FilaManService.probeResult(statusCode: 200) == .confirmed)
    }

    @Test func unauthorizedIsCredentialsRejected() {
        #expect(FilaManService.probeResult(statusCode: 401) == .credentialsRejected)
    }

    @Test func forbiddenIsCredentialsRejected() {
        #expect(FilaManService.probeResult(statusCode: 403) == .credentialsRejected)
    }

    @Test func notFoundIsNotFilaMan() {
        #expect(FilaManService.probeResult(statusCode: 404) == .notFilaMan)
    }

    @Test func serverErrorIsNotFilaMan() {
        #expect(FilaManService.probeResult(statusCode: 500) == .notFilaMan)
    }
}

struct FilaManAuthHeaderTests {
    @Test func explicitKeyWinsOverStoredKey() {
        #expect(FilaManService.authHeader(explicitKey: "test-key", storedKey: "stored-test-key") == "ApiKey test-key")
    }

    @Test func nilExplicitKeyFallsBackToStoredKey() {
        #expect(FilaManService.authHeader(explicitKey: nil, storedKey: "stored-test-key") == "ApiKey stored-test-key")
    }

    @Test func emptyExplicitKeyFallsBackToStoredKey() {
        #expect(FilaManService.authHeader(explicitKey: "", storedKey: "stored-test-key") == "ApiKey stored-test-key")
    }

    @Test func noKeysYieldsNoHeader() {
        #expect(FilaManService.authHeader(explicitKey: nil, storedKey: nil) == nil)
        #expect(FilaManService.authHeader(explicitKey: "", storedKey: "") == nil)
        #expect(FilaManService.authHeader(explicitKey: nil, storedKey: "") == nil)
        #expect(FilaManService.authHeader(explicitKey: "", storedKey: nil) == nil)
    }
}
