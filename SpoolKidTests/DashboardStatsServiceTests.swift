//
//  DashboardStatsServiceTests.swift
//  SpoolKidTests
//

import Testing
import Foundation
@testable import SpoolKid

struct DashboardStatsServiceTests {

    private func spool(
        id: Int = 1,
        remaining: Double? = nil,
        initial: Double? = nil,
        filamentWeight: Double? = nil,
        material: String? = "PLA",
        price: Double? = nil,
        archived: Bool? = nil,
        usedWeight: Double? = nil,
        registered: Date? = nil,
        firstUsed: Date? = nil,
        lastUsed: Date? = nil,
        filamentId: Int = 1,
        colorHex: String? = nil,
        cardUIDsExtra: [String]? = nil
    ) -> Spool {
        let extra: [String: String]? = cardUIDsExtra.map { ["card_uids": CardUIDsCodec.encode($0)] }
        return Spool(
            id: id,
            filament: Filament(id: filamentId, name: "F\(id)", material: material, colorHex: colorHex, weight: filamentWeight),
            registered: registered,
            firstUsed: firstUsed,
            lastUsed: lastUsed,
            remainingWeight: remaining,
            initialWeight: initial,
            usedWeight: usedWeight,
            price: price,
            archived: archived,
            extra: extra,
            statusId: nil, externalId: nil, purchaseDate: nil
        )
    }

    // MARK: fillFraction

    @Test func fillFractionUsesInitialWeight() {
        #expect(DashboardStatsService.fillFraction(for: spool(remaining: 500, initial: 1000)) == 0.5)
    }

    @Test func fillFractionFallsBackToFilamentNetWeight() {
        #expect(DashboardStatsService.fillFraction(for: spool(remaining: 250, initial: nil, filamentWeight: 1000)) == 0.25)
    }

    @Test func fillFractionNilWhenNoBasis() {
        #expect(DashboardStatsService.fillFraction(for: spool(remaining: 500, initial: nil, filamentWeight: nil)) == nil)
    }

    @Test func fillFractionNilWhenNoRemaining() {
        #expect(DashboardStatsService.fillFraction(for: spool(remaining: nil, initial: 1000)) == nil)
    }

    @Test func fillFractionNilOnZeroBasis() {
        #expect(DashboardStatsService.fillFraction(for: spool(remaining: 100, initial: 0)) == nil)
    }

    @Test func fillFractionClampsNegativeRemaining() {
        #expect(DashboardStatsService.fillFraction(for: spool(remaining: -50, initial: 1000)) == 0)
    }

    // MARK: bucket boundaries (half-open: 75→Normal, 50→Low, 25→Critical)

    @Test func bucketBoundaries() {
        #expect(DashboardStatsService.bucket(for: spool(remaining: 1000, initial: 1000)) == .full)
        #expect(DashboardStatsService.bucket(for: spool(remaining: 751, initial: 1000)) == .full)
        #expect(DashboardStatsService.bucket(for: spool(remaining: 750, initial: 1000)) == .normal)
        #expect(DashboardStatsService.bucket(for: spool(remaining: 501, initial: 1000)) == .normal)
        #expect(DashboardStatsService.bucket(for: spool(remaining: 500, initial: 1000)) == .low)
        #expect(DashboardStatsService.bucket(for: spool(remaining: 251, initial: 1000)) == .low)
        #expect(DashboardStatsService.bucket(for: spool(remaining: 250, initial: 1000)) == .critical)
        #expect(DashboardStatsService.bucket(for: spool(remaining: 1, initial: 1000)) == .critical)
    }

    @Test func bucketEmptyOnZeroOrNegativeRemaining() {
        #expect(DashboardStatsService.bucket(for: spool(remaining: 0, initial: 1000)) == .empty)
        #expect(DashboardStatsService.bucket(for: spool(remaining: -5, initial: 1000)) == .empty)
        // Empty wins even with no weight basis.
        #expect(DashboardStatsService.bucket(for: spool(remaining: 0, initial: nil, filamentWeight: nil)) == .empty)
    }

    @Test func bucketNilWhenIndeterminate() {
        #expect(DashboardStatsService.bucket(for: spool(remaining: 500, initial: nil, filamentWeight: nil)) == nil)
        #expect(DashboardStatsService.bucket(for: spool(remaining: nil, initial: 1000)) == nil)
    }

    // MARK: aggregates

