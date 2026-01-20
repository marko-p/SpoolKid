import SwiftUI

struct SpoolSelectionView: View {
    @StateObject private var spoolManService = SpoolManService()
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = AppConfig.defaultSpoolmanUrl
    @State private var searchText = ""
    
    var filteredSpools: [SpoolManSpool] {
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
                Section {
                    Text(error).foregroundColor(.red)
                }
            } else {
                Section(header: Text("Spools")) {
                    ForEach(filteredSpools) { spool in
                        NavigationLink(destination: WriteTagView(initialData: mapSpoolToData(spool))) {
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
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Select Spool")
        .searchable(text: $searchText, prompt: "Search filaments...")
        .refreshable {
            await spoolManService.fetchSpools(baseUrl: spoolmanUrl)
        }
        .onAppear {
            if spoolManService.spools.isEmpty {
                fetchSpools()
            }
        }
    }
    
    private func fetchSpools() {
        Task {
            await spoolManService.fetchSpools(baseUrl: spoolmanUrl)
        }
    }
    
    private func mapSpoolToData(_ spool: SpoolManSpool) -> FilamentTagData {
        var minNozzle = 190
        var maxNozzle = 220
        if let t = spool.filament.settingsExtruderTemp {
            minNozzle = t
            maxNozzle = t + 10
        }
        
        var minBed = 50
        var maxBed = 60
        if let t = spool.filament.settingsBedTemp {
            minBed = t
            maxBed = t + 5
        }
        
        return FilamentTagData(
            name: spool.filament.name,
            material: spool.filament.material ?? "PLA",
            brand: spool.filament.vendor?.name ?? "Generic",
            colorHex: spool.filament.colorHex ?? "000000",
            minNozzleTemp: minNozzle,
            maxNozzleTemp: maxNozzle,
            minBedTemp: minBed,
            maxBedTemp: maxBed,
            spoolmanId: spool.id
        )
    }
}
