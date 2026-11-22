//
//  ServerAddressTests.swift
//  SpoolKidTests
//
//  The one rule for a typed server address: what it normalises to, what it
//  refuses and why, and that a clean address builds exactly the request URLs
//  and ledger scope it did before the rule existed.
//

import Foundation
import Testing
@testable import SpoolKid

struct ServerAddressTests {

    @Test(arguments: [
        ("http://192.168.1.10:7912", "http://192.168.1.10:7912"),
        ("192.168.1.10:7912", "http://192.168.1.10:7912"),
        ("spoolman.local:7912", "http://spoolman.local:7912"),
        ("h:7912", "http://h:7912"),
        ("http://h:7912/", "http://h:7912"),
        ("http://h:7912///", "http://h:7912"),
        ("  http://h:7912 \n", "http://h:7912"),
        ("https://example.com/spoolman", "https://example.com/spoolman"),
        ("https://example.com/spoolman/", "https://example.com/spoolman"),
        ("http://h:7912/api/v1", "http://h:7912"),
        ("http://h:7912/API/V1/", "http://h:7912"),
        ("https://example.com/spoolman/api/v1", "https://example.com/spoolman"),
        ("HTTP://h:7912", "http://h:7912"),
        ("http://[fd00::1]:7912", "http://[fd00::1]:7912"),
        ("http://filaman:8000/spoolman", "http://filaman:8000/spoolman"),
        ("http://api/v1", "http://api/v1"),
    ])
    func normalises(typed: String, expected: String) throws {
        #expect(try ServerAddress.parse(typed).get().text == expected)
    }

    @Test(arguments: [
        ("", ServerAddressProblem.empty), ("   ", .empty),
        ("ftp://h:21", .unsupportedScheme),
        ("http://", .noHost), ("http://:7912", .noHost),
        ("http://h:7912/?x=1", .hasQuery), ("http://h:7912/#top", .hasFragment),
        ("http://admin:pw@h:7912", .hasCredentials), ("http://admin@h:7912", .hasCredentials),
        ("http:/h:7912", .unsupportedScheme), ("https:/h", .unsupportedScheme),
        ("http//h:7912", .unsupportedScheme), ("http:7912", .unsupportedScheme),
    ])
    func refuses(typed: String, problem: ServerAddressProblem) {
        #expect(throws: problem) { try ServerAddress.parse(typed).get() }
    }

    @Test func messagesAreTheSpecCopy() {
        #expect(ServerAddressProblem.unsupportedScheme.message == "Use an address that starts with http:// or https://.")
        #expect(ServerAddressProblem.noHost.message == "That address has no server name.")
        #expect(ServerAddressProblem.hasQuery.message == "Remove the part from \"?\" on. A server address has no query.")
        #expect(ServerAddressProblem.hasFragment.message == "Remove the part from \"#\" on.")
        #expect(ServerAddressProblem.hasCredentials.message == "Remove the user name and password from the address. Use the sign-in fields below instead.")
        #expect(ServerAddressProblem.invalid.message == "SpoolKid can't use that address.")
        #expect(ServerAddressProblem.empty.message == "No server address is set.")
        #expect(ServerAddressProblem.noHost.localizedDescription == ServerAddressProblem.noHost.message)
    }

    /// Anti-goal 1: a clean address builds exactly today's URLs.
    @Test(arguments: [
        "/api/v1/vendor", "/api/v1/spool?allow_archived=true",
        "/api/v1/spools?page=1&page_size=200&include_archived=true",
        "/api/v1/system-extra-fields?target_type=spool",
        "/api/v1/location/My%20Shelf%3F", "/api/v1/spool/12/tag/04A1B2C3",
    ])
    func cleanAddressesBuildTodaysURLs(endpoint: String) throws {
        for base in ["http://192.168.20.31:7912", "https://example.com/spoolman", "http://[fd00::1]:7912"] {
            let url = try #require(try ServerAddress.parse(base).get().url(endpoint: endpoint))
            #expect(url.absoluteString == base + endpoint)
        }
    }

    @Test func trailingSlashNoLongerDoublesTheSlash() throws {
        #expect(try ServerAddress.requestURL("http://h:7912/", endpoint: "/api/v1/info").absoluteString
                == "http://h:7912/api/v1/info")
    }

    @Test func endpointWithAFragmentIsRefused() throws {
        #expect(try ServerAddress.parse("http://h").get().url(endpoint: "/api/v1/x#y") == nil)
        #expect(throws: ServerAddressProblem.invalid) { try ServerAddress.requestURL("http://h", endpoint: "/x#y") }
        #expect(throws: ServerAddressProblem.empty) { try ServerAddress.requestURL("", endpoint: "/api/v1/vendor") }
    }

    /// Anti-goal 2: today's TagAssociationStore rule, copied as the oracle.
    private static func oldLedgerScope(_ s: String) -> String {
        var url = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }

    @Test(arguments: ["", "http://192.168.20.31:7912", "http://a:7912/", " HTTP://A:7912 ",
                      "https://Example.com/Spoolman/", "http://[fd00::1]:7912", "http://h/my spool", "http://",
                      "http://api/v1"])
    func identityMatchesTheOldLedgerRule(typed: String) {
        #expect(ServerAddress.identity(of: typed) == Self.oldLedgerScope(typed))
    }

    @Test func identityTreatsEquivalentTypingsAsOneServer() {
        #expect(ServerAddress.identity(of: "192.168.1.10:7912") == "http://192.168.1.10:7912")
        #expect(ServerAddress.identity(of: "http://h:7912/api/v1/") == "http://h:7912")
        #expect(ServerAddress.identity(of: "http://h:7912/") == ServerAddress.identity(of: "HTTP://H:7912"))
        #expect(ServerAddress.identity(of: "http://api/v1") == "http://api/v1")
    }

    @Test func hint() {
        #expect(ServerAddress.hint(for: "") == nil)
        #expect(ServerAddress.hint(for: "http://h:7912") == nil)
        #expect(ServerAddress.hint(for: " http://h:7912 ") == nil)
        #expect(ServerAddress.hint(for: "192.168.1.10:7912") == .connectsTo("http://192.168.1.10:7912"))
        #expect(ServerAddress.hint(for: "http://h:7912/") == .connectsTo("http://h:7912"))
        #expect(ServerAddress.hint(for: "ftp://h") == .problem(ServerAddressProblem.unsupportedScheme.message))
        #expect(ServerAddress.hint(for: "http:/h:7912") == .problem(ServerAddressProblem.unsupportedScheme.message))
    }

    @Test(arguments: ["h", "ht", "http", "http:", "http:/", "http://", "HTTPS:/", "https://", " https:// "])
    func hintStaysQuietWhileTypingAScheme(typed: String) {
        #expect(ServerAddress.hint(for: typed) == nil)
    }

    @Test func usableAndSecure() throws {
        #expect(ServerAddress.isUsable("192.168.1.10:7912"))
        #expect(!ServerAddress.isUsable("http://"))
        #expect(!ServerAddress.isUsable("http:"))
        #expect(try ServerAddress.parse("https://h").get().isSecure)
        #expect(try !ServerAddress.parse("h:8000").get().isSecure)
    }
}

struct SpoolmanServerInfoTests {
    @Test func serverInfoDescribesTheSameServerTypedDifferently() {
        let info = SpoolmanService.ServerInfo(baseUrl: "http://h:7912/", version: "0.27.0")
        #expect(info.describes("HTTP://h:7912"))
        #expect(info.describes("h:7912"))
        #expect(!info.describes("http://other:7912"))
    }
}
