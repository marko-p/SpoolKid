//
//  TD1SCaptureView.swift
//  SpoolKid
//
//  Purpose: Diagnostics screen that records what a Biqu TD1S sends over USB
//  MIDI while it scans, next to what its own screen showed, and keeps the
//  result for sharing — the evidence its unpublished format is decoded from.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct TD1SCaptureView: View {
    @StateObject private var midi = MIDICaptureService()

    @State private var note = ""
    @State private var displayedTD = ""
    @State private var displayedHex = ""
    @State private var kept: [DiagnosticCapture] = []
    @State private var shareURL: URL?
    /// Held until the Share sheet is dismissed, as in Tag Explorer.
    @State private var packagingID: DiagnosticCapture.ID?
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Form {
            Section {
                if midi.sources.isEmpty {
                    Text("No USB MIDI device found. Plug the TD1S into the iPhone's USB-C port; it appears here within a few seconds.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(midi.sources) { source in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name).font(.body)
                            Text([source.manufacturer, source.model].compactMap { $0 }.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Connected")
            } footer: {
                Text("The TD1S needs firmware 2.0.1 or later, which HueForge 0.9.2 or later installs. The original TD-1 does not work with an iPhone.")
                    .font(.subheadline)
            }

            recordSection

            if !midi.isRecording && !midi.packets.isEmpty {
                saveSection
            }

            if let message = midi.errorMessage ?? errorMessage {
                Section {
                    Text(message).font(.body).foregroundStyle(.red)
                }
            }

            keptSection
        }
        .navigationTitle("TD1S Capture")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneBar()
        .onAppear {
            midi.start()
            kept = DiagnosticCaptureStore.list(kind: .td1sCapture)
        }
        .onDisappear { midi.stop() }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: {
                if !$0 {
                    shareURL = nil
                    packagingID = nil
                }
            }
        )) {
            if let shareURL { ActivityShareSheet(url: shareURL) }
        }
    }

    private var recordSection: some View {
        Section {
            if midi.isRecording {
                Button("Stop Recording", role: .destructive) { midi.stopRecording() }
            } else {
                Button {
                    midi.startRecording()
                } label: {
                    Label("Start Recording", systemImage: "record.circle")
                }
                .disabled(midi.sources.isEmpty)
            }
            LabeledContent("Received", value: "\(midi.packets.count) \(midi.packets.count == 1 ? "packet" : "packets")")
            ForEach(Array(midi.packets.suffix(5).enumerated()), id: \.offset) { _, packet in
                Text(packet.midi1Hex.isEmpty ? packet.wordsHex : packet.midi1Hex)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Recording")
        } footer: {
            Text("Start recording, then scan one filament with the TD1S. Stop once its screen shows the result. One scan per recording keeps them easy to tell apart.")
                .font(.subheadline)
        }
    }

    private var saveSection: some View {
        Section {
            LabeledContent("TD on its screen") {
                TextField("e.g. 4.2", text: $displayedTD)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($fieldFocused)
            }
            LabeledContent("Hex on its screen") {
                TextField("e.g. F5F5F5", text: $displayedHex)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .focused($fieldFocused)
            }
            TextField("What is this filament?", text: $note, axis: .vertical)
                .focused($fieldFocused)
            Button("Keep This Capture") {
                fieldFocused = false
                save()
            }
            Button("Discard", role: .destructive) { midi.discardRecording() }
        } header: {
            Text("This Scan")
        } footer: {
            Text("The values the TD1S showed are what its bytes get decoded against, so copy them exactly. The most recent \(DiagnosticCaptureStore.capacity) captures of all kinds are kept, and the oldest drop off first.")
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private var keptSection: some View {
        Section {
            if kept.isEmpty {
                Text("Nothing kept yet.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(kept) { capture in
                    Button { share(capture) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(capture.summary).font(.body)
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
                    .disabled(packagingID != nil && packagingID != capture.id)
                }
                .onDelete { offsets in
                    for index in offsets { DiagnosticCaptureStore.remove(kept[index]) }
                    kept = DiagnosticCaptureStore.list(kind: .td1sCapture)
                }
            }
        } header: {
            Text("Kept Captures")
        } footer: {
            Text("Tap a capture to share it.")
                .font(.subheadline)
        }
    }

    // MARK: - Actions

    private func save() {
        let capture = midi.capture(
            note: note,
            displayedTD: displayedTD.trimmingCharacters(in: .whitespacesAndNewlines),
            displayedHex: displayedHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        )
        do {
            try MIDICaptureArchiveBuilder.build(capture)
            // Retiring the recording retires the save section, so a second
            // tap cannot keep the same bytes twice.
            midi.discardRecording()
            note = ""
            displayedTD = ""
            displayedHex = ""
            kept = DiagnosticCaptureStore.list(kind: .td1sCapture)
            errorMessage = nil
        } catch {
            errorMessage = "That capture could not be kept: \(error.localizedDescription)"
        }
    }

    private func share(_ capture: DiagnosticCapture) {
        guard packagingID == nil else { return }
        packagingID = capture.id
        errorMessage = nil
        Task {
            do {
                shareURL = try await DiagnosticCaptureStore.packaged(capture)
            } catch {
                errorMessage = "That capture could not be packaged: \(error.localizedDescription)"
                packagingID = nil
            }
        }
    }
}
