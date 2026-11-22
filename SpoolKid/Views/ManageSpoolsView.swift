//
//  ManageSpoolsView.swift
//  SpoolKid
//
//  Purpose: List view for managing spools in Spoolman (view, edit, delete).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import PhotosUI
import SwiftUI

/// Filter applied to the spool list when it is opened as a drill-down. `nil`
/// shows all spools (the plain Manage Spools entry). `nonisolated` so the static
/// predicate seam stays testable from nonisolated contexts.
nonisolated enum SpoolFilter: Hashable {
    case filament(Int)
    case fillBucket(SpoolFillBucket)
    case material(String)
    case untagged
}

/// One active-filter pill shown above the spool list. `nonisolated` so the
/// chip-building seam stays testable from nonisolated contexts.
nonisolated struct ActiveFilterChip: Identifiable, Hashable {
    enum Kind: Hashable {
        case color
        case material(String)
        case archived
        case withoutSpools
    }
    var id: String
    var label: String
    /// Anchor swatch hex for the color chip; nil for the others.
    var swatchHex: String?
    var kind: Kind
}

struct ManageSpoolsView: View {
    @EnvironmentObject private var store: SpoolDataStore
    @AppStorage(AppConfig.confirmBeforeDeleteKey) private var confirmBeforeDelete: Bool = true
    @Environment(\.editMode) private var editMode
    @State private var showingAddSheet = false
    @State private var spoolIDToOpen: Int?
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var selection = Set<Int>()
    @State private var showBulkConfirm = false
    @State private var bulkMessage: String?
    @State private var showBulkResult = false
    @AppStorage(AppConfig.spoolSortFieldKey) private var sortField: String = SpoolSortOption.id.rawValue
    @AppStorage(AppConfig.spoolSortAscendingKey) private var sortAscending: Bool = false
    @AppStorage(AppConfig.manageSpoolsShowArchivedKey) private var showArchived: Bool = false
    @AppStorage(AppConfig.libraryShowsWithoutSpoolsKey) private var showsWithoutSpools = false
    @State private var colorSpec: ColorFilterSpec? = nil
    @State private var showingColorFilter = false
    /// Color Matching opened from the Color grouping's shortcuts.
    @State private var colorMatchingStart: LoadoutPlannerView.Start?
    @State private var choosingMatchPhoto = false
    @State private var selectedMaterials: Set<String> = []
    /// Bound by id, not by `Spool` itself: `Spool` is not `Hashable`, which
    /// `navigationDestination(item:)` requires.
    @State private var spoolIDToWeigh: Int?
    @AppStorage(AppConfig.spoolGroupingKey) private var groupingRaw: String = SpoolGrouping.filament.rawValue
    /// Not persisted: groups open and folds closed each time the screen appears.
    @State private var collapsedGroups: Set<String> = []
    /// The Recently Added section folded to its header, like a group's own
    /// collapse: kept while the screen lives, not across launches.
    @State private var recentlyAddedCollapsed = false
    @State private var expandedFolds: Set<String> = []
    @State private var filamentIDToOpen: Int?
    @State private var vendorIDToOpen: Int?
    @State private var locationToOpen: String?

    var filter: SpoolFilter? = nil

    /// Non-nil turns on Library mode, where this list is the Library tab's root:
    /// the tab's own rows sit above the groups, the Add button leaves the toolbar
    /// (the tab supplies Add Spool in its floating bottom bar), and the screen
    /// is named "Library". `filter` is nil there, so the grouping menu is the
    /// title, except under a harmony colour filter, which offers no grouping.
    var libraryRows: AnyView? = nil
    /// Extra work for pull-to-refresh, after the spools reload. The Library tab
    /// refreshes what its own rows show.
    var onRefresh: (() async -> Void)? = nil
    /// Non-nil puts a Settings button at the toolbar's right end, in the list's own
    /// trailing group: the Library tab's root has no other place on the right.
    var onShowSettings: (() -> Void)? = nil

