//
//  CalendarDateCodecTests.swift
//  SpoolKidTests
//
//  Fix round 1 (2026-08-28): an ISO8601 (UTC) formatter shifted `purchase_date`
//  by a day for anyone off UTC — `DatePicker` hands back local midnight, not a
//  UTC instant, so formatting/parsing through a UTC-fixed reading disagrees
//  with the calendar day the user actually picked. These pin both directions
//  at a non-UTC offset so the shift cannot reappear silently.
//

import Testing
import Foundation
@testable import SpoolKid

struct CalendarDateCodecTests {
    /// A concrete negative UTC offset (no DST ambiguity in August), matching
    /// the "negative offset" case the bug report described.
    private static let nonUTCZone = TimeZone(identifier: "America/New_York")!

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = nonUTCZone
        return calendar
    }

    /// A `Date` at local midnight in `nonUTCZone` — what `DatePicker` hands
    /// back for a picked day, reproduced without needing the picker itself.
    private static func localMidnight(year: Int, month: Int, day: Int) -> Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - Format

    @Test func formatsLocalMidnightAsThePickedCalendarDay() {
        let picked = Self.localMidnight(year: 2026, month: 8, day: 28)

        #expect(CalendarDateCodec.string(from: picked, timeZone: Self.nonUTCZone) == "2026-08-28")
    }

    // MARK: - Parse

    /// FilaMan always echoes back a full instant regardless of which form was
    /// sent (probed live: both `"2026-08-28"` and a full timestamp land on
    /// `"2026-08-28T00:00:00Z"`). Parsing that instant must not slip to the
    /// 27th at a negative offset — the trailing `T00:00:00Z` is discarded
    /// rather than read as a UTC instant.
    @Test func parsesFilaMansEchoedInstantAsTheSameCalendarDay() throws {
        let parsed = try #require(CalendarDateCodec.date(from: "2026-08-28T00:00:00Z", timeZone: Self.nonUTCZone))
        let components = Self.calendar.dateComponents([.year, .month, .day], from: parsed)

        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 28)
    }

    // MARK: - Round trip

    /// The whole point: a date picked in the form, written, read back from
    /// what FilaMan stores, and re-displayed must land on the SAME calendar
    /// day at a non-UTC offset — not one day off in either direction.
    @Test func aDatePickedAtANonUTCOffsetRoundTripsToTheSameCalendarDay() throws {
        let picked = Self.localMidnight(year: 2026, month: 8, day: 28)

        let wire = CalendarDateCodec.string(from: picked, timeZone: Self.nonUTCZone)
        let roundTripped = try #require(CalendarDateCodec.date(from: wire, timeZone: Self.nonUTCZone))
        let components = Self.calendar.dateComponents([.year, .month, .day], from: roundTripped)

        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 28)
    }

    // MARK: - Edges

    @Test func nilAndEmptyStringsParseToNil() {
        #expect(CalendarDateCodec.date(from: nil, timeZone: Self.nonUTCZone) == nil)
        #expect(CalendarDateCodec.date(from: "", timeZone: Self.nonUTCZone) == nil)
    }
}
