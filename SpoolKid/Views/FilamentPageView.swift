//
//  FilamentPageView.swift
//  SpoolKid
//
//  Purpose: One filament, read first: its header, the spools made from it, its
//  specs, tags and manufacturer, and Delete. Edit shows the filament form in
//  place. Views render and route; the rules live in FilamentPage,
//  FilamentManufacturerChange and SpoolListGrouping (conventions A2/A3).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// A pushed destination. It is never wrapped in its own NavigationStack.
struct FilamentPageView: View {
    @ObservedObject var store: SpoolDataStore
    let filamentID: Int
    /// Pushed from another page: cross-links render as plain text, so pages
    /// nest one level only (owner, 2026-11-03).
    var isNested = false

    @Environment(\.dismiss) private var dismiss
    /// The system's row height. The read list lowers its own to the compact
    /// spool-row height, so anything pushed or presented from it gets this back.
    @Environment(\.defaultMinListRowHeight) private var systemMinRowHeight
    @AppStorage(AppConfig.confirmBeforeDeleteKey) private var confirmBeforeDelete: Bool = true

    @State private var isEditing = false
    /// Not remembered: archived spools are hidden each time the page opens.
    @State private var showArchived = false
    @State private var expandedFolds: Set<String> = []
    @State private var showingAddSpools = false
    @State private var spoolIDToOpen: Int?
    @State private var showingChangeError = false
    @State private var changeError = ""
    /// False until the page has looked for its filament once, fetching it when
    /// the store does not hold it (the scan hub can open the page before the
    /// Library has loaded any filaments), so "Not Found" means a real miss.
    @State private var hasLookedUp = false

    private var filament: Filament? { store.filaments.first { $0.id == filamentID } }

    var body: some View {
        Group {
            if let filament {
                if isEditing {
                    FilamentFormView(store: store, filamentToEdit: filament, onFinish: { isEditing = false })
                        .navigationBarBackButtonHidden(true)
                } else {
                    readList(filament).pageTitle("Filament")
                }
            } else if !hasLookedUp {
                ProgressView().pageTitle("Filament")
            } else {
                ContentUnavailableView("Filament Not Found", systemImage: "questionmark.circle")
                    .pageTitle("Filament")
            }
        }
        .task {
            if filament == nil { await store.fetchFilaments() }
            hasLookedUp = true
            if store.vendors.isEmpty { await store.fetchVendors() }
        }
        // Attached outside the List, so the compact row height does not reach
        // the sheets.
        .sheet(isPresented: $showingAddSpools, onDismiss: { Task { await store.fetchSpools() } }) {
            NavigationStack {
                SpoolFormView(store: store, initialFilamentId: filamentID)
            }
        }
        .navigationDestination(item: $spoolIDToOpen) { id in
            SpoolPageView(store: store, spoolID: id, isNested: true)
                .environment(\.defaultMinListRowHeight, systemMinRowHeight)
        }
        .alert("Could Not Change Manufacturer", isPresented: $showingChangeError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(changeError)
        }
    }

    // MARK: - Read list

