//
//  TD1SReadView.swift
//  SpoolKid
//
//  Purpose: The sheet behind the TD1S eyedroppers — one on each color row,
//  one on the filament form's TD row. It listens to the TD1S over USB MIDI
//  and hands back the first scan made while it is open that has what the
//  row asked for, then closes; the scan itself is the confirmation.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct TD1SReadView: View {
    /// What the row that opened the sheet takes from a scan. A color row's
    /// scan also fills an empty TD box (its host decides); it never replaces
    /// a TD already there. The TD row's scan never changes a color.
    enum Target { case color, transmissionDistance }

    let target: Target
    let onRead: (TD1SReading) -> Void
    /// Set when the newest scan had no TD SpoolKid can store; the sheet stays
    /// open for another.
    @State private var unusableScan = false

    @Environment(\.dismiss) private var dismiss
    /// The same CoreMIDI listener the Diagnostics capture uses; recording is
    /// what keeps the packets that arrive while the sheet is open.
    @StateObject private var midi = MIDICaptureService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: midi.sources.isEmpty ? "cable.connector" : "eyedropper")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(midi.sources.isEmpty ? "Plug in the TD1S" : "Scan the filament with the TD1S")
                    .font(.title3.weight(.semibold))
                Text(midi.sources.isEmpty
                     ? "Connect it to the iPhone's USB-C port. It needs firmware 2.0.1 or later, which HueForge 0.9.2 or later installs."
                     : target == .color
                        ? "The color fills in as soon as the scan finishes."
                        : "The TD fills in as soon as the scan finishes.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if unusableScan {
                    Text("That scan had no TD SpoolKid can store. Scan again.")
                        .font(.body)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                if let message = midi.errorMessage {
                    Text(message).font(.body).foregroundStyle(.red)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Read from TD1S")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            midi.start()
            midi.startRecording()
        }
        .onDisappear { midi.stop() }
        .onChange(of: midi.packets.count) {
            let bytes = midi.packets.flatMap { UMPDecoder.midi1Bytes(fromWords: $0.words) }
            guard let reading = TD1SReading.latest(in: bytes) else { return }
            if target == .transmissionDistance && reading.transmissionDistance == nil {
                unusableScan = true
                return
            }
            onRead(reading)
            dismiss()
        }
    }
}
