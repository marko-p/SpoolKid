//
//  TagsTabView.swift
//  SpoolKid
//
//  Purpose: The "Tags" tab content — NFC tag creation and recent tags management.
//  Features:
//  - "Write Tag" section with "From <active backend>" and Manual options.
//  - "Recent Tags" section with swipe-to-delete and quick re-use.
//  - "Scan Label" (camera: label OCR + QR) and "Scan Tag" (NFC) as icons in a
//    floating bottom bar.
//  - Programmatic navigation to WriteTagView after an NFC scan.
//  - Settings button in the toolbar.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI
import TipKit
import UIKit

struct TagsTabView: View {
    @ObservedObject var nfcManager: NFCManager
    @EnvironmentObject private var store: SpoolDataStore
    @EnvironmentObject private var printer: PrinterService
    @StateObject private var recentTagManager = RecentTagManager()

    /// Spelled out because the synthesized memberwise initializer would inherit
    /// the `private` of the stored properties below and stop `ContentView` from
    /// constructing this view.
    init(nfcManager: NFCManager) {
        _nfcManager = ObservedObject(wrappedValue: nfcManager)
    }

    /// Which reader Scan Tag uses. Never stored.
    @State private var tagReader: TagReader = .iPhone
    /// The reader the scan in flight runs on, fixed when it starts.
    @State private var scanRun = TagReaderRun()

    /// The ACTIVE backend's validated-connection flag.
    private var availability = BackendAvailability()

    /// Gates the "create a tag from an existing spool" row, which reads rows
    /// out of the active backend. The local store always qualifies — it
    /// declares no connection flag.
    private var isBackendAvailable: Bool {
        availability.isAvailable(store.capabilities)
    }

    @State private var showSettings = false
    @AppStorage(AppConfig.diagnosticsEnabledKey) private var diagnosticsEnabled = false
    @State private var showDiagnostics = false
    @State private var navigateToWriteFromScan = false
    @State private var navigateToScanHub = false
    @State private var scannedTagData: FilamentTagData? = nil
    @State private var scannedCardUID: String? = nil
    @State private var scanResult: ScanResult? = nil
    @State private var scanPulseScale: CGFloat = 1.0
    @State private var scanPulseOpacity: Double = 0.0

    @State private var cameraSheetRoute: CameraSheetRoute = .none

    /// The launch screen's four first-run tips, one at a time. An ordered
    /// group makes a tip current only after the one before it is closed (✕)
    /// or invalidated by using the feature; tapping outside only hides it.
    /// So two popovers never compete for the screen (audit T1). A new group
    /// is built with the view when `ContentView`'s `tipRefreshToken` changes
    /// after onboarding.
    @State private var tips = TipGroup(.ordered) {
        ScanTagTip()
        ScanLabelTip()
        WriteTagTip()
        AboutTip()
    }

    /// True while the root shows a launch-time sheet: popovers present above
    /// sheets, so all four tips are withheld until it is gone.
    @Environment(\.hidesFirstRunTips) private var hidesFirstRunTips

    /// False while a screen is pushed over the tab's root, or the tab is off
    /// screen. A tip can become current then — leaving a Write Tag screen
    /// opened from the hub makes the Settings tip (AboutTip) current — and its
    /// popover, anchored on this root, would present over the pushed screen,
    /// pointing at that screen's own toolbar button.
    @State private var isRootOnScreen = false

    private var showsFirstRunTips: Bool {
        isRootOnScreen && !hidesFirstRunTips
    }

    enum CameraSheetRoute: Equatable {
        case none
        case smartScanner
    }

    enum SmartScannerAction {
        case scanHub(ScanResult)
        case invalidQRCode
    }

    struct SmartScannerTraceEvent: Equatable {
        let step: String
        let details: [String: String]
    }

