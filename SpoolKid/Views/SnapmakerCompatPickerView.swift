//
//  SnapmakerCompatPickerView.swift
//  SpoolKid
//
//  Purpose: Sheet presented when a material type is not compatible with
//  the Snapmaker U1 printer. Shows the incompatible type and lets the
//  user choose a compatible replacement before writing the NFC tag.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI

struct SnapmakerCompatPickerView: View {
    let incompatibleMaterial: String
    let compatibleMaterials: [String]
    let onSelect: (String) -> Void
    let onCancel: () -> Void
    
    @State private var selected: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Warning header
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.statusWarning)
                
                Text("Incompatible Material Type")
                    .font(.headline)
                
                Text("**\(incompatibleMaterial)** is not supported by the Snapmaker U1. Please choose a compatible material type to write to the NFC tag.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.vertical)
            
            // Material list
            List {
                ForEach(compatibleMaterials, id: \.self) { mat in
                    Button(action: {
                        selected = mat
                    }) {
                        HStack {
                            Text(mat)
                                .foregroundColor(.primary)
                            Spacer()
                            if selected == mat {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
        }
        .navigationTitle("Choose Material")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Write to NFC Tag") {
                    onSelect(selected)
                }
                .disabled(selected.isEmpty)
            }
        }
    }
}
