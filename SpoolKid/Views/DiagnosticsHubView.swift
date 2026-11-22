//
//  DiagnosticsHubView.swift
//  SpoolKid
//
//  Purpose: One place for everything a test user can capture and contribute.
//  Reached from the bug button, which only exists while the single
//  "Help Improve SpoolKid" switch is on.
//
//  Each entry is a feature being actively worked on. When one ships, its row
//  leaves — this screen is not an archive of past experiments.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct DiagnosticsHubView: View {

    /// Held only to hand to the Tag Explorer, which needs a live NFC session.
    /// `NFCManager` is passed by parameter throughout the app rather than
    /// placed in the environment; this screen is on that path.
    @ObservedObject var nfcManager: NFCManager

    @State private var captures: [DiagnosticCapture] = []
    @State private var shareURL: URL?
    /// The capture being prepared for sharing. Held until the Share sheet is
    /// DISMISSED, not until the zip finishes: what a tester waits on is
    /// `UIActivityViewController` presenting itself, not the archive
    /// (owner device pass, 2026-09-07).
    @State private var packagingID: DiagnosticCapture.ID?
    @State private var shareError: String?
    @State private var confirmingClear = false

    /// Spelled out because the synthesized memberwise initializer would inherit
    /// the `private` of the stored properties below and stop the tabs from
    /// constructing this view.
    init(nfcManager: NFCManager) {
        _nfcManager = ObservedObject(wrappedValue: nfcManager)
    }

    var body: some View {
        List {
            Section {
                Text(Self.assurance)
                    .font(.body)
                Link(destination: Self.issuesURL) {
                    Label("Open an issue on GitHub", systemImage: "ladybug")
                }
            } footer: {
                Text(Self.whereToSend)
                    .font(.subheadline)
            }

            labelScanSection

            Section {
                NavigationLink {
                    BLEScaleExplorerView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bluetooth Scale")
                            Text("Find a scale and record what it sends, with photos of its display.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "scalemass")
                    }
                }
            } header: {
                Text("Weighing")
            } footer: {
                Text("SpoolKid reads AiLink-family scales already — set one up in Settings → Bluetooth Scale. This is for the ones it cannot read: a capture from yours is what makes those possible.")
                    .font(.subheadline)
            }

            Section {
                NavigationLink {
                    TD1SCaptureView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TD1S")
                            Text("Record what a Biqu TD1S sends over USB while it scans.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "eyedropper")
                    }
                }
            } header: {
                Text("Color & TD")
            } footer: {
                Text("SpoolKid cannot read the TD1S yet: the format it sends over USB is not published. A few captures, each with the values its screen showed, are what will let SpoolKid fill in color and TD straight from it.")
                    .font(.subheadline)
            }

            Section {
                NavigationLink {
                    TagDumpExplorerView(nfcManager: nfcManager)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tag Explorer")
                            Text("Read a whole tag, including the parts SpoolKid does not understand.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "wave.3.right")
                    }
                }
            } header: {
                Text("Tags")
            } footer: {
                Text("Anycubic ACE tags are the ones we know least about — nobody has looked past the part SpoolKid decodes. A dump from a factory spool is what changes that.")
                    .font(.subheadline)
            }

            Section {
                Text("Turn all of this off again in the iOS Settings app, under SpoolKid → Help Improve SpoolKid. Switching it off stops new captures; it does not delete the ones already here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Help Improve SpoolKid")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { captures = DiagnosticCaptureStore.list(kind: .labelScan) }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: {
                if !$0 {
                    shareURL = nil
                    // The row stops spinning here, not when the zip ends:
                    // the sheet being up is the end of the wait.
                    packagingID = nil
                }
            }
        )) {
            if let shareURL { ActivityShareSheet(url: shareURL) }
        }
        .confirmationDialog(
            "Delete all \(captures.count) kept label scans?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                // Label scans only. Tag dumps live in the same folder and are
                // far harder to re-take, so they are not swept up by a button
                // whose title says "label scans".
                DiagnosticCaptureStore.clear(kind: .labelScan)
                captures = []
            }
            Button("Keep Them", role: .cancel) {}
        }
    }

    // MARK: - Label scans

    @ViewBuilder
    private var labelScanSection: some View {
        Section {
            if captures.isEmpty {
                Text("Nothing kept yet. Scan a filament label and finish the review screen — the scan is kept here automatically.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(captures) { capture in
                    captureRow(capture)
                }
                .onDelete { offsets in
                    for index in offsets { DiagnosticCaptureStore.remove(captures[index]) }
                    captures = DiagnosticCaptureStore.list(kind: .labelScan)
                }
                Button("Delete All", role: .destructive) { confirmingClear = true }
            }
            if let shareError {
                Text(shareError)
                    .font(.body)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Filament Label Scans")
        } footer: {
            // Says plainly that scans are being kept. The review screen no
            // longer mentions it (owner, 2026-09-06 — it belongs here, not in
            // the middle of adding a spool), so this is where a tester learns
            // what is on their phone and how to get rid of it.
            Text("Tap a scan to share it; packaging one takes a few seconds. While this is on, every label scan you finish reviewing is kept here — the photo, what was read from it, and the corrections you made. The corrections are the most useful part. The most recent \(DiagnosticCaptureStore.capacity) captures are kept in all — label scans and tag dumps share that budget — and the oldest drop off first.")
                .font(.subheadline)
        }
    }

    private func captureRow(_ capture: DiagnosticCapture) -> some View {
        Button {
            share(capture)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(capture.summary)
                        .font(.body)
                    Text(capture.capturedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if packagingID == capture.id {
                    ProgressView()
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
        // Every OTHER row is disabled while one is preparing. The spinning
        // row itself stays enabled so its `ProgressView` renders and animates
        // undimmed; `share` guards against the second tap.
        .disabled(packagingID != nil && packagingID != capture.id)
    }

    private func share(_ capture: DiagnosticCapture) {
        guard packagingID == nil else { return }
        packagingID = capture.id
        shareError = nil
        // Off the main actor: zipping a capture with its label photo blocks
        // for long enough that the screen looks frozen (owner device pass,
        // 2026-09-07).
        Task {
            do {
                shareURL = try await DiagnosticCaptureStore.packaged(capture)
            } catch {
                shareError = "Could not package that scan: \(error.localizedDescription)"
                packagingID = nil
            }
        }
    }

    // MARK: - Copy

    /// Stated first, before anything is offered. A screen that collects things
    /// has to answer "where does this go?" before it asks for anything, and
    /// the honest answer here is short: nowhere, unless the user sends it.
    nonisolated static let assurance =
        "Nothing here is sent automatically and nothing is uploaded. Each capture ends at a Share sheet you drive — you choose what leaves the phone, and when."

    nonisolated static let whereToSend =
        "To send one: open an issue on the SpoolKid GitHub repository and attach the file the Share sheet gives you. Say what the scale or label actually read, and what SpoolKid made of it."

    nonisolated static let issuesURL = URL(string: "https://github.com/marko-p/SpoolKid/issues/new")!
}
