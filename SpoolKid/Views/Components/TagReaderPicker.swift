//
//  TagReaderPicker.swift
//  SpoolKid
//
//  Purpose: Choose the iPhone or a U1 toolhead as the NFC reader. Draws
//  nothing without a ready plugin and a connected printer.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct TagReaderPicker: View {
    @Binding var selection: TagReader
    let purpose: TagReaderPurpose
    let title: String
    /// Over scrolling content (a bottom bar): label and choice sit together
    /// in one capsule with its own background.
    let floating: Bool

    @EnvironmentObject private var printer: PrinterService
    @EnvironmentObject private var store: SpoolDataStore
    @State private var fallbackReason: String?
    @State private var droppedReader: TagReader?

    init(selection: Binding<TagReader>, purpose: TagReaderPurpose, title: String? = nil,
         floating: Bool = false) {
        _selection = selection
        self.purpose = purpose
        self.title = title ?? (purpose == .read ? "Read with" : "Write with")
        self.floating = floating
    }

    private var isBusy: Bool { printer.activity.blocksWrites }

    private var options: [TagReaderOption] {
        TagReaderOption.options(printer: printer, store: store, purpose: purpose)
    }

    private var isSettled: Bool {
        TagReaderOption.isSettled(connection: printer.connection,
                                  plugin: printer.tagPlugin, toolheads: printer.toolheads)
    }

    var body: some View {
        let options = options
        // The row exists only when there are options, so without a plugin the
        // picker adds no view and no spacing. The fallback lives on the Group,
        // not the row. A modifier on an empty Group may never run, so while no
        // option is on offer but a toolhead is still selected (the printer went
        // away mid-screen) a zero-size view stands in, runs the fallback, and is
        // gone again once the selection is the iPhone.
        Group {
            if !options.isEmpty {
                row(options)
            } else if selection != .iPhone {
                Color.clear.frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                    .onAppear { applyFallback(options) }
            }
        }
        .onChange(of: options) { _, new in applyFallback(new) }
        .onChange(of: isSettled) { _, _ in applyFallback(options) }
        .onChange(of: selection) { _, _ in applyFallback(options) }
    }

    private func row(_ options: [TagReaderOption]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).accessibilityHidden(true)
                if !floating { Spacer() }
                Menu {
                    ForEach(options) { option in
                        Button { pick(option.reader) } label: {
                            Text(label(option))
                            if let reason = option.disabledReason, reason != TagReaderOption.busyNote {
                                Text(reason)
                            }
                        }
                        .disabled(option.disabledReason != nil)
                    }
                } label: {
                    Text(shownTitle(options))
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
                .accessibilityLabel(title)
                .accessibilityValue(shownTitle(options))
            }
            .frame(minHeight: 44)
            .padding(.horizontal, floating ? 16 : 0)
            .background { if floating { Capsule().fill(.regularMaterial) } }
            .frame(maxWidth: floating ? .infinity : nil)
            if isBusy { note(TagReaderOption.busyNote) }
            if let fallbackReason, !(isBusy && fallbackReason == TagReaderOption.busyNote) {
                note(fallbackReason)
            }
        }
        .onAppear { applyFallback(options) }
    }

    /// The kept toolhead, named, while the printer is still loading.
    private func shownTitle(_ options: [TagReaderOption]) -> String {
        if let option = options.first(where: { $0.reader == selection }) { return option.title }
        if case .toolhead(let index) = selection { return "RFID reader \(index + 1)" }
        return "iPhone"
    }

    private func pick(_ reader: TagReader) {
        selection = reader
        fallbackReason = nil
        droppedReader = nil
    }

    private func applyFallback(_ options: [TagReaderOption]) {
        if let fallback = TagReaderOption.fallback(for: selection, in: options, isSettled: isSettled) {
            droppedReader = selection
            selection = fallback.reader
            fallbackReason = fallback.reason
        } else if TagReaderOption.noteIsStale(droppedReader: droppedReader, in: options) {
            fallbackReason = nil
            droppedReader = nil
        }
    }

    private func label(_ option: TagReaderOption) -> String {
        option.detail.map { "\(option.title) · \($0)" } ?? option.title
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}