    @Test func statusCountsAndTotalsExcludeArchived() {
        let spools = [
            spool(id: 1, remaining: 1000, initial: 1000),            // full
            spool(id: 2, remaining: 600, initial: 1000),             // normal
            spool(id: 3, remaining: 400, initial: 1000),             // low
            spool(id: 4, remaining: 100, initial: 1000),             // critical
            spool(id: 5, remaining: 0, initial: 1000),               // empty
            spool(id: 6, remaining: 500, initial: nil, filamentWeight: nil), // indeterminate → omitted
            spool(id: 7, remaining: 1000, initial: 1000, archived: true)     // archived → omitted
        ]
        let counts = DashboardStatsService.statusCounts(in: spools)
        #expect(counts[.full] == 1)
        #expect(counts[.normal] == 1)
        #expect(counts[.low] == 1)
        #expect(counts[.critical] == 1)
        #expect(counts[.empty] == 1)
    }

    @Test func totalValueSumsPricesIgnoringArchivedAndNil() {
        let spools = [
            spool(id: 1, price: 20.0),
            spool(id: 2, price: nil),
            spool(id: 3, price: 5.50),
            spool(id: 4, price: 99.0, archived: true)
        ]
        #expect(DashboardStatsService.totalValue(of: spools) == 25.50)
    }

    @Test func currencyFormattingHonorsCodeAndFallsBack() {
        let eur = DashboardStatsService.formatCurrency(1234.5, code: "EUR")
        #expect(eur.contains("€"))
        let fallback = DashboardStatsService.formatCurrency(10, code: nil)
        #expect(!fallback.isEmpty)
        let blank = DashboardStatsService.formatCurrency(10, code: "  ")
        #expect(!blank.isEmpty)
    }

    // MARK: filament statistics

    @Test func filamentStatisticsGroupsSortsAndSumsRemaining() {
        let spools = [
            spool(id: 1, remaining: 1000, material: "PLA"),
            spool(id: 2, remaining: 1000, material: "PLA"),
            spool(id: 3, remaining: 1000, material: "ASA"),
            spool(id: 4, remaining: 500, material: nil),            // → "Unknown"
            spool(id: 5, remaining: 1000, material: "PLA", archived: true) // excluded
        ]
        let stats = DashboardStatsService.filamentStatistics(for: spools)
        #expect(stats.map(\.material) == ["PLA", "ASA", "Unknown"]) // count desc, then name
        #expect(stats[0].spoolCount == 2)
        #expect(stats[0].remainingKilograms == 2.0)
        #expect(stats[2].material == "Unknown")
        #expect(stats[2].remainingWeightGrams == 500)
    }

    // MARK: drill-down predicates

    @Test func spoolsInBucketMatchesClassification() {
        let spools = [
            spool(id: 1, remaining: 1000, initial: 1000), // full
            spool(id: 2, remaining: 100, initial: 1000),  // critical
            spool(id: 3, remaining: 1000, initial: 1000, archived: true) // archived excluded
        ]
        #expect(DashboardStatsService.spools(in: spools, bucket: .full).map(\.id) == [1])
        #expect(DashboardStatsService.spools(in: spools, bucket: .critical).map(\.id) == [2])
    }

    @Test func spoolsInMaterialUsesSameKeyAsGrouping() {
        let spools = [
            spool(id: 1, material: "PLA"),
            spool(id: 2, material: nil),
            spool(id: 3, material: "PLA")
        ]
        #expect(DashboardStatsService.spools(in: spools, material: "PLA").map(\.id) == [1, 3])
        #expect(DashboardStatsService.spools(in: spools, material: "Unknown").map(\.id) == [2])
    }

    // MARK: tag coverage

    @Test func tagCoverageCountsLedgerAndCardUIDs() {
        let spools = [spool(id: 1, cardUIDsExtra: ["AA"]),
                      spool(id: 2),
                      spool(id: 3, cardUIDsExtra: ["BB","CC"]),
                      spool(id: 4)]
        let ledger = ["DD": 2]
        let cov = DashboardStatsService.tagCoverage(in: spools, ledger: ledger)
        #expect(cov == TagCoverage(untagged: 1, single: 2, multi: 1))
    }

    @Test func untaggedExcludesLedgerTagged() {
        let spools = [spool(id: 1), spool(id: 2)]
        let ledger = ["EE": 1]
        #expect(DashboardStatsService.untaggedSpools(in: spools, ledger: ledger).map(\.id) == [2])
    }

    // MARK: colour stats

