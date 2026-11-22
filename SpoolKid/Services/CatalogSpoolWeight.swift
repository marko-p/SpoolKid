//
//  CatalogSpoolWeight.swift
//  SpoolKid
//
//  Purpose: The empty-spool weight a filament lacks, looked up in the active
//  backend's public catalogue (SpoolmanDB, or FilaManDB on FilaMan) at the
//  moment a new spool needs it: the exact-match rule, the decision whether a
//  weight the user kept goes back to the filament, and the lookup itself.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.spoolkid", category: "CatalogSpoolWeight")

nonisolated enum CatalogSpoolWeight {
    /// Posted when the spool saved but the write of its weight to the filament
    /// did not.
    static let writeBackFailedNote =
        "The spool was saved, but its empty spool weight could not be saved to the filament."

    /// How many 200-row pages of one brand's matches FilaManDB is read for.
    static let filamanDBMaxPages = 5

    /// The one spool weight the catalogue states for this product, or nil.
    ///
    /// An entry matches when its manufacturer has the same
    /// `ManufacturerName.key`, and its name, material and diameter (within
    /// 0.01 mm) agree, strings exact after trimming and ignoring case. Net
    /// weight must agree too (within a 0.5 g tolerance), but only when both
    /// sides state one above zero: older imports never copied it, and an entry
    /// may state none. A filament missing its name, brand, material or diameter
    /// matches nothing, since there is nothing to agree with.
    ///
    /// Of the matching entries' weights above zero, exactly one distinct value
    /// is the answer. Several (a 1 kg and a 2 kg spool of one product) or none
    /// answer nil: a guess would put a wrong tare on the spool.
    static func match(
        manufacturer: String?, name: String?, material: String?,
        diameter: Double?, netWeight: Double?,
        in entries: [SpoolmanDBFilament]
    ) -> Double? {
        let wantedManufacturer = ManufacturerName.key(manufacturer ?? "")
        let wantedName = key(name)
        let wantedMaterial = key(material)
        guard !wantedManufacturer.isEmpty, !wantedName.isEmpty, !wantedMaterial.isEmpty,
              let diameter
        else { return nil }

        var weights = Set<Double>()
        for entry in entries {
            guard ManufacturerName.key(entry.manufacturer) == wantedManufacturer,
                  key(entry.name) == wantedName,
                  key(entry.material) == wantedMaterial,
                  abs(entry.diameter - diameter) <= 0.01
            else { continue }
            if let netWeight, netWeight > 0, let entryNet = entry.weight, entryNet > 0,
               abs(entryNet - netWeight) >= 0.5 {
                continue
            }
            if let spoolWeight = entry.spoolWeight, spoolWeight > 0 {
                weights.insert(spoolWeight)
            }
        }
        return weights.count == 1 ? weights.first : nil
    }

    /// The grams to write back to the filament after a spool saved, or nil.
    /// Only a weight the user kept goes back: the lookup answered for the very
    /// filament the spool saved under, and the spool's saved empty weight is
    /// still that answer. A typed or picked number, or another filament,
    /// leaves the filament alone.
    static func weightToSave(
        lookedUp: (filamentId: Int, grams: Double)?, savedFilamentId: Int, savedSpoolWeight: Double?
    ) -> Double? {
        guard let lookedUp, lookedUp.grams > 0, lookedUp.filamentId == savedFilamentId,
              savedSpoolWeight == lookedUp.grams
        else { return nil }
        return lookedUp.grams
    }

    /// FilaManDB's answer for one product: its brand's id, then every page of
    /// that brand's filaments matching the name, then `match`. Nil without a
    /// request when the product has no brand or name. Throws on a transport or
    /// decoding failure, so the caller can tell "nothing found" from "could
    /// not ask".
    static func filamanDBWeight(
        manufacturer: String?, name: String?, material: String?,
        diameter: Double?, netWeight: Double?,
        catalog: FilaManDBCatalog
    ) async throws -> Double? {
        guard let manufacturer, let name, !key(name).isEmpty,
              let manufacturerID = try await catalog.manufacturerID(named: manufacturer)
        else { return nil }
        let entries = try await catalog.searchFilaments(
            name, manufacturerID: manufacturerID, maxPages: filamanDBMaxPages
        )
        return match(
            manufacturer: manufacturer, name: name, material: material,
            diameter: diameter, netWeight: netWeight, in: entries
        )
    }

    /// Trimmed and lowercased, "" for nil. Normalises a name or material text;
    /// that is a different rule from `ManufacturerName.key` ("the same
    /// manufacturer"), so the two are not shared.
    private static func key(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// The weight the active backend's catalogue states for `filament`, or nil:
/// no match, an ambiguous one, or a failed lookup (logged). Never throws and
/// never writes anything, so a slow or unreachable catalogue costs the spool
/// form nothing.
@MainActor
func lookUpCatalogSpoolWeight(
    for filament: Filament, store: SpoolDataStore, filamanDB: FilaManDBCatalog = .live
) async -> Double? {
    let manufacturer = filament.vendor?.name
    switch store.capabilities.manufacturerCatalog {
    case .spoolmanDB:
        await SpoolmanDBService.shared.fetchFilaments(for: store)
        return CatalogSpoolWeight.match(
            manufacturer: manufacturer, name: filament.name, material: filament.material,
            diameter: filament.diameter, netWeight: filament.weight,
            in: SpoolmanDBService.shared.filaments
        )
    case .filamanDB:
        do {
            return try await CatalogSpoolWeight.filamanDBWeight(
                manufacturer: manufacturer, name: filament.name, material: filament.material,
                diameter: filament.diameter, netWeight: filament.weight, catalog: filamanDB
            )
        } catch {
            // A form closed or a filament changed mid-lookup cancels it: not a failure.
            if !error.isCancellation {
                logger.error("FilaManDB spool weight lookup failed: \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
    }
}
