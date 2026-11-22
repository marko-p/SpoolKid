//
//  AddLocationView.swift
//  SpoolKid
//
//  Purpose: Creates a location. On FilaMan that is a real row; on Spoolman and
//  the on-device Library there is no create endpoint, so the name is held in
//  the device-local registry and the form says so rather than implying a
//  server write that never happened.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct AddLocationView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var store: SpoolDataStore
    var onAdded: ((String) -> Void)? = nil

    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            ServerDownFormNote()
            Section("Name") {
                TextField("Shelf A", text: $name)
                    .textInputAutocapitalization(.words)
            }

            Section {
                Text("Locations are how SpoolKid groups spools. You can label one with an NFC tag and scan it to assign spools.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .keyboardDoneBar()
        .navigationTitle("Add Location")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { save() }
                    .disabled(LocationName.trimmed(name).isEmpty || isSaving)
                    .needsServer()
            }
        }
        .alert(
            "Could Not Add Location",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func save() {
        let trimmed = LocationName.trimmed(name)
        guard !trimmed.isEmpty else { return }

        Task {
            isSaving = true
            defer { isSaving = false }

            let outcome = await store.addLocation(name: trimmed)
            guard outcome.isSuccess else {
                errorMessage = outcome.note(locationName: trimmed, storageNoun: store.capabilities.storageNoun)
                return
            }

            // A success with a caveat — the location exists for SpoolKid but
            // not yet on the server — reaches the user through the root
            // notice, which survives this sheet dismissing.
            if let note = outcome.note(locationName: trimmed, storageNoun: store.capabilities.storageNoun) {
                store.postSaveNotice(note, record: trimmed)
            }
            onAdded?(trimmed)
            dismiss()
        }
    }
}
