//
//  ChangelogEntry.swift
//  SpoolKid
//
//  Purpose: One released version's user-facing notes, as decoded from
//  Changelog.json — bundled with the app and mirrored in the public repo.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// What a single line of notes is claiming. Drives its symbol and tint.
nonisolated enum ChangeKind: String, Codable, Sendable, CaseIterable {
    case added
    case improved
    case fixed

    var symbolName: String {
        switch self {
        case .added:    return "plus.circle.fill"
        case .improved: return "wand.and.stars"
        case .fixed:    return "checkmark.circle.fill"
        }
    }
}

/// One line of notes.
nonisolated struct ChangelogChange: Codable, Sendable, Equatable, Identifiable {
    let kind: ChangeKind
    let text: String

    var id: String { "\(kind.rawValue)-\(text)" }

    init(kind: ChangeKind, text: String) {
        self.kind = kind
        self.text = text
    }

    /// A `kind` this build does not recognise reads as `.improved`. A newer
    /// remote file must never cost the user every note in it because it
    /// introduced one word this build has not heard of.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .kind)
        kind = ChangeKind(rawValue: raw) ?? .improved
        text = try container.decode(String.self, forKey: .text)
    }
}

/// One released version.
nonisolated struct ChangelogEntry: Codable, Sendable, Equatable, Identifiable {
    let version: String
    /// `yyyy-MM-dd`, or absent.
    let date: String?
    let headline: String?
    let changes: [ChangelogChange]

    var id: String { version }

    var release: ReleaseVersion { ReleaseVersion(version) }

    /// The calendar day these notes were released, or `nil` if absent or
    /// unparseable.
    ///
    /// Through `CalendarDateCodec` rather than a formatter of its own: a
    /// released-on date is a calendar day, not an instant, and a UTC-pinned
    /// parser feeding a local-zone renderer shifts that day back one for
    /// everyone west of UTC — the bug that type was written to end.
    ///
    /// `timeZone` is a parameter only so a test can pin a non-UTC offset
    /// without mutating the process's global timezone, exactly as
    /// `CalendarDateCodec` takes one.
    func day(in timeZone: TimeZone = .current) -> Date? {
        CalendarDateCodec.date(from: date, timeZone: timeZone)
    }

    /// The day in the reader's locale, or `nil` if absent or unparseable.
    var formattedDate: String? {
        day()?.formatted(date: .abbreviated, time: .omitted)
    }
}
