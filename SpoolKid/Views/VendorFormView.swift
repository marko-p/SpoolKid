//
//  VendorFormView.swift
//  SpoolKid
//
//  Purpose: Form for creating or editing a Vendor in Spoolman.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI

struct VendorFormView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var service: SpoolmanService
    let baseUrl: String
    var vendorToEdit: SpoolmanVendor?
    
    @State private var name: String = ""
    @State private var comment: String = ""
    @State private var emptySpoolWeight: String = ""
    @State private var externalId: String = ""
    @State private var extraJSON: String = ""
    @State private var isSaving: Bool = false
    @State private var saveErrorMessage: String?

    static func visibleFieldIDs(store: SpoolmanFieldVisibilityStore = .init()) -> Set<String> {
        store.visibleFieldIDs(for: .vendor)
    }

    static func vendorPayload(
        name: String,
        comment: String,
        emptySpoolWeight: String,
        externalId: String,
        extraJSON: String
    ) -> [String: Any] {
        let normalizedWeight = emptySpoolWeight.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parsedWeight = normalizedWeight.isEmpty ? nil : Double(normalizedWeight)

        let normalizedExtraJSON = extraJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedExtra: [String: String]? = if normalizedExtraJSON.isEmpty {
            nil
        } else {
            (try? JSONSerialization.jsonObject(with: Data(normalizedExtraJSON.utf8))) as? [String: String]
        }

        return SpoolmanPayloadBuilder.vendorPayload(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            comment: comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : comment.trimmingCharacters(in: .whitespacesAndNewlines),
            emptySpoolWeight: parsedWeight,
            externalId: externalId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : externalId.trimmingCharacters(in: .whitespacesAndNewlines),
            extra: parsedExtra
        )
    }
    
    var body: some View {
        let visibleFieldIDs = Self.visibleFieldIDs()

        NavigationStack {
            Form {
                Section("Vendor") {
                    TextField("Vendor Name", text: $name)

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

                    if visibleFieldIDs.contains("extra") {
                        TextField("Extra JSON", text: $extraJSON, axis: .vertical)
                            .lineLimit(2...5)
                            .textInputAutocapitalization(.never)
                    }
                }
            }
            .hideKeyboardOnTap()
            .navigationTitle(vendorToEdit == nil ? "Add Vendor" : "Edit Vendor")
            .alert(
                "Could Not Save Vendor",
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            isSaving = true
                            defer { isSaving = false }

                            let payload = Self.vendorPayload(
                                name: name,
                                comment: comment,
                                emptySpoolWeight: emptySpoolWeight,
                                externalId: externalId,
                                extraJSON: extraJSON
                            )

                            let didSave: Bool

                            if let vendor = vendorToEdit {
                                didSave = await service.updateVendor(
                                    id: vendor.id,
                                    name: payload["name"] as? String,
                                    comment: payload["comment"] as? String,
                                    emptySpoolWeight: payload["empty_spool_weight"] as? Double,
                                    externalId: payload["external_id"] as? String,
                                    extra: payload["extra"] as? [String: String],
                                    baseUrl: baseUrl
                                )
                            } else {
                                didSave = await service.addVendor(
                                    name: payload["name"] as? String ?? name,
                                    comment: payload["comment"] as? String,
                                    emptySpoolWeight: payload["empty_spool_weight"] as? Double,
                                    externalId: payload["external_id"] as? String,
                                    extra: payload["extra"] as? [String: String],
                                    baseUrl: baseUrl
                                ) != nil
                            }

                            if didSave {
                                dismiss()
                            } else {
                                saveErrorMessage = service.errorMessage ?? "The vendor could not be saved."
                            }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let vendor = vendorToEdit {
                    name = vendor.name
                    comment = vendor.comment ?? ""
                    emptySpoolWeight = vendor.emptySpoolWeight.map { String($0) } ?? ""
                    externalId = vendor.externalId ?? ""

                    if let extra = vendor.extra,
                       let data = try? JSONSerialization.data(withJSONObject: extra, options: [.sortedKeys]),
                       let string = String(data: data, encoding: .utf8) {
                        extraJSON = string
                    } else {
                        extraJSON = ""
                    }
                }
            }
        }
    }
}
