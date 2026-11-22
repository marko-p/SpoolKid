//
//  FilaManDBCatalog.swift
//  SpoolKid
//
//  Purpose: FilaManDB's public filaments, read live and mapped into
//  SpoolKid's one catalogue entry (`SpoolmanDBFilament`), so Select Filament,
//  Scan Result and the spool-weight lookups treat both catalogues alike.
//  FilaManDB is queried per search, not downloaded whole: its `/filaments`
//  runs to thousands of rows and takes a text search and a manufacturer.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// One page of `GET https://db.filaman.app/api/v1/filaments`
/// (measured 2026-10-18). Every field a row may lack is optional, so a sparse
/// row decodes and is skipped by the mapping rather than failing the page.
private nonisolated struct FilaManDBFilamentPage: Decodable {
    nonisolated struct Named: Decodable {
        let name: String?
    }

    nonisolated struct SpoolProfile: Decodable {
        let emptyWeightG: Double?
        let spoolMaterial: String?

        enum CodingKeys: String, CodingKey {
            case emptyWeightG = "empty_weight_g"
            case spoolMaterial = "spool_material"
        }
    }

    nonisolated struct Item: Decodable {
        let id: Int
        let colorName: String?
        let designation: String?
        let hexColor: String?
        let diameterMm: Double?
        let densityGCm3: Double?
        let nominalWeightG: Double?
        let manufacturer: Named?
        let material: Named?
        let spoolProfile: SpoolProfile?

        enum CodingKeys: String, CodingKey {
            case id
            case colorName = "color_name"
            case designation
            case hexColor = "hex_color"
            case diameterMm = "diameter_mm"
            case densityGCm3 = "density_g_cm3"
            case nominalWeightG = "nominal_weight_g"
            case manufacturer
            case material
            case spoolProfile = "spool_profile"
        }
    }

    let items: [Item]
    let total: Int
}

/// One page of `GET https://db.filaman.app/api/v1/manufacturers`
/// (measured 2026-10-12: 327 manufacturers, `page_size` at most 200); the id
/// is what `/filaments` filters on.
private nonisolated struct FilaManDBManufacturerPage: Decodable {
    nonisolated struct Item: Decodable {
        let id: Int
        /// A row without one is skipped.
        let name: String?
        /// Absent counts as active.
        let isActive: Bool?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case isActive = "is_active"
        }
    }

    let items: [Item]
    let total: Int?
}