    private var isLibraryMode: Bool { libraryRows != nil }

    /// The Library tab's rows, and under Color grouping, Color Matching's
    /// shortcuts and the color filter (owner, 2026-11-18).
    private var leadingRows: AnyView? {
        guard let libraryRows else { return nil }
        guard offersGrouping, SpoolGrouping(rawValue: groupingRaw) == .color else { return libraryRows }
        return AnyView(Group {
            libraryRows
            colorMatchingSection
        })
    }

    private var colorMatchingSection: some View {
        LeadingSection {
            Button { choosingMatchPhoto = true } label: {
                Label("Match a Photo", systemImage: "photo")
            }
            .accessibilityIdentifier("library.matchPhoto")
            Button { showingColorFilter = true } label: {
                Label("Filter by Color", systemImage: "circle.lefthalf.filled")
            }
            .accessibilityIdentifier("library.colorFilter")
        } footer: {
            Text("Match a Photo finds your spools closest to the colors you pick from a photo. Filter by Color also offers color harmonies.")
        }
    }

    private var currentSort: SpoolSortOption {
        SpoolSortOption(rawValue: sortField) ?? .id
    }

    /// Filament id to pre-select when adding a spool — only meaningful for the
    /// filament drill-down.
    private var addFilamentId: Int? {
        if case .filament(let id) = filter { return id }
        return nil
    }

    private var listTitle: String {
        switch filter {
        case .filament(let id):
            return store.filaments.first(where: { $0.id == id })?.name ?? "Spools"
        case .fillBucket(let bucket):
            return "\(bucket.title) Spools"
        case .material(let material):
            return material
        case .untagged:
            return "Untagged Spools"
        case .none:
            return isLibraryMode ? "Library" : "Manage Spools"
        }
    }

    /// Pipeline stage 1+2: archived-exclusion + drill-down filter. Islands and
    /// the color filter both derive from this set.
    private var baseSpools: [Spool] {
        let visible = Self.excludingArchived(store.spools, showArchived: showArchived)
        return Self.applyFilter(visible, filter: filter, ledger: TagAssociationStore.shared.snapshot())
    }

    /// Post-materials set: what the color filter and its islands operate on.
    private var materialFilteredSpools: [Spool] {
        Self.applyMaterials(baseSpools, selected: selectedMaterials)
    }

