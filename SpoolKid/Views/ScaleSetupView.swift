//
//  ScaleSetupView.swift
//  SpoolKid
//
//  Purpose: The one place a Bluetooth scale is set up. Choose it once here and
//  every weighing screen uses it without asking again — a household owns one
//  kitchen scale, and picking it per spool was the friction the owner reported
//  (2026-09-09).
//
//  Three states, one at a time, because a setup screen is scanned and not read:
//  CHOOSING (two numbered steps and the list), TRYING (one instruction — put a
//  weight on — and no list), and either a paired scale or a step-by-step way to
//  contribute a capture of the one SpoolKid could not read.
//
//  Setting up succeeds when SpoolKid reads a weight, not when it connects.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct ScaleSetupView: View {

    @EnvironmentObject private var scale: BLEScaleService
    @AppStorage(AppConfig.diagnosticsEnabledKey) private var diagnosticsEnabled = false
    @State private var confirmingForget = false
    /// The scale on the bench is not always the scale that was set up — it may
    /// have been replaced, or the system may have forgotten the peripheral. The
    /// list is hidden while a working scale is paired and one tap away when it
    /// is not working.
    @State private var choosingAnother = false
    /// The scale being tried right now. While this is set the list is gone and
    /// the screen asks for one thing only.
    @State private var trying: BLEScaleService.Discovery?
    /// How the trial ended, when it ran out of time. Only then is anything
    /// asked of the user: a scale that has not been given a weight yet is not a
    /// scale that failed.
    ///
    /// The two cases need opposite advice, so they are not one case. A scale
    /// that was never reached is probably switched off; only a scale that
    /// talked and could not be understood is worth a capture.
    private enum Failure { case unreachable, unreadable }
    @State private var failure: Failure?
    /// Whether the link was ever up during this trial. Not `scale.connected`,
    /// which is a live answer: this scale family hangs up every few seconds, so
    /// at the moment of the deadline a working scale is usually disconnected.
    @State private var everConnected = false

    /// How long a scale gets to produce a weight before SpoolKid says it
    /// cannot. Long enough to switch it back on and fetch a spool — this scale
    /// family powers itself down after a few idle seconds, so a short deadline
    /// would condemn a working scale for being asleep.
    private static let giveUpAfter: TimeInterval = 45

    var body: some View {
        Form {
            if let message = scale.availability.message {
                Section { Text(message) }
            }

            if scale.paired != nil && trying == nil {
                pairedSection
            }

            if let trying {
                tryingSection(trying)
            }

            switch failure {
            case .unreadable: unreadableSection
            case .unreachable: unreachableSection
            case nil: EmptyView()
            }

            if showsList {
                if scale.paired == nil && failure == nil { stepsSection }
                discoverySection
            }
        }
        .navigationTitle("Bluetooth Scale")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            scale.start()
            // A paired scale is reconnected, not re-chosen. Scanning is for the
            // case where there is nothing to reconnect to.
            if scale.paired == nil { scale.startScan() } else { scale.ensureConnected() }
        }
        .onDisappear { scale.stopScan() }
        // Pairing completes on a decoded weight, which arrives from the radio
        // rather than from anything the user tapped — so success is observed,
        // not returned.
        .onChange(of: scale.paired) { _, new in
            guard new != nil else { return }
            trying = nil
            failure = nil
        }
        .onChange(of: scale.connected) { _, new in
            if new != nil { everConnected = true }
        }
        .task(id: trying?.id) {
            guard trying != nil else { return }
            try? await Task.sleep(for: .seconds(Self.giveUpAfter))
            guard !Task.isCancelled, trying != nil else { return }
            trying = nil
            failure = everConnected ? .unreadable : .unreachable
            scale.startScan()
        }
        .confirmationDialog(
            "Forget \(scale.paired?.name ?? "this scale")?",
            isPresented: $confirmingForget,
            titleVisibility: .visible
        ) {
            Button("Forget Scale", role: .destructive) {
                scale.unpair()
                // Straight back to a list, not to an empty screen with no way
                // forward: forgetting a scale is usually the first half of
                // setting a different one up.
                scale.startScan()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The weighing screens stop offering a scale until you set one up again. What it calls zero is remembered, so setting the same scale up again takes no relearning.")
        }
    }

    /// The list is for choosing, and choosing is not what any of the other
    /// states are for.
    private var showsList: Bool {
        trying == nil && (scale.paired == nil || choosingAnother)
    }

    // MARK: - Choosing

    private var stepsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label("Turn ON the scale (empty)", systemImage: "1.circle.fill")
                Label("Choose your scale on the list below", systemImage: "2.circle.fill")
            }
            .font(.headline)
            .padding(.vertical, 4)
        }
    }

    private var discoverySection: some View {
        Section {
            if named.isEmpty {
                Text(scale.isScanning ? "Looking…" : "Nothing found yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(named, id: \.discovery.id) { row($0) }

            if !unnamed.isEmpty {
                DisclosureGroup("Devices with no name (\(unnamed.count))") {
                    ForEach(unnamed, id: \.discovery.id) { row($0) }
                }
                .font(.subheadline)
            }
        } header: {
            Text(scale.isScanning ? "Scanning…" : "Found")
        }
    }

    private func row(_ entry: (discovery: BLEScaleService.Discovery, reason: String?)) -> some View {
        Button {
            choosingAnother = false
            failure = nil
            everConnected = false
            trying = entry.discovery
            scale.connect(entry.discovery)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.discovery.name)
                if let reason = entry.reason {
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Trying one

    private func tryingSection(_ discovery: BLEScaleService.Discovery) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Place a weight on your scale to finalize pairing")
                    .font(.headline)
                Text(tryingStatus(discovery))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            Button("Choose a Different Scale") {
                trying = nil
                scale.startScan()
            }
            .buttonStyle(.borderless)
        }
    }

    private func tryingStatus(_ discovery: BLEScaleService.Discovery) -> String {
        if scale.isConnecting { return "Connecting to \(discovery.name)…" }
        if scale.isReconnecting { return "\(discovery.name) went quiet — waiting for it to wake." }
        if scale.connected != nil { return "Connected to \(discovery.name)." }
        return "Waiting for \(discovery.name)."
    }

    // MARK: - Paired

    @ViewBuilder
    private var pairedSection: some View {
        Section {
            HStack {
                Label(scale.paired?.name ?? "Scale", systemImage: "scalemass")
                Spacer()
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let reading = scale.reading {
                HStack {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text("\(reading.grams) g")
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                    Spacer()
                    Text(reading.isSettled ? "steady" : "moving")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Learned by watching the scale rest, so this is a correction and
            // not a step. It is here rather than on the weighing screens for
            // the same reason the whole screen exists: setting a scale up is
            // not something to do with a spool in one hand.
            if scale.canSetZero {
                Button("Pan Is Empty — Zero It") { scale.setZeroToCurrentReading() }
                    .buttonStyle(.borderless)
            }

            if !choosingAnother {
                Button("Choose a Different Scale") {
                    choosingAnother = true
                    scale.startScan()
                }
                .buttonStyle(.borderless)
            }

            Button("Forget This Scale", role: .destructive) { confirmingForget = true }
                .buttonStyle(.borderless)
        } header: {
            Text("Your Scale")
        } footer: {
            Text(scale.knowsZero
                 ? "Ready. Take a weight in Weigh Spools, or on any spool's Measured Weight."
                 : "Take everything off the pan — SpoolKid is learning what this scale calls zero.")
                .font(.subheadline)
        }
    }

    // MARK: - The one that could not be read

    /// Reached only after the trial ran out of time, and written as steps
    /// because every one of them is a thing to do somewhere else in iOS. Each
    /// step is its own row: a Form row holding text AND a control collapses
    /// into one tap target and the control never fires.
    private var unreadableSection: some View {
        Section {
            if diagnosticsEnabled {
                Label("Help Improve SpoolKid is on", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            } else {
                Button { openAppSettings() } label: {
                    Label("Switch on Help Improve SpoolKid", systemImage: "1.circle.fill")
                }
                .buttonStyle(.borderless)
            }
            Label("Tap the bug button on Tags or Library, then Bluetooth Scale", systemImage: "2.circle.fill")
            // Points at the explorer's own steps instead of restating them.
            // This line said "record it with a weight on" for one commit, which
            // skipped the EMPTY pan — the step four of the owner's eight
            // captures missed, and the one that makes a capture decodable at
            // all. A procedure written twice drifts, so it is written once, in
            // `BLEScaleExplorerView.nextStep`.
            Label("Follow its steps — the empty pan comes first, and it matters most", systemImage: "3.circle.fill")
            Link(destination: DiagnosticsHubView.issuesURL) {
                Label("Send it in a GitHub issue", systemImage: "4.circle.fill")
            }
        } header: {
            Text("Not Readable Yet")
        } footer: {
            Text("SpoolKid could not read a weight from that scale. A recording of it is what makes support for it possible — nothing is sent automatically, and every capture ends at a Share sheet you drive.")
                .font(.subheadline)
        }
    }

    private var unreachableSection: some View {
        Section {
            // Names the control that is actually on screen. With a scale
            // already paired the list is not shown — the way back is the button
            // in the section above — and pointing at a list that is not there
            // is the same defect as a button that does nothing.
            Text(scale.paired == nil
                 ? "SpoolKid never reached that scale. Switch it on, keep it close to the phone, and choose it again from the list below."
                 : "SpoolKid never reached that scale. Switch it on, keep it close to the phone, and tap Choose a Different Scale above to retry.")
        } header: {
            Text("No Answer")
        }
    }

    // MARK: - Detail

    /// Never filtered, only ranked — the scale that matters may be the one no
    /// rule recognises.
    ///
    /// Ordered by likelihood, then by signal strength — the scale being set up
    /// is the one on the bench in front of the user, so nearest-first is the
    /// right order. The strength is a three-second mean (`RollingRSSI`), not a
    /// single reading: a raw RSSI wanders several dB between advertisements and
    /// made the rows trade places under the user's thumb. First-seen breaks a
    /// remaining tie, because `sorted(by:)` is not a stable sort and two
    /// equal-strength rows would otherwise swap for no reason at all.
    private var ranked: [(discovery: BLEScaleService.Discovery, reason: String?)] {
        scale.discoveries
            .enumerated()
            .map { index, discovery -> (Int, BLEScaleService.Discovery, BLEScaleLikelihood, String?) in
                let (level, reason) = BLEScaleHeuristic.rank(name: discovery.name, advertised: discovery.advertised)
                return (index, discovery, level, reason)
            }
            .sorted { left, right in
                if left.2 != right.2 { return left.2 > right.2 }
                if left.1.rssi != right.1.rssi { return left.1.rssi > right.1.rssi }
                return left.0 < right.0
            }
            .map { (discovery: $0.1, reason: $0.3) }
    }

    /// Peripherals that have not said what they are. Kept, but folded away:
    /// a bench is surrounded by anonymous radios, and none of them is the
    /// scale — except on the day one is, which is why this collapses rather
    /// than filters.
    private var named: [(discovery: BLEScaleService.Discovery, reason: String?)] {
        ranked.filter { $0.discovery.name != BLEScaleService.Discovery.unnamed }
    }

    private var unnamed: [(discovery: BLEScaleService.Discovery, reason: String?)] {
        ranked.filter { $0.discovery.name == BLEScaleService.Discovery.unnamed }
    }

    private var statusText: String {
        if scale.isConnecting { return "connecting…" }
        if scale.isReconnecting { return "waiting for it" }
        if scale.connected != nil { return scale.canDecode ? "reading" : "connected" }
        return "not connected"
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
