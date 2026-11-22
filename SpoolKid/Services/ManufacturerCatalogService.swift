//
//  ManufacturerCatalogService.swift
//  SpoolKid
//
//  Purpose: The manufacturer names of the active backend's public catalogue,
//  for the manufacturer picker. SpoolmanDB's come from the filament catalogue
//  `SpoolmanDBService` already loads (no second download); FilaManDB's from
//  its public `/api/v1/manufacturers` through `FilaManDBCatalog`, fetched once
//  per app session.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.spoolkid", category: "ManufacturerCatalog")

@MainActor
final class ManufacturerCatalogService: ObservableObject {
    static let shared = ManufacturerCatalogService()

    /// A server whose `total` never comes true must not page forever.
    nonisolated static let filamanDBMaxPages = 20

    /// Distinct by `ManufacturerName.key`, A–Z.
    @Published private(set) var names: [String] = []
    @Published private(set) var isLoading = false
    /// The last load produced no names because it failed; the picker offers Retry.
    @Published private(set) var didFail = false

    private let spoolmanDB: SpoolmanDBService
    private let filamanDB: FilaManDBCatalog
    /// FilaManDB's names, kept for the app session once fetched. A failure is
    /// not kept, so Retry fetches again.
    private var filamanDBNames: [String]?
    /// The source `names` belongs to, and the one being loaded now. A load
    /// for another source supersedes the running one: its result is
    /// discarded by `loadGeneration`.
    private var loadedSource: ManufacturerCatalogSource?
    private var loadingSource: ManufacturerCatalogSource?
    private var loadGeneration = 0

    init(
        spoolmanDB: SpoolmanDBService? = nil,
        filamanDB: FilaManDBCatalog = .live
    ) {
        // Not `= .shared` as a default: a MainActor static read in a default
        // argument warns that it is referenced from a nonisolated context.
        self.spoolmanDB = spoolmanDB ?? SpoolmanDBService.shared
        self.filamanDB = filamanDB
    }

    func load(for store: SpoolDataStore) async {
        await load(source: store.capabilities.manufacturerCatalog, backend: store)
    }

    /// `backend` supplies a Spoolman server's own catalogue
    /// (`fetchFilamentCatalog`); FilaManDB does not use it.
    func load(source: ManufacturerCatalogSource, backend: any SpoolDataRepository) async {
        if isLoading && loadingSource == source { return }
        loadGeneration += 1
        let generation = loadGeneration
        if loadedSource != source { names = [] }
        loadingSource = source
        isLoading = true
        didFail = false

        let loaded: [String]
        let failed: Bool
        switch source {
        case .spoolmanDB:
            await spoolmanDB.fetchFilaments(for: backend)
            loaded = ManufacturerName.distinct(spoolmanDB.filaments.map(\.manufacturer))
            failed = spoolmanDB.filaments.isEmpty && spoolmanDB.errorMessage != nil
        case .filamanDB:
            if let filamanDBNames {
                loaded = filamanDBNames
                failed = false
            } else {
                do {
                    let active = try await filamanDB.manufacturers(maxPages: Self.filamanDBMaxPages).filter(\.isActive)
                    let fetched = ManufacturerName.distinct(active.map(\.name))
                    // An empty answer is not kept: the next load asks again.
                    if !fetched.isEmpty { filamanDBNames = fetched }
                    loaded = fetched
                    failed = false
                } catch {
                    loaded = []
                    // A picker that closed cancels its load: nothing failed.
                    failed = !error.isCancellation
                    if failed {
                        logger.error("FilaManDB manufacturers unavailable: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }

        // A newer load, for another source, has taken over.
        guard generation == loadGeneration else { return }
        names = loaded
        didFail = failed
        loadedSource = source
        loadingSource = nil
        isLoading = false
    }
}
