//
//  FlexibleDateParserTests.swift
//  SpoolKidTests
//
//  The union of what the three former parsers accepted, plus the cases that
//  differed between them — `Spool` used to reject the timezone-less form
//  `FilaManRepository` was extended to accept, so the same string parsed or
//  didn't depending on which read it (A4).
//

import Foundation
import Testing
@testable import SpoolKid

struct FlexibleDateParserTests {

    /// 2026-08-25T10:30:00Z as a Unix interval, so every expectation below can
    /// be stated against one instant rather than a rebuilt `DateComponents`.
    private let instant = Date(timeIntervalSince1970: 1_787_653_800)

    // MARK: - Nothing to parse

    @Test func nilIsNotADate() {
        #expect(FlexibleDateParser.date(from: nil) == nil)
    }

    @Test func theEmptyStringIsNotADate() {
        #expect(FlexibleDateParser.date(from: "") == nil)
    }

    @Test func garbageIsNilRatherThanAThrow() {
        #expect(FlexibleDateParser.date(from: "not a date") == nil)
        #expect(FlexibleDateParser.date(from: "2026-13-45") == nil)
    }

    // MARK: - What every former parser accepted

    @Test func acceptsISO8601WithATimezone() {
        #expect(FlexibleDateParser.date(from: "2026-08-25T10:30:00Z") == instant)
    }

    @Test func acceptsISO8601WithFractionalSeconds() {
        #expect(FlexibleDateParser.date(from: "2026-08-25T10:30:00.000Z") == instant)
    }

    @Test func acceptsAnOffsetRatherThanZulu() {
        #expect(FlexibleDateParser.date(from: "2026-08-25T12:30:00+02:00") == instant)
    }

    // MARK: - The form only FilaMan's parser accepted

    /// `ISO8601DateFormatter` rejects a string with no timezone outright, so
    /// this is the case that made a third parser exist. Read as UTC.
    @Test func acceptsTheTimezonelessFormFilaManSends() {
        #expect(FlexibleDateParser.date(from: "2026-08-25T10:30:00") == instant)
    }

    @Test func acceptsTheTimezonelessFormWithFractionalSeconds() {
        #expect(FlexibleDateParser.date(from: "2026-08-25T10:30:00.000") == instant)
    }

    // MARK: - The unification itself

    /// The point of the change: one string, one answer, whichever backend's
    /// path reads it. `Spool`'s decoder used to return a `DecodingError` for
    /// this exact input while `FilaManRepository` returned a date.
    @Test func everyBackendsPathNowAgreesOnTheSameString() {
        let timezoneless = "2026-08-25T10:30:00"

        #expect(FlexibleDateParser.date(from: timezoneless) != nil)
        #expect(decodedSpoolDate(json: "\"\(timezoneless)\"") == instant)
    }

    // MARK: - `Spool`'s decoder keeps its own two obligations

    /// Unix seconds are a decoding concern — which JSON type the key holds —
    /// and stay in `Spool`, so they must keep working after the split.
    @Test func spoolStillDecodesAUnixTimestamp() {
        #expect(decodedSpoolDate(json: "1787653800") == instant)
    }

    /// `Decodable` owes its caller a typed error, so the decoder still throws
    /// where the parser returns nil.
    @Test func spoolStillThrowsOnAnUnparseableString() {
        #expect(throws: DecodingError.self) {
            _ = try decodeSpool(json: "\"not a date\"")
        }
    }

    @Test func spoolStillReadsAnExplicitNullAsNoDate() throws {
        #expect(try decodeSpool(json: "null").registered == nil)
    }

    // MARK: - Helpers

    private func decodeSpool(json registeredValue: String) throws -> Spool {
        let payload = """
        {"id": 1, "filament": {"id": 2}, "registered": \(registeredValue)}
        """
        return try JSONDecoder().decode(Spool.self, from: Data(payload.utf8))
    }

    private func decodedSpoolDate(json registeredValue: String) -> Date? {
        try? decodeSpool(json: registeredValue).registered
    }
}
