//
//  FilaManDBFilamentSearchTests.swift
//  SpoolKidTests
//
//  Purpose: Select Filament's FilaManDB search on FilaMan: what it publishes,
//  that a failure is reported and names FilaManDB, that a slower, older
//  answer or page never replaces a newer one, that a phrase is paged 200 rows
//  at a time, how several words that sit in different fields are found, and
//  that a blank query clears. No test touches the network; every call goes
//  through an injected fetch.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

/// A fetch the test controls: it records each request, answers from `answer`,
/// and can hold the request `hold` picks until `release` hands it an answer.
private nonisolated final class ScriptedFetch: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private var held: CheckedContinuation<Data, Never>?
    private var isHeld = false
    private let hold: (@Sendable (URL) -> Bool)?
    private let answer: @Sendable (URL) throws -> Data

    init(hold: (@Sendable (URL) -> Bool)? = nil, answer: @escaping @Sendable (URL) throws -> Data) {
        self.hold = hold
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
            if let hold = self.hold, hold(url) {
                return await withCheckedContinuation { continuation in
                    self.park(continuation)
                }
            }
            return try self.answer(url)
        })
    }

    /// True once the held request is waiting; false after five seconds, so a
    /// request that never comes fails the test instead of hanging it.
    func waitUntilHeld() async -> Bool {
        for _ in 0..<500 {
            lock.lock()
            let ready = isHeld
            lock.unlock()
            if ready { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func release(with data: Data) {
        lock.lock()
        let continuation = held
        held = nil
        isHeld = false
        lock.unlock()
        continuation?.resume(returning: data)
    }

    private func record(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        urls.append(url)
    }

    private func park(_ continuation: CheckedContinuation<Data, Never>) {
        lock.lock()
        held = continuation
        isHeld = true
        lock.unlock()
    }

    static func search(_ url: URL) -> String? { value(url, "search") }
    static func page(_ url: URL) -> Int? { value(url, "page").flatMap(Int.init) }
    static func pageSize(_ url: URL) -> Int? { value(url, "page_size").flatMap(Int.init) }

    private static func value(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }
}

/// Counts calls from inside a `@Sendable` closure.
private nonisolated final class Attempts: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}

@MainActor
struct FilaManDBFilamentSearchTests {
    /// One /filaments page as measured 2026-10-18, trimmed to the fields read.
    private nonisolated static let fixture = Data("""
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

    /// What the slow, older "gal" search answers with: one row the newer
    /// search never returns.
    private nonisolated static let galOnly = Data("""
    {"total":1,"page":1,"page_size":200,"items":[
     {"id":999,"color_name":"Galvanised Grey","designation":"x","hex_color":"#888888",
      "diameter_mm":1.75,"density_g_cm3":1.24,"nominal_weight_g":1000,
      "manufacturer":{"id":5,"name":"Acme"},"material":{"id":1,"key":"pla","name":"PLA"},
      "spool_profile":null}
    ]}
    """.utf8)

    /// What the server returns for the word "fiberlogy" or "white": two
    /// Fiberlogy PLA rows (white, black) and a Polymaker white one.
    private nonisolated static let brandPage = Data("""
    {"total":3,"page":1,"page_size":200,"items":[
     {"id":1,"color_name":"Easy PLA White","designation":"x","hex_color":"#FFFFFF",
      "diameter_mm":1.75,"density_g_cm3":1.24,"nominal_weight_g":850,
      "manufacturer":{"id":293,"name":"Fiberlogy"},"material":{"id":1,"key":"pla","name":"PLA"},
      "spool_profile":null},
     {"id":2,"color_name":"Easy PLA Black","designation":"x","hex_color":"#000000",
      "diameter_mm":1.75,"density_g_cm3":1.24,"nominal_weight_g":850,
      "manufacturer":{"id":293,"name":"Fiberlogy"},"material":{"id":1,"key":"pla","name":"PLA"},
      "spool_profile":null},
     {"id":3,"color_name":"Polymaker White","designation":"x","hex_color":"#FFFFFF",
      "diameter_mm":1.75,"density_g_cm3":1.24,"nominal_weight_g":1000,
      "manufacturer":{"id":7,"name":"Polymaker"},"material":{"id":1,"key":"pla","name":"PLA"},
      "spool_profile":null}
    ]}
    """.utf8)

    private nonisolated static let emptyPage = Data(#"{"total":0,"page":1,"page_size":200,"items":[]}"#.utf8)

    /// Row `id` of a generated catalogue: "Black <id>" PLA, made by Acme when
    /// the id is even and by Other when it is odd.
    private nonisolated static func row(_ id: Int) -> String {
        """
        {"id":\(id),"color_name":"Black \(id)","designation":"x","hex_color":"#000000",
         "diameter_mm":1.75,"density_g_cm3":1.24,"nominal_weight_g":1000,
         "manufacturer":{"id":5,"name":"\(id % 2 == 0 ? "Acme" : "Other")"},
         "material":{"id":1,"key":"pla","name":"PLA"},"spool_profile":null}
        """
    }

    /// Page `page` (1-based) of `size` rows from a generated catalogue of
    /// `total` rows, numbered from 1.
    private nonisolated static func catalogue(page: Int, size: Int, total: Int) -> Data {
        let first = (page - 1) * size + 1
        let last = min(page * size, total)
        let rows = first <= last ? (first...last).map(row) : []
        return Data("{\"total\":\(total),\"page\":\(page),\"page_size\":\(size),\"items\":[\(rows.joined(separator: ","))]}".utf8)
    }

    /// The catalogue's page for whatever page and size `url` asks.
    private nonisolated static func catalogue(for url: URL, total: Int) -> Data {
        catalogue(page: ScriptedFetch.page(url) ?? 1, size: ScriptedFetch.pageSize(url) ?? 200, total: total)
    }

    /// A server where only a single word is found (a phrase with a space is
    /// empty, as when its words sit in different fields) and each word has the
    /// rows `totals` says, answered from the generated catalogue.
    private nonisolated static func oneFieldServer(totals: [String: Int]) -> @Sendable (URL) throws -> Data {
        { url in
            let query = ScriptedFetch.search(url) ?? ""
            if query.contains(" ") { return emptyPage }
            return catalogue(for: url, total: totals[query] ?? 0)
        }
    }

    private static func searches(_ fetch: ScriptedFetch) -> [String] {
        fetch.requested.map { ScriptedFetch.search($0) ?? "" }
    }

    /// The requests asking for rows (200 a page), not just a count.
    private static func pageRequests(_ fetch: ScriptedFetch) -> [URL] {
        fetch.requested.filter { ScriptedFetch.pageSize($0) == 200 }
    }

    /// The requests asking only for a word's count (one row).
    private static func countRequests(_ fetch: ScriptedFetch) -> [URL] {
        fetch.requested.filter { ScriptedFetch.pageSize($0) == 1 }
    }

    // MARK: - One answer

    @Test func searchPublishesResults() async throws {
        let fetch = ScriptedFetch { _ in Self.fixture }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        await search.search("galaxy")

        #expect(search.results.map(\.name) == ["Galaxy Black", "30D White"])
        #expect(!search.isLoading)
        #expect(search.errorMessage == nil)
        #expect(search.hasAnswered("galaxy"))
        let url = try #require(fetch.requested.first)
        #expect(ScriptedFetch.search(url) == "galaxy")
    }

    @Test func aFailedSearchReportsIt() async {
        let fetch = ScriptedFetch { _ in throw URLError(.notConnectedToInternet) }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        await search.search("galaxy")

        let message = search.errorMessage
        #expect(message?.contains("FilaManDB") == true)
        #expect(search.results.isEmpty)
        #expect(!search.isLoading)
        #expect(!search.hasAnswered("galaxy"))
    }

    @Test func aFailureClearsTheOlderResults() async {
        let attempts = Attempts()
        let fetch = ScriptedFetch { _ in
            if attempts.next() == 1 { return Self.fixture }
            throw URLError(.timedOut)
        }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        await search.search("galaxy")
        await search.search("galaxy b")

        #expect(search.results.isEmpty)
        #expect(search.errorMessage != nil)
    }

    @Test func aNewSearchClearsTheOlderError() async {
        let attempts = Attempts()
        let fetch = ScriptedFetch { _ in
            if attempts.next() == 1 { throw URLError(.timedOut) }
            return Self.fixture
        }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        await search.search("galaxy")
        await search.search("galaxy")

        #expect(search.errorMessage == nil)
        #expect(search.results.count == 2)
    }

    @Test func aStaleAnswerIsDropped() async {
        let fetch = ScriptedFetch(hold: { ScriptedFetch.search($0) == "gal" }) { _ in Self.fixture }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        let older = Task { await search.search("gal") }
        #expect(await fetch.waitUntilHeld())
        #expect(search.isLoading)

        await search.search("galaxy")
        #expect(search.results.map(\.name) == ["Galaxy Black", "30D White"])
        #expect(!search.isLoading)

        fetch.release(with: Self.galOnly)
        await older.value

        #expect(search.results.map(\.name) == ["Galaxy Black", "30D White"])
        #expect(!search.isLoading)
        #expect(search.errorMessage == nil)
        #expect(search.hasAnswered("galaxy"))
        #expect(!search.hasAnswered("gal"))
    }

    @Test func aStaleFailureIsDropped() async {
        let fetch = ScriptedFetch(hold: { ScriptedFetch.search($0) == "gal" }) { _ in Self.fixture }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        let older = Task { await search.search("gal") }
        #expect(await fetch.waitUntilHeld())
        await search.search("galaxy")

        fetch.release(with: Data("not json".utf8))
        await older.value

        #expect(search.results.count == 2)
        #expect(search.errorMessage == nil)
    }

    @Test func blankClears() async {
        let fetch = ScriptedFetch { _ in Self.fixture }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)
        await search.search("galaxy")
        #expect(fetch.requested.count == 1)

        await search.search("  ")

        #expect(search.results.isEmpty)
        #expect(!search.isLoading)
        #expect(search.errorMessage == nil)
        #expect(fetch.requested.count == 1, "A blank query asks nothing")
        #expect(!search.hasAnswered("  "))
    }

    @Test func blankDropsASearchStillInFlight() async {
        let fetch = ScriptedFetch(hold: { ScriptedFetch.search($0) == "gal" }) { _ in Self.fixture }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        let older = Task { await search.search("gal") }
        #expect(await fetch.waitUntilHeld())
        await search.search("")
        fetch.release(with: Self.galOnly)
        await older.value

        #expect(search.results.isEmpty)
        #expect(!search.isLoading)
    }

    @Test func aCancelledSearchIsNotAnError() async {
        let fetch = ScriptedFetch { _ in throw CancellationError() }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        await search.search("galaxy")

        #expect(search.errorMessage == nil)
        #expect(!search.isLoading)
        #expect(!search.hasAnswered("galaxy"))
    }

    @Test func hasAnsweredNeedsTheQueryThatWasAnswered() async {
        let fetch = ScriptedFetch { _ in Self.fixture }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)
        #expect(!search.hasAnswered("galaxy"), "Nothing has been asked yet")

        await search.search("  galaxy ")

        #expect(search.hasAnswered("galaxy"))
        #expect(search.hasAnswered(" galaxy"))
        #expect(!search.hasAnswered("galaxy b"))
    }

    // MARK: - Pages of one phrase

    @Test func aSingleWordMakesOnePageRequestAndIsNotFilteredLocally() async {
        let fetch = ScriptedFetch { _ in Self.brandPage }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        // Everything the server returned stays, even the Polymaker row that a
        // local filter on "fiberlogy" would drop: the server may have matched a
        // field the filter does not read.
        await search.search("fiberlogy")

        #expect(fetch.requested.count == 1)
        #expect(search.results.map(\.id) == ["filamandb-1", "filamandb-2", "filamandb-3"])
        #expect(!search.hasMore)
    }

    @Test func aPhraseTheServerAnswersIsAskedWholeAndNotFiltered() async throws {
        let fetch = ScriptedFetch { _ in Self.brandPage }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        await search.search("galaxy black")

        let url = try #require(fetch.requested.first)
        #expect(fetch.requested.count == 1, "A non-empty answer needs no other request")
        #expect(url.absoluteString.contains("search=galaxy%20black"))
        #expect(search.results.map(\.id) == ["filamandb-1", "filamandb-2", "filamandb-3"])
        #expect(search.hasAnswered("galaxy black"))
    }

    @Test func theNextPageLoadsWhenAskedAndStopsAtTheTotal() async {
        let fetch = ScriptedFetch { url in Self.catalogue(for: url, total: 450) }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        await search.search("black")
        #expect(search.results.count == 200)
        #expect(search.rowsLoaded == 200)
        #expect(search.hasMore)
        #expect(search.hasAnswered("black"))

        await search.loadMore()
        #expect(search.results.count == 400)
        #expect(search.rowsLoaded == 400)
        #expect(search.hasMore)

        await search.loadMore()
        #expect(search.results.count == 450)
        #expect(!search.hasMore, "All 450 rows are in")
        #expect(search.hasAnswered("black"), "Pages do not make the search unanswered")

        await search.loadMore()
        #expect(fetch.requested.map { ScriptedFetch.page($0) } == [1, 2, 3], "No request past the total")
        #expect(fetch.requested.allSatisfy { ScriptedFetch.search($0) == "black" && ScriptedFetch.pageSize($0) == 200 })
        #expect(Set(search.results.map(\.id)).count == 450)
    }

    @Test func aPhraseIsPagedWholeToo() async {
        let fetch = ScriptedFetch { url in Self.catalogue(for: url, total: 250) }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        await search.search("galaxy black")
        await search.loadMore()

        #expect(search.results.count == 250)
        #expect(fetch.requested.allSatisfy { ScriptedFetch.search($0) == "galaxy black" })
    }

    @Test func loadMoreWithNothingLeftAsksNothing() async {
        let fetch = ScriptedFetch { _ in Self.fixture }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)
        await search.search("galaxy")

        await search.loadMore()

        #expect(fetch.requested.count == 1)
        #expect(search.results.count == 2)
    }

    @Test func aNewSearchEndsThePagingOfTheOldOne() async {
        let fetch = ScriptedFetch { url in Self.catalogue(for: url, total: 450) }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)
        await search.search("black")
        #expect(search.hasMore)

        await search.search("")
        await search.loadMore()

        #expect(!search.hasMore)
        #expect(search.rowsLoaded == 0)
        #expect(search.results.isEmpty)
        #expect(fetch.requested.count == 1)
    }

    @Test func aStalePageLoadIsDroppedAfterANewerSearch() async {
        let fetch = ScriptedFetch(hold: { ScriptedFetch.search($0) == "black" && ScriptedFetch.page($0) == 2 }) { url in
            ScriptedFetch.search(url) == "galaxy" ? Self.fixture : Self.catalogue(for: url, total: 450)
        }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)
        await search.search("black")

        let older = Task { await search.loadMore() }
        #expect(await fetch.waitUntilHeld())

        await search.search("galaxy")
        fetch.release(with: Self.catalogue(page: 2, size: 200, total: 450))
        await older.value

        #expect(search.results.map(\.name) == ["Galaxy Black", "30D White"], "The late page of the old search is not added")
        #expect(search.rowsLoaded == 2)
        #expect(!search.hasMore)
        #expect(search.hasAnswered("galaxy"))
    }

    @Test func aFailedPageKeepsTheRowsAndCanBeRetried() async {
        let page2 = Attempts()
        let fetch = ScriptedFetch { url in
            if ScriptedFetch.page(url) == 2, page2.next() == 1 { throw URLError(.timedOut) }
            return Self.catalogue(for: url, total: 450)
        }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)
        await search.search("black")

        await search.loadMore()
        #expect(search.moreFailed)
        #expect(search.results.count == 200, "The rows already read stay")
        #expect(search.errorMessage == nil, "The list is not replaced by an error")
        #expect(search.hasMore)

        await search.loadMore()
        #expect(!search.moreFailed)
        #expect(search.results.count == 400)
    }

    @Test func aCancelledPageIsNotAFailure() async {
        let fetch = ScriptedFetch { url in
            if ScriptedFetch.page(url) == 2 { throw CancellationError() }
            return Self.catalogue(for: url, total: 450)
        }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)
        await search.search("black")

        await search.loadMore()

        #expect(!search.moreFailed)
        #expect(search.hasMore, "The page can be asked again")
        #expect(search.results.count == 200)
    }

    // MARK: - Words in different fields

    @Test func fallbackWordIsTheOneWithTheFewestRows() {
        #expect(FilaManDBFilamentSearch.fallbackWord(among: [("fiberlogy", 171), ("white", 1697)]) == "fiberlogy")
        #expect(FilaManDBFilamentSearch.fallbackWord(among: [("white", 1697), ("fiberlogy", 171), ("pla", 15755)]) == "fiberlogy")
    }

    @Test func fallbackWordTiesGoToTheFirst() {
        #expect(FilaManDBFilamentSearch.fallbackWord(among: [("pla", 40), ("tpu", 40)]) == "pla")
        #expect(FilaManDBFilamentSearch.fallbackWord(among: [("a", 9), ("b", 5), ("c", 5)]) == "b")
    }

    @Test func aWordWithNoRowsLeavesNoFallbackWord() {
        #expect(FilaManDBFilamentSearch.fallbackWord(among: [("fiberlogy", 171), ("purple", 0)]) == nil)
        #expect(FilaManDBFilamentSearch.fallbackWord(among: []) == nil)
    }

    @Test func distinctWordsKeepTheOrderTypedAndDropRepeats() {
        #expect(FilaManDBFilamentSearch.distinctWords(of: "Fiberlogy  white") == ["Fiberlogy", "white"])
        #expect(FilaManDBFilamentSearch.distinctWords(of: "black BLACK pla black") == ["black", "pla"])
        #expect(FilaManDBFilamentSearch.distinctWords(of: "pla") == ["pla"])
    }

    @Test func severalWordsFallBackToTheRarestWordAndFilterAcrossFields() async {
        // "acme" has 30 rows, "black" 2,447: acme is the word read. Its rows
        // all hold "black" in the name; the odd ids are made by Other, so the
        // manufacturer and the name are matched across fields for the rest.
        let fetch = ScriptedFetch(answer: Self.oneFieldServer(totals: ["acme": 30, "black": 2447]))
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        await search.search("acme black")

        #expect(Self.searches(fetch).first == "acme black", "The whole phrase is asked first")
        #expect(Set(Self.countRequests(fetch).compactMap { ScriptedFetch.search($0) }) == ["acme", "black"])
        let pages = Self.pageRequests(fetch)
        #expect(pages.compactMap { ScriptedFetch.search($0) } == ["acme black", "acme"], "Only the rarest word's rows are read")
        #expect(search.results.count == 15, "Manufacturer (Acme) and name (Black) match across fields")
        #expect(search.results.allSatisfy { $0.manufacturer == "Acme" && $0.name.contains("Black") })
        #expect(search.hasAnswered("acme black"))
        #expect(search.errorMessage == nil)
        #expect(!search.hasMore)
    }

    @Test func theLocalFilterNarrowsTheRarestWordsRows() async {
        // Now "black" is the rarest word: all 30 rows hold it in the name, but
        // only the even ids are made by Acme, so the other word narrows them.
        let fetch = ScriptedFetch(answer: Self.oneFieldServer(totals: ["acme": 900, "black": 30]))
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        await search.search("acme black")

        #expect(search.results.count == 15)
        #expect(search.results.allSatisfy { $0.manufacturer == "Acme" })
    }

    @Test func aWordWithNoRowsAnswersEmptyWithoutReadingPages() async {
        let fetch = ScriptedFetch(answer: Self.oneFieldServer(totals: ["fiberlogy": 171, "purple": 0]))
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        await search.search("fiberlogy purple")

        #expect(search.results.isEmpty)
        #expect(search.errorMessage == nil)
        #expect(search.hasAnswered("fiberlogy purple"), "An empty answer is still an answer")
        #expect(Self.pageRequests(fetch).compactMap { ScriptedFetch.search($0) } == ["fiberlogy purple"], "No word's rows are read")
        #expect(Self.countRequests(fetch).count == 2)
    }

    @Test func theFallbackPublishesMatchesAsPagesArrive() async {
        // "black" has 450 rows over three pages; page 2 is held.
        let fetch = ScriptedFetch(
            hold: { ScriptedFetch.search($0) == "black" && ScriptedFetch.page($0) == 2 && ScriptedFetch.pageSize($0) == 200 },
            answer: Self.oneFieldServer(totals: ["acme": 900, "black": 450])
        )
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        let running = Task { await search.search("acme black") }
        #expect(await fetch.waitUntilHeld())
        #expect(search.results.count == 100, "Page 1's Acme rows are already shown")
        #expect(search.isLoading)
        #expect(!search.hasAnswered("acme black"))

        fetch.release(with: Self.catalogue(page: 2, size: 200, total: 450))
        await running.value

        #expect(search.results.count == 225, "Even ids of 450")
        #expect(!search.isLoading)
        #expect(search.hasAnswered("acme black"))
        #expect(Self.pageRequests(fetch).compactMap { ScriptedFetch.page($0) } == [1, 1, 2, 3])
    }

    @Test func theFallbackReadsAtMostTenPages() async {
        let fetch = ScriptedFetch(answer: Self.oneFieldServer(totals: ["acme": 90_000, "black": 5_000]))
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        await search.search("acme black")

        let wordPages = Self.pageRequests(fetch).filter { ScriptedFetch.search($0) == "black" }
        #expect(wordPages.compactMap { ScriptedFetch.page($0) } == Array(1...FilaManDBFilamentSearch.fallbackMaxPages))
        #expect(FilaManDBFilamentSearch.fallbackMaxPages == 10)
        #expect(search.results.count == 1000, "Even ids of the first 2,000 rows")
        #expect(search.hasAnswered("acme black"))
    }

    @Test func aNewerSearchStartedDuringTheFallbackPagesWins() async {
        let fetch = ScriptedFetch(
            hold: { ScriptedFetch.search($0) == "black" && ScriptedFetch.page($0) == 2 && ScriptedFetch.pageSize($0) == 200 },
            answer: { url in
                let query = ScriptedFetch.search(url) ?? ""
                if query == "galaxy" { return Self.fixture }
                return try Self.oneFieldServer(totals: ["acme": 900, "black": 450])(url)
            }
        )
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        let older = Task { await search.search("acme black") }
        #expect(await fetch.waitUntilHeld())
        await search.search("galaxy")

        fetch.release(with: Self.catalogue(page: 2, size: 200, total: 450))
        await older.value

        #expect(search.results.map(\.name) == ["Galaxy Black", "30D White"])
        #expect(!search.isLoading)
        #expect(search.hasAnswered("galaxy"))
        #expect(!search.hasAnswered("acme black"))
        #expect(Self.pageRequests(fetch).compactMap { ScriptedFetch.page($0) }.filter { $0 > 1 }.count == 1, "Page 3 was never asked for")
    }

    @Test func aNewerSearchStartedDuringTheCountsWins() async {
        let fetch = ScriptedFetch(
            hold: { ScriptedFetch.search($0) == "black" && ScriptedFetch.pageSize($0) == 1 },
            answer: { url in
                let query = ScriptedFetch.search(url) ?? ""
                if query == "galaxy" { return Self.fixture }
                return try Self.oneFieldServer(totals: ["acme": 900, "black": 450])(url)
            }
        )
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        let older = Task { await search.search("acme black") }
        #expect(await fetch.waitUntilHeld())
        await search.search("galaxy")

        fetch.release(with: Self.catalogue(page: 1, size: 1, total: 450))
        await older.value

        #expect(search.results.map(\.name) == ["Galaxy Black", "30D White"])
        #expect(Self.pageRequests(fetch).compactMap { ScriptedFetch.search($0) } == ["acme black", "galaxy"], "The old search read no word's rows")
    }

    @Test func aFailedCountReportsIt() async {
        let fetch = ScriptedFetch { url in
            if ScriptedFetch.pageSize(url) == 1 { throw URLError(.timedOut) }
            return Self.emptyPage
        }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        await search.search("acme black")

        #expect(search.errorMessage?.contains("FilaManDB") == true)
        #expect(search.results.isEmpty)
        #expect(!search.isLoading)
        #expect(!search.hasAnswered("acme black"))
    }

    @Test func aFailedFallbackPageReportsItAndClearsTheRows() async {
        let fetch = ScriptedFetch { url in
            if ScriptedFetch.search(url) == "black", ScriptedFetch.page(url) == 2, ScriptedFetch.pageSize(url) == 200 {
                throw URLError(.timedOut)
            }
            return try Self.oneFieldServer(totals: ["acme": 900, "black": 450])(url)
        }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        await search.search("acme black")

        #expect(search.errorMessage?.contains("FilaManDB") == true)
        #expect(search.results.isEmpty)
        #expect(!search.hasAnswered("acme black"))
    }

    @Test func aCancelledFallbackIsNotAnError() async {
        let fetch = ScriptedFetch { url in
            if ScriptedFetch.pageSize(url) == 1 { throw CancellationError() }
            return Self.emptyPage
        }
        let search = FilaManDBFilamentSearch(catalog: fetch.catalog)

        await search.search("acme black")

        #expect(search.errorMessage == nil)
        #expect(!search.isLoading)
        #expect(!search.hasAnswered("acme black"))
    }
}
