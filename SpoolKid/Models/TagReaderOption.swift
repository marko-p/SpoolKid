//
//  TagReaderOption.swift
//  SpoolKid
//
//  Purpose: The choices the tag reader picker offers, and what each says and
//  allows, from the printer's state. Pure rules; the view only draws them.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum TagReaderPurpose: Equatable, Sendable {
    case read
    case write(format: TagFormat?)
}

nonisolated struct TagReaderOption: Equatable, Identifiable, Sendable {
    let reader: TagReader
    let title: String
    let detail: String?
    /// Nil when selectable.
    let disabledReason: String?
    var id: TagReader { reader }

    static let busyNote = "The printer is busy. Tags can be read and written when the print ends."
    static let iso15693Reason = "This format needs a tag the printer can't write. Use the iPhone."
    static let snapmakerReason = "Snapmaker tags can't be rewritten."
    static let unwritableReason = "This tag type can't be written by the printer."
    static let goneReason = "The RFID reader is no longer available."
    static let noReportDetail = "No tag read yet"
    static let reportedByPrinterNote = "Reported by the printer. This tag can't be read through U1 RFID reader."

    /// A tag UID of 4 bytes (8 hex characters) is MIFARE Classic, which the
    /// printer cannot write. `isOfficial` alone never decides it.
    private static let unwritableUIDLength = 8

    /// Empty when the picker must not appear at all.
    static func options(
        plugin: PrinterTagPlugin, isConnected: Bool, isPrinterBusy: Bool,
        toolheads: [ToolheadState], spoolName: (ToolheadState) -> String?,
        purpose: TagReaderPurpose
    ) -> [TagReaderOption] {
        guard plugin.isUsable, isConnected else { return [] }
        let iPhone = TagReaderOption(reader: .iPhone, title: "iPhone", detail: nil, disabledReason: nil)
        // Readers count 1 to 4 here; the spool-holder layout belongs to the Printer tab alone.
        return [iPhone] + toolheads.sorted { $0.index < $1.index }.map {
            toolheadOption($0, isPrinterBusy: isPrinterBusy, spoolName: spoolName($0), purpose: purpose)
        }
    }

    private static func toolheadOption(
        _ toolhead: ToolheadState, isPrinterBusy: Bool, spoolName: String?, purpose: TagReaderPurpose
    ) -> TagReaderOption {
        let reader = TagReader.toolhead(toolhead.index)
        let title = "RFID reader \(toolhead.index + 1)"
        // The printer reads a tag when filament is loaded, not when a tag is swapped or
        // stuck on a loaded spool, so "nothing reported" does not mean "no tag": the
        // reader stays selectable and the plugin's own read decides.
        let uid = toolhead.tagUID ?? ""
        let unwritable = uid.count == unwritableUIDLength
        let detail: String
        if uid.isEmpty {
            detail = noReportDetail
        } else if let spoolName {
            detail = spoolName
        } else if unwritable && toolhead.isOfficial {
            detail = "Snapmaker tag"
        } else if let described = described(toolhead) {
            detail = described
        } else if toolhead.hasData || toolhead.tag != nil {
            detail = "Tag not in Library"
        } else {
            detail = "Blank or unknown tag"
        }
        var reason: String?
        if isPrinterBusy {
            reason = busyNote
        } else if case .write(let format) = purpose {
            if format == .openPrintTag {
                reason = iso15693Reason
            } else if unwritable {
                reason = toolhead.isOfficial ? snapmakerReason : unwritableReason
            }
        }
        return TagReaderOption(reader: reader, title: title, detail: detail, disabledReason: reason)
    }

    /// The vendor and material the printer reports, when it reports either.
    private static func described(_ toolhead: ToolheadState) -> String? {
        func stated(_ text: String?) -> String? {
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        let parts = [stated(toolhead.vendor) ?? stated(toolhead.tag?.vendor),
                     stated(toolhead.material) ?? stated(toolhead.tag?.material)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// False while the choice must be left alone: the printer is connecting, or
    /// is online with the plugin listed but silent, or online with a usable
    /// plugin and no toolheads yet. Any other not-connected state, and a plugin
    /// known absent or unusable, are settled, so the fallback fires.
    static func isSettled(connection: PrinterConnection, plugin: PrinterTagPlugin,
                          toolheads: [ToolheadState]) -> Bool {
        switch connection {
        case .connecting: return false
        case .online: break
        default: return true
        }
        switch plugin {
        case .notInstalled, .needsAppUpdate: return true
        case .notReady(let reason) where reason == PrinterTagPlugin.waitingReason: return false
        default: return !toolheads.isEmpty
        }
    }

    /// The choice to fall back to, with the reason, when `current` stopped being
    /// selectable. Nil while `isSettled` is false.
    static func fallback(for current: TagReader, in options: [TagReaderOption],
                         isSettled: Bool) -> (reader: TagReader, reason: String)? {
        guard isSettled, current != .iPhone else { return nil }
        let option = options.first { $0.reader == current }
        guard option == nil || option?.disabledReason != nil else { return nil }
        let reason = option?.disabledReason ?? goneReason
        return (.iPhone, reason)
    }

    /// An online printer that never reports toolheads keeps the selection, but
    /// this routes it to the iPhone: accepted.
    /// What an operation must use: the selection only while it is on offer and
    /// selectable, else the iPhone. Covers the loading window, where the
    /// selection is kept but the toolhead is not yet known to be usable.
    static func reader(for selection: TagReader, in options: [TagReaderOption]) -> TagReader {
        guard let option = options.first(where: { $0.reader == selection }),
              option.disabledReason == nil else { return .iPhone }
        return selection
    }

    /// Whether the note about a dropped reader no longer applies.
    static func noteIsStale(droppedReader: TagReader?, in options: [TagReaderOption]) -> Bool {
        guard let droppedReader else { return true }
        return options.first { $0.reader == droppedReader }.map { $0.disabledReason == nil } ?? false
    }
}

extension TagReaderOption {
    /// The options as the printer and Library stand now. The picker and every
    /// operation read them through here, so they cannot disagree.
    @MainActor
    static func options(printer: PrinterService, store: SpoolDataStore,
                        purpose: TagReaderPurpose) -> [TagReaderOption] {
        options(
            plugin: printer.tagPlugin, isConnected: printer.connection == .online,
            isPrinterBusy: printer.activity.blocksWrites,
            toolheads: printer.toolheads,
            spoolName: { ToolheadSpoolMatch.spool(for: $0, printer: printer, store: store)?.listTitle },
            purpose: purpose)
    }

    /// What an operation must use: the screen's selection only while that
    /// toolhead is on offer and selectable now, else the iPhone. Every call
    /// that reads or writes a tag passes its selection through here, so
    /// nothing reaches a toolhead by surprise.
    @MainActor
    static func reader(for selection: TagReader, purpose: TagReaderPurpose,
                       printer: PrinterService, store: SpoolDataStore) -> TagReader {
        guard selection != .iPhone else { return .iPhone }
        return reader(for: selection, in: options(printer: printer, store: store, purpose: purpose))
    }
}

extension TagReaderOption {
    /// What a button says while a toolhead runs the operation; nil on the iPhone,
    /// whose own system sheet shows progress.
    nonisolated static func progressText(for reader: TagReader, writing: Bool) -> String? {
        guard case .toolhead(let index) = reader else { return nil }
        return writing ? "Writing with RFID reader \(index + 1)…" : "Reading from RFID reader \(index + 1)…"
    }

    /// Whether a finished write may offer the other side: only a filament write
    /// that a toolhead did.
    nonisolated static func offersOtherSide(afterWritingWith reader: TagReader?) -> Bool {
        if case .toolhead = reader { return true }
        return false
    }
}

/// The reader one tag operation actually runs on, fixed when it starts. A
/// screen keeps it, so progress wording and the other-side offer follow the
/// reader the operation used, not the picker's current choice.
nonisolated struct TagReaderRun: Equatable, Sendable {
    var reader: TagReader = .iPhone
    var isWriting = false

    var progressText: String? { TagReaderOption.progressText(for: reader, writing: isWriting) }

    /// A toolhead operation shows no system NFC sheet, so while one runs the
    /// screen must not be left. The iPhone's own sheet already holds the screen.
    func holdsScreen(isScanning: Bool) -> Bool { isScanning && reader != .iPhone }

    /// Why a toolhead scan ended without a tag, from the manager's alert text.
    /// Nil on the iPhone, whose session shows its own alert.
    func toolheadFailure(alertMessage: String) -> String? {
        reader != .iPhone && !alertMessage.isEmpty ? alertMessage : nil
    }

    /// A finished toolhead filament write offers the other side.
    var offersOtherSide: Bool { isWriting && TagReaderOption.offersOtherSide(afterWritingWith: reader) }

    /// The run for an operation on `selection`, resolved against the printer now.
    @MainActor
    static func start(_ selection: TagReader, purpose: TagReaderPurpose,
                      printer: PrinterService, store: SpoolDataStore) -> TagReaderRun {
        let isWriting: Bool
        if case .write = purpose { isWriting = true } else { isWriting = false }
        return TagReaderRun(
            reader: TagReaderOption.reader(for: selection, purpose: purpose, printer: printer, store: store),
            isWriting: isWriting)
    }

    /// An operation that only the iPhone can do (a location tag).
    static let iPhone = TagReaderRun()
}
