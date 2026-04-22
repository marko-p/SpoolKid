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
    @State private var isSaving: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Vendor") {
                    TextField("Vendor Name", text: $name)
                }
            }
            .hideKeyboardOnTap()
            .navigationTitle(vendorToEdit == nil ? "Add Vendor" : "Edit Vendor")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            if let vendor = vendorToEdit {
                                await service.updateVendor(id: vendor.id, name: name, baseUrl: baseUrl)
                            } else {
                                _ = await service.addVendor(name: name, baseUrl: baseUrl)
                            }
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty || isSaving)
                }
            }
            .onAppear {
                if let vendor = vendorToEdit {
                    name = vendor.name
                }
            }
        }
    }
}
