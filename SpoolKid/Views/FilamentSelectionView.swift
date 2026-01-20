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

import SwiftUI

struct FilamentSelectionView: View {
    @Binding var selectedFilamentID: Int?
    let baseUrl: String
    @Environment(\.dismiss) var dismiss
    @ObservedObject var spoolManService: SpoolManService
    @StateObject private var spoolmanDBService = SpoolmanDBService.shared
    
    @State private var searchText = ""
    @State private var isImporting = false
    
    var filteredLocalFilaments: [SpoolManFilament] {
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
                                    if let vendor = filament.vendor {
                                        Text(vendor.name)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if let colorHex = filament.colorHex {
                                    Circle()
                                        .fill(Color(hex: colorHex) ?? .gray)
                                        .frame(width: 20, height: 20)
                                        .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                                }
                                if selectedFilamentID == filament.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            
            Section("SpoolmanDB Filaments") {
                if spoolmanDBService.isLoading {
                    ProgressView()
                } else if let error = spoolmanDBService.error {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                } else {
                    ForEach(filteredExternalFilaments) { filament in
                        Button {
                            importFilament(filament)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(filament.name)
                                        .font(.headline)
                                    Text("\(filament.manufacturer) - \(filament.material)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if let colorHex = filament.colorHex {
                                    Circle()
                                        .fill(Color(hex: colorHex) ?? .gray)
                                        .frame(width: 20, height: 20)
                                        .overlay(Circle().stroke(Color.gray, lineWidth: 1))
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
                    // Handle error
                    isImporting = false
                    return
                }
            }
            
            guard let finalVendorId = vendorId else {
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
            }
            
            isImporting = false
        }
    }
}

