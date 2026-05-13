//
//  TagsTabView.swift
//  SpoolKid
//
//  Purpose: The "Tags" tab content — NFC tag creation and recent tags management.
//  Features:
//  - "Create Tag" section with From Spoolman and Manual options.
//  - "Recent Tags" section with swipe-to-delete and quick re-use.
//  - "Scan Tag" button at the bottom for reading existing NFC tags.
//  - Programmatic navigation to WriteTagView after an NFC scan.
//  - About button in the toolbar.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI
import TipKit

struct TagsTabView: View {
    @ObservedObject var nfcManager: NFCManager
    @StateObject private var recentTagManager = RecentTagManager()

    @AppStorage("spoolman_connection_valid") private var isConnectionValid = false
    @AppStorage(AppConfig.spoolmanPersistCardUIDKey) private var persistCardUID: Bool = false

    @State private var showAbout = false
    @State private var navigateToWriteFromScan = false
    @State private var navigateToScanHub = false
    @State private var scannedTagData: FilamentTagData? = nil
    @State private var scanResult: ScanResult? = nil
    @State private var scanPulseScale: CGFloat = 1.0
    @State private var scanPulseOpacity: Double = 0.0

    enum ScanCompletionRoute: Equatable {
        case scanHub
        case writeTag
        case none
    }

    static func scanCompletionRoute(
        persistCardUID: Bool,
        hasScanResult: Bool,
        hasLegacyData: Bool
    ) -> ScanCompletionRoute {
        if hasScanResult {
            return persistCardUID ? .scanHub : .writeTag
        }
        if hasLegacyData {
            return .writeTag
        }
        return .none
    }

    var body: some View {
        NavigationStack {
            VStack {
                List {
                    Section("Create Tag") {
                        TipView(WriteTagTip())
                        
                        if isConnectionValid {
                            NavigationLink(destination: SpoolSelectionView()) {
                                Label("From Spoolman", systemImage: "server.rack")
                            }
                        }

                        NavigationLink(destination: WriteTagView()) {
                            Label("Manually", systemImage: "pencil")
                        }
                    }

                    if !recentTagManager.recentTags.isEmpty {
                        Section("Recent Tags") {
                            ForEach(recentTagManager.recentTags) { recent in
                                NavigationLink(destination: WriteTagView(initialData: recent.data)) {
                                    HStack {
                                        Circle()
                                            .fill(recent.data.color)
                                            .frame(width: 24, height: 24)
                                            .overlay(Circle().stroke(Color.swatchBorder, lineWidth: 1))

                                        VStack(alignment: .leading) {
                                            Text(recent.data.name ?? "\(recent.data.brand) \(recent.data.material)")
                                                .font(.headline)
                                                .lineLimit(1)
                                            HStack {
                                                Text(recent.data.brand)
                                                Text("•")
                                                Text(recent.data.material)
                                            }
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
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

                Menu {
                    Button(action: {
                        nfcManager.startScanning()
                    }) {
                        Label("Scan Tag", systemImage: "wave.3.right")
                    }
                    Button(action: {
                        nfcManager.startScanningRaw()
                    }) {
                        Label("Scan ACE Tag", systemImage: "wave.3.right")
                    }
                } label: {
                    Label(nfcManager.isScanning ? "Scanning..." : "Scan Tag", systemImage: "wave.3.right")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                } primaryAction: {
                    nfcManager.startScanning()
                }
                .buttonStyle(.borderedProminent)
                .disabled(nfcManager.isScanning)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .scaleEffect(scanPulseScale)
                        .opacity(scanPulseOpacity)
                        .allowsHitTesting(false)
                )
                .padding()

                TipView(ScanTagTip())
                    .padding(.horizontal)
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showAbout = true }) {
                        Image(systemName: "info.circle")
                    }
                    .popoverTip(AboutTip())
                }
            }
            .navigationDestination(isPresented: $navigateToScanHub) {
                if let result = scanResult {
                    ScanResultHubView(result: result)
                }
            }
            .navigationDestination(isPresented: $navigateToWriteFromScan) {
                WriteTagView(initialData: scannedTagData)
            }
            .navigationDestination(isPresented: $showAbout) {
                AboutView()
            }
            .onAppear {
                recentTagManager.refresh()
            }
            .onChange(of: nfcManager.isScanning) { _, isScanning in
                if isScanning {
                    startScanPulse()
                } else {
                    stopScanPulse()

                    let route = Self.scanCompletionRoute(
                        persistCardUID: persistCardUID,
                        hasScanResult: nfcManager.scanResult != nil,
                        hasLegacyData: nfcManager.scannedData != nil
                    )

                    switch route {
                    case .scanHub:
                        if let result = nfcManager.scanResult {
                            scanResult = result
                            navigateToScanHub = true
                        }
                    case .writeTag:
                        scannedTagData = nfcManager.scanResult?.tagData ?? nfcManager.scannedData
                        navigateToWriteFromScan = true
                    case .none:
                        break
                    }
                }
            }
            .onChange(of: navigateToScanHub) { _, isNavigating in
                if !isNavigating {
                    scanResult = nil
                    nfcManager.scanResult = nil
                }
            }
            .onChange(of: navigateToWriteFromScan) { _, isNavigating in
                if !isNavigating {
                    scannedTagData = nil
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
