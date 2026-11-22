//
//  SpoolmanManageCountTests.swift
//  SpoolKidTests
//

import Foundation
import Testing
@testable import SpoolKid

struct SpoolmanManageCountTests {
    @Test func usageLabelShowsQuotaOnlyWhenCapped() {
        #expect(SpoolmanTabView.usageLabel(count: 3, capacity: 15) == "3 / 15")
        #expect(SpoolmanTabView.usageLabel(count: 3, capacity: nil) == "3")
    }

    @Test func usageLabelGroupsTheCapsDigits() {
        #expect(SpoolmanTabView.usageLabel(count: 1200, capacity: 5000)
            == "\(1200.formatted()) / \(5000.formatted())")
    }

    @Test func usageLabelAtCapacityStillRendersBothNumbers() {
        #expect(SpoolmanTabView.usageLabel(count: 15, capacity: 15) == "15 / 15")
    }

    @Test func countsLineWithoutTagLinksIsTheSpoolCountOnly() {
        #expect(SpoolmanTabView.countsLine(count: 1, capacity: nil, tagged: nil) == "1 spool")
        #expect(SpoolmanTabView.countsLine(count: 3, capacity: nil, tagged: nil) == "3 spools")
        #expect(SpoolmanTabView.countsLine(count: 1, capacity: 15, tagged: nil) == "1 / 15 spools")
    }

    @Test func countsLineAppendsTaggedUnderTagLinks() {
        #expect(SpoolmanTabView.countsLine(count: 48, capacity: 100, tagged: 31)
            == "\(SpoolmanTabView.usageLabel(count: 48, capacity: 100)) spools · 31 tagged")
        #expect(SpoolmanTabView.countsLine(count: 3, capacity: nil, tagged: 0) == "3 spools · 0 tagged")
    }

    @Test func groupingTipNeedsHeadersAndSpools() {
        #expect(SpoolmanTabView.showsGroupingTip(grouping: .filament, activeSpoolCount: 3))
        #expect(SpoolmanTabView.showsGroupingTip(grouping: .location, activeSpoolCount: 3))
        #expect(!SpoolmanTabView.showsGroupingTip(grouping: .none, activeSpoolCount: 3))
        #expect(!SpoolmanTabView.showsGroupingTip(grouping: .filament, activeSpoolCount: 0))
    }
}
