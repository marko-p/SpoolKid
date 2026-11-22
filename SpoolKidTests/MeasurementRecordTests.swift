import Testing
import Foundation
@testable import SpoolKid

struct MeasurementRecordTests {

    private static let noon = Date(timeIntervalSince1970: 1_757_000_000) // 2026-09-04

    private func record(
        id: String = "r",
        spool: Int = 1,
        gross: Double = 1238,
        net: Double? = 1000,
        at: Date = MeasurementRecordTests.noon,
        origin: MeasurementRecord.Origin = .thisDevice
    ) -> MeasurementRecord {
        MeasurementRecord(
            id: id, spoolID: spool, grossWeight: gross, netWeight: net,
            recordedAt: at, origin: origin
        )
    }

    // MARK: - Merging

    @Test func aWeighWrittenByThisAppIsNotShownTwice() {
        // SpoolKid logs locally AND writes to the backend, so the same weighing
        // arrives from both. Showing both reads as a double-save.
        let local = record(id: "local", origin: .thisDevice)
        let remote = record(id: "remote", at: Self.noon.addingTimeInterval(30), origin: .backend)

        let merged = MeasurementRecord.merge(local: [local], backend: [remote])

        #expect(merged.count == 1)
        #expect(merged.first?.origin == .backend)
    }

    @Test func theBackendCopyWinsACollision() {
        let local = record(id: "local", origin: .thisDevice)
        let remote = record(id: "remote", origin: .backend)
        #expect(MeasurementRecord.merge(local: [local], backend: [remote]).first?.id == "remote")
    }

    @Test func aLocalWeighTheBackendNeverSawSurvives() {
        // A failed write, or a Local-backend session: the device log is the
        // only record there is.
        let local = record(id: "local")
        #expect(MeasurementRecord.merge(local: [local], backend: []).map(\.id) == ["local"])
    }

    @Test func sameWeightOnADifferentSpoolIsNotADuplicate() {
        let local = record(id: "local", spool: 1)
        let remote = record(id: "remote", spool: 2, origin: .backend)
        #expect(MeasurementRecord.merge(local: [local], backend: [remote]).count == 2)
    }

    @Test func sameSpoolAndTimeButADifferentWeightIsNotADuplicate() {
        let local = record(id: "local", gross: 1238)
        let remote = record(id: "remote", gross: 1240, origin: .backend)
        #expect(MeasurementRecord.merge(local: [local], backend: [remote]).count == 2)
    }

    @Test func aWeighWellOutsideTheWindowIsItsOwnMeasurement() {
        // Weighing the same spool to the same gram a week later is a real
        // second measurement, not an echo of the first.
        let local = record(id: "local", at: Self.noon)
        let remote = record(
            id: "remote", at: Self.noon.addingTimeInterval(7 * 86_400), origin: .backend
        )
        #expect(MeasurementRecord.merge(local: [local], backend: [remote]).count == 2)
    }

    @Test func mergedRecordsComeBackNewestFirst() {
        let old = record(id: "old", gross: 1, at: Self.noon.addingTimeInterval(-86_400))
        let new = record(id: "new", gross: 2, at: Self.noon, origin: .backend)
        let middle = record(id: "mid", gross: 3, at: Self.noon.addingTimeInterval(-3600))
        #expect(
            MeasurementRecord.merge(local: [old, middle], backend: [new]).map(\.id)
                == ["new", "mid", "old"]
        )
    }

    // MARK: - Age

    @Test func todayIsTheSameCalendarDay() {
        #expect(MeasurementRecord.age(of: Self.noon, now: Self.noon) == .today)
    }

    @Test func yesterdayIsThePreviousCalendarDayNotTwentyFourHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 23))!
        let justOverAnHourAgo = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 3, hour: 22)
        )!
        #expect(
            MeasurementRecord.age(of: justOverAnHourAgo, now: now, calendar: calendar) == .yesterday
        )
    }

    @Test func aBackendClockRunningAheadDoesNotSinkToTheBottom() {
        // The backend stamps its own events. A server minutes ahead of this
        // phone must not file today's weighing under "Older".
        let ahead = Self.noon.addingTimeInterval(600)
        #expect(MeasurementRecord.age(of: ahead, now: Self.noon) == .today)
    }

    @Test func olderIsTheFallback() {
        let lastYear = Self.noon.addingTimeInterval(-400 * 86_400)
        #expect(MeasurementRecord.age(of: lastYear, now: Self.noon) == .older)
    }

    // MARK: - Grouping

    @Test func groupsComeBackInAgeOrderAndSkipEmptyOnes() {
        let today = record(id: "t", at: Self.noon)
        let ancient = record(id: "a", at: Self.noon.addingTimeInterval(-400 * 86_400))

        let groups = MeasurementRecord.grouped([today, ancient], now: Self.noon)

        #expect(groups.map(\.age) == [.today, .older])
        #expect(groups.first?.records.map(\.id) == ["t"])
    }

    @Test func groupingPreservesInputOrderWithinAGroup() {
        let first = record(id: "1", at: Self.noon)
        let second = record(id: "2", at: Self.noon.addingTimeInterval(-60))
        let groups = MeasurementRecord.grouped([first, second], now: Self.noon)
        #expect(groups.first?.records.map(\.id) == ["1", "2"])
    }

    @Test func noRecordsMeansNoGroups() {
        #expect(MeasurementRecord.grouped([], now: Self.noon).isEmpty)
    }
}
