//
//  CalendarDateCodec.swift
//  SpoolKid
//
//  Purpose: Format/parse a CALENDAR date (FilaMan's `purchase_date`), as
//  opposed to an instant.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// `purchase_date` is a calendar day, not a point in time — unlike
/// `registered`/`first_used`/`last_used`, which are genuine instants and stay
/// on `FlexibleDateParser`/`SpoolFormView`'s ISO8601 formatter.
///
/// `DatePicker` hands back a `Date` at LOCAL midnight of the day the user
/// picked. Formatting that with an ISO8601 (UTC) formatter and later parsing
/// the UTC instant back shifts the calendar day by one for anyone off UTC —
/// west of UTC on write (local midnight is still "yesterday" in UTC), and
/// again on read at a negative offset (`2026-08-28T00:00:00Z` renders as
/// August 27 there). Proven live 2026-08-28: FilaMan stores whatever calendar
/// day it is sent (`2026-08-28` or `2026-08-28T00:00:00Z` alike, both land on
/// `2026-08-28T00:00:00Z`) — the shift was entirely SpoolKid's own, introduced
/// by reading and writing the day through a UTC-fixed formatter.
///
/// ONE formatter, used for both directions, is what keeps a picked date
/// round-tripping to the same calendar day: format and parse must read the
/// SAME zone's midnight, or the day comes back one off again. `timeZone`
/// defaults to `.current` — the same zone `DatePicker`/`Calendar.current`
/// anchor a "calendar day" to — and is a parameter only so a test can pin a
/// non-UTC offset without mutating the process's global timezone.
nonisolated enum CalendarDateCodec {
    /// `"yyyy-MM-dd"`, e.g. `"2026-08-28"` — the form the live probe showed
    /// FilaMan accepts and normalises.
    static func string(from date: Date, timeZone: TimeZone = .current) -> String {
        formatter(timeZone: timeZone).string(from: date)
    }

    /// Reads only the date portion: FilaMan echoes back a full instant
    /// (`"2026-08-28T00:00:00Z"`) regardless of which form was sent, so the
    /// trailing time-of-day/zone — an artifact of storage, not something the
    /// user stated — is discarded rather than parsed as an instant.
    static func date(from string: String?, timeZone: TimeZone = .current) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let datePart = String(string.prefix(10))
        return formatter(timeZone: timeZone).date(from: datePart)
    }

    private static func formatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
