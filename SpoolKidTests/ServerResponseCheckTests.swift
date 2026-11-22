//
//  ServerResponseCheckTests.swift
//  SpoolKidTests
//
//  An HTML answer is a web page, not the API's data: it is an error for
//  Spoolman and FilaMan alike, and an HTML error body is never pasted into a
//  message.
//

import Foundation
import Testing
@testable import SpoolKid

struct ServerResponseCheckTests {
    @Test func isWebPageRecognisesOnlyHTML() {
        for m in ["text/html", "text/html; charset=utf-8", "TEXT/HTML", "application/xhtml+xml"] {
            #expect(ServerResponseCheck.isWebPage(mimeType: m))
        }
        for m in [nil, "application/json", "application/json; charset=utf-8", "text/plain"] as [String?] {
            #expect(!ServerResponseCheck.isWebPage(mimeType: m))
        }
    }

    @Test func onlySuccessAndSignInStatusesMeanAPageInsteadOfData() {
        for s in [200, 204, 401, 403] {
            #expect(ServerResponseCheck.isWebPageInsteadOfData(statusCode: s, mimeType: "text/html"))
        }
        for s in [404, 409, 422, 500, 502] {
            #expect(!ServerResponseCheck.isWebPageInsteadOfData(statusCode: s, mimeType: "text/html"))
        }
    }

    @Test func jsonErrorsAreNotWebPages() {
        for s in [200, 401, 404, 409, 422] {
            #expect(!ServerResponseCheck.isWebPageInsteadOfData(statusCode: s, mimeType: "application/json"))
        }
    }

    @Test func webPageMessageIsTheSpecCopy() {
        #expect(ServerResponseCheck.webPageMessage(backendName: "Spoolman")
            == "The server sent a web page instead of Spoolman data. Check that the address is your Spoolman server, not a page inside it, and that no sign-in page sits in front of its API.")
    }

    @Test func signInPageMessageIsTheCopy() {
        #expect(ServerResponseCheck.signInPageMessage(backendName: "Spoolman", statusCode: 401)
            == "The server answered with a sign-in page (HTTP 401). If a user name and password protect Spoolman, check them under Authentication.")
    }

    @Test func htmlErrorBodiesAreNotPastedIntoMessages() {
        let html = Data("<html><body>Bad Gateway</body></html>".utf8)
        #expect(SpoolmanService.errorText(data: html, status: 502, mimeType: "text/html") == "Server error 502.")
        #expect(FilaManService.extractErrorMessage(from: html, statusCode: 502, mimeType: "text/html") == "Server error 502.")
    }

    @Test func spoolmanJSONErrorTextUnchanged() {
        #expect(SpoolmanService.errorText(data: Data(#"{"message":"Spool not found"}"#.utf8), status: 404, mimeType: "application/json") == "Spool not found")
        #expect(SpoolmanService.errorText(data: Data("boom".utf8), status: 500) == "Server error 500: boom")
    }

    @Test func filaManProbeSeesAWebPage() {
        #expect(FilaManService.probeResult(statusCode: 200, mimeType: "text/html") == .webPage)
        #expect(FilaManService.probeResult(statusCode: 502, mimeType: "text/html; charset=utf-8") == .webPage)
        #expect(FilaManService.probeResult(statusCode: 200, mimeType: "application/json") == .confirmed)
        #expect(FilaManService.probeResult(statusCode: 401, mimeType: nil) == .credentialsRejected)
    }
}
