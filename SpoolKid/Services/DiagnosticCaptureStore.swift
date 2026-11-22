//
//  DiagnosticCaptureStore.swift
//  SpoolKid
//
//  Purpose: Hold captured label scans until the user shares them.
//
//  The archive used to be built and handed straight to a Share sheet from the
//  review screen — nothing kept. Moving that affordance to the Diagnostics
//  screen (owner, 2026-09-06) means the capture has to outlive the scan that
//  made it, because the user is no longer looking at it when they decide to
//  share. So captures land here and stay until they are shared or cleared.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import os

/// One kept capture, as the Diagnostics list needs it.
nonisolated struct DiagnosticCapture: Identifiable, Equatable, Sendable {
    let id: String
    let kind: DiagnosticCaptureKind
    let capturedAt: Date
    /// What the list row says. Its meaning depends on the kind: a label scan's
    /// corrected brand · material · name, a tag dump's note.
    let summary: String
    let directory: URL
}

nonisolated enum DiagnosticCaptureStore {

    /// Enough for a bench session's worth of scans without the folder becoming
    /// a photo library. The oldest go first — a tester who keeps scanning is
    /// contributing the newest labels, not curating an archive.
    static let capacity = 20

    private static let logger = Logger(subsystem: "com.spoolkid", category: "diagnostics")
    private static let folderName = "DiagnosticCaptures"

    /// Application Support, not `tmp` or Caches: iOS reclaims both without
    /// warning, and a capture that vanishes before the tester gets to a
    /// computer is a scan they will not repeat.
    static func directory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    /// Takes ownership of a freshly built archive directory.
    @discardableResult
    static func keep(_ builtDirectory: URL) throws -> URL {
        let destination = try directory().appendingPathComponent(
            builtDirectory.lastPathComponent,
            isDirectory: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: builtDirectory, to: destination)
        trim()
        return destination
    }

    /// Newest first, which is the order a tester thinks in — the scan they
    /// just did is the one they came here to send.
    static func list() -> [DiagnosticCapture] {
        guard let root = try? directory(),
              let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
            return []
        }
        return names
            .filter { !$0.hasPrefix(".") }
            .compactMap { capture(at: root.appendingPathComponent($0, isDirectory: true)) }
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    static func list(kind: DiagnosticCaptureKind) -> [DiagnosticCapture] {
        list().filter { $0.kind == kind }
    }

    static func remove(_ capture: DiagnosticCapture) {
        try? FileManager.default.removeItem(at: capture.directory)
    }

    static func clear() {
        for capture in list() { remove(capture) }
    }

    /// Clears one kind and leaves the others alone. The hub offers a
    /// "Delete All" per section, and a tester emptying their label scans must
    /// not silently lose tag dumps they cannot re-take without the spool,
    /// the printer, and another print cycle.
    static func clear(kind: DiagnosticCaptureKind) {
        for capture in list(kind: kind) { remove(capture) }
    }

    /// Zips a kept capture for sharing. Built on demand rather than stored as
    /// a zip, so the folder holds one copy of each capture rather than two.
    ///
    /// Synchronous and slow: `NSFileCoordinator`'s `.forUploading` option
    /// builds the whole archive before it returns. Call `packaged(_:)` from a
    /// view — calling this one on the main actor freezes the screen for the
    /// length of the zip, which a tester read as the app hanging (owner
    /// device pass, 2026-09-07).
    static func package(_ capture: DiagnosticCapture) throws -> URL {
        try DiagnosticBundle.zip(directory: capture.directory)
    }

    /// `package(_:)` off the main actor, for the two screens that offer
    /// sharing. A label scan carries a photo and a tag dump carries hundreds
    /// of pages, so neither is reliably quick enough to do inline.
    static func packaged(_ capture: DiagnosticCapture) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try package(capture)
        }.value
    }

    // MARK: - Internals

    private static func trim() {
        let kept = list()
        guard kept.count > capacity else { return }
        for capture in kept.dropFirst(capacity) { remove(capture) }
    }

    /// Only the two fields the list row needs are declared, so a growing
    /// `workflow.json` never breaks the list — a capture that cannot be
    /// summarised would otherwise become a capture that cannot be shared.
    private struct Summary: Decodable {
        struct Final: Decodable {
            let material: String?
            let brand: String?
            let filamentName: String?
        }
        let capturedAt: Date
        let final: Final
    }

    private struct TagDumpSummary: Decodable {
        let capturedAt: Date
        let uid: String
        let pagesRead: Int
        let note: String
    }

    private static func capture(at directory: URL) -> DiagnosticCapture? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }

        let name = directory.lastPathComponent
        guard let kind = DiagnosticCaptureKind.from(directoryName: name) else {
            logger.error("Capture of unknown kind at \(name, privacy: .public)")
            return nil
        }

        let manifest = directory.appendingPathComponent(kind.manifestFilename)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: manifest) else {
            logger.error("Unreadable capture at \(name, privacy: .public)")
            return nil
        }

        switch kind {
        case .labelScan:
            guard let summary = try? decoder.decode(Summary.self, from: data) else {
                logger.error("Unreadable capture at \(name, privacy: .public)")
                return nil
            }
            return DiagnosticCapture(
                id: name,
                kind: kind,
                capturedAt: summary.capturedAt,
                summary: describe(
                    brand: summary.final.brand,
                    material: summary.final.material,
                    name: summary.final.filamentName
                ),
                directory: directory
            )
        case .tagDump:
            guard let summary = try? decoder.decode(TagDumpSummary.self, from: data) else {
                logger.error("Unreadable capture at \(name, privacy: .public)")
                return nil
            }
            return DiagnosticCapture(
                id: name,
                kind: kind,
                capturedAt: summary.capturedAt,
                summary: describeTagDump(
                    note: summary.note,
                    uid: summary.uid,
                    pages: summary.pagesRead
                ),
                directory: directory
            )
        case .td1sCapture:
            guard let capture = try? MIDICapture.decoder.decode(MIDICapture.self, from: data) else {
                logger.error("Unreadable capture at \(name, privacy: .public)")
                return nil
            }
            return DiagnosticCapture(
                id: name,
                kind: kind,
                capturedAt: capture.capturedAt,
                summary: describeTD1SCapture(
                    note: capture.note, td: capture.displayedTD, hex: capture.displayedHex,
                    packets: capture.packets.count
                ),
                directory: directory
            )
        case .scaleCapture, .scalePhotos:
            // Not listed in the hub today; skipped rather than shown as broken.
            return nil
        }
    }

    /// A label with nothing readable on it is still worth sending — it is the
    /// most interesting kind of failure — so an empty summary says so rather
    /// than leaving the row blank.
    static func describe(brand: String?, material: String?, name: String?) -> String {
        let parts = [brand, material, name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Nothing read from this label" : parts.joined(separator: " · ")
    }

    /// An unannotated TD1S capture is told apart by what its screen showed,
    /// else by how much it holds.
    static func describeTD1SCapture(note: String, td: String, hex: String, packets: Int) -> String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }
        let count = "\(packets) \(packets == 1 ? "packet" : "packets")"
        let shown = [td.isEmpty ? nil : "TD \(td)", hex.isEmpty ? nil : hex].compactMap { $0 }
        return (shown + [count]).joined(separator: " · ")
    }

    /// A dump the tester did not annotate still has to be identifiable in the
    /// list — the UID and size are what distinguish two dumps of two spools.
    static func describeTagDump(note: String, uid: String, pages: Int) -> String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }
        return "\(uid) · \(pages) \(pages == 1 ? "page" : "pages")"
    }
}
