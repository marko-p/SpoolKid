//
//  ChangelogEntryTests.swift
//  SpoolKidTests
//
//  Purpose: Locks the changelog file's contract — decoding, the unknown-kind
//  fallback, and the bundled file's agreement with MARKETING_VERSION.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

struct ChangelogEntryTests {

    private func decode(_ json: String) throws -> [ChangelogEntry] {
        try JSONDecoder().decode([ChangelogEntry].self, from: Data(json.utf8))
    }

    @Test func aFullEntryDecodes() throws {
        let entries = try decode("""
        [{"version":"0.18","date":"2026-09-20","headline":"Weigh sessions",
          "changes":[{"kind":"added","text":"Weigh a spool."}]}]
        """)
        #expect(entries.count == 1)
        #expect(entries[0].version == "0.18")
        #expect(entries[0].headline == "Weigh sessions")
        #expect(entries[0].changes.first?.kind == .added)
        #expect(entries[0].changes.first?.text == "Weigh a spool.")
    }

    @Test func dateAndHeadlineAreOptional() throws {
        let entries = try decode("""
        [{"version":"0.18","changes":[{"kind":"fixed","text":"A fix."}]}]
        """)
        #expect(entries[0].date == nil)
        #expect(entries[0].headline == nil)
    }

    @Test func anUnknownKindDecodesAsImprovedRatherThanFailingTheFile() throws {
        // One bad word must not cost the user every note in the file.
        let entries = try decode("""
        [{"version":"0.18","changes":[
            {"kind":"sideways","text":"Something happened."},
            {"kind":"added","text":"And this still arrives."}]}]
        """)
        #expect(entries[0].changes.count == 2)
        #expect(entries[0].changes[0].kind == .improved)
        #expect(entries[0].changes[1].kind == .added)
    }

    @Test func theEntryIdIsItsVersion() throws {
        let entries = try decode("""
        [{"version":"0.17","changes":[]}]
        """)
        #expect(entries[0].id == "0.17")
        #expect(entries[0].release == ReleaseVersion("0.17"))
    }

    @Test func everyKindHasASymbol() {
        for kind in ChangeKind.allCases {
            #expect(!kind.symbolName.isEmpty)
        }
    }

    /// West of UTC, where a UTC-pinned parse rendered in the local zone lands
    /// on the previous calendar day. A test at this machine's own CEST offset
    /// would pass against the bug.
    private static let nonUTCZone = TimeZone(identifier: "America/New_York")!

    @Test func theDateIsTheCalendarDayItNames() throws {
        // Not an instant. Parsed and read back in the SAME west-of-UTC zone:
        // a UTC-pinned parse would put 2026-09-05T00:00:00Z on the 4th here,
        // which is the regression this pins down.
        let entries = try decode("""
        [{"version":"0.18","date":"2026-09-05","changes":[]}]
        """)
        let day = try #require(entries[0].day(in: Self.nonUTCZone))

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = Self.nonUTCZone
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 5)
    }

    @Test func anAbsentOrUnparseableDateHasNoDay() throws {
        let absent = try decode("""
        [{"version":"0.18","changes":[]}]
        """)
        #expect(absent[0].day() == nil)
        #expect(absent[0].formattedDate == nil)

        let malformed = try decode("""
        [{"version":"0.18","date":"not a date","changes":[]}]
        """)
        #expect(malformed[0].day() == nil)
        #expect(malformed[0].formattedDate == nil)
    }

    @Test func theBundledFileDecodesAndItsNewestVersionIsTheInstalledOne() throws {
        // `Bundle.main` is the app bundle under a hosted test run — the test
        // bundle carries neither the resource nor the app's MARKETING_VERSION.
        let app = Bundle.main
        let url = try #require(app.url(forResource: "Changelog", withExtension: "json"))
        let entries = try JSONDecoder().decode([ChangelogEntry].self, from: Data(contentsOf: url))
        #expect(!entries.isEmpty)

        let newest = try #require(entries.map(\.release).max())
        let installed = ReleaseVersion(app.appVersion ?? "")
        #expect(
            newest == installed,
            "Changelog.json's newest version must be the version it ships in"
        )
    }
}
