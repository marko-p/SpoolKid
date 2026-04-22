//
//  SpoolSelectionView.swift
//  SpoolKid
//
//  Purpose: Picker view for selecting a spool from Spoolman to create an NFC tag.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI

struct SpoolSelectionView: View {
    @StateObject private var spoolManService = SpoolmanService()
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = AppConfig.defaultSpoolmanUrl
    @State private var searchText = ""
    
    var filteredSpools: [SpoolmanSpool] {
        if searchText.isEmpty {
            return spoolManService.spools
        } else {
            return spoolManService.spools.filter { spool in
                let query = searchText.lowercased()
                let name = (spool.filament.name ?? "").lowercased()
                let vendor = (spool.filament.vendor?.name ?? "").lowercased()
                let material = (spool.filament.material ?? "").lowercased()
                let id = String(spool.id)
                
                return name.contains(query) ||
                       vendor.contains(query) ||
                       material.contains(query) ||
                       id.contains(query)
            }
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
                        fetchSpools()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if filteredSpools.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "No Spools",
                        systemImage: "shippingbox",
                        description: Text("Add spools in the Spoolman tab first.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                Section(header: Text("Spools")) {
                    ForEach(filteredSpools) { spool in
                        NavigationLink(destination: WriteTagView(initialData: FilamentTagData.from(spool: spool))) {
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
                }
            }
        }
        .navigationTitle("Select Spool")
        .searchable(text: $searchText, prompt: "Search spools...")
        .refreshable {
            await spoolManService.fetchSpools(baseUrl: spoolmanUrl)
        }
        .onAppear {
            fetchSpools()
        }
    }
    
    private func fetchSpools() {
        Task {
            await spoolManService.fetchSpools(baseUrl: spoolmanUrl)
        }
    }
}
