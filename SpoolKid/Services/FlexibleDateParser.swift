//
//  FlexibleDateParser.swift
//  SpoolKid
//
//  Purpose: the ONE tolerant timestamp parser. Three backends hand SpoolKid
//  dates in overlapping-but-not-identical shapes; this is where the accepted
//  set is decided, once.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// Parses the timestamp forms SpoolKid's backends actually send.
///
/// There used to be three of these — `Spool.decodeFlexibleDateIfPresent`,
/// `LocalRepository.parseDate` and `FilaManRepository.parseDate` — with
/// overlapping but non-identical fallback chains, which is A4's "one
/// implementation per concept" exactly: `Spool` rejected the timezone-less
/// form that `FilaManRepository` had to add, so the same string parsed or
/// didn't depending on which path read it. The union is the contract now.
///
/// Order is cheapest-and-strictest first. Returns `nil` rather than throwing:
/// a bad timestamp must not fail a whole spool's mapping. The one caller that
/// needs a hard failure — `Spool`'s decoder, which owes `Decodable` a typed
/// error — turns the `nil` into one itself.
nonisolated enum FlexibleDateParser {

    /// `nil` for a missing, empty, or unrecognised string.
    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return iso8601.date(from: string)
            ?? iso8601Fractional.date(from: string)
            ?? noTimeZone.date(from: string)
            ?? noTimeZoneFractional.date(from: string)
    }

    // MARK: - Formatters
    //
    // `ISO8601DateFormatter` REQUIRES a timezone and rejects a string without
    // one outright, which is why the last two are `DateFormatter`s: FilaMan's
    // own fixtures send `2026-08-25T10:30:00`. They are pinned to a POSIX
    // locale and the ISO calendar so a device's regional settings cannot
    // change what a server timestamp means, and read as UTC because a
    // timezone-less server timestamp has no other defensible reading.

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let noTimeZone = fixedFormat("yyyy-MM-dd'T'HH:mm:ss")

    private static let noTimeZoneFractional = fixedFormat("yyyy-MM-dd'T'HH:mm:ss.SSS")

    private static func fixedFormat(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }
}
