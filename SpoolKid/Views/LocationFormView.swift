//
//  LocationFormView.swift
//  SpoolKid
//
//  Purpose: Form for renaming an existing location in Spoolman.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI

struct LocationFormView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var service: SpoolmanService
    let baseUrl: String
    let currentLocation: String
    var onRenamed: ((String) -> Void)? = nil

    @State private var newLocationName: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Current") {
                Text(currentLocation)
            }

            Section("Rename") {
                TextField("New location name", text: $newLocationName)
            }
        }
        .hideKeyboardOnTap()
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

            let success = await service.renameLocation(
                currentName: currentLocation,
                newName: trimmed,
                baseUrl: baseUrl
            )

            if success {
                onRenamed?(trimmed)
                dismiss()
                return
            }

            errorMessage = service.errorMessage ?? "The location could not be renamed."
        }
    }
}
