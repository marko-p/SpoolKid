//
//  TagInspectorView.swift
//  SpoolKid
//
//  Purpose: Inspect Tag. Shows what a scan read off the tag itself: the chip,
//  its memory, and every NDEF record as stored, with the raw pages or blocks
//  below. A renderer: every string comes from `TagInspectionFormatter`, so
//  what a tester reads here is what the Share sheet sends.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct TagInspectorView: View {
    let inspection: TagInspection
    let formatName: String
    /// Set by the hub when a write or erase may have changed the tag since the
    /// scan this screen shows.
    let changedSinceScan: Bool

    /// The records showing hex instead of text. Empty on a new screen, so
    /// every text record starts on Text.
    @State private var hexRecords: Set<Int> = []

    var body: some View {
        List {
            captionSection
            chipSection
            memorySection
            contentSection
            let records = TagInspectionFormatter.records(inspection)
            ForEach(records.indices, id: \.self) { index in
                recordSection(index: index, record: records[index])
            }
            rawSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Inspect Tag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: TagInspectionFormatter.shareText(
                    inspection, formatName: formatName, appVersion: AppConfig.versionString
                ))
            }
        }
    }

    // MARK: - Sections

    private var captionSection: some View {
        let caption = TagInspectionFormatter.caption(
            capturedAt: inspection.capturedAt, changedSinceScan: changedSinceScan
        )
        return Section {
            Group {
                // A warning is `.body` (C8); the plain "As read at" line is
                // secondary text.
                if changedSinceScan {
                    Label(caption, systemImage: "exclamationmark.triangle")
                        .font(.body)
                        .foregroundStyle(.orange)
                } else {
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    private var chipSection: some View {
        Section {
            ForEach(TagInspectionFormatter.chipRows(inspection), id: \.label) { row in
                if row.label == "UID" {
                    LabeledContent(row.label, value: row.value)
                        .contextMenu {
                            Button("Copy UID") { copy(row.value) }
                        }
                } else {
                    LabeledContent(row.label, value: row.value)
                }
            }
        } header: {
            Text("Chip")
        } footer: {
            if !inspection.uid.isEmpty {
                Text("\(inspection.uid.count)-byte UID. Long-press to copy.")
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var memorySection: some View {
        let rows = TagInspectionFormatter.memoryRows(inspection)
        if !rows.isEmpty {
            let usage = TagInspectionFormatter.memoryUsage(inspection)
            Section("Memory") {
                ForEach(rows, id: \.label) { row in
                    LabeledContent(row.label, value: row.value)
                    if row.label == "Used", let usage {
                        ProgressView(value: Double(min(usage.used, usage.capacity)), total: Double(usage.capacity))
                    }
                }
            }
        }
    }

    private var contentSection: some View {
        Section("Content") {
            ForEach(TagInspectionFormatter.contentRows(inspection, formatName: formatName), id: \.label) { row in
                LabeledContent(row.label, value: row.value)
            }
        }
    }

    private func recordSection(index: Int, record: InspectorRecord) -> some View {
        Section {
            ForEach(record.rows, id: \.label) { row in
                LabeledContent(row.label, value: row.value)
            }
            if let text = record.text {
                Picker("Show", selection: showsHex(index)) {
                    Text("Text").tag(false)
                    Text("Hex").tag(true)
                }
                .pickerStyle(.segmented)
                if hexRecords.contains(index) {
                    hexRow(record.hex, copying: record.bareHex)
                } else {
                    textRow(text)
                }
            } else if record.hex.isEmpty {
                Text("No payload")
                    .foregroundStyle(.secondary)
            } else {
                hexRow(record.hex, copying: record.bareHex)
            }
        } header: {
            // The title carries the record's MIME type or well-known type,
            // where the case matters.
            Text(record.title).textCase(nil)
        }
    }

    @ViewBuilder
    private var rawSection: some View {
        if let raw = inspection.rawMemory, !raw.bytes.isEmpty {
            Section(TagInspectionFormatter.rawSectionTitle(inspection)) {
                hexRow(
                    TagInspectionFormatter.rawDump(raw),
                    copying: TagInspectionFormatter.bareHex(raw.bytes)
                )
            }
        }
    }

    // MARK: - Rows

    private var dumpFont: Font { .system(.subheadline, design: .monospaced) }

    /// Record text, then the button that copies it. Two rows: a button in the
    /// same row as the text would make the whole row one tap target and leave
    /// the text unselectable. Text is prose or JSON, so it wraps.
    @ViewBuilder
    private func textRow(_ text: String) -> some View {
        Text(text)
            .font(dumpFont)
            .textSelection(.enabled)
        Button("Copy Text") { copy(text) }
    }

    /// A hex or raw dump, then the button that copies its bare hex. The dump is
    /// fixed-width rows, so it scrolls sideways rather than wrap and misalign
    /// its columns, at any Dynamic Type size.
    @ViewBuilder
    private func hexRow(_ dump: String, copying bareHex: String) -> some View {
        ScrollView(.horizontal) {
            Text(dump)
                .font(dumpFont)
                .fixedSize()
                .textSelection(.enabled)
        }
        Button("Copy Hex") { copy(bareHex) }
    }

    private func showsHex(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { hexRecords.contains(index) },
            set: { showsHex in
                if showsHex { hexRecords.insert(index) } else { hexRecords.remove(index) }
            }
        )
    }

    private func copy(_ string: String) {
        UIPasteboard.general.string = string
    }
}