    private var availableMaterials: [String] {
        Array(Set(baseSpools.map { DashboardStatsService.materialKey(for: $0) }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var colorGroups: [ColorFilterService.RoleGroup] {
        guard let spec = colorSpec else { return [] }
        return ColorFilterService.groupedMatches(materialFilteredSpools, spec: spec)
    }

    /// Sectioned rendering only for harmony modes; Single stays a flat list.
    private var showsRoleSections: Bool {
        guard let spec = colorSpec else { return false }
        return spec.harmony != .single
    }

    /// Chips for every active filter — drives the chip row and the
    /// Sort & Filter button indicator. Includes Show Archived and Without Spools
    /// (which widen), unlike `hasActiveFilters` (narrowing filters only, for the
    /// empty state).
    private var activeChips: [ActiveFilterChip] {
        Self.activeFilterChips(colorSpec: colorSpec, selectedMaterials: selectedMaterials, showArchived: showArchived,
                               showsWithoutSpools: offersWithoutSpools && showsWithoutSpools)
    }

    var filteredAndSortedSpools: [Spool] {
        searchedAndSorted(Self.applyColorFilter(materialFilteredSpools, spec: colorSpec))
    }

    private var layout: SpoolListLayout {
        SpoolListGrouping.layout(
            grouping: SpoolGrouping(rawValue: groupingRaw) ?? .filament,
            isFilamentDrillDown: addFilamentId != nil
        )
    }

    /// Group By has no effect in a filament drill-down (one flat list) or under a
    /// harmony colour filter (role sections), so the menu is not offered there.
    private var offersGrouping: Bool {
        addFilamentId == nil && !showsRoleSections
    }

    /// Only the Library's own list, grouped by Filament or Manufacturer, offers
    /// the spool-less headers: those are the groupings whose records exist apart
    /// from spools, and each such header opens its record's page.
    private var offersWithoutSpools: Bool {
        isLibraryMode && (layout.mode == .filament || layout.mode == .manufacturer) && !showsRoleSections
    }

    /// Plain Manage Spools has no title of its own to keep, so the grouping menu
    /// takes the title's place ("Filaments ⌄", owner 2026-10-26). A Home
    /// drill-down keeps its title ("Low Spools") and Group stays a toolbar button.
    private var groupingIsTitle: Bool {
        offersGrouping && filter == nil
    }

    private var isEditing: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    /// No folds while editing: every spool must be a selectable row. Totals come
    /// from the colour-filtered set, so a header counts what the filter leaves, but
    /// not the search: a search never changes a header.
    private func makeGroups(of rows: [Spool], isSearching: Bool) -> [SpoolGroup] {
        SpoolListGrouping.groups(
            rows: rows,
            totalsFrom: Self.applyColorFilter(materialFilteredSpools, spec: colorSpec),
            mode: layout.mode,
            foldsUnused: layout.foldsUnused && !isEditing,
            isSearching: isSearching
        )
    }

    /// Filament or manufacturer headers with no visible spool, shown after the
    /// groups. Empty unless
    /// the toggle is on and the screen offers it, and while selecting: they hold no
    /// spool to select, and a tap on one would do nothing. The body reads this once
    /// per render.
    private var spoollessGroups: [SpoolGroup] {
        guard offersWithoutSpools && showsWithoutSpools && !isEditing else { return [] }
        return SpoolListGrouping.groupsWithoutSpools(
            filaments: store.filaments,
            vendors: store.vendors,
            visibleSpools: Self.excludingArchived(store.spools, showArchived: showArchived),
            mode: layout.mode,
            filtersActive: Self.hasActiveFilters(colorSpec: colorSpec, selectedMaterials: selectedMaterials),
            searchText: searchText
        )
    }

    /// The Library tab's own list puts the spools added in the last day in a
    /// section of their own at the top; a search or filter shows them in place.
    private var showsRecentlyAdded: Bool {
        SpoolListGrouping.offersRecentlyAdded(
            isLibraryList: isLibraryMode && filter == nil && addFilamentId == nil,
            isSearching: isSearching,
            filtersActive: Self.hasActiveFilters(colorSpec: colorSpec, selectedMaterials: selectedMaterials))
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func searchedAndSorted(_ base: [Spool]) -> [Spool] {
        let filtered = base.filter { spool in
            SearchQuery.matches(searchText, in: [
                spool.filament.name, spool.filament.vendor?.name,
                spool.filament.material, spool.location, String(spool.id)
            ])
        }

        return filtered.sorted { a, b in
            let result = currentSort.areInIncreasingOrder(a, b)
            return sortAscending ? result : !result
        }
    }

    var body: some View {
        // Once per render: the pipeline filters and sorts every spool, and the
        // empty state, the groups and the selection bar all read its result.
        // The spool-less headers are computed here for the same reason.
        let spools = filteredAndSortedSpools
        let spoollessGroups = self.spoollessGroups
        let split = showsRecentlyAdded
            ? SpoolListGrouping.splittingRecentlyAdded(spools, now: .now)
            : (recent: [], rest: spools)
        let recentGroups = SpoolListGrouping.recentlyAddedGroups(
            split.recent, mode: layout.mode, foldsUnused: layout.foldsUnused && !isEditing)
        HarmonizedSearchList(
            title: listTitle,
            searchText: $searchText,
            prompt: "Search spools...",
            selection: $selection,
            trailingControlCount: (offersGrouping && !groupingIsTitle ? 3 : 2) - (isLibraryMode ? 1 : 0)
                + (onShowSettings == nil ? 0 : 1),
            // Rows under a filament are 36 pt, below the system minimum, so the
            // list lowers it for them only; every other row is a normal list row
            // (O25). Colour sections show filament-named rows.
            compactRowHeight: layout.usesCompactRows && !showsRoleSections ? SpoolUsageRow.compactRowHeight : nil,
            titleMenu: groupingIsTitle ? AnyView(SpoolGroupingMenu(grouping: $groupingRaw, style: .title)) : nil,
            // Hidden while selecting: Select acts on spools, and the shortcut
            // rows have nothing to select.
            leadingSections: isEditing ? nil : leadingRows,
            // A search narrows the screen to spools: the tab's rows would only
            // push the matches down. Emptied, not removed, so the field keeps
            // the keyboard.
            collapsesLeadingSections: isSearching,
            // Recently Added and the rest are separate sections of the list.
            contentIsSectioned: true,
            trailing: {
                if offersGrouping && !groupingIsTitle {
                    SpoolGroupingMenu(grouping: $groupingRaw)
                }
                SortMenu(
                    title: "Sort & Filter",
                    filtersActive: !activeChips.isEmpty,
                    options: SpoolSortOption.self,
                    field: $sortField,
                    ascending: $sortAscending
                ) {
                    Divider()
                    Button {
                        showingColorFilter = true
                    } label: {
                        Label("Filter by Color…", systemImage: "paintpalette")
                    }
                    Menu {
                        ForEach(availableMaterials, id: \.self) { material in
                            Button {
                                if selectedMaterials.contains(material) {
                                    selectedMaterials.remove(material)
                                } else {
                                    selectedMaterials.insert(material)
                                }
                            } label: {
                                if selectedMaterials.contains(material) {
                                    Label(material, systemImage: "checkmark")
                                } else {
                                    Text(material)
                                }
                            }
                        }
                    } label: {
                        Label("Materials", systemImage: "square.stack.3d.up")
                    }
                    Toggle(isOn: $showArchived) {
                        Label("Show Archived", systemImage: "archivebox")
                    }
                    if offersWithoutSpools {
                        Toggle(isOn: $showsWithoutSpools) {
                            if layout.mode == .manufacturer {
                                Label("Show Manufacturers Without Spools", systemImage: "building.2")
                            } else {
                                Label("Show Filaments Without Spools", systemImage: "scribble")
                            }
                        }
                    }
                }
                if !isLibraryMode {
                    Button(action: { showingAddSheet = true }) {
                        Label("Add", systemImage: "plus")
                    }
                }
                // Last, at the bar's right edge, where the other tabs keep it.
                if let onShowSettings {
                    Button(action: onShowSettings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        ) {
            // Spools added in the last day get a section of their own above the
            // rest, each its own group on the list (owner 2026-11-10). A load or
            // an error replaces the whole list as before.
            if !recentGroups.isEmpty && !store.isLoading && loadError == nil {
                Section {
                    chipsRow
                    if !recentlyAddedCollapsed {
                        groupedRows(recentGroups, spoolless: [])
                    }
                } header: {
                    recentlyAddedHeader(spoolCount: split.recent.count)
                }
                if !split.rest.isEmpty || !spoollessGroups.isEmpty {
                    // No title: the gap between the two cards is enough (owner).
                    Section {
                        groupedRows(makeGroups(of: split.rest, isSearching: isSearching), spoolless: spoollessGroups)
                    }
                }
            } else {
                Section {
                    listContent(spools: spools, spoollessGroups: spoollessGroups)
                }
            }
        }
        .environment(\.spoolIDDigits, SpoolUsageRow.idDigits(for: store.spools))
        .sheet(isPresented: $showingAddSheet) {
            NavigationStack {
                SpoolFormView(store: store, initialFilamentId: addFilamentId)
            }
        }
        // No reload on pop here: `.onAppear` below already reloads when the
        // page is popped.
        .navigationDestination(item: $spoolIDToOpen) { id in
            SpoolPageView(store: store, spoolID: id)
        }
        .navigationDestination(item: $spoolIDToWeigh) { id in
            WeighSessionView(initialSpool: store.spools.first { $0.id == id })
        }
        // No reload on pop here: `.onAppear` below already reloads when the
        // page is popped.
        .navigationDestination(item: $filamentIDToOpen) { id in
            FilamentPageView(store: store, filamentID: id)
        }
        // No reload on pop here: .onAppear below already reloads when the page is popped.
        .navigationDestination(item: $vendorIDToOpen) { id in
            ManufacturerPageView(store: store, vendorID: id)
        }
        .navigationDestination(item: $colorMatchingStart) { start in
            LoadoutPlannerView(start: start)
        }
        .sheet(isPresented: $choosingMatchPhoto) {
            PhotoSourceSheet {
                choosingMatchPhoto = false
                colorMatchingStart = .camera
            } onPhoto: { item in
                choosingMatchPhoto = false
                colorMatchingStart = .photo(item)
            }
        }
        .navigationDestination(item: $locationToOpen) { name in
            LocationDetailView(store: store, locationName: name)
        }
        .sheet(isPresented: $showingColorFilter) {
            ColorMapFilterSheet(
                spec: $colorSpec,
                islands: ColorFilterService.islands(for: materialFilteredSpools),
                summary: colorSpec == nil ? nil : ColorFilterService.matchSummary(groups: colorGroups)
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            // Swipes on the harmony bar must scroll it, not resize the sheet;
            // vertical drags on non-scrolling areas still resize (device pass
            // 2026-07-02).
            .presentationContentInteraction(.scrolls)
        }
        // The selection actions take the tab's floating bar while selecting:
        // the count, Select All, then Archive (owner, 2026-10-29).
        .floatingBottomBar {
            if isEditing {
                HStack {
                    Text("\(selection.count) selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(selection.count == spools.count && !spools.isEmpty ? "Deselect All" : "Select All") {
                        if selection.count == spools.count { selection.removeAll() }
                        else { selection = Set(spools.map(\.id)) }
                    }
                    .disabled(spools.isEmpty)
                    Spacer()
                    Button(role: .destructive) {
                        if confirmBeforeDelete { showBulkConfirm = true } else { performBulkArchive() }
                    } label: {
                        Text("Archive").fontWeight(.semibold)
                    }
                    .needsServer()
                    .disabled(selection.isEmpty)
                }
                .padding(.vertical)
            }
        }
        .confirmationDialog("Archive \(selection.count) Spool\(selection.count == 1 ? "" : "s")?",
                            isPresented: $showBulkConfirm, titleVisibility: .visible) {
            Button("Archive", role: .destructive) { performBulkArchive() }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Bulk Archive", isPresented: $showBulkResult, presenting: bulkMessage) { _ in
            Button("OK") { }
        } message: { Text($0) }
        .refreshable {
            await reload()
            await onRefresh?()
        }
        .onAppear {
            Task {
                await reload()
            }
        }
    }

    private func groupHeader(_ group: SpoolGroup, isCollapsed collapsed: Bool) -> some View {
        SpoolGroupHeader(
            group: group,
            mode: layout.mode,
            isCollapsed: collapsed,
            isForcedOpen: group.forcedOpen,
            selectedCount: isEditing && collapsed ? group.spoolIDs.filter(selection.contains).count : 0,
            onOpen: openAction(for: group),
            onToggle: { toggleGroup(group) }
        )
        // On the header row alone: `.selectionDisabled` is inherited by a subtree,
        // so on a Section it would disable its spool rows too.
        .selectionDisabled(true)
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

    /// What tapping a header's body does. Nil when the group has no screen of its
    /// own (Material, the none groups, a missing value), so the body collapses it.
    /// Nil while selecting too: a push would leave the selection running behind it.
    private func openAction(for group: SpoolGroup) -> (() -> Void)? {
        guard !isEditing else { return nil }
        switch layout.mode {
        case .filament:
            guard let filament = group.filament else { return nil }
            return { filamentIDToOpen = filament.id }
        case .manufacturer:
            guard let vendor = group.vendor else { return nil }
            return { vendorIDToOpen = vendor.id }
        case .location:
            guard let location = group.location else { return nil }
            return { locationToOpen = location }
        case .material, .color, .none:
            return nil
        }
    }

    /// The filter chips, above everything else in the list.
    @ViewBuilder
    private var chipsRow: some View {
        if !activeChips.isEmpty {
            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                clearAllChip
                ForEach(activeChips) { chip in
                    filterChip(chip)
                }
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
        }
    }

    /// The list without a Recently Added section: chips, then the loading,
    /// error or empty state, the colour role sections, or the groups.
    @ViewBuilder
    private func listContent(spools: [Spool], spoollessGroups: [SpoolGroup]) -> some View {
        chipsRow
        if store.isLoading {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if let error = loadError {
            ContentUnavailableView {
                Label("Could Not Load Spools", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") {
                    Task { await reload() }
                }
                .buttonStyle(.borderedProminent)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if spools.isEmpty && spoollessGroups.isEmpty {
            Group {
                if searchText.isEmpty {
                    if Self.hasActiveFilters(colorSpec: colorSpec, selectedMaterials: selectedMaterials) {
                        ContentUnavailableView {
                            Label("No Spools Match These Filters", systemImage: "line.3.horizontal.decrease")
                        } description: {
                            Text("Adjust or clear the filters.")
                        } actions: {
                            Button("Clear Filters") {
                                colorSpec = nil
                                selectedMaterials = []
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        switch filter {
                        case .filament:
                            ContentUnavailableView {
                                Label("No Spools with This Filament", systemImage: "shippingbox")
                            } description: {
                                Text("No spools with this filament yet.")
                            } actions: {
                                Button("Add Spool") {
                                    showingAddSheet = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        case .fillBucket, .material, .untagged:
                            ContentUnavailableView(
                                "No Spools",
                                systemImage: "shippingbox",
                                description: Text("No spools match this filter.")
                            )
                        case .none:
                            ContentUnavailableView(
                                "No Spools",
                                systemImage: "shippingbox",
                                description: Text(isLibraryMode
                                    ? "Add your first spool with the Add Spool button."
                                    : "Add your first spool using the + button.")
                            )
                        }
                    }
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if showsRoleSections {
            ForEach(colorGroups, id: \.role) { group in
                let rows = searchedAndSorted(group.spools)
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { spool in
                            Button(action: { spoolIDToOpen = spool.id }) {
                                SpoolUsageRow(spool: spool, style: .withFilament)
                            }
                            .accessibilityIdentifier("library.spoolRow")
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: group.swatchHex) ?? Color.swatchFallback)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.swatchBorder, lineWidth: 1))
                            Text("\(group.role) · \(rows.count)")
                        }
                    }
                }
            }
        } else {
            groupedRows(makeGroups(of: spools, isSearching: isSearching), spoolless: spoollessGroups)
        }
    }

    /// Groups with their headers, then the spool-less headers; or, with no
    /// headers (None grouping), the one group's rows.
    @ViewBuilder
    private func groupedRows(_ groups: [SpoolGroup], spoolless: [SpoolGroup]) -> some View {
        if layout.showsHeaders {
            ForEach(groups) { groupSection($0) }
            ForEach(spoolless) { group in
                Section {
                    groupHeader(group, isCollapsed: false)
                }
            }
        } else {
            entryRows(groups.first?.entries ?? [])
        }
    }

    /// One group: its header, then its rows unless collapsed. A search holds its
    /// groups open (`forcedOpen`, decided by the service) so a match is never
    /// hidden; the user's own collapsed set is left alone.
    private func groupSection(_ group: SpoolGroup) -> some View {
        let collapsed = !group.forcedOpen && collapsedGroups.contains(group.id)
        return Section {
            groupHeader(group, isCollapsed: collapsed)
            if !collapsed {
                entryRows(group.entries)
            }
        }
    }

    /// The header of the Recently Added section. A tap anywhere on it folds
    /// the section away or opens it; folded, it says how many spools it holds.
    private func recentlyAddedHeader(spoolCount: Int) -> some View {
        Button {
            recentlyAddedCollapsed.toggle()
        } label: {
            HStack(spacing: 8) {
                Text("Recently Added")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 8)
                if recentlyAddedCollapsed {
                    Text(SpoolUsage.spoolCountText(spoolCount))
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                Image(systemName: "chevron.down")
                    .foregroundStyle(Color.secondary)
                    .rotationEffect(.degrees(recentlyAddedCollapsed ? -90 : 0))
                    .frame(width: 44, height: 44)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(recentlyAddedCollapsed ? "Expand Recently Added" : "Collapse Recently Added")
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
                .selectionDisabled(true)
                .listRowInsets(SpoolUsageRow.compactRowInsets)
                if expandedFolds.contains(fold.id) {
                    ForEach(fold.spools) { spoolRow($0) }
                }
            }
        }
    }

    /// Tagged with the spool id: the enclosing `ForEach` is keyed on entry ids
    /// (strings), which the `Set<Int>` selection cannot match.
    private func spoolRow(_ spool: Spool) -> some View {
        Button(action: {
            spoolIDToOpen = spool.id
        }) {
            SpoolUsageRow(spool: spool, style: layout.rowStyle)
        }
        .accessibilityIdentifier("library.spoolRow")
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                spoolIDToWeigh = spool.id
            } label: {
                Label("Weigh", systemImage: "scalemass")
            }
            .tint(.blue)
        }
        .listRowInsets(SpoolUsageRow.rowInsets(for: layout.rowStyle))
        .tag(spool.id)
    }

    private func toggleFold(_ fold: SpoolFold) {
        if expandedFolds.contains(fold.id) {
            expandedFolds.remove(fold.id)
        } else {
            expandedFolds.insert(fold.id)
        }
    }

    /// The load error is captured from this list's own fetch. `store.errorMessage`
    /// is also set by any failed write — a refused delete in an edit sheet — and
    /// a sheet's dismissal re-runs no fetch, so reading it directly replaced the
    /// whole list with "Could Not Load" after a write that never loaded anything.
    /// With the spool-less headers on, their records are fetched too: one added on
    /// the server would otherwise not show until a tab switch. First, so the error
    /// read below is the spool fetch's: a failed refresh of them keeps the last
    /// ones and shows nothing, as the tab's own fetches do.
    private func reload() async {
        if offersWithoutSpools && showsWithoutSpools {
            if layout.mode == .manufacturer {
                await store.fetchVendors()
            } else {
                await store.fetchFilaments()
            }
        }
        await store.fetchSpools()
        loadError = store.errorMessage
    }

    /// Leading action chip — clears every active filter at once. Bordered
    /// (not tinted) so it reads as an action, not a filter.
    private var clearAllChip: some View {
        Button {
            colorSpec = nil
            selectedMaterials = []
            showArchived = false
            showsWithoutSpools = false
        } label: {
            // HStack, not Label: Label's style resolution inside this List row
            // rendered icon-only at a runaway ideal height (device pass 2026-07-02).
            HStack(spacing: 4) {
                Image(systemName: "trash")
                Text("Clear All")
            }
            .font(.footnote)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .overlay(Capsule().stroke(Color.accentColor.opacity(0.5), lineWidth: 1))
    }

    /// One active-filter pill: swatch (color chip only) + short label + ✕ to
    /// clear just this filter. Body tap reopens the color sheet for the color
    /// chip; inert for the others.
    private func filterChip(_ chip: ActiveFilterChip) -> some View {
        HStack(spacing: 4) {
            if let hex = chip.swatchHex {
                Circle()
                    .fill(Color(hex: hex) ?? Color.swatchFallback)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.swatchBorder, lineWidth: 1))
            }
            Text(chip.label)
                .font(.footnote)
            Button {
                clearFilter(chip)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .padding(4) // widen the ✕ hit target (one-handed bench use)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .foregroundStyle(Color.accentColor)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture {
            if chip.kind == .color { showingColorFilter = true }
        }
    }

    private func clearFilter(_ chip: ActiveFilterChip) {
        switch chip.kind {
        case .color:
            colorSpec = nil
        case .material(let material):
            selectedMaterials.remove(material)
        case .archived:
            showArchived = false
        case .withoutSpools:
            showsWithoutSpools = false
        }
    }

    private func performBulkArchive() {
        let ids = selection
        Task {
            let result = await store.archiveSpools(ids: ids)
            selection.removeAll()
            editMode?.wrappedValue = .inactive
            if !result.isCompleteSuccess {
                bulkMessage = "Archived \(result.succeeded) of \(result.total). \(result.failed) failed."
                showBulkResult = true
            }
        }
    }

    static func excludingArchived(_ spools: [Spool], showArchived: Bool) -> [Spool] {
        showArchived ? spools : spools.filter { $0.archived != true }
    }

    static func applyFilter(_ spools: [Spool], filter: SpoolFilter?, ledger: [String: Int] = [:]) -> [Spool] {
        switch filter {
        case .none:
            return spools
        case .filament(let id):
            return spools.filter { $0.filament.id == id }
        case .fillBucket(let bucket):
            return DashboardStatsService.spools(in: spools, bucket: bucket)
        case .material(let material):
            return DashboardStatsService.spools(in: spools, material: material)
        case .untagged:
            return DashboardStatsService.untaggedSpools(in: spools, ledger: ledger)
        }
    }

    static func applyColorFilter(_ spools: [Spool], spec: ColorFilterSpec?) -> [Spool] {
        guard let spec else { return spools }
        return ColorFilterService.groupedMatches(spools, spec: spec).flatMap(\.spools)
    }

    static func applyMaterials(_ spools: [Spool], selected: Set<String>) -> [Spool] {
        guard !selected.isEmpty else { return spools }
        return spools.filter { selected.contains(DashboardStatsService.materialKey(for: $0)) }
    }

    static func hasActiveFilters(colorSpec: ColorFilterSpec?, selectedMaterials: Set<String>) -> Bool {
        colorSpec != nil || !selectedMaterials.isEmpty
    }

    /// Chips for every active filter, in fixed order: color → materials
    /// (sorted) → archived → without spools. Unlike `hasActiveFilters`, this
    /// includes Show Archived and Without Spools — the chip row and the Sort &
    /// Filter button indicator surface every non-default filter, while the "no
    /// matches" empty state only cares about narrowing filters.
    static func activeFilterChips(
        colorSpec: ColorFilterSpec?,
        selectedMaterials: Set<String>,
        showArchived: Bool,
        showsWithoutSpools: Bool = false
    ) -> [ActiveFilterChip] {
        var chips: [ActiveFilterChip] = []
        if let spec = colorSpec {
            let label = spec.harmony == .single ? "Color" : spec.harmony.displayName
            chips.append(ActiveFilterChip(id: "color", label: label, swatchHex: spec.anchorHex, kind: .color))
        }
        let materials = selectedMaterials.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        for material in materials {
            chips.append(ActiveFilterChip(id: "material:\(material)", label: material, swatchHex: nil, kind: .material(material)))
        }
        if showArchived {
            chips.append(ActiveFilterChip(id: "archived", label: "Archived", swatchHex: nil, kind: .archived))
        }
        if showsWithoutSpools {
            chips.append(ActiveFilterChip(id: "withoutSpools", label: "Without Spools", swatchHex: nil, kind: .withoutSpools))
        }
        return chips
    }
}
