//
//  SortOptionRows.swift
//  SpoolKid
//
//  Purpose: The option rows inside a sort menu — one implementation, so the
//  single-axis `SortMenu` and the two-section `LocationSortMenu` cannot drift
//  into two different-looking menus.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct SortOptionRows<Option: SortOption & RawRepresentable>: View
where Option.RawValue == String, Option.AllCases: RandomAccessCollection {
    let options: Option.Type
    @Binding var field: String
    @Binding var ascending: Bool

    private var currentSort: Option {
        Option(rawValue: field) ?? options.allCases.first!
    }

    // A menu row renders one title and one icon, nothing more: anything drawn
    // after the title is dropped. So the selection is the
    // Toggle's native checkmark, and the direction takes the icon slot.
    var body: some View {
        ForEach(Array(options.allCases)) { option in
            Toggle(isOn: Binding(
                get: { currentSort == option },
                set: { _ in
                    if currentSort == option {
                        ascending.toggle()
                    } else {
                        field = option.rawValue
                    }
                }
            )) {
                Label(option.label, systemImage: Self.iconName(for: option, selected: currentSort, ascending: ascending))
            }
        }
    }

    static func iconName(for option: Option, selected: Option, ascending: Bool) -> String {
        guard option == selected, option.isDirectional else { return option.systemImage }
        return ascending ? "chevron.up" : "chevron.down"
    }
}
