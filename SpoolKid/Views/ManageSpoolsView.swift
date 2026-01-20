import SwiftUI

struct ManageSpoolsView: View {
    @StateObject private var spoolManService = SpoolManService()
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = AppConfig.defaultSpoolmanUrl
    @State private var showingAddSheet = false
    @State private var spoolToEdit: SpoolManSpool?
    @State private var searchText = ""

    var filteredSpools: [SpoolManSpool] {
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
                Text(error).foregroundColor(.red)
            } else {
                ForEach(filteredSpools) { spool in
                    Button(action: {
                        spoolToEdit = spool
                    }) {
                        HStack {
                            Circle()
                                .fill(Color(hex: spool.filament.colorHex ?? "000000") ?? .black)
                                .frame(width: 24, height: 24)
                                .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                            
                            VStack(alignment: .leading) {
                                Text(spool.filament.name ?? "Unknown Filament")
                                    .font(.headline)
                                HStack {
                                    Text(spool.filament.vendor?.name ?? "Generic")
                                    Text("•")
                                    Text(spool.filament.material ?? "PLA")
                                    Text("•")
                                    Text("ID: \(spool.id)")
                                    if let remaining = spool.remainingWeight {
                                        Text("•")
                                        Text("\(Int(remaining))g")
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        if index < filteredSpools.count {
                            let spool = filteredSpools[index]
                            Task {
                                await spoolManService.deleteSpool(id: spool.id, baseUrl: spoolmanUrl)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText)
        .navigationTitle("Manage Spools")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
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
        .onAppear {
            Task {
                await spoolManService.fetchSpools(baseUrl: spoolmanUrl)
            }
        }
    }
}
