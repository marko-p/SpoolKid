//
//  ManageLocationsView.swift
//  SpoolKid
//
//  Purpose: List view for managing Spoolman locations and their assigned spools.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI

struct ManageLocationsView: View {
    @StateObject private var spoolManService = SpoolmanService()
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = AppConfig.defaultSpoolmanUrl

    @State private var searchText = ""
    @State private var selectedLocationToRename: String?

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
                    Label("Could Not Load Locations", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await reload() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if filteredLocations.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "No Locations",
                        systemImage: "mappin.and.ellipse",
                        description: Text("Locations appear after spools are assigned to one.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                ForEach(filteredLocations, id: \.self) { location in
                    let canonicalLocation = Self.canonicalLocationName(
                        for: location,
                        observed: observedLocations,
                        known: spoolManService.locations
                    )

                    Button {
                        selectedLocationToRename = canonicalLocation
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(location)
                                    .font(.headline)
                                    .lineLimit(1)

                                let spoolIDs = Self.spoolIDsForLocation(canonicalLocation, spools: spoolManService.spools)
                                Text(Self.spoolCountDescription(spoolIDs.count))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search locations...")
        .navigationTitle("Manage Locations")
        .sheet(isPresented: Binding(
            get: { selectedLocationToRename != nil },
            set: { if !$0 { selectedLocationToRename = nil } }
        )) {
            if let location = selectedLocationToRename {
                LocationFormView(
                    service: spoolManService,
                    baseUrl: spoolmanUrl,
                    currentLocation: location
                )
            }
        }
        .refreshable {
            await reload()
        }
        .onAppear {
            Task {
                await reload()
            }
        }
    }

    private var observedLocations: [String] {
        spoolManService.spools.compactMap(\.location)
    }

    private var filteredLocations: [String] {
        let merged = Self.mergedLocations(observed: observedLocations, known: spoolManService.locations)
        guard !searchText.isEmpty else { return merged }
        return merged.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private func reload() async {
        await spoolManService.fetchSpools(baseUrl: spoolmanUrl)
        let spoolError = spoolManService.errorMessage
        await spoolManService.fetchLocations(baseUrl: spoolmanUrl)
        if spoolManService.errorMessage == nil, let spoolError {
            spoolManService.errorMessage = spoolError
        }
    }

    static func mergedLocations(observed: [String], known: [String]) -> [String] {
        let normalized = (observed + known)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let unique = Set(normalized)
        return unique.sorted {
            let comparison = $0.localizedCaseInsensitiveCompare($1)
            if comparison == .orderedSame {
                return $0 < $1
            }
            return comparison == .orderedAscending
        }
    }

    static func spoolIDsForLocation(_ location: String, spools: [SpoolmanSpool]) -> [Int] {
        spools
            .filter { $0.location == location }
            .map(\.id)
            .sorted()
    }

    static func canonicalLocationName(for displayName: String, observed: [String], known: [String]) -> String {
        let target = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return displayName }

        for candidate in known + observed {
            if candidate.trimmingCharacters(in: .whitespacesAndNewlines) == target {
                return candidate
            }
        }

        return displayName
    }

    static func spoolCountDescription(_ count: Int) -> String {
        if count == 1 {
            return "1 spool"
        }
        return "\(count) spools"
    }
}
