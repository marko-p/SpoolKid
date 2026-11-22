//
//  MeasurementRecord.swift
//  SpoolKid
//
//  Purpose: One weighing of one spool, from whichever source knew about it —
//  this app's own log or the backend's event history — plus the rules for
//  merging the two and grouping them by how long ago they happened.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct MeasurementRecord: Identifiable, Equatable, Codable, Sendable {

    /// Where the record came from. NOT who took the measurement — no backend
    /// SpoolKid talks to can answer that. FilaMan's `source` reads `"ui"` for a
    /// measurement posted through its API and for one entered in its own web
    /// page alike (probed 2026-09-04), so the only honest distinction is
    /// "this device remembers doing it" versus "the server has it on file".
    enum Origin: String, Codable, Sendable {
        /// Written by this app, on this device, and kept in `WeighHistoryStore`.
        case thisDevice
        /// Read back from the backend's own history.
        case backend
    }

    let id: String
    let spoolID: Int
    /// What was on the scale — the whole spool, filament and core together.
    let grossWeight: Double
    /// The filament-only figure this reading implied, when the source stated
    /// one. A backend event that carries only a delta has no net weight to
    /// report and must not have one invented for it.
    let netWeight: Double?
    let recordedAt: Date
    let origin: Origin
    let note: String?

    init(
        id: String,
        spoolID: Int,
        grossWeight: Double,
        netWeight: Double?,
        recordedAt: Date,
        origin: Origin,
        note: String? = nil
    ) {
        self.id = id
        self.spoolID = spoolID
        self.grossWeight = grossWeight
        self.netWeight = netWeight
        self.recordedAt = recordedAt
        self.origin = origin
        self.note = note
    }

    // MARK: - Merging

    /// How close in time two records of the same weight must be to be believed
    /// to be the same weighing. Generous: SpoolKid posts to the backend and
    /// logs locally within the same second, but the backend stamps the event
    /// with its own clock, which is not this device's.
    static let duplicateWindow: TimeInterval = 120

    /// Merges this device's log with the backend's history into one list,
    /// newest first.
    ///
    /// SpoolKid records every weigh it performs locally AND writes it to the
    /// backend, so a spool weighed through this app appears in both lists.
    /// Rendering both would show the user their own measurement twice, which
    /// reads as a double-save. The backend copy wins when they collide: it is
    /// the shared record, visible to every other client, and it survives this
    /// device.
    static func merge(
        local: [MeasurementRecord],
        backend: [MeasurementRecord]
    ) -> [MeasurementRecord] {
        let survivingLocal = local.filter { candidate in
            !backend.contains { known in
                known.spoolID == candidate.spoolID
                    && known.grossWeight == candidate.grossWeight
                    && abs(known.recordedAt.timeIntervalSince(candidate.recordedAt)) <= duplicateWindow
            }
        }
        return (backend + survivingLocal).sorted { $0.recordedAt > $1.recordedAt }
    }

    // MARK: - Grouping

    /// How long ago a measurement happened, coarsely enough to be a section
    /// header. Calendar-based, not arithmetic on intervals: "yesterday" means
    /// the previous calendar day, not 24-to-48 hours ago.
    enum Age: String, CaseIterable, Equatable, Sendable {
        case today = "Today"
        case yesterday = "Yesterday"
        case thisWeek = "Earlier this week"
        case thisMonth = "Earlier this month"
        case older = "Older"
    }

    static func age(
        of date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Age {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }
        // A date in the FUTURE — a backend clock running ahead of this one —
        // is not "older". Anything past today reads as today rather than
        // falling through every window to the bottom of the list.
        if date > now { return .today }
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) { return .thisWeek }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) { return .thisMonth }
        return .older
    }

    /// The records grouped by age, in `Age.allCases` order, skipping empty
    /// groups. Input order within a group is preserved, so a caller that sorted
    /// newest-first stays newest-first.
    static func grouped(
        _ records: [MeasurementRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [(age: Age, records: [MeasurementRecord])] {
        var buckets: [Age: [MeasurementRecord]] = [:]
        for record in records {
            buckets[age(of: record.recordedAt, now: now, calendar: calendar), default: []]
                .append(record)
        }
        return Age.allCases.compactMap { age in
            guard let records = buckets[age], !records.isEmpty else { return nil }
            return (age, records)
        }
    }
}
