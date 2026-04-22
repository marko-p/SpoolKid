//
//  ManageSpoolsView.swift
//  SpoolKid
//
//  Purpose: List view for managing spools in Spoolman (view, edit, delete).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI

struct ManageSpoolsView: View {
    @StateObject private var spoolManService = SpoolmanService()
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = AppConfig.defaultSpoolmanUrl
    @AppStorage("confirm_before_delete") private var confirmBeforeDelete: Bool = true
    @State private var showingAddSheet = false
    @State private var spoolToEdit: SpoolmanSpool?
    @State private var searchText = ""
    @State private var spoolToDelete: SpoolmanSpool?
    @State private var showDeleteConfirmation = false

    var filteredSpools: [SpoolmanSpool] {
        if searchText.isEmpty {
            return spoolManService.spools
        }
        return spoolManService.spools.filter { spool in
            let searchString = "\(spool.filament.name ?? "") \(spool.filament.vendor?.name ?? "") \(spool.filament.material ?? "") \(spool.id)"
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
                    Label("Could Not Load Spools", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await spoolManService.fetchSpools(baseUrl: spoolmanUrl) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if filteredSpools.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "No Spools",
                        systemImage: "shippingbox",
                        description: Text("Add your first spool using the + button.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                ForEach(filteredSpools) { spool in
                    Button(action: {
                        spoolToEdit = spool
                    }) {
                        HStack {
                            Circle()
                                .fill(Color(hex: spool.filament.colorHex ?? "000000") ?? .swatchFallback)
                                .frame(width: 24, height: 24)
                                .overlay(Circle().stroke(Color.swatchBorder, lineWidth: 1))
                            
                            VStack(alignment: .leading) {
                                Text(spool.filament.name ?? "Unknown")
                                    .font(.headline)
                                    .lineLimit(1)
                                HStack {
                                    Text(spool.filament.vendor?.name ?? "Generic")
                                    Text("•")
                                    Text(spool.filament.material ?? "PLA")
                                    if let remaining = spool.remainingWeight {
                                        Text("•")
                                        Text("\(Int(remaining))g")
                                    }
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
                    if let index = indexSet.first, index < filteredSpools.count {
                        let spool = filteredSpools[index]
                        if confirmBeforeDelete {
                            spoolToDelete = spool
                            showDeleteConfirmation = true
                        } else {
                            Task { await spoolManService.deleteSpool(id: spool.id, baseUrl: spoolmanUrl) }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search spools...")
        .navigationTitle("Manage Spools")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            SpoolFormView(service: spoolManService, baseUrl: spoolmanUrl)
        }
        .sheet(item: $spoolToEdit) { spool in
            SpoolFormView(service: spoolManService, baseUrl: spoolmanUrl, spoolToEdit: spool)
        }
        .refreshable {
            await spoolManService.fetchSpools(baseUrl: spoolmanUrl)
        }
        .confirmationDialog(
            "Delete Spool?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let spool = spoolToDelete {
                    Task { await spoolManService.deleteSpool(id: spool.id, baseUrl: spoolmanUrl) }
                }
                spoolToDelete = nil
            }
            Button("Cancel", role: .cancel) { spoolToDelete = nil }
        } message: {
            if let spool = spoolToDelete {
                Text("\(spool.filament.name ?? "Unknown") will be permanently deleted from Spoolman.")
            }
        }
        .onAppear {
            Task {
                await spoolManService.fetchSpools(baseUrl: spoolmanUrl)
            }
        }
    }
}
