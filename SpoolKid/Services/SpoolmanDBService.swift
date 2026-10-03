//
//  SpoolmanDBService.swift
//  SpoolKid
//
//  Purpose: Service to fetch filament definitions from the external SpoolmanDB.
//  Source: the configured Spoolman's own catalogue (its `EXTERNAL_DB_URL`),
//  else https://donkie.github.io/SpoolmanDB/filaments.json
//  Responsibilities:
//  - Fetching the JSON catalog of filaments.
//  - Decoding the JSON into `SpoolmanDBFilament` objects.
//  - Providing this data to the `FilamentSelectionView` for importing.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import Foundation
import Combine

struct SpoolmanDBFilament: Codable, Identifiable, Hashable {
    let id: String
    let manufacturer: String
    let name: String
    let material: String
    let spoolType: String?
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
        case spoolType = "spool_type"
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
    @Published var errorMessage: String?

    private static let publicCatalogURL = URL(string: "https://donkie.github.io/SpoolmanDB/filaments.json")!

    private let publicCatalog: () async throws -> [SpoolmanDBFilament]

    /// The Spoolman URL the loaded catalogue was fetched for. A retyped server
    /// address changes which catalogue applies.
    private var loadedFor: String?

    init(publicCatalog: @escaping () async throws -> [SpoolmanDBFilament] = SpoolmanDBService.fetchPublicCatalog) {
        self.publicCatalog = publicCatalog
    }

    /// Loads the catalogue the configured Spoolman serves, so a self-hosted
    /// SpoolmanDB fork set in its `EXTERNAL_DB_URL` reaches the import picker.
    func fetchFilaments(from spoolman: SpoolmanService, baseUrl: String) async {
        await fetchFilaments(for: baseUrl) { try await spoolman.fetchExternalFilaments(baseUrl: baseUrl) }
    }

    /// If `serverCatalog` fails, the public catalogue still loads: a Spoolman
    /// that could not sync its own must not cost the user the one they had before.
    func fetchFilaments(for baseUrl: String, serverCatalog: () async throws -> [SpoolmanDBFilament]) async {
        guard filaments.isEmpty || loadedFor != baseUrl else { return }

        isLoading = true
        errorMessage = nil

        do {
            let loaded: [SpoolmanDBFilament]
            do {
                loaded = try await serverCatalog()
            } catch {
                print("Spoolman catalogue unavailable, using the public one: \(error)")
                loaded = try await publicCatalog()
            }
            self.filaments = loaded
            loadedFor = baseUrl
        } catch {
            self.errorMessage = "Failed to fetch SpoolmanDB filaments: \(error.localizedDescription)"
            print("Error fetching SpoolmanDB: \(error)")
        }

        isLoading = false
    }

    static func fetchPublicCatalog() async throws -> [SpoolmanDBFilament] {
        let (data, _) = try await URLSession.shared.data(from: publicCatalogURL)
        return try JSONDecoder().decode([SpoolmanDBFilament].self, from: data)
    }
}
