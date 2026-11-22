//
//  ManageLocationsView.swift
//  SpoolKid
//
//  Purpose: Where spools get put away. Shelves are disclosure groups holding
//  their spools; a long press on a grip lifts a row, collapses every group so
//  the only things on screen are drop targets, and a release either re-seats a
//  shelf or moves a spool onto one.
//
//  The screen renders and routes. Every rule it obeys lives in a pure type:
//  `LocationOrder`, `LocationSortOption`, `LocationGrouping`,
//  `LocationArrangementState`.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct ManageLocationsView: View {
    @EnvironmentObject private var store: SpoolDataStore
    @Environment(\.serverLink) private var serverLink
    @Environment(\.editMode) private var editMode

    @AppStorage(AppConfig.locationSortFieldKey)
    private var locationSortField: String = LocationSortOption.manual.rawValue
    @AppStorage(AppConfig.locationSortAscendingKey)
    private var locationSortAscending: Bool = true
    @AppStorage(AppConfig.locationSpoolSortFieldKey)
    private var spoolSortField: String = SpoolSortOption.name.rawValue
    @AppStorage(AppConfig.locationSpoolSortAscendingKey)
    private var spoolSortAscending: Bool = true

    @State private var searchText = ""
    @State private var expanded: Set<String> = []
    @State private var sheet: LocationSheet?
    @State private var selection = Set<Int>()
    @State private var loadError: String?
    @State private var bulkMessage: String?
    @State private var detailTarget: String?

    // MARK: Drag state
    @State private var grabbed: LocationArrangementState.Grabbed?
    @State private var dragLocation: CGPoint = .zero
    @State private var headerFrames: [String: CGRect] = [:]
    @State private var expandedBeforeDrag: Set<String> = []

    // MARK: Autoscroll
    @State private var scrollProxy: ScrollViewProxy?
    @State private var listBounds: CGRect = .zero
    @State private var autoScrollEdge: DragAutoScroll.Edge?
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var autoScrollIndex: Int?

    /// Drops that have landed on screen but not yet come back from the backend.
    /// The outer optional is "is there a pending move"; the inner one is the
    /// location it asserts, which may legitimately be nil.
    @State private var pendingLocation: [Int: String?] = [:]

    /// Sentinel name for the gap a dragged shelf leaves behind. Not a location:
    /// it cannot collide with a real name because a real name is trimmed and
    /// never empty.
    private static let gapName = "\u{0}gap"

    enum LocationSheet: Identifiable {
        case add
        case assignSession(String?)
        case assignSelection([Int])

        var id: String {
            switch self {
            case .add: return "add"
            case .assignSession(let name): return "session-\(name ?? "-")"
            case .assignSelection(let ids): return "selection-\(ids.sorted().map(String.init).joined(separator: ","))"
            }
        }
    }

    // MARK: - Derived state

    private var isSelecting: Bool { editMode?.wrappedValue.isEditing == true }
    private var isDraggingSpool: Bool { if case .spool = grabbed { return true }; return false }
    private var isDraggingLocation: Bool { if case .location = grabbed { return true }; return false }
    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Grips are live only while browsing: a filtered list cannot be reordered
    /// honestly, and selecting is its own mode.
    private var allowsDragging: Bool { !isSelecting && !isSearching }

    private var mergedNames: [String] { Self.mergedLocationNames(store: store) }

    static func mergedLocationNames(store: SpoolDataStore) -> [String] {
        mergedLocations(
            observed: store.spools.compactMap(\.location),
            known: store.locations,
            registered: store.registeredLocations.map(\.name)
        )
    }

    /// Counts respect a pending move, so a dropped spool is counted on its new
    /// shelf immediately rather than a round trip later.
    private func spoolCount(of name: String) -> Int {
        store.activeSpools.reduce(into: 0) { total, spool in
            if (pendingLocation[spool.id] ?? spool.location) == name { total += 1 }
        }
    }

    private var orderedLocations: [String] {
        Self.orderedLocationNames(
            store: store, sortField: locationSortField, ascending: locationSortAscending, spoolCount: spoolCount(of:)
        )
    }

    /// Every location, in the order the Locations screen lists them. Shared
    /// with the Spool page's Location sheet. `spoolCount` defaults to the
    /// store's active spools; this screen passes its own, which counts a
    /// pending move.
    static func orderedLocationNames(
        store: SpoolDataStore, sortField: String, ascending: Bool, spoolCount: ((String) -> Int)? = nil
    ) -> [String] {
        let names = mergedLocationNames(store: store)
        let count = spoolCount ?? { name in store.activeSpools.filter { $0.location == name }.count }
        return LocationSortOption.arrange(
            names.map { LocationTally(name: $0, spoolCount: count($0)) },
            by: LocationSortOption(rawValue: sortField) ?? .manual,
            ascending: ascending,
            manual: store.locationOrder?.order ?? LocationOrder()
        )
    }

    private var groups: [LocationGroup] {
        LocationGrouping.groups(
            orderedLocations: orderedLocations,
            spools: store.activeSpools,
            query: searchText,
            spoolSort: SpoolSortOption(rawValue: spoolSortField) ?? .name,
            spoolAscending: spoolSortAscending,
            isDragging: isDraggingSpool,
            locationOverride: pendingLocation
        )
    }

    /// What the list actually renders. While a shelf is in the air a gap is put
    /// where it would land, so `List` animates the opening and closing itself —
    /// and the shelf's own row STAYS IN THE ARRAY, rendered at zero height by
    /// `groupRow`.
    ///
    /// Keeping it is not cosmetic. Dropping the dragged row out of the array
    /// un-mounts the view the `DragGrip` lives in, and with it the gesture
    /// tracking the finger: instrumented on the simulator 2026-09-13, the log
    /// read `BEGIN Reorder Bin C` → `GONE Reorder Bin C drag=true` with exactly
    /// ONE `onChanged` delivered. A view that no longer exists cannot run its
    /// own `.onChange(of: isPressed)` either, so `DragGrip`'s cancel path never
    /// fired and `grabbed` was stranded — the lifted card frozen on screen with
    /// no `onEnd`, no `onCancel`, and no drop, until the app was relaunched.
    ///
    /// It is re-inserted at its ORIGINAL index rather than appended: that index
    /// does not move as the gap travels (the gap is placed in the array without
    /// it, so every slot at or after it shifts together), so the row keeps one
    /// position for the whole drag and `List` has no reason to recycle the cell
    /// holding the live gesture. The end of the list would be worse than
    /// useless — a `List` is lazy, and an off-screen row is not mounted at all.
    private var displayGroups: [LocationGroup] {
        guard case .location(let name) = grabbed else { return groups }

        let key = LocationName.normalizedKey(name)
        guard let originalIndex = groups.firstIndex(where: {
            LocationName.normalizedKey($0.name) == key
        }) else { return groups }

        var rest = groups.filter { LocationName.normalizedKey($0.name) != key }
        let unassignedOffset = rest.first?.isUnassigned == true ? 1 : 0
        let index = min(max(liveReorderIndex(), 0), rest.count - unassignedOffset)

        rest.insert(
            LocationGroup(name: Self.gapName, spoolIDs: [], matchedByName: false, forcedOpen: false),
            at: index + unassignedOffset
        )
        rest.insert(groups[originalIndex], at: min(originalIndex, rest.count))
        return rest
    }

    /// The shelf currently in the air — the one row that is mounted but drawn
    /// at zero height.
    private func isLifted(location group: LocationGroup) -> Bool {
        guard case .location(let name) = grabbed else { return false }
        return LocationName.normalizedKey(name) == LocationName.normalizedKey(group.name)
    }

    private var headerFrameList: [HeaderFrame] {
        headerFrames.map { HeaderFrame(name: $0.key, rect: $0.value) }
    }

    private func liveReorderIndex() -> Int {
        guard let grabbed, case .reorder(let index) = LocationArrangementState.drop(
            for: dragLocation, grabbed: grabbed, headers: headerFrameList
        ) else { return 0 }
        return index
    }

    private func spool(_ id: Int) -> Spool? {
        store.activeSpools.first { $0.id == id }
    }

    /// Every spool the search currently admits — what Select All means.
    private var selectableSpoolIDs: [Int] { groups.flatMap(\.spoolIDs) }

    private func isExpanded(_ group: LocationGroup) -> Bool {
        group.forcedOpen || expanded.contains(group.name)
    }

    private func disclosureBinding(for group: LocationGroup) -> Binding<Bool> {
        Binding(
            get: { isExpanded(group) },
            set: { open in
                // A forced-open group is the search's doing, not the user's;
                // toggling it must not write into their own open set.
                guard !group.forcedOpen else { return }
                if open { expanded.insert(group.name) } else { expanded.remove(group.name) }
            }
        )
    }

    // MARK: - Body

    var body: some View {
        HarmonizedSearchList(
            title: "Manage Locations",
            searchText: $searchText,
            prompt: "Search locations and spools...",
            selection: $selection,
            trailingControlCount: 1,
            collapsesTrailing: true,
            onScrollProxy: { scrollProxy = $0 },
            trailing: {
                LocationSortMenu(
                    locationField: $locationSortField,
                    locationAscending: $locationSortAscending,
                    spoolField: $spoolSortField,
                    spoolAscending: $spoolSortAscending
                )
            },
            pinnedTrailing: {
                Button { sheet = .add } label: {
                    Label("Add Location", systemImage: "plus")
                }
                .needsServer()
                .accessibilityIdentifier("locations.add")
            }
        ) {
            content
        }
        .onPreferenceChange(HeaderFramePreferenceKey.self) { headerFrames = $0 }
        // The list's own rect, in the space the drag reports in, so the edge
        // zones are measured against what is actually on screen rather than a
        // guessed inset.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: ArrangeSpace.space) } action: { listBounds = $0 }
        .overlay(alignment: .top) { liftedCard }
        .environment(\.spoolIDDigits, SpoolUsageRow.idDigits(for: store.activeSpools))
        .safeAreaInset(edge: .bottom) { selectionBar }
        .sheet(item: $sheet) { sheet in
            NavigationStack {
                switch sheet {
                case .add:
                    AddLocationView(store: store)
                case .assignSession(let name):
                    LocationAssignmentView(initialLocationName: name)
                case .assignSelection(let ids):
                    LocationPickerSheet(
                        title: ids.count == 1 ? "Assign 1 spool to…" : "Assign \(ids.count) spools to…",
                        locations: orderedLocations
                    ) { patch in
                        assign(spoolIDs: ids, to: patch)
                    }
                }
            }
        }
        .alert("Assign Location", isPresented: Binding(
            get: { bulkMessage != nil },
            set: { if !$0 { bulkMessage = nil } }
        ), presenting: bulkMessage) { _ in
            Button("OK") { bulkMessage = nil }
        } message: { Text($0) }
        .refreshable { await reload() }
        .navigationDestination(item: $detailTarget) { name in
            LocationDetailView(store: store, locationName: name)
        }
        .onAppear { Task { await reload() } }
        // A scroll loop that outlives the screen would scroll the list under
        // whoever came back to it.
        .onDisappear { stopAutoScroll() }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading {
            HStack { Spacer(); ProgressView(); Spacer() }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else if let error = loadError {
            ContentUnavailableView {
                Label("Could Not Load Locations", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await reload() } }
                    .buttonStyle(.borderedProminent)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if displayGroups.isEmpty {
            Group {
                if isSearching {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ContentUnavailableView(
                        "No Locations",
                        systemImage: "mappin.and.ellipse",
                        description: Text("Add a location, or assign a spool to one.")
                    )
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            ForEach(displayGroups) { group in
                if group.name == Self.gapName {
                    Color.clear
                        .frame(height: 56)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    groupRow(group)
                }
            }
        }
    }

    /// TWO LAYOUTS, ONE PER MODE — each is the only one that works there.
    ///
    /// Selecting needs every spool to be its own `List` row: edit-mode
    /// selection circles attach to ROWS, and a group drawn as one cell gave its
    /// spools none (owner device pass, 2026-09-13).
    ///
    /// Browsing and dragging need the group to be ONE cell. A drag hides rows it
    /// must not un-mount by drawing them at zero height (see
    /// `arrangeableGroupRow`), and a zero-height ROW is not zero tall: `List`
    /// enforces a minimum row height, so as sibling rows two hidden spools left
    /// ~100pt of blank space under their shelf (measured on an iPhone 17,
    /// iOS 26, 2026-09-14). Inside one self-sizing cell a zero-height view
    /// really is zero. `defaultMinListRowHeight` 0 closes the gap too, but only
    /// list-wide — measured moving the search field up a row, in a layout this
    /// screen shares with every other Manage list.
    ///
    /// Switching layouts re-creates the rows, which is safe exactly because no
    /// drag can be live while selecting (`allowsDragging`).
    @ViewBuilder
    private func groupRow(_ group: LocationGroup) -> some View {
        if isSelecting {
            selectableGroupRows(group)
        } else {
            arrangeableGroupRow(group)
        }
    }

    @ViewBuilder
    private func selectableGroupRows(_ group: LocationGroup) -> some View {
        // On the header row alone: `.selectionDisabled` is inherited by a
        // subtree, and on anything that also holds the spool rows it disables
        // their selection too. Measured in the Task 1 spike, 2026-09-12.
        header(for: group)
            .selectionDisabled(true)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation { disclosureBinding(for: group).wrappedValue.toggle() }
            }

        if isExpanded(group) {
            ForEach(group.spoolIDs, id: \.self) { id in
                if let spool = spool(id) {
                    spoolRow(spool, in: group)
                }
            }
        }
    }

    @ViewBuilder
    private func arrangeableGroupRow(_ group: LocationGroup) -> some View {
        // MOUNTED BUT HIDDEN, NOT COLLAPSED — do not "simplify" this away.
        //
        // A spool drag leaves the list looking exactly like a shelf drag does:
        // nothing but headers, which are the only drop targets. But the origin
        // group cannot actually CLOSE, because the gesture driving the drag
        // lives on the `DragGrip` inside the dragged row: closing the group
        // un-mounts that row, the gesture goes with it, and the drag dies
        // mid-flight with no `onEnd` and no drop — a failure this screen has
        // already shipped once. So `begin` keeps the origin in `expanded` (the
        // rows stay mounted and the gesture stays alive) and the rows are drawn
        // at zero height instead. The headers then stack as tightly as if the
        // group had really closed, which is exactly what the drop geometry
        // wants. (Owner device pass, 2026-09-13.)
        //
        // A shelf drag hides its own row the same way and for the same reason —
        // see `displayGroups`, which keeps it in the array instead of removing
        // it. The gap still shows where it would land.
        let hidesRows = isDraggingSpool
        let hidesSelf = isLifted(location: group)
        DisclosureGroup(isExpanded: disclosureBinding(for: group)) {
            ForEach(group.spoolIDs, id: \.self) { id in
                if let spool = spool(id) {
                    // Every modifier applies unconditionally and only its VALUE
                    // changes. An `if hidesRows` around them would be two
                    // ViewBuilder branches, and swapping branches re-creates the
                    // row — taking the live gesture down with it, which is the
                    // very thing this is avoiding.
                    spoolRow(spool, in: group)
                        .frame(height: hidesRows ? 0 : nil)
                        .clipped()
                        .allowsHitTesting(!hidesRows)
                        .listRowInsets(hidesRows ? EdgeInsets() : nil)
                        .listRowSeparator(hidesRows ? .hidden : .automatic)
                }
            }
        } label: {
            header(for: group)
        }
        .disclosureGroupStyle(.chevronless)
        .listRowBackground(dropHighlight(for: group))
        // Same unconditional-modifiers rule as the spool rows above, and the
        // same zero-height treatment — this is the row whose `DragGrip` is
        // driving a shelf drag, so it must stay mounted while looking gone.
        .frame(height: hidesSelf ? 0 : nil)
        .clipped()
        .allowsHitTesting(!hidesSelf)
        .listRowInsets(hidesSelf ? EdgeInsets() : nil)
        .listRowSeparator(hidesSelf ? .hidden : .automatic)
    }

    private func header(for group: LocationGroup) -> some View {
        LocationGroupHeader(
            name: group.name,
            isUnassigned: group.isUnassigned,
            spoolCount: group.isUnassigned ? group.spoolIDs.count : spoolCount(of: group.name),
            selectedCount: isSelecting && !isExpanded(group)
                ? group.spoolIDs.filter(selection.contains).count
                : 0,
            isMissingFromBackend: !group.isUnassigned
                && store.syncState(forLocationNamed: group.name) == .missingFromBackend,
            storageNoun: store.capabilities.storageNoun,
            showsControls: grabbed == nil && !isSelecting,
            onOpenDetail: { openDetail(group.name) },
            grip: {
                if allowsDragging {
                    DragGrip(
                        accessibilityLabel: "Reorder \(group.name)",
                        onBegin: { begin(.location(group.name)) },
                        onChange: { location in
                            dragLocation = location
                            updateAutoScroll()
                        },
                        onEnd: { end(commit: true) },
                        onCancel: { end(commit: false) }
                    )
                    .accessibilityIdentifier("location.grip.\(group.name)")
                    .accessibilityAction(named: "Move Up") { nudge(group.name, by: -1) }
                    .accessibilityAction(named: "Move Down") { nudge(group.name, by: 1) }
                }
            }
        )
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HeaderFramePreferenceKey.self,
                    value: [group.name: proxy.frame(in: ArrangeSpace.space)]
                )
            }
        }
    }

    @ViewBuilder
    private func spoolRow(_ spool: Spool, in group: LocationGroup) -> some View {
        HStack(spacing: 4) {
            SpoolUsageRow(spool: spool, style: .withFilament)
            Spacer(minLength: 8)
            if allowsDragging {
                DragGrip(
                    accessibilityLabel: "Move \(spool.listTitle)",
                    onBegin: { begin(.spool(spool.id, from: group.name)) },
                    onChange: { location in
                        dragLocation = location
                        updateAutoScroll()
                    },
                    onEnd: { end(commit: true) },
                    onCancel: { end(commit: false) }
                )
                .accessibilityIdentifier("spool.grip.\(spool.id)")
            }
        }
        .tag(spool.id)
        .opacity(isLifted(spool.id) ? 0 : 1)
        .accessibilityAction(named: "Move to…") {
            sheet = .assignSelection([spool.id])
        }
    }

    // MARK: - Drag

    private func isLifted(_ spoolID: Int) -> Bool {
        if case .spool(let id, _) = grabbed { return id == spoolID }
        return false
    }

    private func begin(_ what: LocationArrangementState.Grabbed) {
        grabbed = what
        expandedBeforeDrag = expanded
        // Collapsing every group is what makes the drop targets unambiguous:
        // once the list is nothing but headers, there is nowhere to land by
        // accident. Both kinds of drag do it, and a spool drag is no exception
        // on screen — but its origin group stays in `expanded` so the dragged
        // row, and the gesture living on it, remain mounted. `groupRow` draws
        // those rows at zero height; see the comment there.
        withAnimation(.snappy(duration: 0.28)) {
            switch what {
            case .location:
                expanded.removeAll()
            case .spool(_, let origin):
                expanded = [origin]
            }
        }
    }

    /// `commit: false` is a gesture the system took away rather than a finger
    /// the user lifted. It unwinds the lift and writes NOTHING: the last known
    /// `dragLocation` is wherever the touch happened to be when it was stolen,
    /// not a target anyone chose, and the thief is usually the row's own context
    /// menu — about to act on the same touch. Moving a spool on the strength of
    /// that would be a write the user never asked for.
    private func end(commit: Bool) {
        let held = grabbed
        let point = dragLocation
        let frames = headerFrameList

        stopAutoScroll()
        withAnimation(.snappy(duration: 0.28)) {
            grabbed = nil
            expanded = expandedBeforeDrag
        }
        expandedBeforeDrag = []

        guard commit, let held else { return }
        apply(LocationArrangementState.drop(for: point, grabbed: held, headers: frames), grabbed: held)
    }

    private func apply(_ drop: LocationArrangementState.Drop, grabbed: LocationArrangementState.Grabbed) {
        switch drop {
        case .cancel:
            return

        case .reorder(let index):
            guard case .location(let name) = grabbed else { return }
            // `move` seeds from what is on screen, so a drag while sorted by
            // Name does not make the list jump — and the sort follows the
            // user's hands rather than silently fighting them.
            store.locationOrder?.move(name, to: index, within: orderedLocations)
            if locationSortField != LocationSortOption.manual.rawValue {
                withAnimation { locationSortField = LocationSortOption.manual.rawValue }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)

        case .assign(let target):
            guard case .spool(let id, _) = grabbed else { return }
            move(spoolID: id, to: .set(target), optimistic: target)

        case .unassign:
            guard case .spool(let id, _) = grabbed else { return }
            move(spoolID: id, to: .setNil, optimistic: nil)
        }
    }

    // MARK: - Autoscroll

    /// A finger cannot travel past the screen, so without this a row could
    /// never be moved beyond the visible region. Held against an edge, the
    /// list walks one group at a time toward it.
    ///
    /// Called on every drag update; it only acts when the answer CHANGES, so a
    /// finger parked in a zone keeps the one loop it started rather than
    /// restarting it 60 times a second. Whether a point is in a zone at all is
    /// geometry and lives in `DragAutoScroll`.
    private func updateAutoScroll() {
        let edge = DragAutoScroll.edge(for: dragLocation, in: listBounds)
        guard edge != autoScrollEdge else { return }

        stopAutoScroll()
        guard let edge else { return }

        autoScrollEdge = edge
        // A `Task` rather than a `Timer`: it inherits this view's main-actor
        // isolation, so the scroll and the state it reads stay on one actor,
        // and cancellation is the whole teardown. The loop stops on its own
        // once the list has no further group to show.
        autoScrollTask = Task {
            while !Task.isCancelled, scrollStep(towards: edge) {
                try? await Task.sleep(for: .milliseconds(220))
            }
        }
    }

    /// Every way a scroll loop can end: the drop, the finger leaving the zone,
    /// and the screen going away. A loop that outlives its gesture scrolls the
    /// list under the user later, which is a leak they can see.
    private func stopAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        autoScrollEdge = nil
        autoScrollIndex = nil
    }

    /// One group further toward `edge`. `false` when there is nothing left to
    /// scroll to, which ends the loop.
    private func scrollStep(towards edge: DragAutoScroll.Edge) -> Bool {
        let items = displayGroups
        // Seeded from the header nearest the finger, then counted from there:
        // the groups already scrolled past are not measured any more, so their
        // frames cannot be consulted a second time.
        let current = autoScrollIndex ?? DragAutoScroll.nearestIndex(
            to: dragLocation.y, orderedNames: items.map(\.name), frames: headerFrames
        )
        guard let current, let scrollProxy else { return false }

        let next = edge == .bottom ? current + 1 : current - 1
        guard items.indices.contains(next) else { return false }

        autoScrollIndex = next
        withAnimation(.linear(duration: 0.2)) {
            scrollProxy.scrollTo(items[next].id, anchor: edge == .bottom ? .bottom : .top)
        }
        return true
    }

    /// VoiceOver's path to a reorder, since a drag is invisible to it.
    private func nudge(_ name: String, by delta: Int) {
        let visible = orderedLocations
        guard let from = visible.firstIndex(of: name) else { return }
        store.locationOrder?.move(name, to: from + delta, within: visible)
        if locationSortField != LocationSortOption.manual.rawValue {
            locationSortField = LocationSortOption.manual.rawValue
        }
    }

    // MARK: - Writes

    private func move(spoolID: Int, to patch: SpoolmanPatchValue<String>, optimistic: String?) {
        // A drop is not a button: it is refused here while the server is down.
        guard !serverLink.isDown else { return }
        // `updateValue(_:forKey:)`, never `pendingLocation[id] = optimistic`:
        // assigning a nil value through the subscript of a dictionary with an
        // Optional value type REMOVES the key, which would silently drop the
        // pending unassign this line exists to record.
        // `_ =` because `updateValue` hands back the previous value, which would
        // otherwise make `withAnimation`'s own result unused — a new warning.
        withAnimation(.snappy) { _ = pendingLocation.updateValue(optimistic, forKey: spoolID) }

        Task {
            let ok = await store.updateSpool(id: spoolID, draft: .locationAssignment(patch))
            // Cleared whether it worked or not, so a failed write cannot go on
            // looking applied.
            withAnimation(.snappy) { _ = pendingLocation.removeValue(forKey: spoolID) }
            if !ok {
                store.postSaveNotice(
                    store.errorMessage ?? "The spool could not be moved.",
                    record: spool(spoolID)?.listTitle ?? "Spool #\(spoolID)"
                )
            }
        }
    }

    private func assign(spoolIDs: [Int], to patch: SpoolmanPatchValue<String>) {
        guard !serverLink.isDown else { return }
        Task {
            let result = await store.assignLocation(spoolIDs: spoolIDs, to: patch)
            selection.removeAll()
            editMode?.wrappedValue = .inactive
            if !result.isCompleteSuccess {
                bulkMessage = "Moved \(result.succeeded) of \(result.total). \(result.failed) could not be moved."
            }
        }
    }

    private func openDetail(_ name: String) {
        detailTarget = Self.canonicalLocationName(
            for: name,
            observed: store.spools.compactMap(\.location),
            known: store.locations
        )
    }

    private func reload() async {
        await store.fetchSpools()
        loadError = store.errorMessage
        await store.fetchLocations()
        // Captured here rather than read live: a failed write elsewhere sets
        // `store.errorMessage` too, and is not a load failure.
        loadError = loadError ?? store.errorMessage
        // Lazy, on read: a shelf deleted in the backend's own web UI drops out
        // of the arrangement without a migration.
        store.locationOrder?.prune(keeping: mergedNames)
    }

    // MARK: - Overlays

    /// `dragLocation` is a point in `ArrangeSpace` — global. This overlay's own
    /// origin is NOT global zero: an overlay is laid out inside its host's safe
    /// area, which here sits below the status and navigation bars (measured at
    /// 116pt on an iPhone 17). Offsetting by the global y alone therefore drew
    /// the card that far below the finger. The reader converts global to local
    /// by measuring, so the card tracks on any device, orientation and split,
    /// and it is read inline rather than through a preference + `@State`: a
    /// preference can emit its default during a transient re-layout and leave
    /// the card stranded a nav-bar's height away, which is exactly what it did.
    private var liftedCard: some View {
        GeometryReader { proxy in
            if let grabbed {
                liftedContent(for: grabbed)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dragLiftSurface()
                    .scaleEffect(1.03)
                    .padding(.horizontal, 12)
                    // Vertical only, like every native reorder: horizontal drift
                    // would say the row can go somewhere it cannot.
                    .offset(y: dragLocation.y - proxy.frame(in: ArrangeSpace.space).minY - 28)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func liftedContent(for grabbed: LocationArrangementState.Grabbed) -> some View {
        switch grabbed {
        case .location(let name):
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline).lineLimit(1)
                Text(SpoolUsage.spoolCountText(spoolCount(of: name)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .spool(let id, _):
            if let spool = spool(id) {
                SpoolUsageRow(spool: spool, style: .withFilament)
            }
        }
    }

    /// The highlight under a header a spool is hovering over. Nothing is
    /// highlighted during a shelf drag — a gap says where that one is going.
    /// `nil` rather than `Color.clear`: a clear `.listRowBackground` strips the
    /// row's own card fill, and every other Manage screen keeps the system
    /// default by never setting one at all. Delegates to
    /// `LocationArrangementState.drop`, the same resolver a release commits —
    /// so the highlight can never disagree with what actually lands.
    private func dropHighlight(for group: LocationGroup) -> AnyView? {
        guard let grabbed, case .spool = grabbed else { return nil }

        let highlighted: Bool
        switch LocationArrangementState.drop(for: dragLocation, grabbed: grabbed, headers: headerFrameList) {
        case .assign(let name):
            highlighted = LocationName.normalizedKey(name) == LocationName.normalizedKey(group.name)
        case .unassign:
            highlighted = group.isUnassigned
        case .reorder, .cancel:
            highlighted = false
        }
        guard highlighted else { return nil }

        return AnyView(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
        )
    }

    @ViewBuilder
    private var selectionBar: some View {
        if isSelecting {
            SelectionActionBar(
                verb: "Assign",
                count: selection.count,
                totalCount: selectableSpoolIDs.count,
                allSelected: selection.count == selectableSpoolIDs.count && !selectableSpoolIDs.isEmpty,
                role: nil,
                onToggleSelectAll: {
                    if selection.count == selectableSpoolIDs.count {
                        selection.removeAll()
                    } else {
                        selection = Set(selectableSpoolIDs)
                    }
                },
                onAction: { sheet = .assignSelection(Array(selection)) }
            )
        } else if loadError == nil {
            // The screen's main job at the bench: scan a location tag, then
            // spools. A full-width button at the thumb, like Scan Tag and
            // Weigh's bar, instead of a fourth toolbar icon (audit L5).
            // Hidden while the list failed to load: Retry is that state's one
            // primary action.
            Button { sheet = .assignSession(nil) } label: {
                Label("Assign Spools", systemImage: "wave.3.right")
                    .font(.headline)
                    .padding(.vertical)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .needsServer()
            .accessibilityIdentifier("locations.assign")
            .padding()
        }
    }

    // MARK: - Naming

    /// Three sources, one list: names observed on spools, names the backend
    /// lists, and names only this device knows about (a location created
    /// before any spool was assigned to it — the only kind Spoolman and the
    /// on-device Library cannot store).
    static func mergedLocations(
        observed: [String], known: [String], registered: [String] = []
    ) -> [String] {
        let normalized = (observed + known + registered)
            .map { LocationName.trimmed($0) }
            .filter { !$0.isEmpty }

        let unique = Set(normalized)
        return unique.sorted {
            let comparison = $0.localizedCaseInsensitiveCompare($1)
            if comparison == .orderedSame {
                return $0 < $1
            }
            return comparison == .orderedAscending
        }
    }

    static func canonicalLocationName(for displayName: String, observed: [String], known: [String]) -> String {
        let target = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return displayName }

        for candidate in known + observed {
            if candidate.trimmingCharacters(in: .whitespacesAndNewlines) == target {
                return candidate
            }
        }

        return displayName
    }
}

/// Where every group header currently sits, in `ArrangeSpace`. A `let` rather
/// than the `var` the protocol declares, because a mutable static would be a
/// Swift 6 concurrency warning and the protocol is satisfied either way.
private struct HeaderFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
