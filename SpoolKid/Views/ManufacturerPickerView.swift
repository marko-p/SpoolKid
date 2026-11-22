//
//  ManufacturerPickerView.swift
//  SpoolKid
//
//  Purpose: The one manufacturer picker — the backend's own manufacturers,
//  then its public catalogue's (SpoolmanDB or FilaManDB, by capability), then
//  the search text as a new name. Pushed by the empty-spool editor and the
//  filament form; each says what it allows.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct ManufacturerPickerView: View {
    /// Gets the checkmark.
    let current: ManufacturerChoice
    /// Offers "None" — the empty-spool editor, whose manufacturer is optional.
    var allowsNone = false
    /// Called with the pick; the picker then pops itself.
    let onPick: (ManufacturerChoice) -> Void

    @EnvironmentObject private var store: SpoolDataStore
    @ObservedObject private var catalog = ManufacturerCatalogService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var isSearchPresented = false

    private var catalogName: String { store.capabilities.manufacturerCatalog.displayName }

    var body: some View {
        let sections = ManufacturerPickerSections.build(
            vendors: store.vendors,
            catalog: catalog.names,
            search: searchText
        )
        List {
            if allowsNone && searchText.isEmpty {
                row("None", for: .none)
                    .accessibilityIdentifier("manufacturerPicker.none")
            }
            if !sections.mine.isEmpty {
                Section("My Manufacturers") {
                    ForEach(sections.mine, id: \.self) { choice in
                        row(choice.name ?? "", for: choice)
                    }
                }
            }
            if catalog.isLoading || catalog.didFail || !sections.catalog.isEmpty {
                Section(catalogName) {
                    if catalog.isLoading {
                        ProgressView()
                            .accessibilityLabel("Loading \(catalogName)")
                    } else if catalog.didFail {
                        HStack {
                            Text("Couldn't load \(catalogName).")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Retry") {
                                Task { await catalog.load(for: store) }
                            }
                            .accessibilityIdentifier("manufacturerPicker.catalogRetry")
                        }
                    } else {
                        ForEach(sections.catalog, id: \.self) { name in
                            row(name, for: .new(name: name))
                        }
                    }
                }
            }
            if let custom = sections.customName {
                Section {
                    Button("Use \u{201C}\(custom)\u{201D}") {
                        pick(.new(name: custom))
                    }
                    .accessibilityIdentifier("manufacturerPicker.useTyped")
                }
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search or type a name"
        )
        .autocorrectionDisabled()
        .navigationTitle("Manufacturer")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.vendors.isEmpty { await store.fetchVendors() }
        }
        .task {
            await catalog.load(for: store)
        }
    }

    private func row(_ title: String, for choice: ManufacturerChoice) -> some View {
        Button {
            pick(choice)
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if choice.matches(current) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityAddTraits(choice.matches(current) ? .isSelected : [])
    }

    private func pick(_ choice: ManufacturerChoice) {
        // Ends a focused search first: popping with it still active left the
        // search bar and keyboard stranded over the form, hiding its nav bar.
        isSearchPresented = false
        onPick(choice)
        dismiss()
    }
}
