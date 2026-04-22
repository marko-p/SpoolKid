//
//  ManageFilamentsView.swift
//  SpoolKid
//
//  Purpose: List view for managing filaments in Spoolman (view, edit, delete).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI

struct ManageFilamentsView: View {
    @StateObject private var spoolManService = SpoolmanService()
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = AppConfig.defaultSpoolmanUrl
    @AppStorage("confirm_before_delete") private var confirmBeforeDelete: Bool = true
    @State private var showingAddSheet = false
    @State private var filamentToEdit: SpoolmanFilament?
    @State private var searchText = ""
    @State private var filamentToDelete: SpoolmanFilament?
    @State private var showDeleteConfirmation = false

    var filteredFilaments: [SpoolmanFilament] {
        if searchText.isEmpty {
            return spoolManService.filaments
        }
        return spoolManService.filaments.filter { filament in
            let searchString = "\(filament.name ?? "") \(filament.vendor?.name ?? "") \(filament.material ?? "") \(filament.id)"
            return searchString.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        List {
            if spoolManService.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let error = spoolManService.errorMessage {
                ContentUnavailableView {
                    Label("Could Not Load Filaments", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await spoolManService.fetchFilaments(baseUrl: spoolmanUrl) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if filteredFilaments.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "No Filaments",
                        systemImage: "cylinder",
                        description: Text("Add your first filament using the + button.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                ForEach(filteredFilaments) { filament in
                    Button(action: {
                        filamentToEdit = filament
                    }) {
                        HStack {
                            Circle()
                                .fill(Color(hex: filament.colorHex ?? "000000") ?? .swatchFallback)
                                .frame(width: 24, height: 24)
                                .overlay(Circle().stroke(Color.swatchBorder, lineWidth: 1))
                            
                            VStack(alignment: .leading) {
                                Text(filament.name ?? "Unknown")
                                    .font(.headline)
                                    .lineLimit(1)
                                HStack {
                                    Text(filament.vendor?.name ?? "Generic")
                                    Text("•")
                                    Text(filament.material ?? "PLA")
                                }
                                .lineLimit(1)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { indexSet in
                    if let index = indexSet.first, index < filteredFilaments.count {
                        let filament = filteredFilaments[index]
                        if confirmBeforeDelete {
                            filamentToDelete = filament
                            showDeleteConfirmation = true
                        } else {
                            Task { await spoolManService.deleteFilament(id: filament.id, baseUrl: spoolmanUrl) }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search filaments...")
        .navigationTitle("Manage Filaments")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            FilamentFormView(service: spoolManService, baseUrl: spoolmanUrl)
        }
        .sheet(item: $filamentToEdit) { filament in
            FilamentFormView(service: spoolManService, baseUrl: spoolmanUrl, filamentToEdit: filament)
        }
        .refreshable {
            await spoolManService.fetchFilaments(baseUrl: spoolmanUrl)
        }
        .confirmationDialog(
            "Delete Filament?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let filament = filamentToDelete {
                    Task { await spoolManService.deleteFilament(id: filament.id, baseUrl: spoolmanUrl) }
                }
                filamentToDelete = nil
            }
            Button("Cancel", role: .cancel) { filamentToDelete = nil }
        } message: {
            if let filament = filamentToDelete {
                Text("\(filament.name ?? "Unknown") will be permanently deleted from Spoolman.")
            }
        }
        .onAppear {
            Task {
                await spoolManService.fetchFilaments(baseUrl: spoolmanUrl)
            }
        }
    }
}
