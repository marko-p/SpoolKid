//
//  ManufacturerChoice.swift
//  SpoolKid
//
//  Purpose: What the manufacturer picker answers, and its rows for one search
//  — computed without the view, so the row rules are tested.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum ManufacturerChoice: Hashable, Sendable {
    case none
    /// One of the backend's manufacturers.
    case existing(id: Int, name: String)
    /// A catalogue name or typed text that is not one of the backend's.
    case new(name: String)

    var name: String? {
        switch self {
        case .none: nil
        case .existing(_, let name), .new(let name): name
        }
    }

    /// Whether a picker row stands for this choice: the same backend
    /// manufacturer by id, or the same new name by `ManufacturerName.key`.
    func matches(_ other: ManufacturerChoice) -> Bool {
        switch (self, other) {
        case (.none, .none): true
        case let (.existing(a, _), .existing(b, _)): a == b
        case let (.new(a), .new(b)): ManufacturerName.key(a) == ManufacturerName.key(b)
        default: false
        }
    }

    /// What a stored name stands for: none when blank, the backend's
    /// manufacturer when one has that name, else a new name.
    static func named(_ name: String, in vendors: [Vendor]) -> ManufacturerChoice {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        if let vendor = ManufacturerName.vendor(named: trimmed, in: vendors) {
            return .existing(id: vendor.id, name: vendor.name)
        }
        return .new(name: trimmed)
    }
}

/// The manufacturer picker's rows for one search.
nonisolated struct ManufacturerPickerSections: Equatable, Sendable {
    /// The backend's manufacturers matching the search, A–Z.
    var mine: [ManufacturerChoice]
    /// Catalogue names matching the search that are not the backend's, one
    /// per manufacturer, A–Z.
    var catalog: [String]
    /// The trimmed search text for the Use "…" row — set only when neither
    /// the backend nor the catalogue has a name with its key.
    var customName: String?

    static func build(vendors: [Vendor], catalog: [String], search: String) -> ManufacturerPickerSections {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        func shows(_ name: String) -> Bool {
            query.isEmpty || name.localizedCaseInsensitiveContains(query)
        }
        func ascending(_ a: String, _ b: String) -> Bool {
            a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }

        let vendorKeys = Set(vendors.map { ManufacturerName.key($0.name) })
        let mine = vendors
            .filter { shows($0.name) }
            .sorted { ascending($0.name, $1.name) }
            .map { ManufacturerChoice.existing(id: $0.id, name: $0.name) }

        var catalogKeys = Set<String>()
        var catalogNames: [String] = []
        for name in catalog {
            let key = ManufacturerName.key(name)
            guard !key.isEmpty, !vendorKeys.contains(key), catalogKeys.insert(key).inserted else { continue }
            if shows(name) {
                catalogNames.append(name.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        catalogNames.sort(by: ascending)

        let queryKey = ManufacturerName.key(query)
        let isKnown = vendorKeys.contains(queryKey) || catalogKeys.contains(queryKey)
        let customName = queryKey.isEmpty || isKnown ? nil : query

        return ManufacturerPickerSections(mine: mine, catalog: catalogNames, customName: customName)
    }
}
