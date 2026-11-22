//
//  DashboardCustomizeView.swift
//  SpoolKid
//
//  Purpose: In-app show/hide for optional dashboard cards (fixed order). Writes
//  through to `DashboardLayoutStore`. Spool status is always shown and not listed.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// In-app show/hide for optional dashboard cards (fixed order). Writes through to
/// `DashboardLayoutStore`. Spool status is always shown and not listed here.
struct DashboardCustomizeView: View {
    let store: DashboardLayoutStore
    let onDone: () -> Void

    @State private var visibility: [String: Bool] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(DashboardCardKind.allCases) { kind in
                        Toggle(kind.title, isOn: Binding(
                            get: { visibility[kind.rawValue] ?? store.isVisible(kind) },
                            set: { newValue in
                                visibility[kind.rawValue] = newValue
                                store.setVisible(newValue, for: kind)
                            }
                        ))
                    }
                } footer: {
                    Text("Spool status is always shown.")
                }
            }
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone() }
                }
            }
            .onAppear {
                for kind in DashboardCardKind.allCases { visibility[kind.rawValue] = store.isVisible(kind) }
            }
        }
    }
}
