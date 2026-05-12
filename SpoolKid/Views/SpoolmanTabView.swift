//
//  SpoolmanTabView.swift
//  SpoolKid
//
//  Purpose: The "Spoolman" tab content — Spoolman resource management.
//  Features:
//  - Navigation links to Manage Spools, Manage Filaments, Manage Vendors, Manage Locations.
//  - Inline "Add Spool" button next to Manage Spools.
//  - ContentUnavailableView when no valid Spoolman connection exists.
//  - About button in the toolbar.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI
import TipKit

struct SpoolmanTabView: View {
    @ObservedObject var spoolManService: SpoolmanService
    let spoolmanUrl: String

    @AppStorage("spoolman_connection_valid") private var isConnectionValid = false

    @State private var showAbout = false
    @State private var showingAddSpoolSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if isConnectionValid {
                    List {
                        Section("Manage Spoolman") {
                            TipView(SpoolmanManageTip())

                            HStack {
                                NavigationLink(destination: ManageSpoolsView()) {
                                    Label("Manage Spools", systemImage: "lifepreserver")
                                }
                                Button(action: { showingAddSpoolSheet = true }) {
                                    Image(systemName: "plus")
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }

                            NavigationLink(destination: ManageFilamentsView()) {
                                Label("Manage Filaments", systemImage: "scribble")
                            }
                            NavigationLink(destination: ManageVendorsView()) {
                                Label("Manage Vendors", systemImage: "building.2")
                            }
                            NavigationLink(destination: ManageLocationsView()) {
                                Label("Manage Locations", systemImage: "mappin.and.ellipse")
                            }
                            .accessibilityIdentifier("spoolman.manageLocations")
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                } else {
                    ContentUnavailableView {
                        Label("No Spoolman Connection", systemImage: "server.rack")
                    } description: {
                        Text("Configure your Spoolman server in Settings to manage spools, filaments, and vendors.")
                    } actions: {
                        Button(action: openAppSettings) {
                            Text("Open Settings")
                        }
                    }
                }
            }
            .navigationTitle("Spoolman")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showAbout = true }) {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .navigationDestination(isPresented: $showAbout) {
                AboutView()
            }
            .sheet(isPresented: $showingAddSpoolSheet) {
                NavigationStack {
                    SpoolFormView(service: spoolManService, baseUrl: spoolmanUrl)
                }
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
