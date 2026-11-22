//
//  LocationSortMenu.swift
//  SpoolKid
//
//  Purpose: The arrangement screen's sort control. Two axes in one menu — how
//  the shelves order, and how the spools inside them order — because they are
//  one question the user asks at one moment.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct LocationSortMenu: View {
    @Binding var locationField: String
    @Binding var locationAscending: Bool
    @Binding var spoolField: String
    @Binding var spoolAscending: Bool

    var body: some View {
        Menu {
            // Scoped to the CONTENT, never the Menu: the Menu's own label must
            // keep inheriting `.labelStyle(.iconOnly)` from the toolbar, while
            // the rows inside always show text and icon. Same rule as SortMenu.
            Group {
                Section("Locations") {
                    SortOptionRows(
                        options: LocationSortOption.self,
                        field: $locationField,
                        ascending: $locationAscending
                    )
                }
                Section("Spools") {
                    SortOptionRows(
                        options: SpoolSortOption.self,
                        field: $spoolField,
                        ascending: $spoolAscending
                    )
                }
            }
            .labelStyle(.titleAndIcon)
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityIdentifier("locations.sort")
    }
}
