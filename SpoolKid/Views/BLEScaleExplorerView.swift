//
//  BLEScaleExplorerView.swift
//  SpoolKid
//
//  Purpose: The bench screen for an unknown Bluetooth scale. Find it, connect,
//  subscribe to whatever it pushes, and record the bytes next to the weights
//  its own display is showing. What leaves this screen is a transcript.
//
//  It does not weigh anything itself, and says so: it records what an
//  unknown scale sends so its format can be decoded from the transcript.
//
//  The screen leads with what the bytes MEAN, not with the bytes. The first
//  owner session (2026-09-08) came back with "the output seemed all jibberish
//  to me" — hex is the deliverable, but it is not the interface.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct BLEScaleExplorerView: View {

    @EnvironmentObject private var scale: BLEScaleService
    @State private var markInput = ""
    @State private var showingCamera = false
    @State private var showingRaw = false
    @State private var commandText = ""
    @State private var commandTarget = ""
    @State private var addFraming = true
    @State private var bundleURL: URL?
    @State private var bundleError: String?
    @FocusState private var markFieldFocused: Bool

    /// Newest first. During a capture the interesting bytes are the ones that
    /// just arrived, and scrolling to the bottom of two thousand rows to see
    /// them is not something to do one-handed at a bench.
    private var recentEntries: [BLELogEntry] {
        Array(scale.log.suffix(120).reversed())
    }

    private var rankedDiscoveries: [(discovery: BLEScaleService.Discovery, reason: String?)] {
        scale.discoveries
            .map { discovery -> (BLEScaleService.Discovery, BLEScaleLikelihood, String?) in
                let (level, reason) = BLEScaleHeuristic.rank(name: discovery.name, advertised: discovery.advertised)
                return (discovery, level, reason)
            }
            .sorted { ($0.1, $0.0.rssi) > ($1.1, $1.0.rssi) }
            .map { (discovery: $0.0, reason: $0.2) }
    }

    private var hasMarks: Bool { scale.markTotal > 0 }

    var body: some View {
        Form {
            if let message = scale.availability.message {
                Section {
                    Text(message).font(.body)
                }
            }

            if let error = scale.lastError {
                Section {
                    Text(error)
                        .font(.body)
                        .foregroundStyle(.red)
                }
            }

            // Order is the owner's (2026-09-08): guidance first and visually
            // distinct so nobody hunts for it, then the two things a tester
            // touches — connect, and mark — and only then what the bytes say.
            // Marking used to sit below the analysis and needed a scroll to
            // reach, which is the wrong way round on a scale that goes quiet
            // five seconds after it starts talking.
            stepsSection
            connectionSection
            // Gated on `device`, NOT on `connected`. This scale drops the link
            // every five seconds; gating on the live link tore the section — and
            // the weight field's keyboard focus with it — out from under the
            // tester mid-word (owner, 2026-09-08). A mark needs a capture, not
            // a live radio.
            if scale.device != nil {
                recognitionSection
                captureSection
                typedMarkSection
            }
            if !scale.digests.isEmpty {
                readingSection
            }
            if scale.connected != nil {
                advancedSection
                commandSection
            }
            logSection
        }
        .navigationTitle("Bluetooth Scale")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneBar()
        .onAppear { scale.start() }
        .onDisappear { scale.stopScan() }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCaptureView { data in
                showingCamera = false
                // A cancelled camera does NOT file the mark. The tester asked
                // for a photograph; quietly filing an unverified mark instead
                // would put a number in the transcript they think is backed by
                // evidence and is not.
                if let data { scale.mark(grams: nil, photo: data) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: Binding(
            get: { bundleURL != nil },
            set: { if !$0 { bundleURL = nil } }
        )) {
            if let bundleURL { ActivityShareSheet(url: bundleURL) }
        }
    }

    // MARK: - Actions

    /// The photograph is the evidence; the typed figure is a convenience. A
    /// mark with neither is meaningless, so that one case is refused.
    private func commitMark(photo: Data?) {
        let grams = SpoolWeightMath.parseWeight(markInput)
        guard grams != nil || photo != nil else { return }
        scale.mark(grams: grams, photo: photo)
        markInput = ""
        markFieldFocused = false
    }

    private func packageAndShare() {
        bundleError = nil
        do {
            bundleURL = try scale.makeBundle()
        } catch {
            bundleError = "Could not package the capture: \(error.localizedDescription)"
        }
    }

    /// Says what the capture is worth to someone reading it later. A run of
    /// typed-only marks is not a failure, but it is worth knowing about while
    /// the scale is still on the bench and another mark costs nothing.
    nonisolated static func markSummary(verified: Int, unverified: Int, unmatchable: Int) -> String {
        let total = verified + unverified
        var summary: String
        switch (verified, unverified) {
        case (let v, 0):
            summary = "\(v) mark\(v == 1 ? "" : "s"), all photographed."
        case (0, let u):
            summary = "\(u) mark\(u == 1 ? "" : "s"), none photographed \u{2014} nobody else can check these."
        case (let v, let u):
            summary = "\(v) photographed, \(u) typed only."
        }
        // Said second because it is the one that decides whether the session
        // was worth doing: a mark taken while the scale was silent can never
        // be paired with a reading.
        if unmatchable > 0 {
            summary += unmatchable == total
                ? " None of them can be matched to a reading \u{2014} every one was taken while the scale was silent."
                : " \(unmatchable) of them cannot be matched to a reading."
        }
        return summary
    }

    /// What the tester should do next, from the state alone. The owner asked
    /// for exactly this (2026-09-08): the screen offers a dozen controls and
    /// said nothing about the order they go in.
    /// The one instruction that matters right now.
    ///
    /// The empty pan comes FIRST, before any weight. A scale at rest reads
    /// zero, so the empty reading is what every later reading has to be
    /// compared against — and in four of the owner's eight captures the pan was
    /// never empty, which is exactly why no rule could recover the scale's zero
    /// from them (2026-09-09). It costs ten seconds and it
    /// is worth more than a third weight.
    nonisolated static func nextStep(
        hasDevice: Bool, isScanning: Bool, foundAny: Bool,
        knowsZero: Bool, canDecode: Bool, packets: Int, marks: Int
    ) -> String {
        if !hasDevice && !isScanning { return "1. Switch the scale on, then tap Scan for Scales." }
        if !hasDevice && !foundAny { return "2. Waiting for the scale to appear. Press its button to wake it." }
        if !hasDevice { return "2. Tap the scale in the list below." }
        // Says how to MAKE it talk. This scale sends nothing at all until the
        // weight changes, so a tester waiting politely on an undisturbed pan
        // waits forever (owner's device session, 2026-09-08).
        if packets == 0 { return "3. Take everything off the pan, then press its button or tap the pan — it says nothing until something changes." }
        if !knowsZero { return "4. With the pan EMPTY and the scale settled, tap Pan Is Empty. This is the important one." }
        if canDecode {
            return marks == 0
                ? "5. SpoolKid can read this scale. Put a spool on and check its figure against the display."
                : "6. Tap Share Capture and attach it to a GitHub issue."
        }
        if marks == 0 { return "5. Put a weight on and, once the display settles, tap Photograph the Display." }
        if marks < 3 { return "6. Change the weight and photograph again. Three different weights is the target." }
        return "7. Tap Share Capture and attach it to a GitHub issue."
    }

    /// Shown when a capture has bytes but SpoolKid cannot read them. Listening
    /// harder is not the next step — the owner's scale took four sessions of it
    /// and was settled in one trace of the vendor app.
    nonisolated static let unreadableAdvice = """
        SpoolKid cannot read this scale's weight. More capturing will not \
        change that on its own — the next step is a trace of the manufacturer's \
        own app talking to it, which shows what SpoolKid is missing. Share this \
        capture on GitHub and say so, and you will be sent the procedure.
        """

    // MARK: - Connection

    @ViewBuilder
    private var connectionSection: some View {
        if let connected = scale.connected {
            Section("Connected") {
                VStack(alignment: .leading, spacing: 2) {
                    Text(connected.name).font(.headline)
                    Text(connected.id.uuidString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button("Disconnect") { scale.disconnect() }
            }
        } else if scale.isReconnecting, let device = scale.device {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Waiting for \(device.name)").font(.body)
                        Text("Everything captured so far is kept.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Stop Waiting") { scale.disconnect() }
            } header: {
                Text("Reconnecting")
            } footer: {
                // The honest framing: the app cannot stop a scale powering
                // down, but it can be already attached when it wakes.
                Text("Most kitchen scales power down after a few idle seconds. SpoolKid will reattach on its own — press the scale's button, or put something on it, and the capture continues.")
                    .font(.subheadline)
            }
        } else {
            Section {
                Button(scale.isScanning ? "Stop Scanning" : "Scan for Scales") {
                    if scale.isScanning { scale.stopScan() } else { scale.startScan() }
                }
                .disabled(scale.availability != .ready || scale.isConnecting)

                // Likely scales first, strongest signal within each band.
                // Nothing is hidden: the device worth finding is the one no
                // rule knows about yet.
                ForEach(rankedDiscoveries, id: \.discovery.id) { row in
                    Button {
                        scale.connect(row.discovery)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.discovery.name).font(.body)
                                if let reason = row.reason {
                                    Label(reason, systemImage: "scalemass")
                                        .font(.subheadline)
                                        .foregroundStyle(.tint)
                                } else if !row.discovery.advertised.isEmpty {
                                    Text(row.discovery.advertised.joined(separator: ", "))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(row.discovery.rssi) dBm")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("Nearby")
            } footer: {
                // Strongest signal first, because the scale being set up is the
                // one on the bench in front of the user — not the neighbour's.
                Text(scale.isScanning
                     ? "Strongest signal first. Put the scale in pairing mode if it has one, and turn it on. SpoolKid subscribes to everything the scale offers as soon as it connects — there is nothing to switch on."
                     : "SpoolKid cannot read a weight from a scale yet. This screen finds one and records what it sends, so the format can be worked out.")
                    .font(.subheadline)
            }
        }
    }

    /// First on the screen and deliberately unlike everything under it. A
    /// tester should never have to look for the instruction — it is the one
    /// element on this page that is neither a control nor a number.
    /// Says outright when the exploration is already over. Most testers who
    /// reach this screen have a scale from a family SpoolKid decodes; making
    /// them work through a byte capture to discover that would be a waste of
    /// their bench time.
    @ViewBuilder
    private var recognitionSection: some View {
        Section {
            if let reading = scale.reading {
                VStack(alignment: .leading, spacing: 6) {
                    Label("SpoolKid can read this scale", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(reading.grams) g")
                            .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                        Text(reading.isSettled ? "steady" : "still moving")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("Check that against the scale's own display. If they differ, tap Pan Is Empty with nothing on it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if scale.packetCount > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Not a scale SpoolKid knows", systemImage: "questionmark.circle")
                        .font(.headline)
                    Text(Self.unreadableAdvice)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                scale.markPanEmpty()
            } label: {
                Label("Pan Is Empty", systemImage: "circle.dashed")
            }
            .disabled(!scale.canSetZero)
        }
    }

    private var stepsSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(Self.nextStep(
                    hasDevice: scale.device != nil,
                    isScanning: scale.isScanning,
                    foundAny: !scale.discoveries.isEmpty,
                    knowsZero: scale.knowsZero,
                    canDecode: scale.canDecode,
                    packets: scale.packetCount,
                    marks: scale.markTotal
                ))
                .font(.headline)
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.accentColor.opacity(0.12))
        }
    }

    // MARK: - What the bytes amount to

    /// The answer to "is this the right device, and is anything happening?" —
    /// which is the question a tester actually has in front of a scale, and
    /// the one a hex dump does not answer.
    private var readingSection: some View {
        Section {
            ForEach(scale.digests) { digest in
                VStack(alignment: .leading, spacing: 6) {
                    Text(digest.characteristic)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(digest.headline).font(.body)
                    if let latest = digest.latest {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Now")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(latest)")
                                .font(.system(.largeTitle, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(.tint)
                        }
                    }
                    ForEach(digest.detail, id: \.self) { line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("What the scale is sending")
        } footer: {
            Text(hasMarks
                 ? "Keep going: marks at two or three different weights are what fix the scaling factor."
                 : "Press down on the scale and watch that number. If it moves, it is the reading — now put a known weight on and mark it below. Without at least two marked weights these bytes cannot be turned into grams.")
                .font(.subheadline)
        }
    }

    // MARK: - Known weights

    private var captureSection: some View {
        Section {
            freshnessRow

            // The photograph IS the mark. Nothing typed is attached to it —
            // the owner's third capture proved why: a tester photographs the
            // display and types the number AFTERWARDS, so whatever sat in the
            // field at shutter time belonged to the PREVIOUS weight. Three
            // photographs reading 1254, 1377 and 267 were filed as nothing,
            // 1254 and 1377 (2026-09-08). A number that disagrees with the
            // photograph beside it is worse than no number at all.
            Button {
                markFieldFocused = false
                showingCamera = true
            } label: {
                Label("Photograph the Display", systemImage: "camera.fill")
                    .font(.headline)
            }
            .disabled(!CameraCaptureView.isAvailable)

            let counts = scale.markCounts
            if counts.verified + counts.unverified > 0 {
                Text(Self.markSummary(
                    verified: counts.verified,
                    unverified: counts.unverified,
                    unmatchable: counts.unmatchable
                ))
                .font(.subheadline)
                .foregroundStyle(counts.unmatchable > 0 ? .red : .secondary)
            }
        } header: {
            Text("Mark a weight")
        } footer: {
            Text("Wait for the scale's own display to stop changing, then photograph it. The photograph is the whole record — there is nothing to type.")
                .font(.subheadline)
        }
    }

    /// The keyboard path, for a tester with no camera. Kept apart from the
    /// photograph so a typed figure can never end up attached to a picture of
    /// a different number.
    private var typedMarkSection: some View {
        Section {
            DisclosureGroup("No camera? Type the weight instead") {
                HStack {
                    Text("Scale reads")
                    Spacer()
                    TextField("0", text: $markInput)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($markFieldFocused)
                    Text("g").foregroundStyle(.secondary)
                }
                Button("Mark Without a Photo") {
                    commitMark(photo: nil)
                }
                .disabled(SpoolWeightMath.parseWeight(markInput) == nil)
            }
        } footer: {
            Text("A typed weight is a claim; a photograph is evidence. Typed marks are filed as UNVERIFIED.")
                .font(.subheadline)
        }
    }

    /// Live, and the reason the capture succeeds or fails. Wrapped in a
    /// TimelineView because when the scale goes quiet there is no packet to
    /// redraw the row — and a silence that does not visibly grow is a silence
    /// nobody notices.
    private var freshnessRow: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let since = scale.lastReadingAt.map { context.date.timeIntervalSince($0) }
            let spread = BLETranscript.principalStream(of: scale.log)?.spreadFraction(
                around: context.date, in: scale.log, window: BLETranscript.matchableWindow
            )
            let ready = (since ?? .greatestFiniteMagnitude) <= BLETranscript.matchableWindow
                && (spread ?? 0) <= BLEStreamDigest.steadyFraction
            HStack(spacing: 8) {
                Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Text(freshnessText(since: since, spread: spread))
            }
            .font(.body)
            .foregroundStyle(ready ? Color.green : Color.red)
        }
    }

    private func freshnessText(since: TimeInterval?, spread: Double?) -> String {
        guard let since else { return "The scale has sent nothing yet — a mark now matches nothing." }
        guard since <= BLETranscript.matchableWindow else {
            return String(format: "Silent for %.0fs — wait for it to talk before marking.", since)
        }
        // Near a packet is not enough. Both of the owner's close marks were
        // taken while the load was still being set down, and a reading in
        // motion pairs with nothing.
        if let spread, spread > BLEStreamDigest.steadyFraction {
            return "Reading is still moving — wait for it to settle."
        }
        return "Steady and talking — mark now."
    }

    // MARK: - Services

    /// Collapsed by default. SpoolKid subscribes to everything on connect, so
    /// these switches exist only to turn a chatty characteristic back off —
    /// which is a rare thing to want and a bad thing to lead with.
    private var advancedSection: some View {
        Section {
            DisclosureGroup("Services and subscriptions") {
                if scale.profile.isEmpty {
                    Text("Discovering services…")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                ForEach(scale.profile) { service in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(service.uuid).font(.headline)
                        ForEach(service.characteristics) { characteristic in
                            characteristicRow(characteristic)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } footer: {
            // Said explicitly because the opposite used to be true: every
            // reconnect re-subscribed to everything, so a tester switching
            // one off watched it come back on seconds later (owner,
            // 2026-09-08).
            Text(scale.hasOptOuts
                 ? "Switched-off characteristics stay off, including after the scale hangs up and reconnects."
                 : "SpoolKid subscribes to everything on connect. Switch one off to silence it — the choice survives every reconnect.")
                .font(.subheadline)
        }
    }

    /// Asking, rather than only listening. Four captures established that this
    /// scale's stream does not carry the displayed weight; the remaining
    /// hypothesis is that it answers a request, and that cannot be tested
    /// without a way to send one.
    private var commandSection: some View {
        Section {
            DisclosureGroup("Send bytes to the scale") {
                Picker("To", selection: $commandTarget) {
                    Text("Choose…").tag("")
                    ForEach(writableCharacteristics, id: \.self) { uuid in
                        Text(String(uuid.prefix(8))).tag(uuid)
                    }
                }
                HStack {
                    Text("Hex")
                    Spacer()
                    TextField("A6 04 00", text: $commandText)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("Add header, checksum and trailer", isOn: $addFraming)
                if let preview = commandBytes {
                    Text(BLETranscript.hex(preview))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Button("Send") {
                    if let bytes = commandBytes, !commandTarget.isEmpty {
                        scale.write(bytes, characteristicUUID: commandTarget)
                    }
                }
                .disabled(commandBytes == nil || commandTarget.isEmpty || scale.connected == nil)
            }
        } footer: {
            Text("This scale frames its own messages as A6 … 6A and A7 … 7A, with the second-to-last byte the sum of everything between. The toggle wraps what you type the same way. Whether it answers a request at all is the open question — everything sent and everything that comes back lands in the capture.")
                .font(.subheadline)
        }
    }

    private var writableCharacteristics: [String] {
        scale.profile.flatMap(\.characteristics).filter(\.canWrite).map(\.uuid)
    }

    /// What pressing Send would actually transmit, shown before it is pressed.
    private var commandBytes: Data? {
        guard let payload = BLECommand.parse(commandText) else { return nil }
        guard addFraming else { return payload }
        return BLECommand.framed(payload: payload, header: 0xA6, trailer: 0x6A)
    }

    private func characteristicRow(_ characteristic: BLECharacteristicProfile) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(characteristic.uuid).font(.subheadline)
                Text(characteristic.properties)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if characteristic.canRead {
                Button("Read") { scale.read(characteristicUUID: characteristic.uuid) }
                    .buttonStyle(.bordered)
                    .font(.subheadline)
            }
            if characteristic.canNotify {
                Toggle("", isOn: Binding(
                    get: { characteristic.isNotifying },
                    set: { scale.setNotifying($0, characteristicUUID: characteristic.uuid) }
                ))
                .labelsHidden()
            }
        }
    }

    // MARK: - Capture

    private var logSection: some View {
        Section {
            if scale.log.isEmpty {
                Text("Nothing captured yet.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    packageAndShare()
                } label: {
                    Label("Share Capture", systemImage: "square.and.arrow.up")
                }
                if let bundleError {
                    Text(bundleError)
                        .font(.body)
                        .foregroundStyle(.red)
                }
                Button("Clear Capture", role: .destructive) { scale.clearLog() }

                // Behind a disclosure: the hex is what gets shared and worked
                // out elsewhere, not what a tester reads at the bench.
                DisclosureGroup("Raw packets", isExpanded: $showingRaw) {
                    ForEach(recentEntries) { entry in
                        entryRow(entry)
                    }
                }
            }
        } header: {
            Text("Capture (\(scale.log.count))")
        } footer: {
            if scale.log.count >= BLEScaleService.logCapacity {
                Text("Holding the most recent \(BLEScaleService.logCapacity) entries; older ones have been dropped.")
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: BLELogEntry) -> some View {
        switch entry.content {
        case .packet(let characteristic, let data):
            VStack(alignment: .leading, spacing: 2) {
                Text(BLETranscript.hex(data))
                    .font(.system(.subheadline, design: .monospaced))
                Text("\(characteristic) · \(data.count) B · |\(BLETranscript.ascii(data))|")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .mark(let grams, let photo):
            let principal = BLETranscript.principalStream(of: scale.log)
            let gap = BLETranscript.nearestPacketGap(
                to: entry.at, in: scale.log, on: principal?.characteristic
            )
            let spread = principal?.spreadFraction(
                around: entry.at, in: scale.log, window: BLETranscript.matchableWindow
            )
            let settled = BLETranscript.settledWeight(before: entry.at, in: scale.log)
            let matchable = settled != nil
                || ((gap ?? .greatestFiniteMagnitude) <= BLETranscript.matchableWindow
                    && (spread ?? 0) <= BLEStreamDigest.steadyFraction)
            HStack(spacing: 6) {
                Image(systemName: photo == nil ? "square.and.pencil" : "camera.fill")
                Text(grams.map { "Display read \(SpoolWeightMath.formatWeight($0)) g" } ?? "Display photographed")
                if !matchable {
                    Text("no reading to match")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
            .font(.body)
            .foregroundStyle(.tint)
        case .decoded(let grams):
            // Green, not tinted: this is SpoolKid's own reading, and it must
            // not look like the tester's. Where they disagree, that disagreement
            // is the most valuable line in the capture.
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                Text("SpoolKid reads \(grams) g")
            }
            .font(.body)
            .foregroundStyle(.green)
        case .panEmpty:
            HStack(spacing: 6) {
                Image(systemName: "circle.dashed")
                Text("Pan empty — this is the scale's zero")
            }
            .font(.body)
            .foregroundStyle(.tint)
        case .note(let text):
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
