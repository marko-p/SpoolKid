//
//  LocationFormView.swift
//  SpoolKid
//
//  Purpose: Form for renaming an existing location in Spoolman.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct LocationFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.serverLink) private var serverLink

    @ObservedObject var store: SpoolDataStore
    let currentLocation: String
    var onRenamed: ((String) -> Void)? = nil

    @AppStorage(AppConfig.confirmBeforeDeleteKey) private var confirmBeforeDelete = true
    @State private var newLocationName: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var deleteErrorMessage: String?

    var body: some View {
        Form {
            ServerDownFormNote()
            Section("Current") {
                Text(currentLocation)
            }

            Section("Rename") {
                TextField("New location name", text: $newLocationName)
            }

            Section {
                DestructiveFormButton(
                    title: "Delete Location",
                    confirmTitle: "Delete Location?",
                    confirmMessage: "\(currentLocation) will be permanently deleted from \(store.capabilities.storageNoun).",
                    confirmBeforeDelete: confirmBeforeDelete
                ) {
                    Task {
                        let deleted = await store.deleteLocation(currentLocation)
                        let outcome = SaveOutcome.classify(
                            didSave: deleted,
                            message: store.errorMessage,
                            failureFallback: "The location could not be deleted."
                        )
                        if outcome.didWrite { dismiss() } else { deleteErrorMessage = outcome.failure }
                    }
                }
            }
            .needsServer()
        }
        .keyboardDoneBar()
        .selectsTextOnFocus()
        .navigationTitle("Rename Location")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveRename()
                }
                .disabled(isSaveDisabled)
                .needsServer()
            }
        }
        .alert(
            "Could Not Rename Location",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .alert(
            "Could Not Delete Location",
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { deleteErrorMessage = nil }
        } message: {
            Text(deleteErrorMessage ?? "Unknown error")
        }
        .onAppear {
            newLocationName = currentLocation
        }
    }

    private var isSaveDisabled: Bool {
        let trimmed = newLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == currentLocation || isSaving
    }

    private func saveRename() {
        let trimmed = newLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != currentLocation else { return }

        Task {
            isSaving = true
            defer { isSaving = false }

            let written = await serverLink.outcome {
                await store.renameLocation(currentName: currentLocation, newName: trimmed)
            }

            if case .saved = written {
                onRenamed?(trimmed)
                dismiss()
                return
            }

            errorMessage = SaveNote.failure(written, otherwise: store.errorMessage ?? "The location could not be renamed.")
        }
    }
}
