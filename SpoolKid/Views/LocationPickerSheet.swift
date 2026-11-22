//
//  LocationPickerSheet.swift
//  SpoolKid
//
//  Purpose: Where a selection of spools is going. "Remove from Location" sits
//  first and clears the field rather than writing a word, so the sheet cannot
//  be used to invent a location called "Unassigned".
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct LocationPickerSheet: View {
    let title: String
    let locations: [String]
    /// When set, a Scan Location Tag row leads the sheet (the Spool page).
    var onScanTag: (() -> Void)? = nil
    let onPick: (SpoolmanPatchValue<String>) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let onScanTag {
                Section {
                    Button {
                        dismiss()
                        onScanTag()
                    } label: {
                        Label("Scan Location Tag", systemImage: "wave.3.right")
                    }
                    .accessibilityIdentifier("locations.picker.scan")
                }
            }
            Section {
                Button {
                    onPick(.setNil)
                    dismiss()
                } label: {
                    Label("Remove from Location", systemImage: "tray")
                }
                .accessibilityIdentifier("locations.picker.remove")
            }

            Section("Locations") {
                if locations.isEmpty {
                    Text("There are no locations yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(locations, id: \.self) { name in
                        Button {
                            onPick(.set(name))
                            dismiss()
                        } label: {
                            Label(name, systemImage: "mappin.and.ellipse")
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