    @Test func colorStatsGroupNormalizedDescByCount() {
        let spools = [spool(id: 1, colorHex: "#FF0000"), spool(id: 2, colorHex: "ff0000"), spool(id: 3, colorHex: "00FF00")]
        let stats = DashboardStatsService.colorStats(in: spools)
        #expect(stats.first == ColorStat(hex: "FF0000", count: 2))
        #expect(DashboardStatsService.distinctColorCount(in: spools) == 2)
    }

    // MARK: filament runway

    @Test func runwaySuppressedBelowThresholds() {
        let day: TimeInterval = 86400
        let s = spool(id: 1, remaining: 900, usedWeight: 40,
                      firstUsed: Date(timeIntervalSince1970: 0),
                      lastUsed: Date(timeIntervalSince1970: 30*day), filamentId: 1)
        #expect(DashboardStatsService.filamentRunway(in: [s], now: Date(timeIntervalSince1970: 30*day)).first?.daysOfStock == nil)
    }

    @Test func runwaySuppressedBelowSpanThreshold() {
        let day: TimeInterval = 86400
        // 200 g used over only 5 days (< 14-day minimum) → estimate suppressed
        let s = spool(id: 1, remaining: 500, usedWeight: 200,
                      firstUsed: Date(timeIntervalSince1970: 0),
                      lastUsed: Date(timeIntervalSince1970: 5*day), filamentId: 7)
        #expect(DashboardStatsService.filamentRunway(in: [s], now: Date(timeIntervalSince1970: 5*day)).first?.daysOfStock == nil)
    }

    @Test func runwayComputesDaysOfStock() {
        let day: TimeInterval = 86400
        let s = spool(id: 1, remaining: 500, usedWeight: 200,
                      firstUsed: Date(timeIntervalSince1970: 0),
                      lastUsed: Date(timeIntervalSince1970: 20*day), filamentId: 5)
        let r = DashboardStatsService.filamentRunway(in: [s], now: Date(timeIntervalSince1970: 20*day)).first
        #expect(r?.ratePerDay == 10)
        #expect(r?.daysOfStock == 50)
    }

    @Test func reorderSoonFiltersByHorizon() {
        let day: TimeInterval = 86400
        let s = spool(id: 1, remaining: 140, usedWeight: 280,
                      firstUsed: Date(timeIntervalSince1970: 0),
                      lastUsed: Date(timeIntervalSince1970: 20*day), filamentId: 9)
        #expect(DashboardStatsService.reorderSoon(in: [s], now: Date(timeIntervalSince1970: 20*day)).map(\.filamentId) == [9])
    }

    // MARK: TagCoverage computed props

    @Test func tagCoverageDerivedNumbers() {
        let c = TagCoverage(untagged: 3, single: 5, multi: 2)
        #expect(c.tagged == 7)
        #expect(c.total == 10)
        #expect(c.percentTagged == 70)
    }

    @Test func tagCoverageEmptyIsZeroPercent() {
        let c = TagCoverage(untagged: 0, single: 0, multi: 0)
        #expect(c.total == 0)
        #expect(c.percentTagged == 0)
    }

    // MARK: isMoreRecent

    private let day: TimeInterval = 86_400

    @Test func recencyOrdersByCoalesceLastUsedThenRegistered() {
        // s1 used most recently; s2 never used but registered latest; s3 used earlier.
        let s1 = spool(id: 1, lastUsed: Date(timeIntervalSince1970: 30 * day))
        let s2 = spool(id: 2, registered: Date(timeIntervalSince1970: 25 * day))
        let s3 = spool(id: 3, registered: Date(timeIntervalSince1970: 5 * day),
                       lastUsed: Date(timeIntervalSince1970: 10 * day))
        let result = [s3, s2, s1].sorted(by: DashboardStatsService.isMoreRecent)
        #expect(result.map(\.id) == [1, 2, 3])
    }

    @Test func recencyUsesRegisteredWhenNeverUsed() {
        let used = spool(id: 1, registered: Date(timeIntervalSince1970: 0),
                         lastUsed: Date(timeIntervalSince1970: 1 * day))
        let neverUsed = spool(id: 2, registered: Date(timeIntervalSince1970: 5 * day))
        let result = [used, neverUsed].sorted(by: DashboardStatsService.isMoreRecent)
        #expect(result.map(\.id) == [2, 1])
    }

    @Test func recencyWithoutDatesSortsLastByDescendingId() {
        let dated = spool(id: 1, registered: Date(timeIntervalSince1970: 5 * day))
        let noDateA = spool(id: 7)
        let noDateB = spool(id: 8)
        let result = [noDateA, dated, noDateB].sorted(by: DashboardStatsService.isMoreRecent)
        #expect(result.map(\.id) == [1, 8, 7])
    }
}
