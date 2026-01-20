import SwiftUI

struct ManageFilamentsView: View {
    @StateObject private var spoolManService = SpoolManService()
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = AppConfig.defaultSpoolmanUrl
    @State private var showingAddSheet = false
    @State private var filamentToEdit: SpoolManFilament?
    @State private var searchText = ""

    var filteredFilaments: [SpoolManFilament] {
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
                Text(error).foregroundColor(.red)
            } else {
                ForEach(filteredFilaments) { filament in
                    Button(action: {
                        filamentToEdit = filament
                    }) {
                        HStack {
                            Circle()
                                .fill(Color(hex: filament.colorHex ?? "000000") ?? .black)
                                .frame(width: 24, height: 24)
                                .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                            
                            VStack(alignment: .leading) {
                                Text(filament.name ?? "Unknown")
                                    .font(.headline)
                                HStack {
                                    Text(filament.vendor?.name ?? "Generic")
                                    Text("•")
                                    Text(filament.material ?? "PLA")
                                    Text("•")
                                    Text("ID: \(filament.id)")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        if index < filteredFilaments.count {
                            let filament = filteredFilaments[index]
                            Task {
                                await spoolManService.deleteFilament(id: filament.id, baseUrl: spoolmanUrl)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText)
        .navigationTitle("Manage Filaments")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
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
        .onAppear {
            Task {
                await spoolManService.fetchFilaments(baseUrl: spoolmanUrl)
            }
        }
    }
}
