//
//  DashboardLayoutStore.swift
//  SpoolKid
//
//  Purpose: In-app dashboard card visibility (show/hide, fixed order).
//  UserDefaults-backed, following the FieldVisibilityStore pattern.
//  Persists a per-kind override map; absent entries fall back to
//  `kind.defaultVisible`.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum DashboardCardKind: String, CaseIterable, Identifiable, Sendable {
    case tagCoverage, reorderSoon, colors, materialStats, totalValue, locations
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tagCoverage: "Tag coverage"
        case .reorderSoon: "Reorder soon"
        case .colors: "Colours"
        case .materialStats: "Material statistics"
        case .totalValue: "Total value"
        case .locations: "Locations"
        }
    }
    /// Off by default: plenty of users never organize by shelf, and a card
    /// reading "0 locations" is noise to them. One toggle away in Customize
    /// for the users who do.
    var defaultVisible: Bool { self != .totalValue && self != .locations }
}

/// In-app dashboard card visibility (show/hide, fixed order). UserDefaults-backed,
/// following the field-visibility store pattern. Persists a per-kind override map;
/// absent entries fall back to `kind.defaultVisible`.
struct DashboardLayoutStore {
    private let userDefaults: UserDefaults
    private let key = AppConfig.dashboardHiddenCardsKey
    init(userDefaults: UserDefaults = .standard) { self.userDefaults = userDefaults }

    private var overrides: [String: Bool] {
        get { userDefaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: Bool].self, from: $0) } ?? [:] }
        nonmutating set { userDefaults.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    func isVisible(_ kind: DashboardCardKind) -> Bool { overrides[kind.rawValue] ?? kind.defaultVisible }

    func setVisible(_ visible: Bool, for kind: DashboardCardKind) {
        var o = overrides
        o[kind.rawValue] = visible
        overrides = o
    }
}
