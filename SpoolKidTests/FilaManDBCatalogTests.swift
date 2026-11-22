//
//  FilaManDBCatalogTests.swift
//  SpoolKidTests
//
//  Purpose: The FilaManDB client: the mapping of a /filaments page into
//  catalogue entries, the request URLs, paging, manufacturer lookup, and
//  failure. No test touches the network; every call goes through an
//  injected fetch.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

/// Records the URLs a catalogue asked for and answers each from `answer`.
private nonisolated final class FakeFetch: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private let answer: @Sendable (URL) throws -> Data

    init(answer: @escaping @Sendable (URL) throws -> Data) {
        self.answer = answer
    }

    var requested: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }

    var catalog: FilaManDBCatalog {
        FilaManDBCatalog(fetch: { url in
            self.record(url)
            return try self.answer(url)
        })
    }

    private func record(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        urls.append(url)
    }
}

struct FilaManDBCatalogTests {
    /// One /filaments page as measured 2026-10-18, trimmed to the fields read.
    private static let fixture = Data("""
    {"total":2,"page":1,"page_size":200,"items":[
     {"id":18517,"color_name":"Galaxy Black","designation":"   Other    - Galaxy Black","hex_color":"#1A1A1A",
      "diameter_mm":1.75,"density_g_cm3":1.24,"nominal_weight_g":1000,
      "manufacturer":{"id":79,"name":"add:north"},"material":{"id":11,"key":"pla","name":"PLA"},
      "spool_profile":{"id":721,"name":"207g Spool","empty_weight_g":207.0,"spool_material":"Plastic"}},
     {"id":22631,"color_name":"30D White","designation":"   Other    - 30D White","hex_color":"#FFFFFF",
      "diameter_mm":1.75,"density_g_cm3":null,"nominal_weight_g":850,
      "manufacturer":{"id":293,"name":"Fiberlogy"},"material":{"id":43,"key":"tpu","name":"TPU"},
      "spool_profile":null}
    ]}
    """.utf8)

    /// A /filaments page of `count` plain items numbered from `first`.
    private static func page(first: Int, count: Int, total: Int) -> Data {
        let items = (first..<first + count).map { id in
            """
            {"id":\(id),"color_name":"Colour \(id)","designation":"x","hex_color":"#000000",
             "diameter_mm":1.75,"density_g_cm3":1.24,"nominal_weight_g":1000,
             "manufacturer":{"id":5,"name":"Acme"},"material":{"id":1,"key":"pla","name":"PLA"},
             "spool_profile":null}
            """
        }
        return Data("{\"total\":\(total),\"page\":1,\"page_size\":200,\"items\":[\(items.joined(separator: ","))]}".utf8)
    }

    private static func manufacturers(_ rows: [(Int, String)], total: Int? = nil) -> Data {
        let items = rows.map { "{\"id\":\($0.0),\"name\":\"\($0.1)\"}" }
        return Data("{\"total\":\(total ?? rows.count),\"page\":1,\"page_size\":200,\"items\":[\(items.joined(separator: ","))]}".utf8)
    }

