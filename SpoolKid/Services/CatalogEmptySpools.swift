//
//  CatalogEmptySpools.swift
//  SpoolKid
//
//  Purpose: The empty-spool weights the active backend's public catalogue
//  states (SpoolmanDB, or FilaManDB on FilaMan), as the Empty Spools picker
//  lists them: one row per brand, spool type and weight, the chosen brand
//  first, and the load that asks the catalogue for them.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// One weight a brand's catalogue entries state for one spool type, and what
/// they hold: a picked row hands back `grams` only.
nonisolated struct CatalogEmptySpool: Identifiable, Hashable, Sendable {
    /// The first spelling met in the catalogue.
    let brand: String
    /// Trimmed and lowercased ("plastic", "cardboard"); nil when not stated.
    let spoolType: String?
    let grams: Double
    /// The net filament weights (> 0) the entries state, ascending.
    let netWeights: [Double]
    let productCount: Int
    /// The alphabetically first product name, to tell two rows apart.
    let exampleName: String

    var id: String { "\(ManufacturerName.key(brand))|\(spoolType ?? "")|\(grams)" }
}

nonisolated enum CatalogEmptySpools {
    nonisolated struct Section: Identifiable, Hashable, Sendable {
        let brand: String
        /// Ascending grams.
        let rows: [CatalogEmptySpool]

        var id: String { ManufacturerName.key(brand) }
    }

    /// The chosen brand's section (nil when it has none), then every other
    /// brand A–Z by `ManufacturerName.key`. A row is one distinct brand,
    /// spool type and weight among the entries stating a weight above zero;
    /// net sizes are listed on it rather than splitting it (FilaManDB states
    /// 220 g for every Prusament filament across eight sizes).
    static func sections(
        from entries: [SpoolmanDBFilament], forManufacturer manufacturer: String?
    ) -> (brand: Section?, others: [Section]) {
        struct RowKey: Hashable {
            let brand: String
            let spoolType: String?
            let grams: Double
        }
        var spelling: [String: String] = [:]
        var members: [RowKey: [SpoolmanDBFilament]] = [:]
        for entry in entries {
            guard let grams = entry.spoolWeight, grams > 0 else { continue }
            let brandKey = ManufacturerName.key(entry.manufacturer)
            guard !brandKey.isEmpty else { continue }
            if spelling[brandKey] == nil {
                spelling[brandKey] = entry.manufacturer.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            members[RowKey(brand: brandKey, spoolType: spoolType(entry.spoolType), grams: grams), default: []]
                .append(entry)
        }

        var rowsByBrand: [String: [CatalogEmptySpool]] = [:]
        for (key, entries) in members {
            rowsByBrand[key.brand, default: []].append(CatalogEmptySpool(
                brand: spelling[key.brand] ?? key.brand,
                spoolType: key.spoolType,
                grams: key.grams,
                netWeights: Set(entries.compactMap(\.weight).filter { $0 > 0 }).sorted(),
                productCount: entries.count,
                exampleName: entries.map(\.name)
                    .min { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } ?? ""
            ))
        }

        let sections = rowsByBrand.map { brandKey, rows in
            Section(
                brand: spelling[brandKey] ?? brandKey,
                rows: rows.sorted { ($0.grams, $0.spoolType ?? "") < ($1.grams, $1.spoolType ?? "") }
            )
        }
        .sorted { $0.id < $1.id }

        let wanted = ManufacturerName.key(manufacturer ?? "")
        let brand = wanted.isEmpty ? nil : sections.first { $0.id == wanted }
        return (brand, sections.filter { $0.id != brand?.id })
    }

    /// What the catalogue answered: its entries, and whether it was asked.
    typealias Load = (entries: [SpoolmanDBFilament], answer: ScanResolutionService.CatalogueAnswer)

    /// The most 200-row pages of one brand's FilaManDB filaments read; the
    /// largest brand, SUNLU, has 979.
    static let filamanDBMaxPages = 5

    /// The active backend's catalogue: SpoolmanDB's whole list (every brand),
    /// or on FilaMan the chosen brand's FilaManDB filaments only.
    @MainActor
    static func load(
        forManufacturer manufacturer: String?, store: SpoolDataStore, filamanDB: FilaManDBCatalog = .live
    ) async -> Load {
        switch store.capabilities.manufacturerCatalog {
        case .spoolmanDB:
            await SpoolmanDBService.shared.fetchFilaments(for: store)
            // `fetchFilaments` clears the message when it starts, so a message
            // now is this fetch's.
            let service = SpoolmanDBService.shared
            return (service.filaments, service.errorMessage == nil ? .answered : .failed)
        case .filamanDB:
            return await filamanDBEntries(forManufacturer: manufacturer, catalog: filamanDB)
        }
    }

    /// One brand's FilaManDB filaments. No brand, or one FilaManDB does not
    /// list, is `.noBrand` (a blank brand asks nothing); a failure is
    /// `.failed`; a cancelled ask has nothing to tell.
    static func filamanDBEntries(forManufacturer manufacturer: String?, catalog: FilaManDBCatalog) async -> Load {
        let brand = (manufacturer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brand.isEmpty else { return ([], .noBrand) }
        do {
            guard let manufacturerID = try await catalog.manufacturerID(named: brand) else { return ([], .noBrand) }
            let entries = try await catalog.filaments(manufacturerID: manufacturerID, maxPages: filamanDBMaxPages)
            return (entries, .answered)
        } catch {
            return ([], error.isCancellation ? .answered : .failed)
        }
    }

    private static func spoolType(_ text: String?) -> String? {
        let type = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return type.isEmpty ? nil : type
    }
}
