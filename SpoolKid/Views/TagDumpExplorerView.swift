//
//  TagDumpExplorerView.swift
//  SpoolKid
//
//  Purpose: The bench screen for a tag nobody has mapped. Read all of it,
//  say what it came off, keep it, and compare two reads of the same tag.
//
//  It interprets nothing, and says so. What leaves this screen is bytes.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct TagDumpExplorerView: View {

    /// Passed in, not taken from the environment: `NFCManager` is owned by
    /// `ContentView` and threaded through by parameter everywhere else.
    @ObservedObject var nfcManager: NFCManager

    @EnvironmentObject private var printer: PrinterService
    @EnvironmentObject private var store: SpoolDataStore
    /// Which reader dumps the tag. Never stored.
    @State private var tagReader: TagReader = .iPhone
    @State private var scanRun = TagReaderRun()
    @State private var note = ""
    @State private var kept: [DiagnosticCapture] = []
    /// Each kept capture's UID, decoded once whenever `kept` is refreshed —
    /// never from inside the view body, which would mean reading a file off
    /// disk on every render.
    @State private var uidsByCaptureID: [String: String] = [:]
    @State private var shareURL: URL?
    /// The capture being prepared for sharing, so its row can say so.
    ///
    /// Held until the Share sheet is DISMISSED, not until the zip finishes.
    /// A tag dump zips in milliseconds; what the tester actually waits on is
    /// `UIActivityViewController` presenting itself, which is why moving the
    /// zip off the main actor alone still left the tap with no feedback
    /// (owner device pass, 2026-09-07).
    @State private var packagingID: DiagnosticCapture.ID?
    @State private var errorMessage: String?
    @State private var comparison: [TagDumpDiff.PageChange]?
    @FocusState private var noteFocused: Bool

    /// Spelled out because the synthesized memberwise initializer would inherit
    /// the `private` of the stored properties below.
    init(nfcManager: NFCManager) {
        _nfcManager = ObservedObject(wrappedValue: nfcManager)
    }

    var body: some View {
        Form {
            Section {
                TagReaderPicker(selection: $tagReader, purpose: .read)
                Button {
                    scanRun = .start(tagReader, purpose: .read, printer: printer, store: store)
                    nfcManager.startTagDump(reader: scanRun.reader)
                } label: {
                    Label(nfcManager.isScanning
                            ? (scanRun.progressText ?? "Scan a Tag")
                            : "Scan a Tag", systemImage: "wave.3.right")
                }
                .disabled(nfcManager.isScanning)
            } footer: {
                Text("Reads every page the tag will return, including the ones SpoolKid does not understand. Nothing is written to the tag.")
                    .font(.subheadline)
            }

            if let dump = nfcManager.tagDumpResult {
                dumpSection(dump)
                saveSection(dump)
            }

            if let message = nfcManager.tagDumpError ?? errorMessage {
                Section {
                    Text(message).font(.body).foregroundStyle(.red)
                }
            }

            keptSection

            if let comparison {
                comparisonSection(comparison)
            }
        }
        .navigationTitle("Tag Explorer")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshKept() }
        // A note belongs to the dump that was on screen when it was typed.
        // Scanning a second tag without saving the first must not carry the
        // first tag's description over onto the second tag's bytes.
        .onChange(of: nfcManager.tagDumpResult) { note = "" }
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
    }

    private func dumpSection(_ dump: TagDump) -> some View {
        Section {
            LabeledContent("UID", value: dump.uid)
            LabeledContent("Pages", value: String(dump.pages.count))
            LabeledContent("Chip", value: dump.chipVersion ?? "Did not say")
            LabeledContent("Ended", value: Self.endedByDescription(dump.endedBy))
            LabeledContent("Decoded as", value: dump.decodedAs ?? "Nothing recognised it")
        } header: {
            Text("This Tag")
        }
    }

    /// Plain language for how the walk stopped. `endOfTag` is a reading and
    /// `wrap` is a deduction, so they do not get the same sentence.
    nonisolated static func endedByDescription(_ reason: TagDump.EndReason) -> String {
        switch reason {
        case .endOfTag: return "Read to the end of the tag"
        case .wrap:     return "Read until the tag repeated itself"
        case .error:    return "Stopped responding"
        }
    }

    private func saveSection(_ dump: TagDump) -> some View {
        Section {
            TextField("What is this spool?", text: $note, axis: .vertical)
                .focused($noteFocused)
            Button("Keep This Dump") {
                noteFocused = false
                save(dump)
            }
        } footer: {
            Text("A note like “Anycubic PLA+ black, factory, unused” is what tells these apart later. The most recent \(DiagnosticCaptureStore.capacity) captures are kept in all — label scans and tag dumps share that budget — and the oldest drop off first.")
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
                    // Every OTHER row is disabled while one is preparing.
                    // The spinning row itself stays enabled so its
                    // `ProgressView` renders and animates undimmed; `share`
                    // guards against the second tap.
                    .disabled(packagingID != nil && packagingID != capture.id)
                }
                .onDelete { offsets in
                    for index in offsets { DiagnosticCaptureStore.remove(kept[index]) }
                    refreshKept()
                }
                if let pair = comparablePair() {
                    Button("Compare the Two Newest") { compare(pair) }
                }
            }
        } header: {
            Text("Kept Dumps")
        } footer: {
            Text("Tap a dump to share it; packaging one takes a few seconds.")
                .font(.subheadline)
        }
    }

    private func comparisonSection(_ changes: [TagDumpDiff.PageChange]) -> some View {
        Section {
            if changes.isEmpty {
                Text("Nothing changed between these two reads.")
                    .font(.body)
            } else {
                ForEach(changes, id: \.page) { change in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Page \(change.page)").font(.body)
                        Text("\(change.before ?? "—") → \(change.after ?? "—")")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("What Changed")
        }
    }

    // MARK: - Actions

    private func save(_ dump: TagDump) {
        var annotated = dump
        annotated.note = note
        do {
            _ = try TagDumpArchiveBuilder.build(annotated)
            note = ""
            // Clearing the result retires the save section with it. Leaving it
            // up invites a second tap, which would archive the same bytes again
            // under an empty note and burn another kept slot.
            nfcManager.tagDumpResult = nil
            refreshKept()
            errorMessage = nil
        } catch {
            errorMessage = "That dump could not be kept: \(error.localizedDescription)"
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
                errorMessage = "That dump could not be packaged: \(error.localizedDescription)"
                packagingID = nil
            }
        }
    }

    /// Reloads the kept-dump list and, alongside it, the UID cache that
    /// `comparablePair()` reads. This is the only place a dump's JSON is
    /// decoded off the list — the view body never touches disk.
    private func refreshKept() {
        kept = DiagnosticCaptureStore.list(kind: .tagDump)
        var uids: [String: String] = [:]
        for capture in kept {
            if let uid = try? loadDump(capture).uid {
                uids[capture.id] = uid
            }
        }
        uidsByCaptureID = uids
    }

    /// The two newest dumps of one tag. Returns nil when the kept dumps are
    /// all of different tags, so the control is absent rather than inert.
    /// Reads only the UID cache `refreshKept()` already populated — no file
    /// I/O, so this is safe to call from the view body.
    private func comparablePair() -> (DiagnosticCapture, DiagnosticCapture)? {
        for (index, capture) in kept.enumerated() {
            guard let uid = uidsByCaptureID[capture.id] else { continue }
            for other in kept.dropFirst(index + 1) where uidsByCaptureID[other.id] == uid {
                return (other, capture)
            }
        }
        return nil
    }

    private func loadDump(_ capture: DiagnosticCapture) throws -> TagDump {
        let manifest = capture.directory
            .appendingPathComponent(DiagnosticCaptureKind.tagDump.manifestFilename)
        return try TagDump.decoder.decode(TagDump.self, from: Data(contentsOf: manifest))
    }

    private func compare(_ pair: (DiagnosticCapture, DiagnosticCapture)) {
        do {
            comparison = TagDumpDiff.changes(from: try loadDump(pair.0), to: try loadDump(pair.1))
            errorMessage = nil
        } catch {
            errorMessage = "Those dumps could not be compared: \(error.localizedDescription)"
        }
    }
}
