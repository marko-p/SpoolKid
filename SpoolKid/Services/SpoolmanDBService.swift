//
//  SpoolmanDBService.swift
//  SpoolKid
//
//  Purpose: Service to fetch filament definitions from the external SpoolmanDB.
//  Source: the active backend's own catalogue when it serves one (Spoolman's
//  `EXTERNAL_DB_URL`), else https://donkie.github.io/SpoolmanDB/filaments.json
//  Responsibilities:
//  - Fetching the JSON catalog of filaments.
//  - Decoding the JSON into `SpoolmanDBFilament` objects.
//  - Providing this data to the `FilamentSelectionView` for importing.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.spoolkid", category: "SpoolmanDB")

/// One filament of a public catalogue: SpoolmanDB's own entries, and FilaManDB's
/// mapped into this shape (`FilaManDBCatalog`), so every importer, scorer and
/// list keeps one type.
///
/// `nonisolated`: `FilaManDBCatalog` builds these off the main actor.
nonisolated struct SpoolmanDBFilament: Codable, Identifiable, Hashable {
    let id: String
    let manufacturer: String
    let name: String
    let material: String
    let spoolType: String?
    /// FilaManDB entries may state none.
    let density: Double?
    let weight: Double?
    let spoolWeight: Double?
    let diameter: Double
    let colorHex: String?
    /// SpoolmanDB's multi-color entries: the colors, in order. Nil on FilaManDB
    /// entries, which state one color.
    var colorHexes: [String]? = nil
    /// `coaxial` or `longitudinal`, as `FilamentColors.Pattern` reads it.
    var multiColorDirection: String? = nil
    let extruderTemp: Int?
    let bedTemp: Int?
    /// SpoolmanDB's `extruder_temp_range`: [min, max].
    var extruderTempRange: [Int]? = nil
    
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
        case colorHexes = "color_hexes"
        case multiColorDirection = "multi_color_direction"
        case extruderTemp = "extruder_temp"
        case bedTemp = "bed_temp"
        case extruderTempRange = "extruder_temp_range"
    }
    
    var displayName: String {
        "\(manufacturer) - \(name) (\(material))"
    }

    /// The color(s) this entry states, read by `FilamentColors`'s rule.
    var colors: FilamentColors {
        FilamentColors(
            colorHex: colorHex,
            multiColorHexes: colorHexes?.joined(separator: ","),
            multiColorDirection: multiColorDirection
        )
    }
}

extension SpoolmanDBFilament {
    /// Headline for list rows: manufacturer followed by the filament name.
    var listTitle: String {
        let parts = [manufacturer, name]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Unknown" : parts.joined(separator: " ")
    }

    /// The single detail row beneath the title: material, variant, diameter,
    /// density, weight, spool weight, and spool type. Unset fields are omitted.
    var listDetailParts: [String] {
        var parts: [String] = []
        if !material.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(material)
        }
        parts.append(SubtypeOptionService.derive(from: name))
        parts.append(String(format: "%.2f mm", diameter))
        if let density {
            parts.append(String(format: "%.2f g/cm³", density))
        }
        if let weight {
            parts.append(String(format: "%.0f g", weight))
        }
        if let spoolWeight {
            parts.append(String(format: "%.0f g spool", spoolWeight))
        }
        if let spoolType, !spoolType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(spoolType)
        }
        return parts
    }
}

extension SpoolmanDBFilament {
    /// The draft both catalogue importers create a filament from, so a field
    /// added here reaches Select Filament and Scan Result alike.
    ///
    /// Create-only: an entry naming no temperature, or no spool weight (0 is
    /// "unknown" in the catalogue too), says nothing about it, which is
    /// `.ignore`.
    func filamentDraft(vendorId: Int) -> FilamentDraft {
        let knownSpoolWeight: SpoolmanPatchValue<Double> =
            if let spoolWeight, spoolWeight > 0 { .set(spoolWeight) } else { .ignore }
        let color = colors.draftFields(loaded: nil)
        return FilamentDraft(
            name: name,
            vendorId: .set(vendorId),
            material: material,
            density: density,
            diameter: diameter,
            spoolWeight: knownSpoolWeight,
            extruderTemp: extruderTemp.map { .set($0) } ?? .ignore,
            bedTemp: bedTemp.map { .set($0) } ?? .ignore,
            colorHex: color.colorHex,
            multiColorHexes: color.multiColorHexes,
            multiColorDirection: color.multiColorDirection
        )
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

    /// The `connectionTarget` the loaded catalogue was fetched for. A backend
    /// switch or a retyped server address changes which catalogue applies.
    private var loadedFor: String?

    init(publicCatalog: @escaping () async throws -> [SpoolmanDBFilament] = SpoolmanDBService.fetchPublicCatalog) {
        self.publicCatalog = publicCatalog
    }

    func fetchFilaments(for backend: any SpoolDataRepository) async {
        let target = backend.connectionTarget
        guard filaments.isEmpty || loadedFor != target else {
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            filaments = try await catalog(for: backend)
            loadedFor = target
            errorMessage = nil
        } catch {
            // A closed screen cancels its load: not a failure to show.
            if !error.isCancellation {
                errorMessage = "Failed to fetch SpoolmanDB filaments: \(error.localizedDescription)"
                logger.error("Error fetching SpoolmanDB: \(error.localizedDescription, privacy: .public)")
            }
        }

        isLoading = false
    }

    /// The backend's own catalogue when it serves one. If it fails, the public
    /// catalogue still loads (owner's call, 2026-10-04): a Spoolman that could
    /// not sync its own must not cost the user the one they had before.
    private func catalog(for backend: any SpoolDataRepository) async throws -> [SpoolmanDBFilament] {
        do {
            if let own = try await backend.fetchFilamentCatalog() { return own }
        } catch {
            logger.error("Backend catalogue unavailable, using the public one: \(error.localizedDescription, privacy: .public)")
        }
        return try await publicCatalog()
    }

    static func fetchPublicCatalog() async throws -> [SpoolmanDBFilament] {
        let (data, _) = try await URLSession.shared.data(from: publicCatalogURL)
        return try JSONDecoder().decode([SpoolmanDBFilament].self, from: data)
    }
}
