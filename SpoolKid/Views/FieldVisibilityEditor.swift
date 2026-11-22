//
//  FieldVisibilityEditor.swift
//  SpoolKid
//
//  Purpose: Reusable per-form "Customize Fields" editor. Renders a Toggle
//  for each non-essential field in a FieldCatalog entity or an
//  NFCFieldCatalog format, bound directly to the AppConfig visibility key.
//  Essential fields are never shown (always visible).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct FieldVisibilityEditor: View {
    private let fields: [(label: String, key: String, defaultVisible: Bool)]

    /// Only fields the ACTIVE backend has — a toggle that cannot change
    /// anything is a control wired to nothing.
    init(
        entity: LibraryEntity,
        capabilities: BackendCapabilities,
        store: FieldVisibilityStore? = nil
    ) {
        let support = capabilities.fieldSupport
        let store = store ?? FieldVisibilityStore(support: support)
        self.fields = FieldCatalog.fields(for: entity)
            .filter { !$0.isEssential && support.supports($0.id, in: entity) }
            .compactMap { field in
                guard let key = store.visibilityKey(for: entity, fieldID: field.id) else { return nil }
                return (field.label, key, field.defaultVisible)
            }
    }

    /// For tests: what this editor actually offers.
    var fieldLabels: [String] { fields.map(\.label) }

    init(format: TagFormat, store: NFCFieldVisibilityStore = .init()) {
        self.fields = NFCFieldCatalog.fields(for: format)
            .filter { !$0.isEssential }
            .compactMap { field in
                guard let key = store.visibilityKey(for: format, fieldID: field.id) else { return nil }
                return (field.label, key, field.defaultVisible)
            }
    }

    var body: some View {
        ForEach(fields.indices, id: \.self) { index in
            let field = fields[index]
            Toggle(field.label, isOn: visibilityBinding(for: field.key, defaultVisible: field.defaultVisible))
        }
    }

    private func visibilityBinding(for key: String, defaultVisible: Bool) -> Binding<Bool> {
        Binding(
            get: {
                if UserDefaults.standard.object(forKey: key) == nil { return defaultVisible }
                return UserDefaults.standard.bool(forKey: key)
            },
            set: { UserDefaults.standard.set($0, forKey: key) }
        )
    }
}
