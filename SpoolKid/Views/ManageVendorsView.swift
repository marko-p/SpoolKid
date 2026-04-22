//
//  ManageVendorsView.swift
//  SpoolKid
//
//  Purpose: List view for managing vendors in Spoolman (view, edit, delete).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI

struct ManageVendorsView: View {
    @StateObject private var spoolManService = SpoolmanService()
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = AppConfig.defaultSpoolmanUrl
    @AppStorage("confirm_before_delete") private var confirmBeforeDelete: Bool = true
    @State private var showingAddSheet = false
    @State private var vendorToEdit: SpoolmanVendor?
    @State private var searchText = ""
    @State private var vendorToDelete: SpoolmanVendor?
    @State private var showDeleteConfirmation = false

    var filteredVendors: [SpoolmanVendor] {
        if searchText.isEmpty {
            return spoolManService.vendors
        }
        return spoolManService.vendors.filter { vendor in
            let searchString = "\(vendor.name) \(vendor.id)"
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
                    Label("Could Not Load Vendors", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await spoolManService.fetchVendors(baseUrl: spoolmanUrl) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if filteredVendors.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "No Vendors",
                        systemImage: "building.2",
                        description: Text("Add your first vendor using the + button.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                ForEach(filteredVendors) { vendor in
                    Button(action: {
                        vendorToEdit = vendor
                    }) {
                        Text(vendor.name)
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
                .onDelete { indexSet in
                    if let index = indexSet.first, index < filteredVendors.count {
                        let vendor = filteredVendors[index]
                        if confirmBeforeDelete {
                            vendorToDelete = vendor
                            showDeleteConfirmation = true
                        } else {
                            Task { await spoolManService.deleteVendor(id: vendor.id, baseUrl: spoolmanUrl) }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search vendors...")
        .navigationTitle("Manage Vendors")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            VendorFormView(service: spoolManService, baseUrl: spoolmanUrl)
        }
        .sheet(item: $vendorToEdit) { vendor in
            VendorFormView(service: spoolManService, baseUrl: spoolmanUrl, vendorToEdit: vendor)
        }
        .refreshable {
            await spoolManService.fetchVendors(baseUrl: spoolmanUrl)
        }
        .confirmationDialog(
            "Delete Vendor?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let vendor = vendorToDelete {
                    Task { await spoolManService.deleteVendor(id: vendor.id, baseUrl: spoolmanUrl) }
                }
                vendorToDelete = nil
            }
            Button("Cancel", role: .cancel) { vendorToDelete = nil }
        } message: {
            if let vendor = vendorToDelete {
                Text("\(vendor.name) will be permanently deleted from Spoolman.")
            }
        }
        .onAppear {
            Task {
                await spoolManService.fetchVendors(baseUrl: spoolmanUrl)
            }
        }
    }
}
