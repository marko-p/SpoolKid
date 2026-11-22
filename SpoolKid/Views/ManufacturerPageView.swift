//
//  ManufacturerPageView.swift
//  SpoolKid
//
//  Purpose: One manufacturer, read first: its header, the fields it states,
//  its filaments with their stock, its brand's empty spools, and Delete. Edit
//  shows the manufacturer form in place. Views render and route; the rules
//  live in ManufacturerPage and SpoolUsage (conventions A2/A3).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// A pushed destination. It is never wrapped in its own NavigationStack.
struct ManufacturerPageView: View {
    @ObservedObject var store: SpoolDataStore
    let vendorID: Int
    /// Pushed from another page: cross-links render as plain text, so pages
    /// nest one level only (owner, 2026-11-03).
    var isNested = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var emptySpools: EmptySpoolLibrary
    @AppStorage(AppConfig.confirmBeforeDeleteKey) private var confirmBeforeDelete: Bool = true

    @State private var isEditing = false
    /// False until the page has looked for its manufacturer once, fetching it
    /// when the store does not hold it (a list can push the page before the
    /// Library has loaded any vendors), so "Not Found" means a real miss.
    @State private var hasLookedUp = false

    private var vendor: Vendor? { store.vendors.first { $0.id == vendorID } }

    var body: some View {
        Group {
            // Held on the spinner while a found manufacturer's filaments are
            // still loading, so the list never flashes "No filaments".
            if let vendor, hasLookedUp || !store.filaments.isEmpty {
                if isEditing {
                    VendorFormView(store: store, vendorToEdit: vendor, onFinish: { isEditing = false })
                        .navigationBarBackButtonHidden(true)
                } else {
                    readList(vendor).pageTitle("Manufacturer")
                }
            } else if !hasLookedUp {
                ProgressView().pageTitle("Manufacturer")
            } else {
                ContentUnavailableView("Manufacturer Not Found", systemImage: "questionmark.circle")
                    .pageTitle("Manufacturer")
            }
        }
        .task {
            if vendor == nil { await store.fetchVendors() }
            // Only for a manufacturer that exists: a miss shows Not Found at once.
            if vendor != nil, store.filaments.isEmpty { await store.fetchFilaments() }
            hasLookedUp = true
        }
    }

    // MARK: - Read list

    private func readList(_ vendor: Vendor) -> some View {
        let stock = SpoolUsage.stock(of: store.spools)
        return List {
            headerSection(vendor)
            manufacturerSection(vendor)
            filamentsSection(vendor, stock: stock)
            emptySpoolsSection(vendor)
            deleteSection(vendor)
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
                    .accessibilityIdentifier("manufacturerPage.edit")
            }
        }
    }

    private func headerSection(_ vendor: Vendor) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(vendor.name)
                        .font(.title3.bold())
                    Text("#\(vendor.id)")
                        .foregroundStyle(.secondary)
                }
                Text(ManufacturerPage.headerText(vendorID: vendor.id, filaments: store.filaments, spools: store.spools))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Manufacturer fields

    @ViewBuilder
    private func manufacturerSection(_ vendor: Vendor) -> some View {
        let rows = ManufacturerPage.fieldRows(
            for: vendor,
            visibleFieldIDs: VendorFormView.visibleFieldIDs(for: store.capabilities)
        )
        if !rows.isEmpty {
            Section {
                ForEach(rows, id: \.label) { row in
                    LabeledContent(row.label, value: row.value)
                }
            } header: {
                Text("Manufacturer")
            }
        }
    }

    // MARK: - Filaments

    private func filamentsSection(_ vendor: Vendor, stock: [Int: FilamentStock]) -> some View {
        let filaments = ManufacturerPage.filaments(ofVendor: vendor.id, in: store.filaments)
        return Section {
            if filaments.isEmpty {
                Text("No filaments")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filaments) { filament in
                    if isNested {
                        filamentLabel(filament, stock: stock[filament.id])
                    } else {
                        NavigationLink {
                            FilamentPageView(store: store, filamentID: filament.id, isNested: true)
                        } label: {
                            filamentLabel(filament, stock: stock[filament.id])
                        }
                    }
                }
            }
        } header: {
            Text("Filaments · \(filaments.count)")
        }
    }

    private func filamentLabel(_ filament: Filament, stock: FilamentStock?) -> some View {
        HStack(spacing: 12) {
            FilamentSwatch(colors: filament.colors, size: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                let title = ManufacturerPage.title(of: filament)
                Text(title)
                if let material = filament.material.nonBlank, material != title {
                    Text(material)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(SpoolUsage.stockText(stock))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                // The name wraps first, as in the group headers.
                .fixedSize()
        }
    }

    // MARK: - Empty spools

    /// Read-only: the brand's entries, with the brand default marked by
    /// `EmptySpoolRow`. No navigation and no swipe actions here.
    @ViewBuilder
    private func emptySpoolsSection(_ vendor: Vendor) -> some View {
        let entries = ManufacturerPage.emptySpools(forVendorNamed: vendor.name, in: emptySpools.entries)
        if !entries.isEmpty {
            Section {
                ForEach(entries) { record in
                    EmptySpoolRow(record: record)
                }
            } header: {
                Text("Empty Spools")
            }
        }
    }

    // MARK: - Delete

    private func deleteSection(_ vendor: Vendor) -> some View {
        Section {
            CascadeDeleteButton(
                record: .vendor(id: vendor.id, name: vendor.name),
                store: store,
                confirmBeforeDelete: confirmBeforeDelete,
                onDeleted: { dismiss() }
            )
        }
    }
}
