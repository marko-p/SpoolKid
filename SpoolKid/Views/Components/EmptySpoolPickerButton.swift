//
//  EmptySpoolPickerButton.swift
//  SpoolKid
//
//  Purpose: The one way a weight field opens the empty-spool library. Shared
//  by the spool form and Weigh Spools so the two cannot drift apart. Picking
//  hands back grams only — the spool keeps no link to the entry. The caller
//  passes the spool's brand, whose entries the picker lists first.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct EmptySpoolPickerButton: View {
    let accessibilityID: String
    /// The spool's brand; nil when it has none.
    let manufacturer: String?
    let onPick: (Double) -> Void

    @State private var showingPicker = false

    init(accessibilityID: String, manufacturer: String?, onPick: @escaping (Double) -> Void) {
        self.accessibilityID = accessibilityID
        self.manufacturer = manufacturer
        self.onPick = onPick
    }

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            Image(systemName: "books.vertical")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        // Borderless, so a tap elsewhere in the form row does not fire it.
        .buttonStyle(.borderless)
        .accessibilityLabel("Choose an empty spool")
        .accessibilityIdentifier(accessibilityID)
        .sheet(isPresented: $showingPicker) {
            NavigationStack {
                EmptySpoolListView(mode: .pick(manufacturer: manufacturer, onPick: onPick))
            }
        }
    }
}