    static func smartScannerAction(
        for output: UnifiedSmartScanOutput,
        spoolmanURL: String = UserDefaults.standard.string(forKey: AppConfig.spoolmanUrlKey) ?? "",
        filamanURL: String = UserDefaults.standard.string(forKey: AppConfig.filamanUrlKey) ?? ""
    ) -> SmartScannerAction {
        switch output {
        case .qr(let payload):
            if let label = BackendLabel.parse(payload, spoolmanURL: spoolmanURL, filamanURL: filamanURL) {
                var result = ScanResult(cardUID: nil, tagData: nil, format: .backendLabel, url: URL(string: payload))
                result.backendLabel = label
                return .scanHub(result)
            }
            if let url = validatedWebURL(from: payload) {
                return .scanHub(
                    ScanResult(
                        cardUID: nil,
                        tagData: nil,
                        format: .webUrl,
                        rawPageLogBytes: nil,
                        url: url
                    )
                )
            }
            return .invalidQRCode
        case .ocr(let candidate):
            // Skip OCRReviewView and go directly to ScanResultHubView
            let tagData = convertCandidateToTagData(candidate)
            let scanResult = ScanResult(
                cardUID: nil,
                tagData: tagData,
                format: .ocr,
                ocrSerialNumber: candidate.serialNumber,
                ocrDiameterMM: candidate.diameterMM,
                ocrFilamentName: candidate.filamentName,
                ocrSubtype: candidate.subtype,
                ocrNominalNetWeightG: candidate.netWeightG.map { Double($0) },
                ocrCandidate: candidate
            )
            return .scanHub(scanResult)
        }
    }
    
    private static func convertCandidateToTagData(_ candidate: OCRParsedCandidate) -> FilamentTagData {
        return FilamentTagData(
            name: candidate.filamentName,
            material: candidate.material ?? "PLA",
            subtype: candidate.subtype,
            brand: candidate.brand ?? "Unknown",
            colorHex: candidate.colorHex ?? "FFFFFF",
            minNozzleTemp: candidate.minNozzleTemp ?? 200,
            maxNozzleTemp: candidate.maxNozzleTemp ?? 220,
            minBedTemp: candidate.minBedTemp ?? 60,
            maxBedTemp: candidate.maxBedTemp ?? 60,
            nominalNetWeight: candidate.netWeightG.map { Double($0) }
        )
    }

    static func smartScannerSelectionTraceEvent(for action: SmartScannerAction) -> SmartScannerTraceEvent {
        switch action {
        case .scanHub(let result):
            if result.format == .ocr {
                let lineCount = result.ocrCandidate?.rawLines.count ?? 0
                return SmartScannerTraceEvent(step: SmartScanTelemetryContract.arbitrationSelected, details: [
                    "type": "ocr",
                    "lineCount": String(lineCount)
                ])
            }
            return SmartScannerTraceEvent(step: SmartScanTelemetryContract.arbitrationSelected, details: [
                "type": "qr"
            ])
        case .invalidQRCode:
            return SmartScannerTraceEvent(step: SmartScanTelemetryContract.arbitrationSelected, details: [
                "type": "qr-invalid"
            ])
        }
    }

    static func smartScannerTraceStep(forStatus status: String) -> String? {
        SmartScanTelemetryContract.statusSteps.contains(status) ? status : nil
    }

    private static func validatedWebURL(from payload: String) -> URL? {
        guard let components = URLComponents(string: payload),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = components.host,
              !host.isEmpty,
              let url = components.url else {
            return nil
        }
        return url
    }

    static func cameraSheetRoute(forReviewOutcome outcome: OCRReviewOutcome) -> CameraSheetRoute? {
        switch outcome {
        case .retakeSmartScan:
            return .smartScanner
        default:
            return nil
        }
    }



    enum ScanCompletionRoute: Equatable {
        case scanHub
        case writeTag
        case none
    }