    private nonisolated static func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }

    @Test func mapsTheFixture() throws {
        let entries = try FilaManDBCatalog.entries(fromPage: Self.fixture)

        #expect(entries.count == 2)
        let first = entries[0]
        #expect(first.id == "filamandb-18517")
        #expect(first.manufacturer == "add:north")
        #expect(first.name == "Galaxy Black")
        #expect(first.material == "PLA")
        #expect(first.spoolType == "Plastic")
        #expect(first.density == 1.24)
        #expect(first.weight == 1000)
        #expect(first.spoolWeight == 207)
        #expect(first.diameter == 1.75)
        #expect(first.colorHex == "1A1A1A")
        #expect(first.extruderTemp == nil)
        #expect(first.bedTemp == nil)

        let second = entries[1]
        #expect(second.id == "filamandb-22631")
        #expect(second.manufacturer == "Fiberlogy")
        #expect(second.material == "TPU")
        #expect(second.density == nil)
        #expect(second.spoolWeight == nil)
        #expect(second.spoolType == nil)
        #expect(second.weight == 850)
    }

    @Test func aBlankColourNameFallsBackToTheTidiedDesignation() throws {
        let data = Data("""
        {"total":1,"items":[{"id":1,"color_name":"  ","designation":"   Other    - Galaxy   Black ",
         "hex_color":"1A1A1A","diameter_mm":2.85,"manufacturer":{"id":1,"name":"Acme"},
         "material":{"id":1,"name":"PLA"}}]}
        """.utf8)

        let entry = try #require(try FilaManDBCatalog.entries(fromPage: data).first)

        #expect(entry.name == "Other - Galaxy Black")
        #expect(entry.colorHex == "1A1A1A")
        #expect(entry.diameter == 2.85)
    }

    @Test func anItemWithoutManufacturerMaterialOrDiameterIsSkipped() throws {
        let data = Data("""
        {"total":4,"items":[
         {"id":1,"color_name":"A","diameter_mm":1.75,"manufacturer":null,"material":{"id":1,"name":"PLA"}},
         {"id":2,"color_name":"B","diameter_mm":1.75,"manufacturer":{"id":1,"name":"Acme"},"material":null},
         {"id":3,"color_name":"C","manufacturer":{"id":1,"name":"Acme"},"material":{"id":1,"name":"PLA"}},
         {"id":4,"color_name":"D","diameter_mm":1.75,"manufacturer":{"id":1,"name":"Acme"},"material":{"id":1,"name":"PLA"}}
        ]}
        """.utf8)

        let entries = try FilaManDBCatalog.entries(fromPage: data)

        #expect(entries.map(\.id) == ["filamandb-4"])
    }

    @Test func searchURL() async throws {
        let fetch = FakeFetch { _ in Self.fixture }

        _ = try await fetch.catalog.searchFilaments("Galaxy Black", manufacturerID: 79, maxPages: 1)

        let url = try #require(fetch.requested.first)
        #expect(fetch.requested.count == 1)
        #expect(url.absoluteString.hasPrefix("https://db.filaman.app/api/v1/filaments?"))
        #expect(url.absoluteString.contains("search=Galaxy%20Black"))
        #expect(url.absoluteString.contains("manufacturer_id=79"))
        #expect(url.absoluteString.contains("page_size=200"))
        #expect(url.absoluteString.contains("page=1"))
    }

    @Test func searchWithoutAManufacturerLeavesTheFilterOut() async throws {
        let fetch = FakeFetch { _ in Self.fixture }

        _ = try await fetch.catalog.searchFilaments("Galaxy", manufacturerID: nil, maxPages: 1)

        let url = try #require(fetch.requested.first)
        #expect(Self.query(url, "manufacturer_id") == nil)
        #expect(Self.query(url, "search") == "Galaxy")
    }

    @Test func aPlusInTheQueryReachesTheServerAsAPlus() async throws {
        let fetch = FakeFetch { _ in Self.fixture }

        _ = try await fetch.catalog.searchFilaments("PLA+ Silk", manufacturerID: nil, maxPages: 1)

        let url = try #require(fetch.requested.first)
        #expect(url.absoluteString.contains("search=PLA%2B%20Silk"))
    }

    @Test func blankQueryFetchesNothing() async throws {
        let fetch = FakeFetch { _ in Self.fixture }

        let entries = try await fetch.catalog.searchFilaments("  ", manufacturerID: 79, maxPages: 1)

        #expect(entries.isEmpty)
        #expect(fetch.requested.isEmpty)
    }

    @Test func manufacturerIDPicksTheExactName() async throws {
        let fetch = FakeFetch { _ in Self.manufacturers([(689, "Prusament"), (953, "Prusamentos")]) }

        let exact = try await fetch.catalog.manufacturerID(named: "prusament ")
        let partial = try await fetch.catalog.manufacturerID(named: "Prusa")

        #expect(exact == 689)
        #expect(partial == nil)
        let url = try #require(fetch.requested.first)
        #expect(url.absoluteString.hasPrefix("https://db.filaman.app/api/v1/manufacturers?"))
        #expect(Self.query(url, "search") == "prusament")
        #expect(Self.query(url, "page") == "1")
        #expect(Self.query(url, "page_size") == "200")
    }

    @Test func aBlankManufacturerNameFetchesNothing() async throws {
        let fetch = FakeFetch { _ in Self.manufacturers([(1, "Acme")]) }

        let id = try await fetch.catalog.manufacturerID(named: "   ")

        #expect(id == nil)
        #expect(fetch.requested.isEmpty)
    }

    @Test func pagesStopAtTotalOrCap() async throws {
        let capped = FakeFetch { url in
            let page = Int(Self.query(url, "page") ?? "") ?? 0
            return Self.page(first: (page - 1) * 200, count: 200, total: 450)
        }
        let cappedEntries = try await capped.catalog.filaments(manufacturerID: 5, maxPages: 2)

        #expect(capped.requested.count == 2)
        #expect(cappedEntries.count == 400)
        #expect(capped.requested.allSatisfy { Self.query($0, "manufacturer_id") == "5" })
        #expect(capped.requested.allSatisfy { Self.query($0, "search") == nil })
        #expect(capped.requested.map { Self.query($0, "page") } == ["1", "2"])

        let short = FakeFetch { _ in Self.page(first: 0, count: 150, total: 150) }
        let shortEntries = try await short.catalog.filaments(manufacturerID: 5, maxPages: 5)

        #expect(short.requested.count == 1)
        #expect(shortEntries.count == 150)
    }

    /// FilaManDB shifts between two page reads: id 199 is the last row of page 1
    /// and the first of page 2. The list must not carry it twice (SwiftUI's
    /// `ForEach` needs unique ids).
    @Test func aRowRepeatedOnTwoPagesIsKeptOnce() async throws {
        let fetch = FakeFetch { url in
            let page = Int(Self.query(url, "page") ?? "") ?? 0
            return Self.page(first: page == 1 ? 0 : 199, count: 200, total: 400)
        }

        let entries = try await fetch.catalog.filaments(manufacturerID: 5, maxPages: 2)

        #expect(entries.count == 399)
        #expect(Set(entries.map(\.id)).count == entries.count)
    }

    @Test func anEmptyPageEndsPaging() async throws {
        let fetch = FakeFetch { _ in Self.page(first: 0, count: 0, total: 999) }

        let entries = try await fetch.catalog.filaments(manufacturerID: 5, maxPages: 5)

        #expect(entries.isEmpty)
        #expect(fetch.requested.count == 1)
    }

    // MARK: - Paging

    @Test func searchReadsEveryPageUpToTheTotal() async throws {
        let fetch = FakeFetch { url in
            let page = Int(Self.query(url, "page") ?? "") ?? 0
            return Self.page(first: (page - 1) * 200, count: page < 3 ? 200 : 50, total: 450)
        }

        let entries = try await fetch.catalog.searchFilaments("black", manufacturerID: nil, maxPages: 10)

        #expect(entries.count == 450)
        #expect(fetch.requested.map { Self.query($0, "page") } == ["1", "2", "3"])
        #expect(fetch.requested.allSatisfy { Self.query($0, "search") == "black" })
        #expect(fetch.requested.allSatisfy { Self.query($0, "page_size") == "200" })
    }

    @Test func searchStopsAtTheCap() async throws {
        let fetch = FakeFetch { url in
            let page = Int(Self.query(url, "page") ?? "") ?? 0
            return Self.page(first: (page - 1) * 200, count: 200, total: 5_000)
        }

        let entries = try await fetch.catalog.searchFilaments("pla", manufacturerID: 5, maxPages: 2)

        #expect(entries.count == 400)
        #expect(fetch.requested.count == 2)
        #expect(fetch.requested.allSatisfy { Self.query($0, "manufacturer_id") == "5" })
    }

    @Test func searchPageReadsTheAskedPageAndCountsSkippedRows() async throws {
        // Two raw rows; the second has no manufacturer, so it is skipped.
        let data = Data("""
        {"total":266,"page":2,"page_size":200,"items":[
         {"id":1,"color_name":"A","diameter_mm":1.75,"manufacturer":{"id":1,"name":"Acme"},"material":{"id":1,"name":"PLA"}},
         {"id":2,"color_name":"B","diameter_mm":1.75,"manufacturer":null,"material":{"id":1,"name":"PLA"}}
        ]}
        """.utf8)
        let fetch = FakeFetch { _ in data }

        let page = try await fetch.catalog.searchPage("galaxy", manufacturerID: nil, page: 2)

        let url = try #require(fetch.requested.first)
        #expect(Self.query(url, "page") == "2")
        #expect(Self.query(url, "search") == "galaxy")
        #expect(page.entries.map(\.id) == ["filamandb-1"])
        #expect(page.rowCount == 2, "Raw rows, so they add up to total")
        #expect(page.total == 266)
    }

    @Test func aBlankSearchPageIsEmptyWithoutARequest() async throws {
        let fetch = FakeFetch { _ in Self.fixture }

        let page = try await fetch.catalog.searchPage("  ", manufacturerID: nil, page: 1)

        #expect(page.entries.isEmpty)
        #expect(page.rowCount == 0)
        #expect(page.total == 0)
        #expect(fetch.requested.isEmpty)
    }

    @Test func totalAsksForOneRowAndReadsTheTotal() async throws {
        let fetch = FakeFetch { _ in Self.page(first: 1, count: 1, total: 266) }

        let total = try await fetch.catalog.total("galaxy", manufacturerID: nil)

        #expect(total == 266)
        let url = try #require(fetch.requested.first)
        #expect(fetch.requested.count == 1)
        #expect(Self.query(url, "page_size") == "1")
        #expect(Self.query(url, "page") == "1")
        #expect(Self.query(url, "search") == "galaxy")
    }

    @Test func aBlankTotalIsZeroWithoutARequest() async throws {
        let fetch = FakeFetch { _ in Self.fixture }

        let total = try await fetch.catalog.total(" ", manufacturerID: 79)

        #expect(total == 0)
        #expect(fetch.requested.isEmpty)
    }

    @Test func manufacturerIDIsFoundOnALaterPage() async throws {
        let fetch = FakeFetch { url in
            if Self.query(url, "page") == "1" {
                return Self.manufacturers((1...200).map { ($0, "Prusa \($0)") }, total: 201)
            }
            return Self.manufacturers([(689, "Prusament")], total: 201)
        }

        let id = try await fetch.catalog.manufacturerID(named: "Prusament")

        #expect(id == 689)
        #expect(fetch.requested.map { Self.query($0, "page") } == ["1", "2"])
        #expect(fetch.requested.allSatisfy { Self.query($0, "search") == "Prusament" })
    }

    @Test func manufacturerLookupStopsWhenTheResultsRunOut() async throws {
        let fetch = FakeFetch { _ in Self.manufacturers([(953, "Prusamentos")]) }

        let id = try await fetch.catalog.manufacturerID(named: "Prusament")

        #expect(id == nil)
        #expect(fetch.requested.count == 1)
    }

    @Test func manufacturerLookupStopsAtTheCap() async throws {
        let fetch = FakeFetch { _ in
            Self.manufacturers((1...200).map { ($0, "Other \($0)") }, total: 99_999)
        }

        let id = try await fetch.catalog.manufacturerID(named: "Prusament")

        #expect(id == nil)
        #expect(fetch.requested.count == FilaManDBCatalog.manufacturerLookupMaxPages)
    }

    @Test func manufacturersListsEveryPageWithIdsAndActiveFlags() async throws {
        let fetch = FakeFetch { url in
            if Self.query(url, "page") == "1" {
                return Data(#"{"items":[{"id":1,"name":"Sunlu","is_active":true},{"id":2,"name":"Gone","is_active":false}],"total":4,"page":1,"page_size":200}"#.utf8)
            }
            return Data(#"{"items":[{"id":3,"name":null},{"id":4,"name":"Elegoo"}],"total":4,"page":2,"page_size":200}"#.utf8)
        }

        let list = try await fetch.catalog.manufacturers(maxPages: 5)

        #expect(list.map(\.id) == [1, 2, 4])
        #expect(list.map(\.name) == ["Sunlu", "Gone", "Elegoo"])
        // A row without `is_active` counts as active; a row without a name is skipped.
        #expect(list.map(\.isActive) == [true, false, true])
        #expect(fetch.requested.map { Self.query($0, "page") } == ["1", "2"])
        #expect(fetch.requested.allSatisfy { Self.query($0, "search") == nil && Self.query($0, "page_size") == "200" })
    }

    @Test func manufacturersStopAtTheCap() async throws {
        let fetch = FakeFetch { _ in Self.manufacturers([(1, "Sunlu")], total: 10_000) }

        let list = try await fetch.catalog.manufacturers(maxPages: 3)

        #expect(list.count == 3)
        #expect(fetch.requested.count == 3)
    }

    @Test func requestsGiveUpAfterFifteenSeconds() {
        let url = URL(string: "https://db.filaman.app/api/v1/filaments?page=1")!

        let request = FilaManDBCatalog.request(for: url)

        #expect(request.url == url)
        #expect(request.timeoutInterval == 15)
    }

    @Test func aServerErrorThrows() async {
        let failing = FakeFetch { _ in throw URLError(.badServerResponse) }

        await #expect(throws: (any Error).self) {
            _ = try await failing.catalog.searchFilaments("Galaxy", manufacturerID: nil, maxPages: 1)
        }
        await #expect(throws: (any Error).self) {
            _ = try await failing.catalog.filaments(manufacturerID: 5, maxPages: 2)
        }
        await #expect(throws: (any Error).self) {
            _ = try await failing.catalog.manufacturerID(named: "Acme")
        }
    }

    @Test func anUndecodableBodyThrows() async {
        let garbage = FakeFetch { _ in Data("<html>502</html>".utf8) }

        await #expect(throws: (any Error).self) {
            _ = try await garbage.catalog.searchFilaments("Galaxy", manufacturerID: nil, maxPages: 1)
        }
    }
}
