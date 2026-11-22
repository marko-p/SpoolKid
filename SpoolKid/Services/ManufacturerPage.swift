//
//  ManufacturerPage.swift
//  SpoolKid
//
//  Purpose: The pure rules the Manufacturer page renders: which filaments
//  belong to a vendor and in what order; the header line; the vendor's spec
//  rows; and its brand's empty spools. Views render these values; the rules
//  live here (conventions A2/A3).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// `nonisolated`: the target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`;
/// these pure rules must stay usable from nonisolated contexts (tests included).
nonisolated enum ManufacturerPage {
    /// The filaments of the vendor with `id`, in name order
    /// (`localizedStandardCompare`). The vendor is matched by id, never by name.
    static func filaments(ofVendor id: Int, in filaments: [Filament]) -> [Filament] {
        filaments
            .filter { $0.vendor?.id == id }
            .sorted {
                switch sortKey($0).localizedStandardCompare(sortKey($1)) {
                case .orderedAscending: true
                case .orderedDescending: false
                case .orderedSame: $0.id < $1.id
                }
            }
    }

    /// "2 filaments · 3 spools · 1 kg left", counting the vendor's non-archived
    /// spools. The weight part is dropped when no counted spool states a
    /// remaining weight.
    static func headerText(vendorID: Int, filaments: [Filament], spools: [Spool]) -> String {
        let owned = Self.filaments(ofVendor: vendorID, in: filaments)
        let ownedIDs = Set(owned.map(\.id))
        let stocks = SpoolUsage.stock(of: spools.filter { ownedIDs.contains($0.filament.id) }).values
        let spoolCount = stocks.reduce(0) { $0 + $1.spoolCount }
        var text = "\(filamentCountText(owned.count)) · \(SpoolUsage.spoolCountText(spoolCount))"
        let known = stocks.compactMap(\.remaining)
        if !known.isEmpty {
            text += " · \(SpoolUsage.weightText(known.reduce(0, +))) left"
        }
        return text
    }

    /// The vendor's spec rows, in the vendor form's order. A row is left out
    /// when its field is not visible, or when its value is nil or blank.
    static func fieldRows(for vendor: Vendor, visibleFieldIDs: Set<String>) -> [FilamentSpecRow] {
        let rows: [(label: String, gate: String, value: String?)] = [
            ("Comment", "comment", vendor.comment.nonBlank),
            ("Empty Spool Weight", "empty_spool_weight", vendor.emptySpoolWeight.map(SpoolUsage.weightText)),
            ("External ID", "external_id", vendor.externalId.nonBlank),
        ]
        return rows.compactMap { row in
            guard visibleFieldIDs.contains(row.gate), let value = row.value else { return nil }
            return FilamentSpecRow(label: row.label, value: value)
        }
    }

    /// The empty spools of the vendor's brand, by the rule the empty-spool
    /// picker uses (`EmptySpoolLibrary.pickerSections`).
    static func emptySpools(forVendorNamed name: String, in entries: [EmptySpoolRecord]) -> [EmptySpoolRecord] {
        EmptySpoolLibrary.pickerSections(forManufacturer: name, in: entries).brand
    }

    /// A filament row's title: its name, else its material, else "Filament".
    static func title(of filament: Filament) -> String {
        filament.name.nonBlank ?? filament.material.nonBlank ?? "Filament"
    }

    /// The name a filament sorts by: its name, else its material, else "".
    private static func sortKey(_ filament: Filament) -> String {
        filament.name.nonBlank ?? filament.material.nonBlank ?? ""
    }

    private static func filamentCountText(_ count: Int) -> String {
        count == 1 ? "1 filament" : "\(count) filaments"
    }
}
