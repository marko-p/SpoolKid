//
//  WeighSessionView.swift
//  SpoolKid
//
//  Purpose: One batch weighing session. Scan or pick a spool, type its GROSS
//  weight, save and move to the next. All rules live in `WeighSessionState`;
//  this view renders it and performs the writes.
//
//  Why "Save automatically" exists: CoreNFC puts a system sheet over the app
//  for every scan and a session times out at 60s, so a per-spool "start the
//  next scan" tap is unavoidable. Letting that tap also commit is therefore
//  free, and it is the fast path most of a stack wants. But it is not everyone's
//  path, so it is a toggle rather than a rule (owner, bench pass 2026-09-04),
//  and with it off nothing is written without an explicit Save.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI
import TipKit

struct WeighSessionView: View {
    @EnvironmentObject private var store: SpoolDataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hidesFirstRunTips) private var hidesFirstRunTips

    /// The (i) first, then the bar's icons left to right, one at a time.
    @State private var tips = TipGroup(.ordered) {
        InfoButtonTip()
        WeighFinishTip()
        WeighChooseTip()
        WeighScanTip()
    }

    /// The scan sheet and the spool picker present above this screen, and a
    /// popover would present above them.
    private var showsTips: Bool {
        !hidesFirstRunTips && !showSpoolPicker && !nfcManager.isScanning
    }

    /// This view owns its scanner rather than taking one from the environment:
    /// `NFCManager` is NOT an environment object (`ContentView` holds it as a
    /// `@StateObject` and hands it to `TagsTabView` explicitly), and none of
    /// this view's three entry points has an instance to pass. Same pattern as
    /// `ScanResultHubView.secondTagNFCManager`.
    @StateObject private var nfcManager = NFCManager()

    /// Set when entered from a spool that is already known (the Scan Result Hub
    /// or a spool row), nil when entered cold from the Library.
    let initialSpool: Spool?

    /// Whether "Scan" and "Choose" commit the reading on screen on their way
    /// out. Default true — the batch path this screen exists for.
    @AppStorage(AppConfig.weighAutoSaveOnAdvanceKey)
    private var autoSaveOnAdvance: Bool = true

    @State private var session = WeighSessionState()
    @State private var showSpoolPicker = false
    /// True for the whole span from a save-bearing tap through the write
    /// completing. Set synchronously in the action — never inside an `async`
    /// function — so a second tap arriving before the first `Task` has even
    /// been scheduled still sees it and no-ops.
    @State private var isSaving = false
    @State private var unresolvedTagMessage: String?
    @State private var discardPrompt: DiscardPrompt?
    @State private var unsavedAdvance: UnsavedAdvance?
    @State private var emptyWeightInput = ""
    /// `onAppear` re-fires whenever the view comes back — a tab switch is one
    /// tap away from this screen — and `load` blanks `weightInput`. Without
    /// this latch, glancing at Home mid-reading silently discards the number
    /// the user just typed.
    @State private var didLoadInitial = false
    /// Merged device + backend history for the spool on the scale, and for the
    /// session's recent past. Loaded per spool, not held for the whole app.
    @State private var pendingHistory: [MeasurementRecord] = []
    /// Weighing by scale is a MODE, not a per-spool choice: a bench session is
    /// all one way or all the other, and asking again for every spool is the
    /// friction the owner asked to remove (2026-09-08).
    @AppStorage(AppConfig.weighWithScaleKey) private var weighWithScale = false
    @EnvironmentObject private var scale: BLEScaleService
    @State private var showingScaleSetup = false
    @State private var recentHistory: [MeasurementRecord] = []
    @State private var historyTask: Task<Void, Never>?

    private enum Field: Hashable { case weight, emptyWeight }
    @FocusState private var focusedField: Field?

    /// Where an advance was heading when it had to stop and ask.
    private enum Destination { case scan, picker }

    /// What Done is about to throw away, and whether closing has to clear a
    /// pending reading on the way out. One prompt covering every reason rather
    /// than one alert per reason: a second `.alert` raised from the first's
    /// button never appears.
    private struct DiscardPrompt: Identifiable {
        let id = UUID()
        let message: String
        let clearsPending: Bool
    }

    /// A reading the user is advancing past while auto-save is off. Carries
    /// everything the write needs, because by the time they answer, `pending`
    /// is the wrong place to read it from.
    private struct UnsavedAdvance: Identifiable {
        let id = UUID()
        let destination: Destination
        let spoolID: Int
        let spoolName: String
        let gross: Double
        let net: Double
        let emptySpoolWeight: Double?
    }

    /// The mode switch, above everything, because it changes what the rest of
    /// the screen is for — but only for someone who has a scale. Without one
    /// this row is the way to get one, because a toggle that cannot do anything
    /// is worse than no toggle (owner, 2026-09-09).
    private var scaleModeSection: some View {
        Section {
            if scale.paired == nil {
                HStack {
                    Button {
                        showingScaleSetup = true
                    } label: {
                        Label("Set Up a Bluetooth Scale", systemImage: "scalemass")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    scaleInfoButton
                }
            } else {
                infoToggle("Weigh with a Bluetooth Scale", isOn: $weighWithScale, info: scaleInfoButton)
            }
        }
    }

    /// How the scale row works, in every state, behind the screen's first (i)
    /// — which also carries the one-time tip (audit W1).
    private var scaleInfoButton: some View {
        InfoButton(
            title: "Bluetooth Scale",
            lines: [scaleModeFooter],
            introTip: showsTips ? tips.currentTip as? InfoButtonTip : nil
        )
    }

    private var scaleModeFooter: String {
        if scale.paired == nil {
            return "Set a scale up once — here or in Settings → Bluetooth Scale — and its readings fill the weight field on their own."
        }
        return weighWithScale
            ? "Settled readings from \(scale.paired?.name ?? "your scale") fill the weight field. Save is still yours."
            : "Weights are typed. Switch this on to take them off \(scale.paired?.name ?? "your scale") instead."
    }

    /// Fill the pending weight from a settled reading, in scale mode only.
    ///
    /// Settled only: a number that moves while the spool is being set down is
    /// not a weight, and writing every intermediate value into the field would
    /// make Save a race. Guarded on there BEING a pending spool, so a reading
    /// cannot land anywhere when nothing is selected.
    private func takeScaleReading(_ reading: AiLinkScaleReading?) {
        guard weighWithScale, let reading, reading.isSettled, session.pending != nil else { return }
        guard session.pending?.weightInput != String(reading.grams) else { return }
        session.updateWeightInput(String(reading.grams))
        focusedField = nil
    }

    /// Whether handing a spool back to the user puts the cursor in the weight
    /// field. Not in scale mode: the scale fills the field, and a raised
    /// keyboard covered the scale's row along with Scan, Choose and Finish
    /// (owner, 2026-09-25).
    nonisolated static func focusesWeightOnReturn(weighWithScale: Bool, hasPairedScale: Bool) -> Bool {
        !(weighWithScale && hasPairedScale)
    }

    private var returnFocus: Field? {
        Self.focusesWeightOnReturn(weighWithScale: weighWithScale, hasPairedScale: scale.paired != nil)
            ? .weight : nil
    }

    static let emptyWeightHint =
        "typical cores — plastic ≈ 180–250 g, cardboard ≈ 110–160 g; check yours if unsure"

    var body: some View {
        List {
            scaleModeSection
            pendingSection
            autoSaveSection
            if !session.log.isEmpty { logSection }
            historySection
        }
        .onChange(of: scale.reading) { _, new in takeScaleReading(new) }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Weigh Spools")
        .floatingBottomBar { actionBar }
        // The system back button would leave without the guard `finish()`
        // applies, taking any unsaved reading and every failed row with it.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    finish()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
                .disabled(isSaving)
            }
            // `.decimalPad` has no return key, so without this the keyboard
            // covers the screen with no way to put it away — it blocked the
            // tab bar entirely (bench pass 2026-09-04).
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        // Turning the mode on is not presumptuous here: this sheet is only
        // reachable from the mode row, and only while no scale is paired.
        // Someone who set a scale up from Weigh Spools came to weigh with it.
        .sheet(isPresented: $showingScaleSetup, onDismiss: {
            if scale.paired != nil { weighWithScale = true }
        }) {
            NavigationStack {
                ScaleSetupView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingScaleSetup = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showSpoolPicker) {
            NavigationStack {
                SpoolSelectionView(onSelect: { spool in
                    showSpoolPicker = false
                    load(spool)
                })
            }
        }
        .onAppear {
            loadRecentHistory()
            guard !didLoadInitial else { return }
            didLoadInitial = true
            if let initialSpool { load(initialSpool) }
        }
        .onDisappear { historyTask?.cancel() }
        .onChange(of: nfcManager.isScanning) { _, isScanning in
            guard !isScanning else { return }
            resolveScannedTag()
        }
        .confirmationDialog(
            "This reading isn't saved yet",
            isPresented: Binding(
                get: { unsavedAdvance != nil },
                set: { if !$0 { unsavedAdvance = nil } }
            ),
            presenting: unsavedAdvance
        ) { item in
            Button("Save \(SpoolWeightMath.formatWeight(item.gross)) g and continue") {
                commitUnsaved(item)
            }
            Button("Discard and continue", role: .destructive) {
                session.clearPending()
                perform(item.destination)
            }
            Button("Keep weighing", role: .cancel) { focusedField = returnFocus }
        } message: { item in
            Text("\(item.spoolName) is still on the scale. Saving is off, so moving on now would lose this reading.")
        }
        .alert(
            "Unsaved work",
            isPresented: Binding(
                get: { discardPrompt != nil },
                set: { if !$0 { discardPrompt = nil } }
            ),
            presenting: discardPrompt
        ) { prompt in
            Button("Keep weighing", role: .cancel) {
                if prompt.clearsPending { focusedField = returnFocus }
            }
            Button("Discard and close", role: .destructive) {
                if prompt.clearsPending { session.clearPending() }
                dismiss()
            }
        } message: { prompt in
            Text(prompt.message)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var pendingSection: some View {
        if let pending = session.pending {
            Section("On the scale") {
                HStack(spacing: 12) {
                    colorSwatch(colors: pending.colors)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pending.spoolName).font(.headline)
                        if !pending.detail.isEmpty {
                            Text(pending.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        // What this spool weighed last time, so a reading that
                        // has drifted the wrong way is obvious while the spool
                        // is still on the scale.
                        if let last = pendingHistory.first {
                            Text("Last weighed \(Self.lastWeighedSummary(last))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack {
                    Text("Weight")
                    Spacer()
                    TextField("0", text: Binding(
                        get: { session.pending?.weightInput ?? "" },
                        set: { session.updateWeightInput($0) }
                    ))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .weight)
                    Text("g").foregroundStyle(.secondary)
                }
                Text("GROSS — the whole spool on the scale, filament and spool together.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // In scale mode the reading fills the field on its own. That is
                // the point of the mode and it does NOT break the rule about
                // never producing an unseen number: the figure lands in a
                // visible field the user still has to Save, and they opted into
                // this by switching the mode on. Outside the mode nothing here
                // renders at all.
                if weighWithScale && scale.paired != nil {
                    ScaleWeightRow { grams in
                        session.updateWeightInput(String(grams))
                        focusedField = nil
                    }
                }

                if pending.emptySpoolWeight == nil { emptyWeightPrompt }
            }
        } else {
            Section {
                Text("Scan a tag or choose a spool to begin.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var autoSaveSection: some View {
        Section {
            infoToggle(
                "Save automatically",
                isOn: $autoSaveOnAdvance,
                info: InfoButton(title: "Save automatically", lines: [autoSaveExplanation])
            )
            .disabled(isSaving)
        }
    }

    /// A switch row with its (i) beside the label, not inside it. Inside a
    /// `Toggle`'s label the button became part of the switch's one
    /// accessibility element, which VoiceOver does not look into. The switch
    /// keeps the title as its spoken label, so the visible text is hidden from
    /// VoiceOver rather than read twice.
    private func infoToggle(_ title: String, isOn: Binding<Bool>, info: some View) -> some View {
        HStack {
            Text(title)
                .accessibilityHidden(true)
            info
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
        }
    }

    private var autoSaveExplanation: String {
        autoSaveOnAdvance
            ? "Scan and Choose save the reading on screen before moving to the next spool."
            : "Readings are saved only when you tap Save. Scan and Choose will ask first."
    }

    /// Shown only when the pending spool has no core weight. The hint is never
    /// prefilled: an estimate sitting in the box becomes indistinguishable from
    /// a measurement the moment it is saved. For the same reason the empty-spool
    /// library's default is not prefilled either; a pick from the library is the
    /// user's own choice, so it fills the box, and "Use this empty weight" still
    /// applies it.
    @ViewBuilder
    private var emptyWeightPrompt: some View {
        HStack {
            Text("Empty spool weight")
            Spacer()
            TextField("0", text: $emptyWeightInput)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: .emptyWeight)
                .onSubmit { applyEmptyWeight() }
            Text("g").foregroundStyle(.secondary)
            EmptySpoolPickerButton(
                accessibilityID: "weigh.emptySpoolPicker",
                manufacturer: session.pending?.manufacturer
            ) { grams in
                emptyWeightInput = SpoolWeightMath.formatWeight(grams)
            }
        }
        Text(Self.emptyWeightHint)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        Button("Use this empty weight") { applyEmptyWeight() }
            .disabled(SpoolWeightMath.parseWeight(emptyWeightInput) == nil)
    }

    private var logSection: some View {
        Section("Weighed this session") {
            ForEach(session.log) { entry in
                Button {
                    reopen(entry)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.spoolName)
                            // The row has to read correctly on its own — the
                            // icon next to it is not enough (R5).
                            Text(Self.caption(for: entry))
                                .font(.subheadline)
                                .foregroundStyle(Self.captionTint(for: entry))
                        }
                        Spacer()
                        statusIcon(for: entry)
                    }
                }
                .tint(.primary)
                // A save in flight is for the row that was just reopened out
                // from under it (see the pre-await clear) — a second row tapped
                // mid-write would have its `load` wiped by that same clear.
                .disabled(isSaving)
            }
        }
    }

    /// Previous sessions, grouped by how long ago. Deliberately below the log
    /// of THIS session: the two answer different questions, and mixing them
    /// would make it hard to tell what has just been saved from what was saved
    /// last week.
    @ViewBuilder
    private var historySection: some View {
        let groups = MeasurementRecord.grouped(recentHistory)
        if !groups.isEmpty {
            ForEach(groups, id: \.age) { group in
                Section(group.age.rawValue) {
                    ForEach(group.records) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(spoolLabel(record.spoolID))
                                Text(Self.historyDetail(record))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Self.timeFormatter.string(from: record.recordedAt))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// A history row states the GROSS reading, because that is what the scale
    /// showed and the only figure every source agrees on — a backend event
    /// carries no net weight (the tara at the time is not recorded), so
    /// leading with a net weight would print a blank for half the rows.
    private static func historyDetail(_ record: MeasurementRecord) -> String {
        var text = "\(SpoolWeightMath.formatWeight(record.grossWeight)) g on the scale"
        if let net = record.netWeight {
            text += " · \(SpoolWeightMath.formatWeight(net)) g remaining"
        }
        return text
    }

    private static func lastWeighedSummary(_ record: MeasurementRecord) -> String {
        "\(dayFormatter.string(from: record.recordedAt)) — "
            + "\(SpoolWeightMath.formatWeight(record.grossWeight)) g on the scale"
    }

    /// A history row can name a spool this session never touched, and one the
    /// backend may no longer have.
    private func spoolLabel(_ spoolID: Int) -> String {
        guard let spool = store.spools.first(where: { $0.id == spoolID }),
              let name = spool.filament.name else {
            return "Spool #\(spoolID)"
        }
        return name
    }

    @ViewBuilder
    private func colorSwatch(colors: FilamentColors) -> some View {
        FilamentSwatch(colors: colors, size: 28)
    }

    /// A caveat row is amber, NOT green and NOT red. Green would be the
    /// invariant broken — the write did not do all of the work. Red would say
    /// "not saved" about a spool whose weight is already on the server, and
    /// the obvious response to a red row here is to tap it and write again,
    /// which on FilaMan files a second measurement for the same reading.
    private static func caption(for entry: WeighSessionState.Entry) -> String {
        let remaining = "\(SpoolWeightMath.formatWeight(entry.netWeight)) g remaining"
        switch entry.outcome {
        case .saved: return remaining
        case .savedWithCaveat: return "\(remaining) — saved, with a warning"
        case .notSaved: return "\(remaining) — not saved"
        }
    }

    private static func captionTint(for entry: WeighSessionState.Entry) -> Color {
        switch entry.outcome {
        case .saved: .secondary
        case .savedWithCaveat: .orange
        case .notSaved: .red
        }
    }

    @ViewBuilder
    private func statusIcon(for entry: WeighSessionState.Entry) -> some View {
        switch entry.outcome {
        case .saved:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .savedWithCaveat:
            Label("Saved with a warning", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.orange)
        case .notSaved:
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.red)
        }
    }

    /// Everything lives here rather than in the navigation bar: this screen is
    /// used one-handed at a bench, and the top-right corner is the hardest
    /// place on a phone to reach.
    ///
    /// Scan and Choose are co-equal on purpose — a user whose spools are all
    /// untagged never touches NFC and is never routed through a fallback — so
    /// neither is the prominent icon (owner, 2026-10-30). Finish is the left
    /// icon; the bar's edges line up with the tab bar's.
    private var actionBar: some View {
        VStack(spacing: 8) {
            if let unresolvedTagMessage {
                Text(unresolvedTagMessage)
                    .font(.body)
                    .foregroundStyle(.red)
            }
            // The pending spool is cleared BEFORE the write, so during a save
            // the screen shows "Scan a tag or choose a spool to begin." with
            // every control greyed out. On a backend that is timing out, that
            // is thirty seconds of a dead-looking screen unless something says
            // a save is in flight.
            if isSaving {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Saving…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            // Glass buttons add about 10 pt of their own between them.
            HStack(spacing: 4) {
                // An icon since the device pass of 2026-10-30: beside Save,
                // Choose and Scan a worded button no longer fit inside the tab
                // bar's width. Its label still says when it saves, for
                // VoiceOver and the Large Content Viewer, and its tip says it
                // once on screen.
                BottomBarButton(title: finishLabel, systemImage: "checkmark") {
                    WeighFinishTip().invalidate(reason: .actionPerformed)
                    finish()
                }
                .disabled(isSaving)
                .popoverTip(showsTips ? tips.currentTip as? WeighFinishTip : nil, arrowEdge: .bottom)
                Spacer(minLength: 0)
                if !autoSaveOnAdvance {
                    BottomBarButton(title: "Save", systemImage: "square.and.arrow.down") {
                        saveNow()
                    }
                    .disabled(isSaving || !hasReading)
                    .needsServer()
                }
                BottomBarButton(title: "Choose", systemImage: "list.bullet") {
                    WeighChooseTip().invalidate(reason: .actionPerformed)
                    advance(to: .picker)
                }
                .disabled(isSaving)
                .popoverTip(showsTips ? tips.currentTip as? WeighChooseTip : nil, arrowEdge: .bottom)
                BottomBarButton(title: "Scan", systemImage: "wave.3.right") {
                    WeighScanTip().invalidate(reason: .actionPerformed)
                    advance(to: .scan)
                }
                .disabled(isSaving)
                .popoverTip(showsTips ? tips.currentTip as? WeighScanTip : nil, arrowEdge: .bottom)
            }
        }
        .padding(.vertical)
    }

    /// Names what Finish will actually do. "Done" alone read as "abandon" at
    /// the bench, so the label says when it saves (bench pass 2026-09-04); the
    /// rest is plain "Finish" (owner, 2026-10-30).
    private var finishLabel: String {
        hasReading ? "Save & Finish" : "Finish"
    }

    private var hasReading: Bool {
        session.commitOutcome() != .nothingToSave
    }

    // MARK: - Actions

    private func load(_ spool: Spool) {
        emptyWeightInput = ""
        unresolvedTagMessage = nil
        session.setPending(WeighSessionState.Pending(
            spoolID: spool.id,
            spoolName: spoolName(spool),
            emptySpoolWeight: spool.spoolWeight,
            detail: Self.detail(for: spool),
            colors: spool.filament.colors,
            manufacturer: spool.filament.vendor?.name
        ))
        focusedField = returnFocus
        loadHistory(for: spool.id)
    }

    /// History for the spool now on the scale. Cancels whatever was in flight:
    /// on a fast pass through a stack the previous spool's fetch is still
    /// running, and letting it land would caption THIS spool with the LAST
    /// one's last-weighed line.
    private func loadHistory(for spoolID: Int) {
        historyTask?.cancel()
        pendingHistory = WeighHistoryStore.shared.history(spoolID: spoolID, limit: 1)
        guard store.capabilities.providesMeasurementHistory else { return }
        historyTask = Task {
            let backend = await store.fetchMeasurementHistory(spoolID: spoolID)
            guard !Task.isCancelled, session.pending?.spoolID == spoolID else { return }
            pendingHistory = MeasurementRecord.merge(
                local: WeighHistoryStore.shared.history(spoolID: spoolID),
                backend: backend
            )
        }
    }

    /// The recent past across every spool, for the list at the bottom.
    ///
    /// Device-log only. The backend's equivalent would need one request per
    /// spool — FilaMan has no "all events for these spools" filter, and
    /// `all-events` returns every event type for every spool on the instance —
    /// so a bench loop would pay a fan-out on every save to decorate a list the
    /// user is not looking at. The per-spool fetch above is where the backend's
    /// history earns its round trip.
    private func loadRecentHistory() {
        recentHistory = WeighHistoryStore.shared.history(limit: 20)
    }

    private func spoolName(_ spool: Spool) -> String {
        spool.filament.name ?? "Spool #\(spool.id)"
    }

    /// Material · vendor · id — enough to tell two spools of the same filament
    /// apart without opening either (bench pass 2026-09-04).
    private static func detail(for spool: Spool) -> String {
        var parts: [String] = []
        if let material = spool.filament.material, !material.isEmpty { parts.append(material) }
        if let vendor = spool.filament.vendor?.name, !vendor.isEmpty { parts.append(vendor) }
        parts.append("Spool #\(spool.id)")
        return parts.joined(separator: " · ")
    }

    private func applyEmptyWeight() {
        guard let grams = SpoolWeightMath.parseWeight(emptyWeightInput) else { return }
        session.setEmptySpoolWeight(grams)
        // Every path that resolves the "blocked" condition must also clear
        // the message describing it — the advance paths already do; this is
        // the other one: the field's `onSubmit` and "Use this empty weight"
        // both route here too.
        unresolvedTagMessage = nil
    }

    /// Promotes a typed-but-unconfirmed empty weight into the session before
    /// a commit check runs. Typing the number and tapping a primary button is
    /// the default one-handed bench workflow; requiring a separate tap on "Use
    /// this empty weight" first would turn that into a false "blocked" state
    /// while the number sits visibly in the box (R4).
    private func applyPendingEmptyWeightIfNeeded() {
        guard session.pending?.emptySpoolWeight == nil else { return }
        applyEmptyWeight()
    }

    private func perform(_ destination: Destination) {
        switch destination {
        case .scan: nfcManager.startScanning()
        case .picker: showSpoolPicker = true
        }
    }

    /// Moves to the next spool, saving the current reading first when — and
    /// only when — the user has said that is what advancing means.
    private func advance(to destination: Destination) {
        guard !isSaving else { return }
        applyPendingEmptyWeightIfNeeded()

        switch session.advanceIntent(autoSave: autoSaveOnAdvance) {
        case .blockedNeedsEmptySpoolWeight:
            // Never let a primary button do nothing visible. The prompt is
            // already on screen, but a tap that silently no-ops reads as a bug.
            unresolvedTagMessage = "Enter this spool's empty weight before moving on."
            focusedField = nil
        case .advance:
            unresolvedTagMessage = nil
            session.clearPending()
            perform(destination)
        case .commitThenAdvance(let spoolID, let gross, let net):
            guard let pending = session.pending else { return }
            unresolvedTagMessage = nil
            isSaving = true
            // Cleared BEFORE the write, not after: the log rows stay tappable
            // during a save (R3), and a row reopened mid-write (`reopen` calls
            // `load`, which calls `setPending`) must not be wiped out by a
            // clear meant for the spool that was actually just committed.
            session.clearPending()
            Task {
                // The result is intentionally ignored: `perform` re-arms an NFC
                // session or opens the picker either way. Holding the whole
                // batch for one failed write is worse than letting the user
                // keep weighing — `write` has already filed the row as "not
                // saved" and raised the banner, so the failure is visible, not
                // silent, and stays retriable (tap the row) for the rest of
                // this session. `finish()` below makes the opposite call,
                // because Finish ends the session and would take that same
                // evidence with it.
                _ = await write(
                    spoolID: spoolID,
                    spoolName: pending.spoolName,
                    gross: gross,
                    net: net,
                    emptySpoolWeight: pending.emptySpoolWeight
                )
                isSaving = false
                perform(destination)
            }
        case .confirmUnsaved(let spoolID, let gross, let net):
            guard let pending = session.pending else { return }
            unresolvedTagMessage = nil
            unsavedAdvance = UnsavedAdvance(
                destination: destination,
                spoolID: spoolID,
                spoolName: pending.spoolName,
                gross: gross,
                net: net,
                emptySpoolWeight: pending.emptySpoolWeight
            )
        }
    }

    private func commitUnsaved(_ item: UnsavedAdvance) {
        guard !isSaving else { return }
        isSaving = true
        session.clearPending()
        Task {
            _ = await write(
                spoolID: item.spoolID,
                spoolName: item.spoolName,
                gross: item.gross,
                net: item.net,
                emptySpoolWeight: item.emptySpoolWeight
            )
            isSaving = false
            perform(item.destination)
        }
    }

    /// The explicit Save, shown only while auto-save is off. Stays on the same
    /// spool: the user chose to separate saving from advancing, so this must
    /// not also advance.
    private func saveNow() {
        guard !isSaving else { return }
        applyPendingEmptyWeightIfNeeded()

        switch session.commitOutcome() {
        case .nothingToSave:
            break
        case .blockedNeedsEmptySpoolWeight:
            unresolvedTagMessage = "Enter this spool's empty weight before moving on."
            focusedField = nil
        case .ready(let spoolID, let gross, let net):
            guard let pending = session.pending else { return }
            unresolvedTagMessage = nil
            isSaving = true
            session.clearPending()
            Task {
                _ = await write(
                    spoolID: spoolID,
                    spoolName: pending.spoolName,
                    gross: gross,
                    net: net,
                    emptySpoolWeight: pending.emptySpoolWeight
                )
                isSaving = false
            }
        }
    }

    /// Takes everything it needs as parameters rather than reading
    /// `session.pending` — by the time the write's `await` returns, the
    /// pending slot may hold a different spool.
    private func write(
        spoolID: Int,
        spoolName: String,
        gross: Double,
        net: Double,
        emptySpoolWeight: Double?
    ) async -> Bool {
        var draft = SpoolDraft()
        // The GROSS reading travels alongside the net one it implies. Only
        // FilaMan reads it, to file the save as a `measurement` rather than a
        // `manual_adjust`; every other backend uses `remainingWeight`.
        draft.measuredWeight = gross
        draft.remainingWeight = .set(net)
        // A core weight supplied during this session is part of the same save.
        if let emptySpoolWeight, emptySpoolWeight != spoolCoreWeight(spoolID) {
            draft.spoolWeight = .set(emptySpoolWeight)
        }

        let didWrite = await store.updateSpool(id: spoolID, draft: draft)
        // `updateSpool`'s Bool is half the contract. It returns `true` WITH a
        // message on `store.errorMessage` when the spool's PATCH landed but
        // something it carried did not — on this path most often a FilaMan
        // measurement that was never recorded, or a tara the backend could not
        // turn into a remaining weight. Reading only the Bool files that as a
        // green tick over work the backend did not do. Classified IMMEDIATELY,
        // before any follow-up write could overwrite the message, exactly as
        // `SpoolFormView.saveOutcome(didSave:)` does.
        let outcome = SaveOutcome.classify(
            didSave: didWrite,
            message: store.errorMessage,
            failureFallback: "The spool's weight could not be saved."
        )
        if let caveat = outcome.caveat {
            store.postSaveNotice(caveat, record: recordLabel(spoolID))
        }
        session.recordWrite(
            spoolID: spoolID,
            spoolName: spoolName,
            gross: gross,
            net: net,
            outcome: outcome
        )
        // Only a write that reached the backend becomes history. A failed one
        // is a failure the session already reports, and filing it here would
        // show it back to the user as a weighing that happened.
        if outcome.didWrite {
            WeighHistoryStore.shared.record(spoolID: spoolID, grossWeight: gross, netWeight: net)
            loadRecentHistory()
        }
        WorkflowTraceStore.log(path: "weigh", step: "spool.saved", details: [
            "spoolId": String(spoolID),
            "didWrite": String(outcome.didWrite),
            "caveat": outcome.caveat ?? ""
        ])
        if outcome.failure != nil {
            // The row this just filed shows "not saved", but the sheet that
            // follows (a new NFC scan, or the spool picker) covers the screen
            // immediately — this banner is what the user actually sees (R5).
            // A caveat needs no banner of its own: `postSaveNotice` above put
            // it on the ROOT banner, which outlives this screen.
            unresolvedTagMessage = "Could not save \(spoolName)'s weight — it's marked \"not saved\" below."
        }
        return outcome.didWrite
    }

    private func spoolCoreWeight(_ spoolID: Int) -> Double? {
        store.spools.first(where: { $0.id == spoolID })?.spoolWeight
    }

    /// What the root banner calls this spool. A caveat the user cannot trace
    /// back to a row is barely a caveat — same rule, and same shape, as
    /// `SpoolFormView.recordLabel`.
    private func recordLabel(_ spoolID: Int) -> String {
        guard let name = store.spools.first(where: { $0.id == spoolID })?.filament.name else {
            return "Spool #\(spoolID)"
        }
        return "Spool #\(spoolID) · \(name)"
    }

    /// The same resolver every other scan surface uses. Both of its collaborators
    /// are process singletons (`ScanResultHubView` holds `SpoolmanDBService.shared`
    /// too), so routing through it costs this view no new plumbing — and doing
    /// the cascade by hand here got only tier 2.
    private var resolutionService: ScanResolutionService {
        ScanResolutionService(
            repository: store,
            spoolmanDBService: .shared,
            webParserService: .shared,
            identity: store.tagIdentity
        )
    }

    /// Resolves the tag through `ScanResolutionService` rather than
    /// `findSpool(byCardUID:)` alone. That call is tier 2 of three: it misses a
    /// tag carrying an embedded spool id (tier 1) and a UID only the on-device
    /// ledger knows (tier 3), and it searches archived spools as well as
    /// active ones.
    ///
    /// `resolveMappedSpool` FIRST, then the two-pass `resolve` as a fallback.
    ///
    /// `resolve` answers a web-URL tag by fetching and
    /// parsing the page and returning `.parsedWebData` WITHOUT ever reaching
    /// the UID cascade below it. A single pass therefore reported "not mapped
    /// to a spool" for every web-URL tag on every backend (bench pass
    /// 2026-09-04), and feeding the parsed result back in fixed that — at the
    /// cost of a network round trip, then a second pass, before a tag whose
    /// mapping was already on file could be recognised. On the bench that was
    /// a visible wait next to an OpenSpool tag's instant answer (2026-09-05).
    ///
    /// So the stored mapping is asked first and answers without a network at
    /// all. The two-pass path remains for everything a stored mapping cannot
    /// answer — an unmapped tag whose web page names a filament.
    ///
    /// The resolver's other cases (a heuristic filament match, an unparsed web
    /// URL) are all "not a specific spool", which is the only answer this
    /// screen can act on: weighing needs the row to write to, not a guess.
    private func resolveScannedTag() {
        // No result: a cancelled or failed scan. Leave the session as it was
        // rather than re-arming whatever the previous scan returned.
        guard let scan = nfcManager.scanResult else { return }
        nfcManager.scanResult = nil
        let resolver = resolutionService
        Task {
            // The stored mapping first, and usually last: it needs no network,
            // and a tag already mapped to a spool should not wait on a fetch to
            // a third-party web page to find that out.
            if let spool = await resolver.resolveMappedSpool(scan) {
                guard session.pending == nil else { return }
                load(spool)
                return
            }
            var resolution = await resolver.resolve(scan, effectiveTagData: nil)
            if case .parsedWebData(let parsed) = resolution {
                resolution = await resolver.resolve(scan, effectiveTagData: parsed)
            }
            // The resolver awaits `fetchSpools()`. Anything the user loaded
            // during that window — a spool picked from the list, a log row
            // reopened — is newer than this scan and must not be stomped by
            // it. Every path that starts a scan clears `pending` first, so a
            // non-nil `pending` here means exactly that.
            guard session.pending == nil else { return }
            switch resolution {
            case .authoritativeSpool(let spool), .cardUIDSpool(let spool, _):
                load(spool)
            case .filamentTag(let filament):
                // Spec 4: the tag names a filament type, not one spool.
                unresolvedTagMessage = "That tag identifies the filament \(filament.listTitle), not a spool. Choose a spool from the list instead."
            case .matchResults, .unknownTag, .noMatch, .needsWebChallenge, .parsedWebData, .spoolIDMismatch, .backendLabelProblem:
                unresolvedTagMessage = "That tag is not mapped to a spool. Choose it from the list instead."
            }
        }
    }

    private func reopen(_ entry: WeighSessionState.Entry) {
        guard let spool = store.spools.first(where: { $0.id == entry.spoolID }) else { return }
        load(spool)
        session.updateWeightInput(SpoolWeightMath.formatWeight(entry.grossWeight))
    }

    /// Finish must not end the session silently while a reading is unsaved —
    /// that would drop work the user believes was saved. It saves regardless of
    /// the auto-save toggle, which is why the button says so: ending the
    /// session is the one moment where "later" is not an option. Guarded by
    /// `isSaving` for the same reason as the other buttons: a tap here while a
    /// scan-triggered save is still in flight must not fire a second write for
    /// the same spool.
    private func finish() {
        guard !isSaving else { return }
        applyPendingEmptyWeightIfNeeded()

        switch session.commitOutcome() {
        case .blockedNeedsEmptySpoolWeight:
            promptToDiscard(pendingIsUnsaveable: true)
        case .nothingToSave:
            promptToDiscard(pendingIsUnsaveable: false)
        case .ready(let spoolID, let gross, let net):
            guard let pending = session.pending else { return }
            isSaving = true
            session.clearPending()
            Task {
                _ = await write(
                    spoolID: spoolID,
                    spoolName: pending.spoolName,
                    gross: gross,
                    net: net,
                    emptySpoolWeight: pending.emptySpoolWeight
                )
                isSaving = false
                promptToDiscard(pendingIsUnsaveable: false)
            }
        }
    }

    /// Finish's last gate. Unlike the advance buttons, Finish ends the session,
    /// and `session` is local `@State` — closing takes the failed rows and the
    /// banner with them, which is the strongest form of reporting success for
    /// work that was not done. So Finish closes silently only when there is
    /// nothing left to lose; otherwise it says what would be lost and makes
    /// discarding it a deliberate choice.
    ///
    /// A CAVEAT row does not block: the spool's weight is on the server, and
    /// the caveat itself was handed to the root banner by `write`, which
    /// outlives this screen. Only a row that never reached the backend has its
    /// sole record here.
    ///
    /// Every reason goes into ONE prompt. Raising a second alert from the
    /// first's button is how the second gets dropped.
    private func promptToDiscard(pendingIsUnsaveable: Bool) {
        var reasons: [String] = []
        if pendingIsUnsaveable {
            reasons.append(
                "This spool has no empty spool weight yet, so its reading cannot be saved."
            )
        }
        let failed = session.log.filter { !$0.didWrite }.count
        if failed == 1 {
            reasons.append("One weighed spool could not be saved. Closing loses that record.")
        } else if failed > 1 {
            reasons.append("\(failed) weighed spools could not be saved. Closing loses those records.")
        }
        guard !reasons.isEmpty else {
            dismiss()
            return
        }
        discardPrompt = DiscardPrompt(
            message: reasons.joined(separator: "\n\n"),
            clearsPending: pendingIsUnsaveable
        )
    }
}
