//
//  WelcomeGuideView.swift
//  SpoolKid
//
//  Purpose: Multi-step welcome guide shown on first launch.
//  Steps:
//  1. Welcome + NFC format selection (full-screen cards with printer brand hints)
//  2. Backend selection (Library / Spoolman / FilaMan) + that backend's
//     connection form (skippable) — delegates to the per-backend forms
//  3. Snapmaker U1 connection (skippable) — the Printer tab appears once set up
//  4. Completion confirmation + how spools are identified (Tag Identity)
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI
import TipKit

struct WelcomeGuideView: View {
    @Binding var hasCompletedWelcome: Bool
    @ObservedObject var spoolManService: SpoolmanService
    @ObservedObject var filaManService: FilaManService

    /// The backend this launch is actually running, from the live
    /// `SpoolDataStore`. The guide WRITES the user's choice but cannot make it
    /// current: `ContentView.init` builds the repository once, before the guide
    /// is ever presented. Step 3 compares the two and says so when they differ,
    /// rather than implying a backend is in use that is not.
    let activeKind: BackendKind

    @AppStorage(AppConfig.nfcTagFormatKey) private var nfcTagFormat: String = TagFormat.openSpool.rawValue
    @AppStorage(AppConfig.tagIdentityModeKey) private var storedIdentityMode: String?

    /// The chosen backend's own validated-connection flag, selected by
    /// capability rather than hardcoded to Spoolman's — the guide is one of the
    /// shared surfaces F34 was about.
    private var availability = BackendAvailability()

    @State private var currentStep = 0
    @State private var selectedFormat: TagFormat = .openSpool
    @State private var selectedBackend: BackendKind = .local
    @State private var showSkipSummary = false
    @EnvironmentObject private var printer: PrinterService
    @AppStorage(AppConfig.printerAddressKey) private var printerAddress = ""
    @State private var printerDraft = ""

    private let totalSteps = 4

    /// Spelled out because `availability` is a private stored property of a
    /// non-property-wrapper type, which would otherwise make the memberwise
    /// initialiser private too.
    init(
        hasCompletedWelcome: Binding<Bool>,
        spoolManService: SpoolmanService,
        filaManService: FilaManService,
        activeKind: BackendKind
    ) {
        _hasCompletedWelcome = hasCompletedWelcome
        _spoolManService = ObservedObject(wrappedValue: spoolManService)
        _filaManService = ObservedObject(wrappedValue: filaManService)
        self.activeKind = activeKind
    }

    private var backendCapabilities: BackendCapabilities { .for(selectedBackend) }

    private var backendIsConnected: Bool { availability.isAvailable(backendCapabilities) }

    /// The guide's answer to "Identify spools by"; Tag Links until picked.
    private var selectedIdentityMode: TagIdentityMode {
        storedIdentityMode.flatMap(TagIdentityMode.init(rawValue:)) ?? .tagLinks
    }

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            stepIndicator
                .padding(.top, 16)
                .padding(.bottom, 8)