nonisolated struct FilaManDBCatalog: Sendable {
    /// Returns one response body. A non-2xx status or a transport failure
    /// throws, so the caller never decodes an error page.
    let fetch: @Sendable (URL) async throws -> Data

    static let baseURL = "https://db.filaman.app/api/v1"
    /// The API's maximum; a larger `page_size` answers 422.
    static let pageSize = 200

    /// How long one request may take. `URLSession`'s default is 60 s, which
    /// leaves Select Filament spinning for a minute on a stalled network before
    /// it says FilaManDB could not be reached.
    static let requestTimeout: TimeInterval = 15

    static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        return request
    }

    static let live = FilaManDBCatalog(fetch: { url in
        let (data, response) = try await URLSession.shared.data(for: FilaManDBCatalog.request(for: url))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    })

    /// One page of `/filaments`: the mapped entries, and the counts a caller
    /// pages by. `rowCount` is the raw rows on the page, before the rows
    /// SpoolKid cannot import are skipped, so `rowCount` summed over the pages
    /// read is comparable with `total`.
    nonisolated struct Page: Sendable {
        let entries: [SpoolmanDBFilament]
        let rowCount: Int
        /// Rows matching the whole query, over every page.
        let total: Int
    }

    /// The most pages `manufacturerID(named:)` reads (200 manufacturers each).
    static let manufacturerLookupMaxPages = 5

    /// One page of matches (1-based). Blank query → an empty page without a
    /// request.
    func searchPage(_ query: String, manufacturerID: Int?, page: Int) async throws -> Page {
        guard let items = Self.searchItems(query, manufacturerID: manufacturerID) else {
            return Page(entries: [], rowCount: 0, total: 0)
        }
        return try await fetchPage(page, items)
    }

    /// Every match, page by page, at most `maxPages` pages. Blank query → []
    /// without a request.
    func searchFilaments(_ query: String, manufacturerID: Int?, maxPages: Int) async throws -> [SpoolmanDBFilament] {
        guard let items = Self.searchItems(query, manufacturerID: manufacturerID) else { return [] }
        return try await allPages(items, maxPages: maxPages)
    }

    /// Every filament of one manufacturer, page by page, at most `maxPages`
    /// pages.
    func filaments(manufacturerID: Int, maxPages: Int) async throws -> [SpoolmanDBFilament] {
        try await allPages([URLQueryItem(name: "manufacturer_id", value: String(manufacturerID))], maxPages: maxPages)
    }

    /// How many filaments match, without reading them: one row requested, only
    /// `total` read. Blank query → 0 without a request.
    func total(_ query: String, manufacturerID: Int?) async throws -> Int {
        guard let items = Self.searchItems(query, manufacturerID: manufacturerID) else { return 0 }
        return try await fetchPage(1, items, pageSize: 1).total
    }

    /// One manufacturer of `/manufacturers`.
    nonisolated struct Manufacturer: Sendable {
        let id: Int
        let name: String
        let isActive: Bool
    }

    /// Every manufacturer, page by page, at most `maxPages` pages. A row
    /// without a name is skipped; one without `is_active` counts as active.
    func manufacturers(maxPages: Int) async throws -> [Manufacturer] {
        var manufacturers: [Manufacturer] = []
        try await readManufacturerPages(search: nil, maxPages: maxPages) { rows in
            manufacturers += rows.compactMap { row in
                row.name.map { Manufacturer(id: row.id, name: $0, isActive: row.isActive ?? true) }
            }
            return false
        }
        return manufacturers
    }

    /// The id whose name has the same `ManufacturerName.key`, or nil. FilaManDB's
    /// `search` is a partial match ("Prusa" also lists "Prusament"), so the
    /// answer is picked from the pages, not taken from the first row; pages are
    /// read until a name matches, they run out, or `manufacturerLookupMaxPages`.
    func manufacturerID(named name: String) async throws -> Int? {
        let wanted = ManufacturerName.key(name)
        guard !wanted.isEmpty else { return nil }
        var found: Int?
        try await readManufacturerPages(
            search: name.trimmingCharacters(in: .whitespacesAndNewlines),
            maxPages: Self.manufacturerLookupMaxPages
        ) { rows in
            found = rows.first(where: { ($0.name.map(ManufacturerName.key) ?? "") == wanted })?.id
            return found != nil
        }
        return found
    }

    /// The mapping, exposed for tests.
    static func entries(fromPage data: Data) throws -> [SpoolmanDBFilament] {
        try decodePage(data).items.compactMap(entry(from:))
    }

    // MARK: - Private

    private static func decodePage(_ data: Data) throws -> FilaManDBFilamentPage {
        try JSONDecoder().decode(FilaManDBFilamentPage.self, from: data)
    }

    /// The query items of a text search, or nil for a blank text.
    private static func searchItems(_ query: String, manufacturerID: Int?) -> [URLQueryItem]? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var items = [URLQueryItem(name: "search", value: text)]
        if let manufacturerID {
            items.append(URLQueryItem(name: "manufacturer_id", value: String(manufacturerID)))
        }
        return items
    }

    private func fetchPage(_ page: Int, _ items: [URLQueryItem], pageSize: Int = Self.pageSize) async throws -> Page {
        let url = Self.url(path: "filaments", page: page, items, pageSize: pageSize)
        let decoded = try Self.decodePage(try await fetch(url))
        return Page(
            entries: decoded.items.compactMap(Self.entry(from:)),
            rowCount: decoded.items.count,
            total: decoded.total
        )
    }

    /// The filaments pager: pages 1… until the rows read reach `total`, a page
    /// is empty, or `maxPages` pages have been read. A row that FilaManDB's
    /// shifting repeats on a later page is kept once, as `loadMore` does.
    private func allPages(_ items: [URLQueryItem], maxPages: Int) async throws -> [SpoolmanDBFilament] {
        var entries: [SpoolmanDBFilament] = []
        var seen = Set<String>()
        var rowsSeen = 0
        var page = 1
        while page <= maxPages {
            let result = try await fetchPage(page, items)
            guard result.rowCount > 0 else { break }
            rowsSeen += result.rowCount
            entries += result.entries.filter { seen.insert($0.id).inserted }
            if rowsSeen >= result.total { break }
            page += 1
        }
        return entries
    }

    /// The manufacturers pager: pages 1…, optionally filtered by `search`,
    /// each page's rows handed to `visit`, until `visit` returns true, the rows
    /// read reach `total` (a missing one counts as 0), a page is empty, or
    /// `maxPages` pages have been read.
    private func readManufacturerPages(
        search: String?,
        maxPages: Int,
        _ visit: ([FilaManDBManufacturerPage.Item]) -> Bool
    ) async throws {
        let items = search.map { [URLQueryItem(name: "search", value: $0)] } ?? []
        var rowsSeen = 0
        var page = 1
        while page <= maxPages {
            let url = Self.url(path: "manufacturers", page: page, items)
            let decoded = try JSONDecoder().decode(FilaManDBManufacturerPage.self, from: try await fetch(url))
            guard !decoded.items.isEmpty else { return }
            if visit(decoded.items) { return }
            rowsSeen += decoded.items.count
            if rowsSeen >= (decoded.total ?? 0) { return }
            page += 1
        }
    }

    /// `page` and `page_size` first, then `items`, percent-encoded. A `+` stays
    /// literal in `URLComponents`' query, which a server reads as a space
    /// ("PLA+" would search "PLA "), so it is encoded here.
    private static func url(path: String, page: Int, _ items: [URLQueryItem], pageSize: Int = Self.pageSize) -> URL {
        var components = URLComponents(string: "\(baseURL)/\(path)")!
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize))
        ] + items
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    /// Nil for a row without a manufacturer, material or diameter: SpoolKid
    /// cannot import a filament that lacks them.
    private static func entry(from item: FilaManDBFilamentPage.Item) -> SpoolmanDBFilament? {
        guard let manufacturer = nonBlank(item.manufacturer?.name),
              let material = nonBlank(item.material?.name),
              let diameter = item.diameterMm
        else { return nil }
        return SpoolmanDBFilament(
            id: "filamandb-\(item.id)",
            manufacturer: manufacturer,
            name: displayName(of: item),
            material: material,
            spoolType: item.spoolProfile?.spoolMaterial,
            density: item.densityGCm3,
            weight: item.nominalWeightG,
            spoolWeight: item.spoolProfile?.emptyWeightG,
            diameter: diameter,
            colorHex: nonBlank(item.hexColor.map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }),
            extruderTemp: nil,
            bedTemp: nil
        )
    }

    /// The colour name; a row without one falls back to its designation
    /// ("   Other    - Galaxy Black") with whitespace runs collapsed.
    private static func displayName(of item: FilaManDBFilamentPage.Item) -> String {
        if let colorName = nonBlank(item.colorName) { return colorName }
        return (item.designation ?? "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func nonBlank(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
