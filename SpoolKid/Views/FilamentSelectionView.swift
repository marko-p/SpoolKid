//
//  FilamentSelectionView.swift
//  SpoolKid
//
//  Purpose: A specialized picker view for selecting a filament.
//  Features:
//  - Lists local filaments from the user's Spoolman instance.
//  - Lists global filaments from the external SpoolmanDB.
//  - Search functionality filtering both lists simultaneously.
//  - "Import" logic: Tapping an external filament automatically creates the Vendor (if missing) and Filament in the local Spoolman instance.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI

struct FilamentSelectionView: View {
    @Binding var selectedFilamentID: Int?
    let baseUrl: String
    @Environment(\.dismiss) var dismiss
    @ObservedObject var spoolManService: SpoolmanService
    @StateObject private var spoolmanDBService = SpoolmanDBService.shared
    
    @State private var searchText = ""
    @State private var isImporting = false
    @State private var importError: String? = nil
    
    var filteredLocalFilaments: [SpoolmanFilament] {
        if searchText.isEmpty {
            return spoolManService.filaments
        } else {
            return spoolManService.filaments.filter { filament in
                let nameMatch = filament.name?.localizedCaseInsensitiveContains(searchText) ?? false
                let vendorMatch = filament.vendor?.name.localizedCaseInsensitiveContains(searchText) ?? false
                let materialMatch = filament.material?.localizedCaseInsensitiveContains(searchText) ?? false
                return nameMatch || vendorMatch || materialMatch
            }
        }
    }
    
    var filteredExternalFilaments: [SpoolmanDBFilament] {
        if searchText.isEmpty {
            return spoolmanDBService.filaments
        } else {
            return spoolmanDBService.filaments.filter { filament in
                let nameMatch = filament.name.localizedCaseInsensitiveContains(searchText)
                let manufacturerMatch = filament.manufacturer.localizedCaseInsensitiveContains(searchText)
                let materialMatch = filament.material.localizedCaseInsensitiveContains(searchText)
                return nameMatch || manufacturerMatch || materialMatch
            }
        }
    }
    
    var body: some View {
        List {
            if !filteredLocalFilaments.isEmpty {
                Section("My Filaments") {
                    ForEach(filteredLocalFilaments) { filament in
                        Button {
                            selectedFilamentID = filament.id
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(filament.name ?? "Unknown")
                                        .font(.headline)
                                        .lineLimit(1)
                                    if let vendor = filament.vendor {
                                        Text(vendor.name)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if let colorHex = filament.colorHex {
                                    Circle()
                                        .fill(Color(hex: colorHex) ?? .swatchFallback)
                                        .frame(width: 24, height: 24)
                                        .overlay(Circle().stroke(Color.swatchBorder, lineWidth: 1))
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
            } else if !searchText.isEmpty && !spoolManService.filaments.isEmpty {
                Section("My Filaments") {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            
            Section("SpoolmanDB Filaments") {
                if spoolmanDBService.isLoading {
                    ProgressView()
                } else if let error = spoolmanDBService.errorMessage {
                    ContentUnavailableView {
                        Label("Could Not Load SpoolmanDB", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") {
                            Task { await spoolmanDBService.fetchFilaments() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if filteredExternalFilaments.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(filteredExternalFilaments) { filament in
                        Button {
                            importFilament(filament)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(filament.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        Text(filament.manufacturer)
                                        Text("•")
                                        Text(filament.material)
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                }
                                Spacer()
                                if let colorHex = filament.colorHex {
                                    Circle()
                                        .fill(Color(hex: colorHex) ?? .swatchFallback)
                                        .frame(width: 24, height: 24)
                                        .overlay(Circle().stroke(Color.swatchBorder, lineWidth: 1))
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search filaments...")
        .navigationTitle("Select Filament")
        .task {
            await spoolManService.fetchFilaments(baseUrl: baseUrl)
            await spoolmanDBService.fetchFilaments()
            if spoolManService.vendors.isEmpty {
                await spoolManService.fetchVendors(baseUrl: baseUrl)
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
    
    private func importFilament(_ dbFilament: SpoolmanDBFilament) {
        isImporting = true
        
        Task {
            // 1. Check if vendor exists
            let vendorName = dbFilament.manufacturer
            var vendorId: Int? = spoolManService.vendors.first(where: { $0.name.localizedCaseInsensitiveCompare(vendorName) == .orderedSame })?.id
            
            if vendorId == nil {
                // Create vendor
                if let newVendor = await spoolManService.addVendor(name: vendorName, baseUrl: baseUrl) {
                    vendorId = newVendor.id
                } else {
                    importError = "Could not create vendor \"\(vendorName)\". Check your Spoolman connection."
                    isImporting = false
                    return
                }
            }
            
            guard let finalVendorId = vendorId else {
                importError = "Could not resolve vendor ID. Check your Spoolman connection."
                isImporting = false
                return
            }
            
            // 2. Create filament
            if let newFilament = await spoolManService.addFilament(
                name: dbFilament.name,
                vendorId: finalVendorId,
                material: dbFilament.material,
                colorHex: dbFilament.colorHex,
                density: dbFilament.density,
                diameter: dbFilament.diameter,
                extruderTemp: dbFilament.extruderTemp,
                bedTemp: dbFilament.bedTemp,
                baseUrl: baseUrl
            ) {
                selectedFilamentID = newFilament.id
                dismiss()
            } else {
                importError = "Could not create filament \"\(dbFilament.name)\". Check your Spoolman connection."
            }
            
            isImporting = false
        }
    }
}

