//
//  VendorFormView.swift
//  SpoolKid
//
//  Purpose: Edits a manufacturer, embedded in its page. Manufacturers are
//  created through the manufacturer picker, when a filament that names a new
//  one is saved.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct VendorFormView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.serverLink) private var serverLink
    @ObservedObject var store: SpoolDataStore
    let vendorToEdit: Vendor
    /// The manufacturer page embeds this form in place of its read view, so
    /// finishing there returns to the read page rather than popping it. When
    /// set, Cancel and a successful Save call it instead of `dismiss()`. Delete
    /// still dismisses: a deleted manufacturer has no page to return to.
    var onFinish: (() -> Void)? = nil

    @State private var name: String = ""
    @State private var comment: String = ""
    @State private var emptySpoolWeight: String = ""
    @State private var externalId: String = ""
    @AppStorage(AppConfig.confirmBeforeDeleteKey) private var confirmBeforeDelete = true
    @State private var isSaving: Bool = false
    @State private var saveErrorMessage: String?
    @State private var showCustomizeFields = false
    @State private var fieldVisibilityRefreshToken = 0

    private func finish() {
        if let onFinish { onFinish() } else { dismiss() }
    }

    static func visibleFieldIDs(for capabilities: BackendCapabilities) -> Set<String> {
        FieldVisibilityStore(support: capabilities.fieldSupport).visibleFieldIDs(for: .vendor)
    }

    static func vendorDraft(
        name: String,
        comment: String,
        emptySpoolWeight: String,
        externalId: String
    ) -> VendorDraft {
        let normalizedWeight = emptySpoolWeight.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parsedWeight = normalizedWeight.isEmpty ? nil : Double(normalizedWeight)

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExternalId = externalId.trimmingCharacters(in: .whitespacesAndNewlines)

        return VendorDraft(
            name: trimmedName,
            comment: trimmedComment.isEmpty ? nil : trimmedComment,
            emptySpoolWeight: parsedWeight,
            externalId: trimmedExternalId.isEmpty ? nil : trimmedExternalId
        )
    }
    
    var body: some View {
        let _ = fieldVisibilityRefreshToken
        let visibleFieldIDs = Self.visibleFieldIDs(for: store.capabilities)

        Form {
            ServerDownFormNote()
            Section("Manufacturer") {
                TextField("Manufacturer Name", text: $name)

                if visibleFieldIDs.contains("comment") {
                    TextField("Comment", text: $comment, axis: .vertical)
                        .lineLimit(2...5)
                }

                if visibleFieldIDs.contains("empty_spool_weight") {
                    TextField("Default Empty Spool Weight", text: $emptySpoolWeight)
                        .keyboardType(.decimalPad)
                }

                if visibleFieldIDs.contains("external_id") {
                    TextField("External ID", text: $externalId)
                        .textInputAutocapitalization(.never)
                }
            }

            Section {
                CascadeDeleteButton(
                    record: .vendor(id: vendorToEdit.id, name: vendorToEdit.name),
                    store: store,
                    confirmBeforeDelete: confirmBeforeDelete,
                    onDeleted: { dismiss() }
                )
            }
        }
        .keyboardDoneBar()
        .selectsTextOnFocus()
        .navigationTitle("Edit Manufacturer")
        .alert(
            "Could Not Save Manufacturer",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "Unknown error")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCustomizeFields = true
                } label: {
                    Label("Customize Fields", systemImage: "slider.horizontal.3")
                        .labelStyle(.iconOnly)
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { finish() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        isSaving = true
                        defer { isSaving = false }

                        let draft = Self.vendorDraft(
                            name: name,
                            comment: comment,
                            emptySpoolWeight: emptySpoolWeight,
                            externalId: externalId
                        )

                        let written = await serverLink.outcome {
                            await store.updateVendor(id: vendorToEdit.id, draft: draft)
                        }

                        if case .saved = written {
                            finish()
                        } else {
                            saveErrorMessage = SaveNote.failure(
                                written, otherwise: store.errorMessage ?? "The manufacturer could not be saved."
                            )
                        }
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                .needsServer()
            }
        }
        .sheet(isPresented: $showCustomizeFields, onDismiss: { fieldVisibilityRefreshToken += 1 }) {
            NavigationStack {
                Form {
                    Section("Optional Fields") {
                        FieldVisibilityEditor(entity: .vendor, capabilities: store.capabilities)
                    }
                }
                .navigationTitle("Customize Fields")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showCustomizeFields = false }
                    }
                }
            }
        }
        .onAppear {
            name = vendorToEdit.name
            comment = vendorToEdit.comment ?? ""
            emptySpoolWeight = vendorToEdit.emptySpoolWeight.map { String($0) } ?? ""
            externalId = vendorToEdit.externalId ?? ""
        }
    }
}