            // Step content
            TabView(selection: $currentStep) {
                welcomeStep.tag(0)
                backendStep.tag(1)
                printerStep.tag(2)
                completionStep.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentStep)
        }
        .interactiveDismissDisabled()
        .keyboardDoneBar()
        .onAppear {
            if let format = TagFormat(rawValue: nfcTagFormat) {
                selectedFormat = format
            }
        }
    }

    // MARK: - Copy

    /// Header for the backend step, named for whichever backend is selected.
    static func backendStepTitle(_ capabilities: BackendCapabilities) -> String {
        capabilities.isOnDeviceStorage
            ? "Use This iPhone"
            : "Connect to \(capabilities.displayName)"
    }

    static func backendStepSubtitle(_ capabilities: BackendCapabilities) -> String {
        capabilities.isOnDeviceStorage
            ? "Keep your spools in SpoolKid's own library, right here on this iPhone. No server required."
            : "Manage your filament library on your \(capabilities.displayName) server and write tags from the spools you already have."
    }

    /// One line under each card, describing what picking it means.
    static func backendCardHint(_ capabilities: BackendCapabilities) -> String {
        capabilities.isOnDeviceStorage
            ? "Stored on this iPhone — nothing to set up"
            : "Self-hosted \(capabilities.displayName) server on your network"
    }

    /// The escape from an unconfigured server backend. Named for what it
    /// DOES — the choice it makes is the on-device Library, not an absence of
    /// a choice — rather than "Skip for Now", which described the step being
    /// left instead of the backend being picked (owner feedback, 2026-08-23).
    static var useLocalLibraryLabel: String {
        "Use on-device \(BackendCapabilities.local.displayName)"
    }

    /// Whether the backend step's Continue button is enabled.
    ///
    /// On-device storage needs no connection, so it is always ready. A server
    /// backend is ready only once its connection has actually been validated —
    /// `useLocalLibraryLabel` is the way past an unconfigured server, and it
    /// selects the on-device Library rather than leaving the app pointed at a
    /// server it has never reached.
    nonisolated static func canLeaveBackendStep(
        capabilities: BackendCapabilities, connectionValid: Bool
    ) -> Bool {
        capabilities.isOnDeviceStorage || connectionValid
    }

    /// The completion step's backend row.
    nonisolated static func backendSummaryValue(
        capabilities: BackendCapabilities, connectionValid: Bool
    ) -> String {
        guard !capabilities.isOnDeviceStorage else { return "On this iPhone" }
        return connectionValid ? "Connected" : "Not configured"
    }

    /// Non-nil when the backend the user just picked is not the one this launch
    /// is running, which is every case where they picked anything other than
    /// what `ContentView.init` already resolved. Saying nothing here would be
    /// the guide reporting a switch it did not perform.
    /// The completion step's note when the guide picked a backend that is not
    /// the running one.
    ///
    /// It used to ask the user to close and reopen the app. Since 2026-08-25
    /// `ContentView` rebuilds itself on dismissal instead, so the note says
    /// what will happen rather than what the user must do — a wizard whose
    /// last step assigns homework is a poor first impression, and the homework
    /// is no longer necessary.
    nonisolated static func backendActivationNote(chosen: BackendKind, active: BackendKind) -> String? {
        guard chosen != active else { return nil }
        return "\(BackendCapabilities.for(chosen).displayName) will be ready as soon as you finish here."
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep ? Color.accentColor : Color(.systemGray4))
                    .frame(width: index == currentStep ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentStep)
            }
        }
    }

    // MARK: - Step 1: Welcome + NFC Format

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image("SpoolKidLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .padding(.bottom, 4)
                        Text("Welcome to SpoolKid")
                            .font(.largeTitle.bold())
                        Text("Your NFC filament tag companion. Choose the tag format that matches your printer.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.top, 16)

                    // Format cards
                    VStack(spacing: 12) {
                        ForEach(TagFormat.allCases) { format in
                            FormatCard(
                                format: format,
                                isSelected: selectedFormat == format
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedFormat = format
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }

            // Continue button
            Button {
                nfcTagFormat = selectedFormat.rawValue
                withAnimation { currentStep = 1 }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Step 2: Backend

    private var backendStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: backendCapabilities.tabSymbol)
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)
                            .padding(.bottom, 4)
                        Text(Self.backendStepTitle(backendCapabilities))
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text(Self.backendStepSubtitle(backendCapabilities))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.top, 16)

                    // Backend cards
                    VStack(spacing: 12) {
                        ForEach(BackendKind.allCases, id: \.self) { kind in
                            let capabilities = BackendCapabilities.for(kind)
                            ChoiceCard(
                                title: capabilities.displayName,
                                hint: Self.backendCardHint(capabilities),
                                isSelected: selectedBackend == kind
                            ) {
                                Image(systemName: capabilities.tabSymbol)
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                            } action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedBackend = kind
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    // The selected backend's connection form, or — for the
                    // on-device Library, which has nothing to connect to — the
                    // same expectations the Skip dialog sets, shown up front.
                    switch selectedBackend {
                    case .local:
                        localModeDisclosure
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    case .spoolman:
                        SpoolmanConnectionForm(spoolManService: spoolManService)
                            .padding(.horizontal, 20)
                    case .filaman:
                        FilaManConnectionForm(filaManService: filaManService)
                            .padding(.horizontal, 20)
                    }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        // Pinned as a safe-area inset rather than a sibling in a VStack: the
        // step's content now ends in a connection form whose own Test
        // Connection button landed UNDERNEATH this bar, unreachable without
        // scrolling past it. An inset reserves its height in the scroll
        // content, so the last control is always clear of it.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    commitBackendChoice(selectedBackend)
                    withAnimation { currentStep = 2 }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!Self.canLeaveBackendStep(
                    capabilities: backendCapabilities,
                    connectionValid: backendIsConnected
                ))

                if !backendCapabilities.isOnDeviceStorage {
                    Button {
                        showSkipSummary = true
                    } label: {
                        Text(Self.useLocalLibraryLabel)
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 16)
            .background(.bar)
        }
        .confirmationDialog(
            "Using SpoolKid without \(backendCapabilities.displayName)",
            isPresented: $showSkipSummary,
            titleVisibility: .visible
        ) {
            Button("Continue") {
                // Skipping is a choice of the on-device Library, not an absence
                // of one: leaving the stored kind on a server that was never
                // reached is what the F37 dead-end screen was about.
                selectedBackend = .local
                commitBackendChoice(.local)
                withAnimation { currentStep = 2 }
            }
            Button("Connect Instead", role: .cancel) { }
        } message: {
            localModeDisclosure
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var localModeDisclosure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalModeCopy.storageExplanation)
            Text(LocalModeCopy.capSummary)
            Text(LocalModeCopy.notAReplacement)
            Text(LocalModeCopy.dataLossDisclaimer)
        }
    }

    /// Stores the picked backend. Written here — on an explicit Continue or
    /// Skip — rather than on every card tap, so browsing the options never
    /// changes what the next launch opens.
    private func commitBackendChoice(_ kind: BackendKind) {
        UserDefaults.standard.set(kind.rawValue, forKey: AppConfig.backendKindKey)
    }

    // MARK: - Step 3: Printer

    /// What the printer step says about the connection, or nil before one is tried.
    nonisolated static func printerStatusText(_ connection: PrinterConnection) -> String? {
        switch connection {
        case .notConfigured: nil
        case .connecting: "Connecting…"
        case .online: "Connected. The Printer tab is ready."
        case .needsSignIn: "Your printer wants a sign-in. You can sign in on the Printer tab."
        case .offline(let reason): reason
        }
    }

    private var printerStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "printer")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                        .padding(.bottom, 4)
                    Text("Connect Your Snapmaker U1")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("See what each toolhead holds and load Library spools into them from the Printer tab. SpoolKid talks to the printer over your local network, with no pairing.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 12) {
                    ServerAddressField(placeholder: "http://192.168.1.50", text: $printerDraft)
                    Button("Connect") {
                        printerAddress = printerDraft
                        Task { await printer.connect() }
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .disabled(!ServerAddress.isUsable(printerDraft))
                    if let status = Self.printerStatusText(printer.connection) {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(printer.connection == .online ? Color.secondary : Color.orange)
                    }
                    Text("Enter your printer's IP address or host name. You can skip this and set it up later in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button {
                withAnimation { currentStep = 3 }
            } label: {
                Text(PrinterService.isConfigured(address: printerAddress) ? "Continue" : "Skip for Now")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 16)
            .background(.bar)
        }
        .onAppear { if printerDraft.isEmpty { printerDraft = printerAddress } }
    }

    // MARK: - Step 4: Completion

    private var completionStep: some View {
        VStack(spacing: 0) {
            // Scrolls, centred when short. The on-device disclosure plus the
            // identity picker is taller than a phone screen, and a plain
            // VStack truncated the data-loss disclaimer to fit.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.accentColor)

                        Text("You're All Set!")
                            .font(.largeTitle.bold())

                        VStack(spacing: 12) {
                            summaryRow(
                                icon: "dot.radiowaves.left.and.right",
                                label: "Tag Format",
                                value: selectedFormat.displayName
                            )
                            summaryRow(
                                icon: backendCapabilities.tabSymbol,
                                label: "Library",
                                value: Self.backendSummaryValue(
                                    capabilities: backendCapabilities,
                                    connectionValid: backendIsConnected
                                )
                            )
                            summaryRow(
                                icon: "printer",
                                label: "Printer",
                                value: PrinterService.isConfigured(address: printerAddress) ? "Snapmaker U1" : "Not set up"
                            )
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 8)

                        VStack(alignment: .leading, spacing: 6) {
                            // The whole row is the menu's label, so the tap target
                            // is the row (at least 44 pt), not the ~34 pt value a
                            // bare menu picker draws. The value never wraps: a
                            // two-line value drew over the line below it.
                            Menu {
                                Picker("Identify spools by", selection: Binding(
                                    get: { selectedIdentityMode },
                                    set: { storedIdentityMode = $0.rawValue }
                                )) {
                                    ForEach(TagIdentityMode.allCases, id: \.self) { Text($0.label).tag($0) }
                                }
                            } label: {
                                HStack {
                                    // `Color.secondary`, not `.secondary`: inside a
                                    // menu label the latter derives from the tint.
                                    Text("Identify spools by")
                                        .foregroundStyle(Color.secondary)
                                    Spacer()
                                    Text(selectedIdentityMode.label)
                                        .lineLimit(1)
                                        .fixedSize()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.footnote)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            Text(TagStoreText.welcomeModeLine(selectedIdentityMode, capabilities: backendCapabilities))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 32)

                        if let note = Self.backendActivationNote(chosen: selectedBackend, active: activeKind) {
                            Label(note, systemImage: "checkmark.circle")
                                .font(.subheadline)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 32)
                        }

                        Text("You can change the tag format and the printer anytime in Settings, and the library and how spools are identified in Library → \(backendCapabilities.connectionRowLabel). Contextual tips will help you discover features as you explore.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        if backendCapabilities.isOnDeviceStorage {
                            localModeDisclosure
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 32)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicatorsFlash(onAppear: true)
            }

            Button {
                hasCompletedWelcome = true
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Helpers

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Choice Card

/// The selectable full-width card both choosing steps are built from: a 44pt
/// icon well, a title, a hint line, and a selection check. Shared so the tag
/// format and backend steps cannot drift apart visually.
private struct ChoiceCard<Icon: View>: View {
    let title: String
    let hint: String
    let isSelected: Bool
    @ViewBuilder let icon: Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                icon
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Color.accentColor.opacity(0.12) : Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.systemGray3))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color(.systemGray4), lineWidth: isSelected ? 2 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Format Card

private struct FormatCard: View {
    let format: TagFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        ChoiceCard(
            title: format.displayName,
            hint: printerHint,
            isSelected: isSelected
        ) {
            formatSymbol
        } action: {
            action()
        }
    }

    /// One plain symbol for every format: the card's title names it, and a
    /// format's logo is its owner's mark, and SpoolKid uses none.
    private var formatSymbol: some View {
        Image(systemName: "tag")
            .font(.title3)
            .foregroundStyle(Color.accentColor)
    }

    private var printerHint: String {
        switch format {
        case .openSpool:
            return "Snapmaker U1 with community firmware and other OpenSpool-compatible printers"
        case .openPrintTag:
            return "Prusa printers and OpenPrintTag-compatible tools"
        case .openTag3D:
            return "Community standard for 3D printing NFC tags"
        case .anycubicACE:
            return "Anycubic ACE Pro spool holder"
        case .elegoo:
            return "ELEGOO FDM 3D printers with RFID spool recognition"
        case .tigerTag:
            return "eSun, Sunlu, Rosa3D and other TigerTag-compatible brands and readers"
        }
    }
}
