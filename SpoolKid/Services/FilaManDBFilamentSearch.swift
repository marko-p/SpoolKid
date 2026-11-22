//
//  FilaManDBFilamentSearch.swift
//  SpoolKid
//
//  Purpose: Select Filament's search of FilaManDB on FilaMan. The catalogue
//  is queried per search, not downloaded, and answers 200 rows a page, so this
//  publishes the rows read so far, whether a search is in flight, whether more
//  pages wait, and a message when FilaManDB could not be reached. A slower,
//  older answer (a search or a page of one) never replaces a newer one.
//
//  FilaManDB's `search` is ONE substring matched against a single field
//  (manufacturer, colour/product name or material). A phrase inside one field
//  ("galaxy black") is asked whole and paged as the server answers it, page
//  after page as the list is scrolled. Words spread over fields ("fiberlogy
//  white") match nothing whole; only then is each word counted, the rarest one
//  paged (capped) and its rows kept when they match every word across those
//  fields, like the other lists.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.spoolkid", category: "FilaManDB")

@MainActor
final class FilaManDBFilamentSearch: ObservableObject {
    @Published private(set) var results: [SpoolmanDBFilament] = []
    /// True while a non-blank search is in flight (its first page, or every
    /// page of a several-word fallback).
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    /// The trimmed query `results` answers; nil when nothing was answered
    /// (blank, failed or cancelled).
    @Published private(set) var answeredQuery: String?
    /// Raw rows read so far for the phrase being paged. Changes with every
    /// page, which is what a screen keys its "load the next page" on.
    @Published private(set) var rowsLoaded = 0
    /// More pages of the phrase wait on the server.
    @Published private(set) var hasMore = false
    /// The last page load failed; `loadMore` tries it again.
    @Published private(set) var moreFailed = false

    /// A several-word fallback reads at most this many pages (2,000 rows) of
    /// its rarest word; a rarer word has fewer.
    static let fallbackMaxPages = 10

    private let catalog: FilaManDBCatalog
    /// Counts `search` calls; an answer, or a page of one, is published only
    /// while its call is still the latest.
    private var generation = 0
    /// The phrase `loadMore` pages and the page it reads next.
    private var pagedQuery: String?
    private var nextPage = 2
    private var rowsAvailable = 0
    private var isLoadingMore = false

    init(catalog: FilaManDBCatalog = .live) {
        self.catalog = catalog
    }

    /// True once the latest search answered `text` (trimmed): nothing in
    /// flight, no failure. Text typed since is not answered yet. Pages still
    /// to come do not make it unanswered.
    func hasAnswered(_ text: String) -> Bool {
        let query = Self.trimmed(text)
        return !query.isEmpty && !isLoading && errorMessage == nil && answeredQuery == query
    }

    func search(_ text: String) async {
        generation += 1
        let mine = generation
        let query = Self.trimmed(text)
        errorMessage = nil
        pagedQuery = nil
        hasMore = false
        moreFailed = false
        isLoadingMore = false
        guard !query.isEmpty else {
            results = []
            answeredQuery = nil
            rowsLoaded = 0
            isLoading = false
            return
        }
        isLoading = true
        do {
            let first = try await catalog.searchPage(query, manufacturerID: nil, page: 1)
            guard mine == generation else { return }
            if first.rowCount == 0, query.contains(where: \.isWhitespace) {
                // The words sit in different fields.
                guard try await searchWordsSeparately(query, generation: mine) else { return }
            } else {
                results = first.entries
                rowsLoaded = first.rowCount
                rowsAvailable = first.total
                nextPage = 2
                pagedQuery = query
                hasMore = first.rowCount > 0 && first.rowCount < first.total
            }
            answeredQuery = query
        } catch {
            // A newer search owns the state now.
            guard mine == generation else { return }
            // A search the view dropped (the screen closed) is not a failure.
            if !error.isCancellation {
                results = []
                answeredQuery = nil
                hasMore = false
                errorMessage = "Could not reach FilaManDB: \(error.localizedDescription)"
                logger.error("FilaManDB search failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        isLoading = false
    }

    /// Reads the phrase's next page and adds its rows. Does nothing while a
    /// search or another page is loading, or when no page is left. A failure
    /// keeps the rows read and sets `moreFailed`.
    func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore, let query = pagedQuery else { return }
        let mine = generation
        isLoadingMore = true
        moreFailed = false
        do {
            let page = try await catalog.searchPage(query, manufacturerID: nil, page: nextPage)
            guard mine == generation else { return }
            let known = Set(results.map(\.id))
            results += page.entries.filter { !known.contains($0.id) }
            rowsLoaded += page.rowCount
            rowsAvailable = page.total
            nextPage += 1
            hasMore = page.rowCount > 0 && rowsLoaded < rowsAvailable
        } catch {
            guard mine == generation else { return }
            // A list scrolled away cancels its load: it can ask again.
            if !error.isCancellation {
                moreFailed = true
                logger.error("FilaManDB page \(self.nextPage) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        isLoadingMore = false
    }

    /// The several-word fallback: counts each word (in parallel), pages the
    /// rarest, and publishes the rows matching every word as the pages arrive.
    /// A word nothing contains means no row holds them all, so no page is read.
    /// False when a newer search took over.
    private func searchWordsSeparately(_ query: String, generation mine: Int) async throws -> Bool {
        let words = Self.distinctWords(of: query)
        let catalog = self.catalog
        let totals = try await withThrowingTaskGroup(of: (Int, Int).self) { group in
            for (index, word) in words.enumerated() {
                group.addTask { (index, try await catalog.total(word, manufacturerID: nil)) }
            }
            var byIndex: [Int: Int] = [:]
            for try await (index, total) in group { byIndex[index] = total }
            return words.indices.map { (word: words[$0], total: byIndex[$0] ?? 0) }
        }
        guard mine == generation else { return false }
        results = []
        rowsLoaded = 0
        guard let word = Self.fallbackWord(among: totals) else { return true }

        var matches: [SpoolmanDBFilament] = []
        var rowsRead = 0
        for page in 1...Self.fallbackMaxPages {
            let result = try await catalog.searchPage(word, manufacturerID: nil, page: page)
            guard mine == generation else { return false }
            let wanted = result.entries.filter {
                SearchQuery.matches(query, in: [$0.manufacturer, $0.name, $0.material])
            }
            let known = Set(matches.map(\.id))
            matches += wanted.filter { !known.contains($0.id) }
            results = matches
            rowsRead += result.rowCount
            if result.rowCount == 0 || rowsRead >= result.total { break }
        }
        return true
    }

    /// The query's words, each once (case-insensitively), in the order typed.
    nonisolated static func distinctWords(of query: String) -> [String] {
        var seen = Set<String>()
        return query.split(whereSeparator: \.isWhitespace).map(String.init).filter {
            seen.insert($0.lowercased()).inserted
        }
    }

    /// The word to page when a phrase found nothing whole: the one with the
    /// fewest rows (the first of equals). Nil when there is none, or when any
    /// word has no rows at all, because then no row can hold every word.
    nonisolated static func fallbackWord(among totals: [(word: String, total: Int)]) -> String? {
        guard !totals.isEmpty, totals.allSatisfy({ $0.total > 0 }) else { return nil }
        return totals.reduce(totals[0]) { $1.total < $0.total ? $1 : $0 }.word
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
