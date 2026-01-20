//
//  ContentView.swift
//  SpoolKid
//
//  Purpose: The root view of the application, providing the main navigation structure.
//  Features:
//  - Dashboard showing options to create tags (Manual or from SpoolMan).
//  - List of recently created tags for quick re-use.
//  - "Scan Tag" button for reading existing tags.
//  - Toolbar menu for accessing management views (Spools, Filaments, Vendors) and Settings.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var recentTagManager = RecentTagManager()
    @StateObject private var spoolManService = SpoolManService()
    @State private var showConfig = false
    @State private var showingAddSpoolSheet = false
    @AppStorage("spoolman_connection_valid") private var isConnectionValid = false
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = AppConfig.defaultSpoolmanUrl
    
    var body: some View {
        NavigationView {
            VStack {
                List {
                    if isConnectionValid {
                        Section(header: Text("Manage Spoolman")) {
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
                        }
                    }

                    Section(header: Text("Create Tag")) {
                        if isConnectionValid {
                            NavigationLink(destination: SpoolSelectionView()) {
                                Label("From SpoolMan", systemImage: "server.rack")
                            }
                        }
                        
                        NavigationLink(destination: WriteTagView()) {
                            Label("Manually", systemImage: "pencil")
                        }
                    }
                    
                    if !recentTagManager.recentTags.isEmpty {
                        Section(header: Text("Recent Tags")) {
                            ForEach(recentTagManager.recentTags) { recent in
                                NavigationLink(destination: WriteTagView(initialData: recent.data)) {
                                    HStack {
                                        Circle()
                                            .fill(recent.data.color)
                                            .frame(width: 24, height: 24)
                                            .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                                        
                                        VStack(alignment: .leading) {
                                            Text(recent.data.name ?? "\(recent.data.brand) \(recent.data.material)")
                                                .font(.headline)
                                            HStack {
                                                Text(recent.data.brand)
                                                Text("•")
                                                Text(recent.data.material)
                                                if let id = recent.data.spoolmanId {
                                                    Text("•")
                                                    Text("ID: \(id)")
                                                }
                                            }
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
                .listStyle(InsetGroupedListStyle())
                
                Spacer()
                
                NavigationLink(destination: ReadTagView()) {
                    Label("Scan Tag", systemImage: "wave.3.right")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()

                NavigationLink(destination: SpoolKidConfigView(), isActive: $showConfig) { EmptyView() }
            }
            .navigationTitle("SpoolKid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showConfig = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingAddSpoolSheet) {
                SpoolFormView(service: spoolManService, baseUrl: spoolmanUrl)
            }
            .onAppear {
                recentTagManager.refresh()
            }
        }
        .navigationViewStyle(.stack)
    }
}

#Preview {
    ContentView()
}
