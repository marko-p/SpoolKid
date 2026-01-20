//
//  SpoolmanDBService.swift
//  SpoolKid
//
//  Purpose: Service to fetch filament definitions from the external SpoolmanDB.
//  Source: https://donkie.github.io/SpoolmanDB/filaments.json
//  Responsibilities:
//  - Fetching the global JSON catalog of filaments.
//  - Decoding the JSON into `SpoolmanDBFilament` objects.
//  - Providing this data to the `FilamentSelectionView` for importing.
//

import Foundation
import Combine

struct SpoolmanDBFilament: Codable, Identifiable, Hashable {
    let id: String
    let manufacturer: String
    let name: String
    let material: String
    let density: Double
    let weight: Double?
    let spoolWeight: Double?
    let diameter: Double
    let colorHex: String?
    let extruderTemp: Int?
    let bedTemp: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case manufacturer
        case name
        case material
        case density
        case weight
        case spoolWeight = "spool_weight"
        case diameter
        case colorHex = "color_hex"
        case extruderTemp = "extruder_temp"
        case bedTemp = "bed_temp"
    }
    
    var displayName: String {
        "\(manufacturer) - \(name) (\(material))"
    }
}

@MainActor
class SpoolmanDBService: ObservableObject {
    static let shared = SpoolmanDBService()
    
    @Published var filaments: [SpoolmanDBFilament] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let url = URL(string: "https://donkie.github.io/SpoolmanDB/filaments.json")!
    
    func fetchFilaments() async {
        guard filaments.isEmpty else { return }
        
        isLoading = true
        error = nil
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode([SpoolmanDBFilament].self, from: data)
            self.filaments = decoded
        } catch {
            self.error = "Failed to fetch SpoolmanDB filaments: \(error.localizedDescription)"
            print("Error fetching SpoolmanDB: \(error)")
        }
        
        isLoading = false
    }
}
