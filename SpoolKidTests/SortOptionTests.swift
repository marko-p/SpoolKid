import Testing
import Foundation
@testable import SpoolKid

struct SortOptionTests {

    @Test func spoolSortOptionHasAllCases() {
        let allCases = SpoolSortOption.allCases
        #expect(allCases.count == 8)
    }

    @Test func spoolSortOptionLabelsNotEmpty() {
        for option in SpoolSortOption.allCases {
            #expect(!option.label.isEmpty)
        }
    }

    @Test func spoolSortOptionSystemImagesNotEmpty() {
        for option in SpoolSortOption.allCases {
            #expect(!option.systemImage.isEmpty)
        }
    }

    @Test func spoolSortOptionRawValuesUnique() {
        let rawValues = SpoolSortOption.allCases.map { $0.rawValue }
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test func spoolSortOptionIdMatchesRawValue() {
        for option in SpoolSortOption.allCases {
            #expect(option.id == option.rawValue)
        }
    }

    // A menu row shows only one icon, so the selected
    // option's icon slot carries the sort direction.
    @Test @MainActor func selectedSortRowIconShowsDirection() {
        let up = SortOptionRows<SpoolSortOption>.iconName(for: .name, selected: .name, ascending: true)
        let down = SortOptionRows<SpoolSortOption>.iconName(for: .name, selected: .name, ascending: false)
        #expect(up == "chevron.up")
        #expect(down == "chevron.down")
    }

    @Test @MainActor func unselectedSortRowKeepsItsOwnIcon() {
        for option in SpoolSortOption.allCases where option != .name {
            let icon = SortOptionRows<SpoolSortOption>.iconName(for: option, selected: .name, ascending: true)
            #expect(icon == option.systemImage)
        }
    }

    // Manual order ignores `ascending`, so its row must not show a direction.
    @Test @MainActor func manualLocationSortRowShowsNoDirection() {
        let icon = SortOptionRows<LocationSortOption>.iconName(for: .manual, selected: .manual, ascending: true)
        #expect(icon == LocationSortOption.manual.systemImage)
    }

    // Two never-used spools tie on Last Used; the one registered later is the
    // more recent. A real use still beats a never-used spool, however new.
    @Test func lastUsedTiesBreakByRegistered() throws {
        let formatter = ISO8601DateFormatter()
        let older = try #require(formatter.date(from: "2026-01-01T00:00:00Z"))
        let newer = try #require(formatter.date(from: "2026-06-01T00:00:00Z"))
        let used = try #require(formatter.date(from: "2026-02-01T00:00:00Z"))
        func spool(_ id: Int, registered: Date, lastUsed: Date? = nil) -> Spool {
            Spool(id: id, filament: Filament(id: id), registered: registered, lastUsed: lastUsed,
                  statusId: nil, externalId: nil, purchaseDate: nil)
        }
        let neverUsedOlder = spool(1, registered: older)
        let neverUsedNewer = spool(2, registered: newer)
        let usedOlder = spool(3, registered: older, lastUsed: used)

        #expect(SpoolSortOption.lastUsed.areInIncreasingOrder(neverUsedOlder, neverUsedNewer) == true)
        #expect(SpoolSortOption.lastUsed.areInIncreasingOrder(neverUsedNewer, neverUsedOlder) == false)
        #expect(SpoolSortOption.lastUsed.areInIncreasingOrder(neverUsedNewer, usedOlder) == true)
        #expect(SpoolSortOption.lastUsed.areInIncreasingOrder(usedOlder, neverUsedNewer) == false)

        // Library spools carry neither date: the final tie-break on id keeps the order
        // total, so the descending flip (`!result`) is a valid ordering too.
        func bare(_ id: Int) -> Spool {
            Spool(id: id, filament: Filament(id: id), statusId: nil, externalId: nil, purchaseDate: nil)
        }
        let bareSpools = [bare(2), bare(9), bare(5)]
        #expect(SpoolSortOption.lastUsed.areInIncreasingOrder(bare(2), bare(5)) == true)
        #expect(SpoolSortOption.lastUsed.areInIncreasingOrder(bare(5), bare(2)) == false)
        #expect(bareSpools.sorted { SpoolSortOption.lastUsed.areInIncreasingOrder($0, $1) }.map(\.id) == [2, 5, 9])
        #expect(bareSpools.sorted { !SpoolSortOption.lastUsed.areInIncreasingOrder($0, $1) }.map(\.id) == [9, 5, 2])
    }

    // MARK: - Recent

    private func recencySpool(_ id: Int, registered: Date? = nil, lastUsed: Date? = nil) -> Spool {
        Spool(id: id, filament: Filament(id: id), registered: registered, lastUsed: lastUsed,
              statusId: nil, externalId: nil, purchaseDate: nil)
    }

    @Test func recentSitsRightAfterLastUsed() throws {
        let cases = SpoolSortOption.allCases
        let lastUsed = try #require(cases.firstIndex(of: .lastUsed))
        #expect(cases[lastUsed + 1] == .recent)
        #expect(SpoolSortOption.recent.label == "Recent")
        #expect(SpoolSortOption.recent.systemImage == "clock.arrow.circlepath")
    }

    // A spool added today has not been used, but it is the most recent thing in the
    // library: `lastUsed ?? registered` puts it ahead of one used last week.
    @Test func recentPutsANewNeverUsedSpoolBeforeOneUsedLastWeek() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let lastWeek = today.addingTimeInterval(-7 * 86_400)
        let newNeverUsed = recencySpool(1, registered: today)
        let usedLastWeek = recencySpool(2, registered: lastWeek.addingTimeInterval(-30 * 86_400), lastUsed: lastWeek)

        #expect(SpoolSortOption.recent.areInIncreasingOrder(usedLastWeek, newNeverUsed) == true)
        #expect(SpoolSortOption.recent.areInIncreasingOrder(newNeverUsed, usedLastWeek) == false)
        let descending = [usedLastWeek, newNeverUsed].sorted { !SpoolSortOption.recent.areInIncreasingOrder($0, $1) }
        #expect(descending.map(\.id) == [1, 2])
    }

    // A Library spool has no `registered` (LocalRepository does not map it) and no
    // `lastUsed` until a weigh-in, so the order falls back to the id: newest first
    // when descending.
    @Test func recentFallsBackToIdWithoutDates() {
        let spools = [recencySpool(4), recencySpool(11), recencySpool(7)]

        #expect(spools.sorted { SpoolSortOption.recent.areInIncreasingOrder($0, $1) }.map(\.id) == [4, 7, 11])
        #expect(spools.sorted { !SpoolSortOption.recent.areInIncreasingOrder($0, $1) }.map(\.id) == [11, 7, 4])
    }

    // `.recent` and `DashboardStatsService.isMoreRecent` are one rule.
    @Test func recentAgreesWithTheSharedRecencyRule() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let spools = [
            recencySpool(1, registered: base),
            recencySpool(2, registered: base.addingTimeInterval(-86_400), lastUsed: base.addingTimeInterval(3_600)),
            recencySpool(3),
            recencySpool(4, registered: base),
            recencySpool(5, lastUsed: base.addingTimeInterval(-3_600)),
        ]
        let viaSort = spools.sorted { !SpoolSortOption.recent.areInIncreasingOrder($0, $1) }.map(\.id)
        let viaRule = spools.sorted(by: DashboardStatsService.isMoreRecent).map(\.id)
        #expect(viaSort == viaRule)
    }
}