    private func readList(_ filament: Filament) -> some View {
        let spools = FilamentPage.spools(ofFilament: filamentID, in: store.spools, showArchived: showArchived)
        let group = FilamentPage.group(ofFilament: filamentID, in: store.spools, showArchived: showArchived)
        return List {
            headerSection(filament)
            addSection
            spoolsSection(group)
            specsSection(filament)
            // Its Write Tag link pushes a form, which must not inherit the
            // compact row height.
            FilamentTagsSection(store: store, filamentId: filament.id)
                .environment(\.defaultMinListRowHeight, systemMinRowHeight)
            manufacturerSection(filament)
            deleteSection(filament)
        }
        .listStyle(.insetGrouped)
        .environment(\.defaultMinListRowHeight, SpoolUsageRow.compactRowHeight)
        .environment(\.spoolIDDigits, SpoolUsageRow.idDigits(for: spools))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
                    .accessibilityIdentifier("filamentPage.edit")
            }
        }
    }

    private func headerSection(_ filament: Filament) -> some View {
        Section {
            HStack(spacing: 12) {
                FilamentSwatch(colors: filament.colors, size: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(filament.name ?? filament.material ?? "Filament")
                            .font(.title3.bold())
                        Text("#\(filament.id)")
                            .foregroundStyle(.secondary)
                    }
                    Text(FilamentPage.headerSubtitle(filament))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var addSection: some View {
        Section {
            Button {
                showingAddSpools = true
            } label: {
                Text("Add Spools of This")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("filamentPage.addSpools")
        }
    }

    // MARK: - Spools

    private func spoolsSection(_ group: SpoolGroup?) -> some View {
        Section {
            if let group {
                entryRows(group.entries)
            } else {
                Text("No spools")
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text(FilamentPage.spoolsHeader(group))
                Spacer()
                Toggle("Show Archived", isOn: $showArchived)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func entryRows(_ entries: [SpoolListEntry]) -> some View {
        ForEach(entries) { entry in
            switch entry {
            case .spool(let spool):
                spoolRow(spool)
            case .fold(let fold):
                SpoolFoldRow(
                    fold: fold,
                    isExpanded: expandedFolds.contains(fold.id),
                    onToggle: { toggleFold(fold) }
                )
                .listRowInsets(SpoolUsageRow.compactRowInsets)
                if expandedFolds.contains(fold.id) {
                    ForEach(fold.spools) { spoolRow($0) }
                }
            }
        }
    }

    /// A nested page's rows open nothing (the one-level rule).
    @ViewBuilder
    private func spoolRow(_ spool: Spool) -> some View {
        Group {
            if isNested {
                SpoolUsageRow(spool: spool, style: .underFilament, showsLocation: true)
            } else {
                Button {
                    spoolIDToOpen = spool.id
                } label: {
                    SpoolUsageRow(spool: spool, style: .underFilament, showsLocation: true)
                }
            }
        }
        .accessibilityIdentifier("filamentPage.spoolRow")
        .listRowInsets(SpoolUsageRow.rowInsets(for: .underFilament))
    }

    private func toggleFold(_ fold: SpoolFold) {
        if expandedFolds.contains(fold.id) {
            expandedFolds.remove(fold.id)
        } else {
            expandedFolds.insert(fold.id)
        }
    }

    // MARK: - Specs, tags, manufacturer, delete

    @ViewBuilder
    private func specsSection(_ filament: Filament) -> some View {
        let rows = FilamentPage.specRows(
            for: filament,
            visibleFieldIDs: FilamentFormView.visibleFieldIDs(for: store.capabilities)
        )
        Section {
            ForEach(rows, id: \.label) { row in
                LabeledContent(row.label, value: row.value)
            }
        }
    }

    @ViewBuilder
    private func manufacturerSection(_ filament: Filament) -> some View {
        Section {
            LabeledContent("Name", value: filament.vendor?.name ?? "None")
            if let weight = filament.vendor?.emptySpoolWeight {
                LabeledContent("Empty Spool Weight", value: SpoolUsage.weightText(weight))
            }
            NavigationLink {
                ManufacturerPickerView(current: manufacturerChoice(of: filament)) { picked in
                    Task { await changeManufacturer(to: picked, of: filament) }
                }
                .environmentObject(store)
                .environment(\.defaultMinListRowHeight, systemMinRowHeight)
            } label: {
                Text("Change")
            }
            .needsServer()
            if let vendor = filament.vendor, !isNested {
                NavigationLink {
                    ManufacturerPageView(store: store, vendorID: vendor.id, isNested: true)
                        .environment(\.defaultMinListRowHeight, systemMinRowHeight)
                } label: {
                    Text("Open Manufacturer")
                }
            }
        } header: {
            Text("Manufacturer")
        }
    }

    /// The picker's checkmark: the filament's current manufacturer, or none.
    private func manufacturerChoice(of filament: Filament) -> ManufacturerChoice {
        guard let vendor = filament.vendor else { return ManufacturerChoice.none }
        return .existing(id: vendor.id, name: vendor.name)
    }

    private func changeManufacturer(to choice: ManufacturerChoice, of filament: Filament) async {
        let outcome = await FilamentManufacturerChange.apply(choice, toFilament: filament, store: store)
        if case .failed(let message) = outcome {
            changeError = message
            showingChangeError = true
        }
    }

    @ViewBuilder
    private func deleteSection(_ filament: Filament) -> some View {
        Section {
            CascadeDeleteButton(
                record: .filament(id: filament.id, name: filament.name ?? filament.material ?? "this filament"),
                store: store,
                confirmBeforeDelete: confirmBeforeDelete,
                onDeleted: { dismiss() }
            )
        }
    }
}
