//
//  FilamentSelectionView.swift
//  SpoolKid
//
//  Purpose: A specialized picker view for selecting a filament.
//  Features:
//  - Lists local filaments from the user's Spoolman instance.
//  - Lists global filaments from the backend's public catalogue: SpoolmanDB, or
//    FilaManDB on FilaMan (searched online as the user types).
//  - Search functionality filtering both lists simultaneously.
//  - "Import" logic: Tapping a catalogue filament automatically creates the Vendor (if missing) and Filament in the active backend.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct FilamentSelectionView: View {
    @Binding var selectedFilamentID: Int?
    @Environment(\.dismiss) var dismiss
    @ObservedObject var store: SpoolDataStore
    /// False: picking, creating or importing still sets the selection, but the picker stays up for its owner to replace.
    var dismissesOnSelect = true
    @StateObject private var spoolmanDBService = SpoolmanDBService.shared
    @StateObject private var filaManDBSearch = FilaManDBFilamentSearch()
    
    @State private var searchText = ""
    @State private var isImporting = false
    @State private var importError: String? = nil
    @State private var showingAddFilament = false
    
    var filteredLocalFilaments: [Filament] {
        store.filaments.filter { filament in
            SearchQuery.matches(searchText, in: [
                filament.name, filament.vendor?.name, filament.material
            ])
        }
    }
    
    var filteredExternalFilaments: [SpoolmanDBFilament] {
        spoolmanDBService.filaments.filter { filament in
            SearchQuery.matches(searchText, in: [
                filament.name, filament.manufacturer, filament.material
            ])
        }
    }
    
    /// Which public catalogue the second list shows: the backend's, by capability.
    private var catalogSource: ManufacturerCatalogSource { store.capabilities.manufacturerCatalog }

    /// FilaManDB is searched online, so the screen waits this long after the
    /// last keystroke before asking.
    private static let filaManDBSearchDebounce: Duration = .milliseconds(350)

    private var catalogMatches: Int {
        switch catalogSource {
        case .spoolmanDB: filteredExternalFilaments.count
        case .filamanDB: filaManDBSearch.results.count
        }
    }

    private var catalogAnswered: Bool {
        switch catalogSource {
        case .spoolmanDB: !spoolmanDBService.isLoading && spoolmanDBService.errorMessage == nil
        case .filamanDB: filaManDBSearch.hasAnswered(searchText)
        }
    }

    /// Only a search that matched nothing in either list gets the full-size
    /// "No Results"; with the keyboard up it fills the screen, so when one list
    /// does match, the empty one says so in a single line instead (owner,
    /// 2026-10-12). A catalog still loading, or failed, has not answered yet.
    private var searchMatchesNothing: Bool {
        Self.searchMatchesNothing(
            searchText: searchText,
            localMatches: filteredLocalFilaments.count,
            catalogMatches: catalogMatches,
            catalogAnswered: catalogAnswered
        )
    }

    nonisolated static func searchMatchesNothing(
        searchText: String, localMatches: Int, catalogMatches: Int, catalogAnswered: Bool
    ) -> Bool {
        !searchText.isEmpty && localMatches == 0 && catalogMatches == 0 && catalogAnswered
    }

    private var noMatchesRow: some View {
        Text("No matches")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    var body: some View {
        HarmonizedSearchList(title: "Select Filament", searchText: $searchText, prompt: "Search filaments...") {
            Section {
                Button {
                    showingAddFilament = true
                } label: {
                    Label("Add New Filament…", systemImage: "plus.circle")
                }
            }
            if searchMatchesNothing {
                Section {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                if !filteredLocalFilaments.isEmpty {
                    Section("My Filaments") {
                        ForEach(filteredLocalFilaments) { filament in
                            Button {
                                selectedFilamentID = filament.id
                                if dismissesOnSelect { dismiss() }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(filament.listTitle)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Text(filament.listSpecParts.joined(separator: " • "))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if !filament.colors.hexes.isEmpty {
                                        FilamentSwatch(colors: filament.colors, size: 24)
                                    }
                                    if selectedFilamentID == filament.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                            .foregroundColor(.primary)
                        }
                    }
                } else if !searchText.isEmpty && !store.filaments.isEmpty {
                    Section("My Filaments") {
                        noMatchesRow
                    }
                }
            
                Section("\(catalogSource.displayName) Filaments") {
                    switch catalogSource {
                    case .spoolmanDB: spoolmanDBRows
                    case .filamanDB: filaManDBRows
                    }
                }
            }
        }
        .task {
            await store.fetchFilaments()
            // FilaMan shows FilaManDB, searched below; its SpoolmanDB list is not shown.
            if catalogSource == .spoolmanDB {
                await spoolmanDBService.fetchFilaments(for: store)
            }
            if store.vendors.isEmpty {
                await store.fetchVendors()
            }
        }
        // Keyed on the trimmed text: a stray space neither cancels nor repeats a search.
        .task(id: searchText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            guard catalogSource == .filamanDB else { return }
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // A keystroke restarts this task, which cancels the wait.
                do { try await Task.sleep(for: Self.filaManDBSearchDebounce) } catch { return }
            }
            await filaManDBSearch.search(searchText)
        }
        .sheet(isPresented: $showingAddFilament) {
            NavigationStack {
                FilamentFormView(store: store, onSaveFilament: { created in
                    // The filament the user just created becomes the
                    // selection, and the picker hands it back to the spool
                    // form — that is why they opened this sheet.
                    selectedFilamentID = created.id
                    if dismissesOnSelect { dismiss() }
                })
            }
        }
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView("Importing...")
                        .padding()
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(10)
                }
            }
        }
        .alert("Import Failed", isPresented: Binding<Bool>(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            if let msg = importError {
                Text(msg)
            }
        }
    }
    
    @ViewBuilder
    private var spoolmanDBRows: some View {
        if spoolmanDBService.isLoading {
            ProgressView()
        } else if let error = spoolmanDBService.errorMessage {
            ContentUnavailableView {
                Label("Could Not Load SpoolmanDB", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") {
                    Task { await spoolmanDBService.fetchFilaments(for: store) }
                }
                .buttonStyle(.borderedProminent)
            }
        } else if filteredExternalFilaments.isEmpty && !searchText.isEmpty {
            noMatchesRow
        } else {
            catalogRows(filteredExternalFilaments)
        }
    }

    /// FilaManDB is not downloaded: nothing is listed until the user types, and
    /// rows already shown stay until the next answer replaces them.
    @ViewBuilder
    private var filaManDBRows: some View {
        let name = catalogSource.displayName
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Type to search \(name)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if let error = filaManDBSearch.errorMessage {
            ContentUnavailableView {
                Label("Could Not Reach \(name)", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") {
                    Task { await filaManDBSearch.search(searchText) }
                }
                .buttonStyle(.borderedProminent)
            }
        } else if !filaManDBSearch.results.isEmpty || filaManDBSearch.hasMore {
            catalogRows(filaManDBSearch.results)
            filaManDBMoreRow
        } else if filaManDBSearch.hasAnswered(searchText) {
            noMatchesRow
        } else {
            ProgressView()
        }
    }

    /// Under the rows: the next page loads when this row scrolls into view, and
    /// again for each page that lands while it still shows (the task is keyed
    /// on the rows read). A failed page says so and offers a retry.
    @ViewBuilder
    private var filaManDBMoreRow: some View {
        if filaManDBSearch.moreFailed {
            Button("Could not load more. Tap to retry.") {
                Task { await filaManDBSearch.loadMore() }
            }
        } else if filaManDBSearch.hasMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .task(id: filaManDBSearch.rowsLoaded) { await filaManDBSearch.loadMore() }
        } else if filaManDBSearch.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }

    private func catalogRows(_ filaments: [SpoolmanDBFilament]) -> some View {
        ForEach(filaments) { filament in
            Button {
                importFilament(filament)
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(filament.listTitle)
                            .font(.headline)
                            .lineLimit(1)
                        Text(filament.listDetailParts.joined(separator: " • "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if !filament.colors.hexes.isEmpty {
                        FilamentSwatch(colors: filament.colors, size: 24)
                    }
                }
            }
            .foregroundColor(.primary)
            .needsServer()
        }
    }

    /// The advice appended to an import failure. A server backend gets its own
    /// name; on-device storage gets nothing, because it has no connection to
    /// check and inventing one would send the user looking for a setting that
    /// does not exist. All three said "Check your Spoolman connection." until
    /// the I4 sweep.
    static func importFailureHint(_ capabilities: BackendCapabilities) -> String {
        capabilities.isOnDeviceStorage ? "" : " Check your \(capabilities.displayName) connection."
    }

    private func importFilament(_ dbFilament: SpoolmanDBFilament) {
        isImporting = true
        
        Task {
            // 1. Check if vendor exists
            let vendorName = dbFilament.manufacturer
            var vendorId: Int? = ManufacturerName.vendor(named: vendorName, in: store.vendors)?.id
            
            if vendorId == nil {
                // Create vendor
                if let newVendor = await store.addVendor(name: vendorName) {
                    vendorId = newVendor.id
                } else {
                    importError = "Could not create manufacturer \"\(vendorName)\"." + Self.importFailureHint(store.capabilities)
                    isImporting = false
                    return
                }
            }
            
            guard let finalVendorId = vendorId else {
                importError = "Could not resolve the manufacturer." + Self.importFailureHint(store.capabilities)
                isImporting = false
                return
            }
            
            // 2. Create filament
            let draft = dbFilament.filamentDraft(vendorId: finalVendorId)
            
            if let newFilament = await store.addFilament(
                draft: draft
            ) {
                selectedFilamentID = newFilament.id
                if dismissesOnSelect { dismiss() }
            } else {
                importError = "Could not create filament \"\(dbFilament.name)\"." + Self.importFailureHint(store.capabilities)
            }
            
            isImporting = false
        }
    }
}

