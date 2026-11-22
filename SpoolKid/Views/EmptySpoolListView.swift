//
//  EmptySpoolListView.swift
//  SpoolKid
//
//  Purpose: The empty-spool library as a list, in two modes. `.pick` is the
//  sheet the spool form and Weigh Spools open: tapping an entry hands its
//  grams back and closes. `.manage` is pushed from the Library tab: tapping
//  an entry edits it. Both can add, edit and delete, so a spool missing from
//  the library can be added without leaving the form. A picker opened for a
//  spool whose brand has entries lists them first, in a section of their own.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct EmptySpoolListView: View {
    enum Mode {
        /// `manufacturer` is the brand of the spool being edited or weighed.
        case pick(manufacturer: String?, onPick: (Double) -> Void)
        case manage
    }

    let mode: Mode

    @EnvironmentObject private var library: EmptySpoolLibrary
    @EnvironmentObject private var store: SpoolDataStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppConfig.confirmBeforeDeleteKey) private var confirmBeforeDelete: Bool = true

    @State private var editorTarget: EditorTarget?
    @State private var pendingDelete: EmptySpoolRecord?
    @State private var failureMessage: String?
    /// Pick mode only: the catalogue's weights, and how it answered (nil while
    /// it loads). Bumping `catalogueAttempt` (Retry) loads it again.
    @State private var catalogueSections: (brand: CatalogEmptySpools.Section?, others: [CatalogEmptySpools.Section]) = (nil, [])
    @State private var catalogueAnswer: ScanResolutionService.CatalogueAnswer?
    @State private var catalogueAttempt = 0

    private enum EditorTarget: Identifiable {
        case add
        case edit(EmptySpoolRecord)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let record): return record.id.uuidString
            }
        }

        var record: EmptySpoolRecord? {
            if case .edit(let record) = self { return record }
            return nil
        }
    }

    private var isPicking: Bool {
        if case .pick = mode { return true }
        return false
    }

    var body: some View {
        Group {
            if showsEmptyState {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Empty Spools")
        .task(id: catalogueAttempt) { await loadCatalogue() }
        .toolbar {
            if isPicking {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorTarget = .add
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Empty Spool")
                .accessibilityIdentifier("emptySpools.add")
            }
        }
        .sheet(item: $editorTarget) { target in
            NavigationStack {
                EmptySpoolEditorView(editing: target.record)
            }
        }
        .confirmationDialog(
            "Delete \u{201C}\(pendingDelete?.listTitle ?? "")\u{201D}?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { record in
            Button("Delete", role: .destructive) { delete(record) }
                .accessibilityIdentifier("emptySpools.confirmDelete")
        } message: { _ in
            Text("Spools that use this weight keep it.")
        }
        .alert(
            failureMessage ?? "",
            isPresented: Binding(
                get: { failureMessage != nil },
                set: { if !$0 { failureMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    /// In pick mode, the brand of the spool the picker was opened for; its
    /// entries get a section of their own on top.
    private var pickManufacturer: String? {
        if case .pick(let manufacturer, _) = mode { return manufacturer }
        return nil
    }

    /// An empty library shows the empty state, except in pick mode while the
    /// catalogue is loading, could not be reached, or has rows to pick.
    private var showsEmptyState: Bool {
        guard library.entries.isEmpty else { return false }
        guard isPicking else { return true }
        let catalogueDone = catalogueAnswer == .answered || catalogueAnswer == .noBrand
        return catalogueDone && catalogueSections.brand == nil && catalogueSections.others.isEmpty
    }

    private var catalogName: String { store.capabilities.manufacturerCatalog.displayName }

    private var trimmedPickManufacturer: String {
        pickManufacturer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// The spool's brand first, the user's spools before the catalogue's:
    /// the library's brand section, the catalogue's, the user's other spools,
    /// then the catalogue's other brands (pick mode only).
    private var list: some View {
        let sections = EmptySpoolLibrary.pickerSections(forManufacturer: pickManufacturer, in: library.entries)
        let catalogueBrand = isPicking ? catalogueSections.brand : nil
        return List {
            if !sections.brand.isEmpty {
                Section {
                    ForEach(sections.brand) { row($0) }
                } header: {
                    Text(trimmedPickManufacturer)
                }
            }
            if isPicking, let status = catalogueStatusRow {
                Section { status }
            }
            if let catalogueBrand {
                catalogueSection(catalogueBrand)
            }
            if !sections.other.isEmpty {
                if sections.brand.isEmpty && catalogueBrand == nil {
                    ForEach(sections.other) { row($0) }
                } else {
                    Section("Other Spools") {
                        ForEach(sections.other) { row($0) }
                    }
                }
            }
            if isPicking {
                ForEach(catalogueSections.others) { catalogueSection($0) }
            }
        }
    }

    private func catalogueSection(_ section: CatalogEmptySpools.Section) -> some View {
        Section("\(section.brand) · \(catalogName)") {
            ForEach(section.rows) { catalogueRow in
                Button {
                    pick(catalogueRow.grams)
                } label: {
                    CatalogEmptySpoolRow(row: catalogueRow)
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("emptySpools.catalogRow")
            }
        }
    }

    /// Says what the catalogue is doing, so a missing answer is never read as
    /// "nothing found" (the Scan Result candidate list's copy); nil when there
    /// is nothing to say.
    private var catalogueStatusRow: AnyView? {
        switch catalogueAnswer {
        case nil:
            return AnyView(ProgressView().frame(maxWidth: .infinity))
        case .failed:
            return AnyView(HStack(spacing: 12) {
                Label("Could not reach \(catalogName)", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                Spacer()
                Button("Retry") { catalogueAttempt += 1 }
                    .buttonStyle(.bordered)
            })
        case .noBrand:
            guard !trimmedPickManufacturer.isEmpty else { return nil }
            return AnyView(footnote("\(catalogName) has no filaments for this brand."))
        case .answered:
            guard !trimmedPickManufacturer.isEmpty, catalogueSections.brand == nil else { return nil }
            return AnyView(footnote("\(catalogName) states no empty spool weight for \(trimmedPickManufacturer)."))
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func loadCatalogue() async {
        guard isPicking else { return }
        catalogueAnswer = nil
        let load = await CatalogEmptySpools.load(forManufacturer: pickManufacturer, store: store)
        guard !Task.isCancelled else { return }
        catalogueSections = CatalogEmptySpools.sections(from: load.entries, forManufacturer: pickManufacturer)
        catalogueAnswer = load.answer
    }

    @ViewBuilder
    private func row(_ record: EmptySpoolRecord) -> some View {
        Button {
            tapped(record)
        } label: {
            EmptySpoolRow(record: record)
        }
        .foregroundStyle(.primary)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                if confirmBeforeDelete {
                    pendingDelete = record
                } else {
                    delete(record)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityIdentifier("emptySpools.delete")
            if isPicking {
                Button {
                    editorTarget = .edit(record)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !isPicking {
                Button {
                    toggleDefault(record)
                } label: {
                    Label(
                        record.isDefault ? "Remove Default" : "Make Default",
                        systemImage: record.isDefault ? "star.slash" : "star"
                    )
                }
                .tint(.orange)
                if !record.manufacturer.isEmpty {
                    Button {
                        toggleManufacturerDefault(record)
                    } label: {
                        Label(
                            record.isManufacturerDefault ? "Remove Brand Default" : "Brand Default",
                            systemImage: record.isManufacturerDefault ? "star.slash" : "star.circle"
                        )
                    }
                    .tint(.indigo)
                    .accessibilityLabel(
                        record.isManufacturerDefault
                            ? "Remove default for \(record.manufacturer) spools"
                            : "Make default for \(record.manufacturer) spools"
                    )
                    .accessibilityIdentifier("emptySpools.brandDefault")
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Empty Spools Yet", systemImage: "circle.circle")
        } description: {
            Text("Weigh a bare spool once, save it here with a photo, and pick it for every spool like it.")
        } actions: {
            Button("Add Empty Spool") { editorTarget = .add }
                .buttonStyle(.borderedProminent)
        }
    }

    private func tapped(_ record: EmptySpoolRecord) {
        switch mode {
        case .pick:
            pick(record.weight)
        case .manage:
            editorTarget = .edit(record)
        }
    }

    /// Hands back the grams only; the spool keeps no link to the row.
    private func pick(_ grams: Double) {
        guard case .pick(_, let onPick) = mode else { return }
        onPick(grams)
        dismiss()
    }

    private func delete(_ record: EmptySpoolRecord) {
        if !library.delete(record.id) {
            failureMessage = "Could not delete the empty spool."
        }
    }

    private func toggleDefault(_ record: EmptySpoolRecord) {
        if !library.setDefault(record.isDefault ? nil : record.id) {
            failureMessage = "Could not save the empty spool."
        }
    }

    private func toggleManufacturerDefault(_ record: EmptySpoolRecord) {
        if !library.setManufacturerDefault(record.id, !record.isManufacturerDefault) {
            failureMessage = "Could not save the empty spool."
        }
    }
}