    /// `hasLocationTag` is deliberately the FIRST question and has no default:
    /// a location tag has no filament write path at all, so routing it to
    /// `WriteTagView` opens a blank write form armed with the shelf tag's UID
    /// and ledgers that tag to a spool on save. The hub is its only correct
    /// destination.
    ///
    /// Anything the scanner actually resolved goes to the hub too. This used to
    /// read `persistCardUID ? .scanHub : .writeTag`, which predated the
    /// 2026-08-25 "keep + explain" work: the hub rendered every mapping
    /// action with a hint that SpoolLink was off and the mapping would not be
    /// stored (since replaced by hiding link controls outside Tag Links). With
    /// the hub safe in every state, bypassing it only cost the user the
    /// answer — a tag that resolved to a spool went straight to a write form
    /// that never said which spool it had matched (bench pass 2026-09-04).
    ///
    /// `.writeTag` survives for the legacy path alone: tag data with no
    /// `ScanResult` has nothing for the hub to resolve.
    static func scanCompletionRoute(
        hasScanResult: Bool,
        hasLegacyData: Bool,
        hasLocationTag: Bool
    ) -> ScanCompletionRoute {
        if hasLocationTag {
            return .scanHub
        }
        if hasScanResult {
            return .scanHub
        }
        if hasLegacyData {
            return .writeTag
        }
        return .none
    }

