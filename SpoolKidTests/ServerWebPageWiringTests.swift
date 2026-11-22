//
//  ServerWebPageWiringTests.swift
//  SpoolKidTests
//
//  Drives the real `SpoolmanService` / `FilaManService` request paths against
//  a stub `URLProtocol`, so "a web page is never data" is pinned at the
//  transport, not only in `ServerResponseCheck`'s pure rules. Spoolman answers
//  `200 text/html` for any path outside /api (measured 2026-10-20).
//

import Foundation
import Testing
@testable import SpoolKid

/// Answers every request on its session from `handler`; nothing reaches the
/// network. A request with no handler fails as unreachable.
nonisolated final class StubURLProtocol: URLProtocol {
    struct Reply: Sendable {
        let status: Int
        let contentType: String
        let body: String
    }

    static let host = "spoolkid-stub.invalid"
    static let baseUrl = "http://\(host)"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: (@Sendable (URLRequest) -> Reply)?

    static var handler: (@Sendable (URLRequest) -> Reply)? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    /// A session that only this stub answers.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard request.url?.host == Self.host, let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let reply = handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": reply.contentType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Serialized: the stub's handler is shared by every test here.
@MainActor
@Suite(.serialized)
struct ServerWebPageWiringTests {
    private static let page = "<!doctype html><html><body>Spoolman</body></html>"

    private func reply(_ status: Int, _ contentType: String, _ body: String) {
        StubURLProtocol.handler = { _ in .init(status: status, contentType: contentType, body: body) }
    }

    private func htmlPage(_ status: Int = 200) { reply(status, "text/html; charset=utf-8", Self.page) }

    private func spoolman() -> SpoolmanService { SpoolmanService(session: StubURLProtocol.session(), authType: { "none" }) }
    private func filaMan() -> FilaManService { FilaManService(session: StubURLProtocol.session()) }

    private static func spool(_ id: Int) -> Spool {
        Spool(
            id: id,
            filament: Filament(id: 1, name: "PLA Black", material: "PLA", vendor: nil, colorHex: "000000", density: 1.24),
            remainingWeight: 1000, extra: nil, rfidUID: nil, statusId: nil, externalId: nil, purchaseDate: nil
        )
    }

    // MARK: - Reachability reports

    @Test func spoolmanReportsUnreachable() async {
        StubURLProtocol.handler = nil
        let service = spoolman()
        var reports: [TransportReport] = []
        service.transportReport = { report, _ in reports.append(report) }
        _ = await service.healthCheck(baseUrl: StubURLProtocol.baseUrl)
        #expect(reports == [.failed(.notSent)])
    }

    @Test func spoolmanReportsAnAnswer() async {
        htmlPage(404)
        let service = spoolman()
        var reports: [TransportReport] = []
        service.transportReport = { report, _ in reports.append(report) }
        _ = await service.healthCheck(baseUrl: StubURLProtocol.baseUrl)
        #expect(reports == [.answered])
    }

    @Test func filaManReportsUnreachable() async {
        StubURLProtocol.handler = nil
        let service = filaMan()
        var reports: [TransportReport] = []
        service.transportReport = { report, _ in reports.append(report) }
        _ = await service.healthCheck(baseUrl: StubURLProtocol.baseUrl)
        #expect(reports == [.failed(.notSent)])
    }

    // MARK: - Spoolman

    @Test func anHTMLPageOnLinkTagFailsAndNeverLinks() async {
        htmlPage()
        let outcome = await spoolman().linkTag(spoolId: 3, uid: "04AABBCC", baseUrl: StubURLProtocol.baseUrl)
        #expect(outcome == .failed(ServerResponseCheck.webPageMessage(backendName: "Spoolman")))
    }

    @Test func aJSON201OnLinkTagLinks() async {
        reply(201, "application/json", #"{"uid":"04AABBCC"}"#)
        let outcome = await spoolman().linkTag(spoolId: 3, uid: "04AABBCC", baseUrl: StubURLProtocol.baseUrl)
        #expect(outcome == .linked)
    }

    @Test func anHTMLPageForVendorsFailsTestConnectionWithTheWebPageMessage() async {
        htmlPage()
        let service = spoolman()
        #expect(await service.testConnection(baseUrl: StubURLProtocol.baseUrl) == false)
        #expect(service.errorMessage == ServerResponseCheck.webPageMessage(backendName: "Spoolman"))
    }

    @Test func anHTMLPageFailsTheHealthCheck() async {
        htmlPage()
        #expect(await spoolman().healthCheck(baseUrl: StubURLProtocol.baseUrl) == false)
    }

    @Test func aJSONVendorListPassesTheHealthCheck() async {
        reply(200, "application/json", "[]")
        #expect(await spoolman().healthCheck(baseUrl: StubURLProtocol.baseUrl))
    }

    @Test func aSpoolman401PageGetsTheSignInCopy() async {
        htmlPage(401)
        let service = spoolman()
        #expect(await service.testConnection(baseUrl: StubURLProtocol.baseUrl) == false)
        #expect(service.errorMessage == ServerResponseCheck.signInPageMessage(backendName: "Spoolman", statusCode: 401))
    }

    @Test func anHTML404IsNotAnAlreadyAbsentCardUIDsField() async {
        htmlPage(404)
        #expect(await spoolman().deleteCardUIDsField(baseUrl: StubURLProtocol.baseUrl) == false)
    }

    @Test func spoolmansOwn404IsAnAlreadyAbsentCardUIDsField() async {
        StubURLProtocol.handler = { request in
            request.httpMethod == "DELETE"
                ? .init(status: 404, contentType: "application/json", body: #"{"message":"Field does not exist."}"#)
                : .init(status: 200, contentType: "application/json", body: "[]")
        }
        #expect(await spoolman().deleteCardUIDsField(baseUrl: StubURLProtocol.baseUrl))
    }

    @Test func anHTML404KeepsTheSpoolOnRefetch() async {
        htmlPage(404)
        let service = spoolman()
        service.spools = [Self.spool(7)]
        await service.refetchSpool(id: 7, baseUrl: StubURLProtocol.baseUrl)
        #expect(service.spools.map(\.id) == [7])
    }

    @Test func spoolmansOwn404DropsTheSpoolOnRefetch() async {
        reply(404, "application/json", #"{"message":"No spool with ID 7 found."}"#)
        let service = spoolman()
        service.spools = [Self.spool(7)]
        await service.refetchSpool(id: 7, baseUrl: StubURLProtocol.baseUrl)
        #expect(service.spools.isEmpty)
    }

    @Test func anHTML404OnLinkTagIsNotNoTagAPI() async {
        htmlPage(404)
        let outcome = await spoolman().linkTag(spoolId: 3, uid: "04AABBCC", baseUrl: StubURLProtocol.baseUrl)
        #expect(outcome == .failed("Server error 404."))
    }

    // MARK: - FilaMan

    @Test func anHTMLPageFailsAFilaManRequestWithTheWebPageMessage() async {
        htmlPage()
        do {
            _ = try await filaMan().fetchSpool(id: 7, baseUrl: StubURLProtocol.baseUrl)
            Issue.record("An HTML page decoded as a spool")
        } catch {
            #expect(error.localizedDescription == ServerResponseCheck.webPageMessage(backendName: "FilaMan"))
        }
    }

    @Test func anHTMLPageProbesAsAWebPage() async {
        htmlPage()
        #expect(await filaMan().probeIsFilaMan(baseUrl: StubURLProtocol.baseUrl, apiKey: nil) == .webPage)
    }

    @Test func anUnsupportedSchemeProbesAsUnreachableWithTheAddressMessage() async {
        StubURLProtocol.handler = nil
        let service = filaMan()
        #expect(await service.probeIsFilaMan(baseUrl: "ftp://h", apiKey: nil) == .unreachable)
        #expect(service.errorMessage == ServerAddressProblem.unsupportedScheme.message)
    }
}
