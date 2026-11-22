//
//  SpoolSelectionView.swift
//  SpoolKid
//
//  Purpose: Picker view for selecting a spool from Spoolman to create an NFC tag.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct SpoolSelectionView: View {
    @EnvironmentObject private var store: SpoolDataStore
    @AppStorage(AppConfig.spoolPickerSortFieldKey) private var sortField: String = SpoolSortOption.recent.rawValue
    @AppStorage(AppConfig.spoolPickerSortAscendingKey) private var sortAscending: Bool = false
    @AppStorage(AppConfig.spoolPickerGroupingKey) private var groupingRaw: String = SpoolGrouping.none.rawValue
    /// Not persisted: groups open each time the picker appears.
    @State private var collapsedGroups: Set<String> = []
    @State private var searchText = ""

    /// When set, rows report the tapped spool to the caller instead of
    /// navigating to `WriteTagView`. Optional, so the Tags-tab entry point
    /// (`TagsTabView`) pushes the tag writer as before.
    var onSelect: ((Spool) -> Void)? = nil

    /// The system's minimum row height, read outside the list: the list lowers it
    /// for its rows, and a screen pushed from a row would inherit that.
    @Environment(\.defaultMinListRowHeight) private var systemMinRowHeight

    private var currentSort: SpoolSortOption {
        SpoolSortOption(rawValue: sortField) ?? .id
    }
    
    var filteredAndSortedSpools: [Spool] {
        let filtered = store.activeSpools.filter { spool in
            SearchQuery.matches(searchText, in: [
                spool.filament.name, spool.filament.vendor?.name,
                spool.filament.material, String(spool.id)
            ])
        }
        
        return filtered.sorted { a, b in
            let result = currentSort.areInIncreasingOrder(a, b)
            return sortAscending ? result : !result
        }
    }
    
    /// An unknown stored value reads as None, the picker's default.
    private var layout: SpoolListLayout {
        SpoolListGrouping.layout(
            grouping: SpoolGrouping(rawValue: groupingRaw) ?? .none,
            isFilamentDrillDown: false
        )
    }

    /// No folds in a picker: every spool must stay selectable.
    private func makeGroups(of rows: [Spool], isSearching: Bool) -> [SpoolGroup] {
        SpoolListGrouping.groups(
            rows: rows,
            totalsFrom: store.activeSpools,
            mode: layout.mode,
            foldsUnused: false,
            isSearching: isSearching
        )
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        // Once per render: the empty state and the groups both read it.
        let spools = filteredAndSortedSpools
        HarmonizedSearchList(
            title: "Select Spool",
            searchText: $searchText,
            prompt: "Search spools...",
            trailingControlCount: 2,
            // Only rows under a filament are 36 pt, below the system minimum
            // (O25); with no grouping, the default here, rows are normal list rows.
            compactRowHeight: layout.usesCompactRows ? SpoolUsageRow.compactRowHeight : nil,
            // The bar already names the picker; a large title repeated it.
            showsLargeTitle: false,
            trailing: {
                SpoolGroupingMenu(grouping: $groupingRaw, fallback: .none)
                SortMenu(options: SpoolSortOption.self, field: $sortField, ascending: $sortAscending)
            }
        ) {
            if store.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if let error = store.errorMessage {
                ContentUnavailableView {
                    Label("Could Not Load Spools", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        fetchSpools()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if spools.isEmpty {
                Group {
                    if searchText.isEmpty {
                        ContentUnavailableView(
                            "No Spools",
                            systemImage: "shippingbox",
                            // The tab says "Library" on every backend
                            // (`ContentView`, audit L1).
                            description: Text("Add spools in the Library tab first.")
                        )
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if layout.showsHeaders {
                ForEach(makeGroups(of: spools, isSearching: isSearching)) { group in
                    // A search holds its groups open (`forcedOpen`, decided by the
                    // service) so a match is never hidden; the user's own collapsed
                    // set is left alone.
                    let collapsed = !group.forcedOpen && collapsedGroups.contains(group.id)
                    Section {
                        groupHeader(group, isCollapsed: collapsed)
                        if !collapsed {
                            entryRows(group.entries)
                        }
                    }
                }
            } else {
                Section(header: Text("Spools")) {
                    entryRows(makeGroups(of: spools, isSearching: isSearching).first?.entries ?? [])
                }
            }
        }
        .environment(\.spoolIDDigits, SpoolUsageRow.idDigits(for: store.activeSpools))
        .refreshable {
            await store.fetchSpools()
        }
        .onAppear {
            fetchSpools()
        }
    }

    private func groupHeader(_ group: SpoolGroup, isCollapsed: Bool) -> some View {
        SpoolGroupHeader(
            group: group,
            mode: layout.mode,
            isCollapsed: isCollapsed,
            isForcedOpen: group.forcedOpen,
            // A picker has no screen per group, so the header body only collapses it.
            onOpen: nil,
            onToggle: { toggleGroup(group) }
        )
    }

    /// A forced-open group is the search's doing, not the user's; toggling it
    /// must not write into their own collapsed set.
    private func toggleGroup(_ group: SpoolGroup) {
        guard !group.forcedOpen else { return }
        if collapsedGroups.contains(group.id) {
            collapsedGroups.remove(group.id)
        } else {
            collapsedGroups.insert(group.id)
        }
    }

    @ViewBuilder
    private func entryRows(_ entries: [SpoolListEntry]) -> some View {
        ForEach(entries) { entry in
            if case .spool(let spool) = entry {
                spoolRow(spool).listRowInsets(SpoolUsageRow.rowInsets(for: layout.rowStyle))
            }
        }
    }

    /// Both branches are the picker's original rows; only the label is new.
    @ViewBuilder
    private func spoolRow(_ spool: Spool) -> some View {
        if let onSelect {
            Button { onSelect(spool) } label: { SpoolUsageRow(spool: spool, style: layout.rowStyle) }
                .buttonStyle(.plain)
        } else {
            // The pushed screen is not a spool list: it gets the system's row height
            // back, not the 36 pt this list inherits to its rows.
            NavigationLink(destination: WriteTagView(initialData: FilamentTagData.from(spool: spool))
                .environment(\.defaultMinListRowHeight, systemMinRowHeight)) {
                SpoolUsageRow(spool: spool, style: layout.rowStyle)
            }
        }
    }

    private func fetchSpools() {
        Task {
            await store.fetchSpools()
        }
    }
}