    var body: some View {
        NavigationStack {
            contentView
            .safeAreaInset(edge: .top, spacing: 0) { ServerDownBanner() }
            .navigationTitle("Tags")
            .toolbar {
                // Opposite the Settings button: the bug is the way IN to the
                // experiments, the cog the way in to SpoolKid's settings.
                // Absent entirely unless the user has opted in — an ordinary
                // user has nothing to do behind it.
                if diagnosticsEnabled {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: { showDiagnostics = true }) {
                            Image(systemName: "ladybug")
                        }
                        .accessibilityLabel("Help Improve SpoolKid")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        // Using the feature retires its tip; a tap outside
                        // the popover only hides it until the tab reappears.
                        AboutTip().invalidate(reason: .actionPerformed)
                        showSettings = true
                    }) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .popoverTip(showsFirstRunTips ? tips.currentTip as? AboutTip : nil, arrowEdge: .top)
                }
            }
            .navigationDestination(isPresented: $showDiagnostics) {
                DiagnosticsHubView(nfcManager: nfcManager)
            }
            .navigationDestination(isPresented: $navigateToScanHub) {
                if let result = scanResult {
                    ScanResultHubView(result: result)
                }
            }
            .navigationDestination(isPresented: $navigateToWriteFromScan) {
                WriteTagView(initialData: scannedTagData, scannedCardUID: scannedCardUID)
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: Binding<Bool>(
                get: { cameraSheetRoute != .none },
                set: { if !$0 { cameraSheetRoute = .none } }
            )) {
                switch cameraSheetRoute {
                case .smartScanner:
                    UnifiedSmartScannerView(
                        onOutput: { output, imageData in
                            cameraSheetRoute = .none
                            let action = Self.smartScannerAction(for: output)
                            let event = Self.smartScannerSelectionTraceEvent(for: action)
                            WorkflowTraceStore.log(path: "smart-scan", step: event.step, details: event.details)

                            switch action {
                            case .scanHub(var result):
                                if result.format == .ocr {
                                    result.ocrCapturedImageData = imageData
                                }
                                scanResult = result
                                navigateToScanHub = true
                            case .invalidQRCode:
                                nfcManager.alertMessage = "Invalid QR Code format"
                            }
                        },
                        onCancel: {
                            cameraSheetRoute = .none
                        },
                        onStatus: { status in
                            if let step = Self.smartScannerTraceStep(forStatus: status) {
                                WorkflowTraceStore.log(path: "smart-scan", step: step)
                            }
                        }
                    )
                    .edgesIgnoringSafeArea(.all)
                case .none:
                    EmptyView()
                }
            }
            .onAppear {
                isRootOnScreen = true
                recentTagManager.refresh()
                Task { await store.fetchSpools() }
            }
            .onDisappear { isRootOnScreen = false }
            .onChange(of: nfcManager.isScanning) { _, isScanning in
                if isScanning {
                    WorkflowTraceStore.log(path: "tags", step: "scan-state.started")
                    startScanPulse()
                } else {
                    WorkflowTraceStore.log(path: "tags", step: "scan-state.stopped")
                    // The shared manager also scans for other tabs; the run is this screen's alone.
                    scanRun = TagReaderRun()
                    stopScanPulse()

                    let route = Self.scanCompletionRoute(
                        hasScanResult: nfcManager.scanResult != nil,
                        hasLegacyData: nfcManager.scannedData != nil,
                        hasLocationTag: nfcManager.scanResult?.locationTag != nil
                    )

                    WorkflowTraceStore.log(path: "tags", step: "scan-route.decided", details: [
                        "hasScanResult": String(nfcManager.scanResult != nil),
                        "hasLegacyData": String(nfcManager.scannedData != nil),
                        "hasLocationTag": String(nfcManager.scanResult?.locationTag != nil),
                        "route": String(describing: route)
                    ])

                    switch route {
                    case .scanHub:
                        if let result = nfcManager.scanResult {
                            WorkflowTraceStore.log(path: "tags", step: "scan-route.to-hub", details: [
                                "format": result.format?.displayName ?? "",
                                "hasURL": String(result.url != nil),
                                "hasTagData": String(result.tagData != nil),
                                "cardUID": result.cardUID ?? ""
                            ])
                            scanResult = result
                            navigateToScanHub = true
                        }
                    case .writeTag:
                        WorkflowTraceStore.log(path: "tags", step: "scan-route.to-write-tag", details: [
                            "scanResultTagData": String(nfcManager.scanResult?.tagData != nil),
                            "legacyTagData": String(nfcManager.scannedData != nil)
                        ])
                        scannedTagData = nfcManager.scanResult?.tagData ?? nfcManager.scannedData
                        scannedCardUID = nfcManager.scanResult?.cardUID
                        navigateToWriteFromScan = true
                    case .none:
                        WorkflowTraceStore.log(path: "tags", step: "scan-route.none")
                        break
                    }
                }
            }
            .onChange(of: navigateToScanHub) { _, isNavigating in
                if !isNavigating {
                    WorkflowTraceStore.log(path: "tags", step: "scan-hub.dismissed")
                    scanResult = nil
                    nfcManager.scanResult = nil
                }
            }
            .onChange(of: navigateToWriteFromScan) { _, isNavigating in
                if !isNavigating {
                    scannedTagData = nil
                    scannedCardUID = nil
                    nfcManager.scannedData = nil
                }
            }
            .alert(isPresented: Binding<Bool>(
                get: { !nfcManager.alertMessage.isEmpty },
                set: { _ in nfcManager.alertMessage = "" }
            )) {
                Alert(title: Text("NFC Error"), message: Text(nfcManager.alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        List {
            Section {
                // One row, named by whichever backend is active. The two
                // branches this replaces both pushed SpoolSelectionView and
                // differed only in the backend they named — and neither
                // named FilaMan, so a connected FilaMan user got no row at
                // all.
                if isBackendAvailable {
                    NavigationLink(destination: SpoolSelectionView()) {
                        Label("From \(store.capabilities.displayName)", systemImage: store.capabilities.tabSymbol)
                    }
                }

                NavigationLink(destination: WriteTagView()) {
                    Label("Manually", systemImage: "pencil")
                }
            } header: {
                Text("Write Tag")
                    // Full width, so the popover has no room beside the header
                    // and opens below it, as `arrowEdge: .top` asks.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .popoverTip(showsFirstRunTips ? tips.currentTip as? WriteTagTip : nil, arrowEdge: .top)
            }

            if !recentTagManager.recentTags.isEmpty {
                Section("Recent Tags") {
                    ForEach(recentTagManager.recentTags) { recent in
                        NavigationLink(destination: WriteTagView(initialData: recent.data, initialFormat: recent.format)) {
                            HStack {
                                FilamentSwatch(colors: recent.data.colors, size: 24)

                                VStack(alignment: .leading) {
                                    HStack(spacing: 6) {
                                        Text(recent.data.displayName)
                                            .font(.headline)
                                            .lineLimit(1)
                                        // Same capsule as the hub's "tag differs".
                                        if let stale = WriteTagFormAssembler.staleSpoolID(in: recent.data, spools: store.spools) {
                                            Text(stale.badge)
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .foregroundStyle(Color.accentColor)
                                                .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1))
                                                .fixedSize()
                                        }
                                    }
                                    HStack {
                                        Text(recent.data.brand)
                                        Text("•")
                                        Text(recent.data.material)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                }

                                Spacer(minLength: 8)

                                // The format by name, never logo: a logo is
                                // its owner's mark, and SpoolKid uses none.
                                if let format = recent.format {
                                    Text(format.displayName)
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .foregroundStyle(.secondary)
                                        .overlay(Capsule().stroke(Color.secondary, lineWidth: 1))
                                        .fixedSize()
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete { offsets in
                        recentTagManager.removeTag(at: offsets)
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: recentTagManager.recentTags.count)
        .floatingBottomBar(alignedToTabBar: false) { scanButtonsView }
    }
    
    /// Icon-only, large and centred, in thumb reach: Scan Label (label OCR +
    /// QR), then Scan Tag, the screen's one prominent action (owner,
    /// 2026-10-29; large and centred 2026-11-04).
    private var scanButtonsView: some View {
        VStack(spacing: 4) {
            TagReaderPicker(selection: $tagReader, purpose: .read, floating: true)
            if nfcManager.isScanning, let progress = scanRun.progressText {
                Text(progress).font(.caption).foregroundStyle(.secondary)
            }
            scanButtons
        }
    }

    private var scanButtons: some View {
        // Glass buttons add about 12 pt of their own between them on iOS
        // 26.5 and none on the owner's device, so the spacing alone keeps
        // them apart; four large ones still fit a 390-pt-wide iPhone 17e.
        HStack(spacing: 8) {
            BottomBarButton(title: "Scan Label", systemImage: "camera.viewfinder", large: true) {
                ScanLabelTip().invalidate(reason: .actionPerformed)
                cameraSheetRoute = .smartScanner
            }
            .popoverTip(showsFirstRunTips ? tips.currentTip as? ScanLabelTip : nil, arrowEdge: .bottom)

            // A plain button since 2026-09-27. Its long-press menu offered
            // "Scan ACE Tag", which opened this same session (audit T3).
            BottomBarButton(title: "Scan Tag", systemImage: "wave.3.right", prominent: true, large: true) {
                // Using the feature retires its tip; a tap outside the
                // popover only hides it, so it came back after every scan.
                ScanTagTip().invalidate(reason: .actionPerformed)
                scanRun = .start(tagReader, purpose: .read, printer: printer, store: store)
                nfcManager.startScanning(queryingChipDetails: true, reader: scanRun.reader)
            }
            .disabled(nfcManager.isScanning)
            // On the circle, at the top: the name under it makes the button
            // taller than wide.
            .overlay(alignment: .top) {
                Circle()
                    .stroke(Color.accentColor, lineWidth: nfcManager.isScanning ? 2 : 0)
                    .aspectRatio(1, contentMode: .fit)
                    .scaleEffect(scanPulseScale)
                    .opacity(scanPulseOpacity)
                    .allowsHitTesting(false)
            }
            // On a transparent stand-in: anchored on the prominent glass
            // button itself, the popover opened beside it, not above. Hit
            // testing goes off outside popoverTip: inside it, the tip's
            // anchor still caught every tap meant for the button.
            .overlay {
                Color.clear
                    .popoverTip(showsFirstRunTips ? tips.currentTip as? ScanTagTip : nil, arrowEdge: .bottom)
                    .allowsHitTesting(false)
            }
        }
        .padding(.vertical)
    }
    
    // MARK: - Scan pulse animation
    
    private func startScanPulse() {
        scanPulseScale = 1.0
        scanPulseOpacity = 0.0
        animatePulseStep()
    }
    
    private func animatePulseStep() {
        guard nfcManager.isScanning else { return }
        scanPulseScale = 1.0
        scanPulseOpacity = 0.7
        withAnimation(.easeOut(duration: 0.9)) {
            scanPulseScale = 1.12
            scanPulseOpacity = 0.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            animatePulseStep()
        }
    }
    
    private func stopScanPulse() {
        withAnimation(.easeOut(duration: 0.2)) {
            scanPulseOpacity = 0.0
            scanPulseScale = 1.0
        }
    }

}
