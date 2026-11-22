//
//  SpoolGroupingMenu.swift
//  SpoolKid
//
//  Purpose: The Group By menu for the spool lists, a control of its own rather
//  than part of Sort & Filter. Each screen binds it to its own remembered choice:
//  Manage Spools uses `AppConfig.spoolGroupingKey` (default Filament), Select
//  Spool uses `AppConfig.spoolPickerGroupingKey` (default None).
//  Two looks (`Style`). As a toolbar button it is highlighted while any grouping
//  is on: the grouping's own symbol, white on an accent circle; with None it is
//  the plain grouping icon. As the screen's title it is text with a chevron,
//  naming what the list is made of ("Filaments ⌄", owner 2026-10-26).
//  The stored value is a raw string, so an unknown or missing value falls back to
//  the screen's own default (`fallback`, Filament unless given) rather than leaving
//  the menu with no current choice.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct SpoolGroupingMenu: View {
    enum Style {
        /// An icon-only toolbar button.
        case toolbarButton
        /// The screen's title, in `HarmonizedSearchList`'s title slot.
        case title
    }

    @Binding var grouping: String
    /// What an unknown stored value reads as. It must match the fallback the
    /// screen's list uses, so the menu names the grouping the list shows.
    let fallback: SpoolGrouping
    let style: Style

    init(grouping: Binding<String>, fallback: SpoolGrouping = .filament, style: Style = .toolbarButton) {
        self._grouping = grouping
        self.fallback = fallback
        self.style = style
    }

    private var current: SpoolGrouping {
        SpoolGrouping(rawValue: grouping) ?? fallback
    }

    var body: some View {
        Menu {
            Picker("Group By", selection: $grouping) {
                ForEach(SpoolGrouping.allCases) { option in
                    Label(option.label, systemImage: option.systemImage)
                        .tag(option.rawValue)
                }
            }
        } label: {
            switch style {
            case .toolbarButton:
                Label {
                    Text("Group By: \(current.label)")
                } icon: {
                    if current.isHighlightedInToolbar {
                        Image(systemName: current.toolbarSymbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.accentColor))
                    } else {
                        Image(systemName: current.toolbarSymbol)
                    }
                }
            case .title:
                HStack(spacing: 4) {
                    Text(current.titleMenuLabel)
                        .font(.headline)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                }
                // The fixed colour, not `.primary`: a bar button's hierarchical
                // styles resolve against its tint, which drew the title orange.
                // Black or white, like any title (owner, 2026-10-26).
                .foregroundStyle(Color.primary)
                // A custom title gets no system hit area: make the whole bar
                // height tappable.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
        .accessibilityLabel(Text("Group By: \(current.label)"))
        .accessibilityIdentifier("spoolList.group")
    }
}
