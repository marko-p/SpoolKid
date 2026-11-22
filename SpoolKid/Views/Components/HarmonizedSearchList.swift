import SwiftUI

struct HarmonizedSearchList<SelectionValue: Hashable, Content: View>: View {
    let title: String
    @Binding var searchText: String
    let prompt: String
    var selection: Binding<Set<SelectionValue>>?
    let trailingControlCount: Int
    /// Hands the list's `ScrollViewProxy` to a caller that needs to drive the
    /// scroll itself — Manage Locations autoscrolls while a row is being
    /// dragged. Optional and defaulted, so the other consumers are untouched.
    let onScrollProxy: ((ScrollViewProxy) -> Void)?
    let trailingControls: AnyView
    /// Puts Select and the trailing controls under "…" at every scroll
    /// position, for a screen whose own bottom bar carries its main action
    /// (Manage Locations, audit L5).
    let collapsesTrailing: Bool
    /// Controls that never collapse into "…" (Manage Locations' +).
    let pinnedTrailingControls: AnyView
    /// A minimum row height for the list's rows, for a list of rows shorter than
    /// the system minimum (the spool lists, 36 pt). Nil keeps the system's.
    ///
    /// The minimum is read list-wide, so it reaches more than the rows: the search
    /// field's anchor row (`anchorRow`) would shrink with it and pull the field up,
    /// and a screen pushed from a row would inherit it. The first is handled here;
    /// a caller restores the system value on any destination it pushes.
    let compactRowHeight: CGFloat?
    /// A control that stands in for the title in the bar, such as Manage Spools'
    /// grouping menu. With one the title is inline: the bar shows the control,
    /// and there is no large title repeating it. `title` still names the screen
    /// for the back button. Nil shows `title` as text, with the large title.
    let titleMenu: AnyView?
    /// False drops the large title for a plain inline one, as a title menu does:
    /// for a pushed picker, whose bar already names it (Select Spool, owner
    /// 2026-10-26).
    let showsLargeTitle: Bool
    /// Sections shown above the search field and the content's own section, as
    /// separate groups (the Library's shortcut rows). The content is one section,
    /// so sections passed inside it would be flattened into it as plain rows.
    /// Meant for a screen with an inline title: there the field's own position
    /// drives its lift into the bar, wherever it rests.
    let leadingSections: AnyView?
    /// Empties the leading sections without removing them (the Library while
    /// a search runs). Removing them would move the search field's row, and
    /// the list rebuilds a moved row, taking the keyboard with it after the
    /// first letter. The sections build with `LeadingSection` to follow it.
    let collapsesLeadingSections: Bool
    /// True when the content builds its own `Section`s, each a separate group
    /// (the Library's Recently Added and Other Spools). False wraps the content
    /// in one section, as every other caller wants.
    let contentIsSectioned: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.editMode) private var editMode
    /// The system's minimum row height, read outside the list's own override.
    @Environment(\.defaultMinListRowHeight) private var outerMinRowHeight
    @State private var transitionProgress: CGFloat = 0
    @State private var initialFieldGlobalMidY: CGFloat = 0
    /// The tracked row's last reported top, for when the list stops laying it out.
    @State private var lastTrackedMinY: CGFloat?
    /// Which copy of the search field holds the keyboard. The list's and the
    /// bar's take turns as the screen scrolls, and the one going out stops
    /// taking touches, which drops the keyboard; `followFocus` hands it over.
    @State private var listFieldFocused = false
    @State private var barFieldFocused = false

    init<Trailing: View, Pinned: View>(
        title: String,
        searchText: Binding<String>,
        prompt: String,
        selection: Binding<Set<SelectionValue>>? = nil,
        trailingControlCount: Int = 0,
        collapsesTrailing: Bool = false,
        onScrollProxy: ((ScrollViewProxy) -> Void)? = nil,
        compactRowHeight: CGFloat? = nil,
        titleMenu: AnyView? = nil,
        showsLargeTitle: Bool = true,
        leadingSections: AnyView? = nil,
        collapsesLeadingSections: Bool = false,
        contentIsSectioned: Bool = false,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder pinnedTrailing: () -> Pinned = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self._searchText = searchText
        self.prompt = prompt
        self.selection = selection
        self.trailingControlCount = trailingControlCount
        self.collapsesTrailing = collapsesTrailing
        self.onScrollProxy = onScrollProxy
        self.trailingControls = AnyView(trailing())
        self.pinnedTrailingControls = AnyView(pinnedTrailing())
        self.compactRowHeight = compactRowHeight
        self.titleMenu = titleMenu
        self.showsLargeTitle = showsLargeTitle
        self.leadingSections = leadingSections
        self.collapsesLeadingSections = collapsesLeadingSections
        self.contentIsSectioned = contentIsSectioned
        self.content = content
    }

    var body: some View {
        GeometryReader { containerProxy in
            // With an inline title the search field rests just below the bar (see
            // `transitionProgressValue`); the safe area's top is the bar's
            // bottom. Read here, outside the preference closure, which must not
            // capture the proxy.
            let fieldRestTop = containerProxy.safeAreaInsets.top + Self.inlineTitleTopMargin
            // Layout-neutral: it only vends the proxy. Present for every
            // consumer so the list's structure does not depend on whether a
            // caller asked for the proxy.
            ScrollViewReader { scrollProxy in
                List(selection: selection) {
                    if !isInlineTitle {
                        anchorRow
                    }

                    // Above the field, so it sits right over the list it searches
                    // (owner, 2026-10-26).
                    if let leadingSections {
                        leadingSections
                            .environment(\.leadingSectionsCollapsed, collapsesLeadingSections)
                    }

                    CustomSearchBar(text: $searchText, prompt: prompt, isFocused: $listFieldFocused)
                        .background {
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(
                                        key: InitialSearchMidYPreferenceKey.self,
                                        value: proxy.frame(in: .global).midY
                                    )
                                    // With an inline title there is no anchor row:
                                    // the field's own top drives the transition.
                                    // Nil otherwise, which the key's `reduce`
                                    // ignores in favour of the anchor row's.
                                    .preference(
                                        key: ScrollOffsetPreferenceKey.self,
                                        value: isInlineTitle ? proxy.frame(in: .global).minY : nil
                                    )
                            }
                        }
                        .padding(.horizontal, initialSearchPadding(for: containerProxy.size.width, progress: transitionProgress))
                        .opacity(initialOpacity(progress: transitionProgress))
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)

                    if contentIsSectioned {
                        content()
                    } else {
                        Section {
                            content()
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .modifier(MinRowHeight(height: collapsesLeadingSections && leadingSections != nil ? 0 : compactRowHeight))
                .navigationTitle(title)
                // `.large`, not `.automatic`: the fixed 144/94 thresholds assume a
                // large title, and `.automatic` inherits the pushing screen's mode,
                // so an inline root (the Library tab) would hand inline to every
                // list screen it pushes.
                .navigationBarTitleDisplayMode(isInlineTitle ? .inline : .large)
                // Without a large title the list's own top margin would leave an
                // empty band where the title was.
                .contentMargins(.top, isInlineTitle ? Self.inlineTitleTopMargin : nil, for: .scrollContent)
                // Handed out from `onAppear`, not from inside the builder:
                // calling a caller's closure during a view update is how you
                // get "Modifying state during view update".
                .onAppear { onScrollProxy?(scrollProxy) }
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { minY in
                    if let minY { lastTrackedMinY = minY }
                    let nextProgress = transitionProgressValue(minY: minY, fieldRestTop: fieldRestTop)
                    if abs(nextProgress - transitionProgress) > 0.001 {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                            transitionProgress = nextProgress
                        }
                        followFocus(progress: nextProgress)
                    }
                }
                .onPreferenceChange(InitialSearchMidYPreferenceKey.self) { value in
                    initialFieldGlobalMidY = value
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        principalTransitionView(
                            availableWidth: containerProxy.size.width,
                            progress: transitionProgress,
                            containerProxy: containerProxy
                        )
                    }
                    if isEditable || trailingControlCount > 0 {
                        ToolbarItem(placement: .topBarTrailing) {
                            trailingToolbar()
                        }
                    }
                }
                // Adds the standard "X" above the keyboard to dismiss it, so the
                // search field matches the forms. Covers every
                // HarmonizedSearchList consumer (Manage lists + selection
                // pickers).
                .keyboardDoneBar()
            }
        }
    }

    /// The zero-height row whose position drives the search field's transition
    /// into the toolbar. A zero-height row is still padded up to the list's
    /// minimum row height, and the search field sits below it, so lowering that
    /// minimum for the rows (`compactRowHeight`) would pull the field up by the
    /// difference. The row is therefore held at the system's height in an outer
    /// frame. The zero-height reader stays centred in it, so its `minY` is
    /// what it always was and the transition thresholds still hold; making the
    /// reader itself that tall would put its `minY` half a row higher.
    private var anchorRow: some View {
        GeometryReader { anchorProxy in
            Color.clear.preference(
                key: ScrollOffsetPreferenceKey.self,
                value: anchorProxy.frame(in: .global).minY
            )
        }
        .frame(height: 0)
        .frame(height: compactRowHeight == nil ? nil : outerMinRowHeight)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    /// No large title: with a title menu, or when the caller asked for none.
    private var isInlineTitle: Bool { titleMenu != nil || !showsLargeTitle }

    /// The gap between the bar and the search field at rest, with an inline title.
    private static var inlineTitleTopMargin: CGFloat { 8 }

    /// With a large title, `minY` is the anchor row's and the thresholds are
    /// fixed. With an inline title there is no anchor row and no large title to
    /// collapse first: `minY` is the search field's top, and the transition runs
    /// over the 50 pt after it reaches `fieldRestTop`, just below the bar —
    /// at once when the field rests there, later when rows sit above it.
    ///
    /// The list reports nothing for a row it has not laid out. That is "scrolled
    /// past" when the row was last seen above the start line, and "not reached
    /// yet" when it was last seen below it — or never seen, as for a field that
    /// rests under the Library's shortcut rows, below a small screen's fold.
    private func transitionProgressValue(minY: CGFloat?, fieldRestTop: CGFloat) -> CGFloat {
        let start: CGFloat = isInlineTitle ? fieldRestTop : 144
        guard let minY else {
            guard let lastTrackedMinY else { return 0 }
            return lastTrackedMinY < start ? 1 : 0
        }

        let end: CGFloat = start - 50
        let raw = (start - minY) / (start - end)

        return min(max(raw, 0), 1)
    }

    /// Editable is inferred from the selection binding: the binding exists
    /// precisely to drive multi-select edit mode.
    private var isEditable: Bool { selection != nil }
    private var isEditing: Bool { editMode?.wrappedValue.isEditing == true }

    private var collapsibleCount: Int {
        trailingControlCount + ((isEditable && !isEditing) ? 1 : 0)
    }

    /// Trailing controls. Only included by the toolbar when
    /// `isEditable || trailingControlCount > 0`, so this need not re-guard.
    private func trailingToolbar() -> some View {
        let collapsed = collapsesTrailing || ToolbarMetrics.shouldCollapse(
            collapsibleCount: collapsibleCount,
            transitionProgress: transitionProgress
        )
        return HStack(spacing: ToolbarMetrics.controlSpacing) {
            // The confirm ("Done") affordance stays pinned while editing, as a
            // compact checkmark icon so it doesn't crowd the centered search field.
            if isEditable && isEditing {
                Button {
                    withAnimation { editMode?.wrappedValue = .inactive }
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel("Done")
            }

            if collapsed {
                Menu {
                    if isEditable && !isEditing {
                        Button {
                            withAnimation { editMode?.wrappedValue = .active }
                        } label: { Label("Select", systemImage: "checkmark.circle") }
                    }
                    trailingControls
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            } else {
                if isEditable && !isEditing {
                    // The selection circle, not the pencil, which read as Edit
                    // (audit X1); an icon, not the word, so the bar has room
                    // (owner, 2026-10-26). The "…" menu's Select uses the same
                    // symbol.
                    Button {
                        withAnimation { editMode?.wrappedValue = .active }
                    } label: { Image(systemName: "checkmark.circle") }
                    .accessibilityLabel("Select")
                }
                // .labelStyle(.iconOnly) propagates through AnyView via the
                // environment, reaching the wrapped controls' Labels.
                trailingControls
                    .labelStyle(.iconOnly)
            }
            pinnedTrailingControls.labelStyle(.iconOnly)
        }
        // A new identity per state: the bar's glass capsule otherwise keeps the
        // previous state's width, clipping "Select" after "…" or leaving "…" wide.
        .id(collapsed)
    }

    private func principalSearchWidth(for availableWidth: CGFloat) -> CGFloat {
        // Reserve room only for the collapsed "…" (or a single uncollapsed
        // control) plus the leading title margin — far less than the old
        // multi-button reservation, so the toolbar search field stays wide.
        let candidate = availableWidth - 168
        return min(max(candidate, 176), 820)
    }

    private func initialSearchPadding(for availableWidth: CGFloat, progress: CGFloat) -> CGFloat {
        let startPadding: CGFloat = 16
        let endPadding = (availableWidth - principalSearchWidth(for: availableWidth)) / 2
        let shrink = smoothStep(progress, from: 0.28, to: 0.84)
        return startPadding + (endPadding - startPadding) * shrink
    }

    private func initialOpacity(progress: CGFloat) -> CGFloat {
        // Keep initial search visible longer; fade later to align vertically with principal.
        1 - smoothStep(progress, from: 0.56, to: 0.90)
    }

    private func principalOpacity(progress: CGFloat) -> CGFloat {
        // Delay principal emergence to avoid seeing both fields at once.
        smoothStep(progress, from: 0.52, to: 0.86)
    }

    private func principalOffset(progress: CGFloat, containerProxy: GeometryProxy) -> CGFloat {
        let currentPrincipalMidY = principalMidY(containerProxy: containerProxy) + (1 - progress) * 14
        let delta = initialFieldGlobalMidY - currentPrincipalMidY
        let settle = smoothStep(progress, from: 0.50, to: 0.86)
        // Ensure offset is strictly positive so it always snaps into position from below,
        // avoiding top-down flying if initialFieldGlobalMidY is 0 on the first render pass.
        return abs(delta) * (1 - settle)
    }

    private func titleOpacity(progress: CGFloat) -> CGFloat {
        // Title dissolves as principal field becomes present.
        1 - smoothStep(progress, from: 0.34, to: 0.78)
    }

    private func smoothStep(_ value: CGFloat, from start: CGFloat, to end: CGFloat) -> CGFloat {
        guard end > start else { return value >= end ? 1 : 0 }
        let x = min(max((value - start) / (end - start), 0), 1)
        return x * x * (3 - 2 * x)
    }

    private func principalMidY(containerProxy: GeometryProxy) -> CGFloat {
        let safeTop = containerProxy.safeAreaInsets.top
        let navBarHeight: CGFloat = 44
        return safeTop + navBarHeight / 2
    }

    @ViewBuilder
    private func principalTransitionView(
        availableWidth: CGFloat,
        progress: CGFloat,
        containerProxy: GeometryProxy
    ) -> some View {
        ZStack {
            Group {
                if let titleMenu {
                    // Not tappable once the search field has taken its place.
                    titleMenu.allowsHitTesting(progress < 0.5)
                } else {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .opacity(titleOpacity(progress: progress))
            .scaleEffect(1 - (0.10 * progress))
            .blur(radius: progress * 0.8)

            CustomSearchBar(text: $searchText, prompt: prompt, isFocused: $barFieldFocused)
                .frame(width: principalSearchWidth(for: availableWidth))
                .opacity(principalOpacity(progress: progress))
                .offset(y: principalOffset(progress: progress, containerProxy: containerProxy))
                .scaleEffect(0.975 + (0.025 * smoothStep(progress, from: 0.50, to: 0.86)), anchor: .center)
                .allowsHitTesting(progress > Self.barFieldThreshold)
        }
        .frame(maxWidth: .infinity)
    }

    /// Past this progress the bar's field takes touches, and the list's has
    /// faded out.
    private static var barFieldThreshold: CGFloat { 0.90 }

    /// Moves the keyboard to the field now in use, as the scroll position
    /// hands over. Typing in the docked field is what triggers it most: the
    /// first letter collapses the rows above the list, the list fits on screen,
    /// and it settles back at the top.
    private func followFocus(progress: CGFloat) {
        if barFieldFocused && progress <= Self.barFieldThreshold {
            listFieldFocused = true
        } else if listFieldFocused && progress > Self.barFieldThreshold {
            barFieldFocused = true
        }
    }
}

extension HarmonizedSearchList where SelectionValue == Never {
    init<Trailing: View>(
        title: String,
        searchText: Binding<String>,
        prompt: String,
        trailingControlCount: Int = 0,
        compactRowHeight: CGFloat? = nil,
        showsLargeTitle: Bool = true,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            searchText: searchText,
            prompt: prompt,
            selection: nil,
            trailingControlCount: trailingControlCount,
            compactRowHeight: compactRowHeight,
            showsLargeTitle: showsLargeTitle,
            trailing: trailing,
            content: content
        )
    }
}

extension EnvironmentValues {
    @Entry var leadingSectionsCollapsed: Bool = false
}

/// A section of `HarmonizedSearchList`'s `leadingSections`. While the list
/// collapses them its rows shrink to nothing rather than leave: a row the list
/// deletes moves every row after it, the search field's among them.
struct LeadingSection<Content: View, Footer: View>: View {
    @Environment(\.leadingSectionsCollapsed) private var collapsed
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder footer: @escaping () -> Footer) {
        self.content = content
        self.footer = footer
    }

    var body: some View {
        Section {
            // Row modifiers on the group reach each of its rows.
            content()
                .frame(height: collapsed ? 0 : nil)
                .clipped()
                .opacity(collapsed ? 0 : 1)
                .accessibilityHidden(collapsed)
                .allowsHitTesting(!collapsed)
                .modifier(CollapsedRow(active: collapsed))
        } footer: {
            if !collapsed { footer() }
        }
        .listSectionSpacing(collapsed ? .custom(0) : .default)
    }
}

/// The row chrome a collapsed leading row drops. Applied either way, so the
/// rows keep their identity.
private struct CollapsedRow: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .listRowInsets(active ? EdgeInsets() : nil)
            .listRowBackground(active ? Color.clear : nil)
            .listRowSeparator(active ? .hidden : .automatic)
    }
}

extension LeadingSection where Footer == EmptyView {
    init(@ViewBuilder content: @escaping () -> Content) {
        self.init(content: content, footer: { EmptyView() })
    }
}

/// Sets the list's minimum row height, the system's when `height` is nil.
/// Always through the environment: a branch here would rebuild the whole list
/// when it flips, the focused search field with it. Zero while leading rows
/// are collapsed, which would otherwise keep a row's height each; the spool
/// rows hold their own minimum.
private struct MinRowHeight: ViewModifier {
    let height: CGFloat?
    @Environment(\.defaultMinListRowHeight) private var systemHeight

    func body(content: Content) -> some View {
        content.environment(\.defaultMinListRowHeight, height ?? systemHeight)
    }
}

private struct InitialSearchMidYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
