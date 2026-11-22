//
//  AddSpoolFlowView.swift
//  SpoolKid
//
//  Purpose: The Add Spool sheet. It opens on the filament search. Once a
//  filament is picked, the spool form replaces the search as the sheet's
//  root, so the form's own Cancel and Save close the whole sheet.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct AddSpoolFlowView: View {
    @ObservedObject var store: SpoolDataStore

    @Environment(\.dismiss) private var dismiss
    @State private var filamentID: Int?

    var body: some View {
        NavigationStack {
            Group {
                if let filamentID {
                    SpoolFormView(store: store, initialFilamentId: filamentID)
                        .id("form-\(filamentID)")
                } else {
                    FilamentSelectionView(selectedFilamentID: $filamentID, store: store, dismissesOnSelect: false)
                        .id("search")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { dismiss() }
                            }
                        }
                }
            }
        }
    }
}
