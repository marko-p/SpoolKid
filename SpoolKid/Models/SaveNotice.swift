//
//  SaveNotice.swift
//  SpoolKid
//
//  Purpose: What the root banner has to say, as a list of labelled entries
//  rather than one accumulated string.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// Everything a partial success still has to tell the user, with each note
/// attached to the record it is about.
///
/// This was a bare `String` until 2026-08-28, appended to across writes (I4).
/// Two faults followed from that. The banner could not name WHICH spool a
/// caveat was about — the owner's device pass, finding 4.2.1 — and the
/// duplicate suppression compared messages alone, so a second spool failing
/// the same way as the first said nothing at all.
///
/// Both are the same missing fact: a note is about a record, and a string has
/// nowhere to put one.
nonisolated struct SaveNotice: Equatable, Sendable {
    /// One thing that did not happen, and the record it did not happen to.
    /// `record` is nil where the caller genuinely has no name to give — a
    /// create that failed before the record existed.
    nonisolated struct Entry: Equatable, Sendable, Identifiable {
        let record: String?
        let message: String

        var id: String { "\(record ?? "")\u{1F}\(message)" }
    }

    var entries: [Entry]

    /// Adds a note to whatever is still on screen rather than replacing it.
    ///
    /// A notice is cleared only when the user dismisses it, so anything still
    /// showing is by definition unread; overwriting it destroys the only
    /// report of a write that half-failed, which is the silent success this
    /// whole mechanism exists to end.
    ///
    /// A `message` carrying newlines is split: `SaveOutcome.combinedNote`
    /// joins several caveats that way, and they are separate pieces of news
    /// about one record, not one paragraph.
    static func appending(record: String?, message: String, to existing: SaveNotice?) -> SaveNotice? {
        let lines = message
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return existing }

        var entries = existing?.entries ?? []
        for line in lines {
            let entry = Entry(record: record, message: line)
            // Deduplicated on record AND message together. Comparing messages
            // alone is what swallowed the second record's identical caveat.
            guard !entries.contains(entry) else { continue }
            entries.append(entry)
        }
        return entries.isEmpty ? nil : SaveNotice(entries: entries)
    }
}
