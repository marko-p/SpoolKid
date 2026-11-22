//
//  RegistryPickerSheet.swift
//  SpoolKid
//
//  Purpose: Searchable picker over a fixed list — TigerTag's registries
//  (materials, brands) and ELEGOO's Canvas filaments. One component for all
//  of them so the lists cannot drift apart visually. A sheet, not a push:
//  WriteTagView's onAppear sets up the form and must run once.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct RegistryPickerSheet<Entry: Identifiable>: View {
    let title: String
    let entries: [Entry]
    let label: (Entry) -> String
    @Binding var selection: Entry?
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [Entry] {
        guard !search.isEmpty else { return entries }
        let needle = TigerTagRegistry.normalize(search)
        return entries.filter { TigerTagRegistry.normalize(label($0)).contains(needle) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { entry in
                Button {
                    selection = entry
                    dismiss()
                } label: {
                    HStack {
                        Text(label(entry))
                        Spacer()
                        if selection?.id == entry.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .foregroundColor(.primary)
            }
            .searchable(text: $search, prompt: "Search \(title)")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
