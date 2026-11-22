//
//  DashboardInfoTests.swift
//  SpoolKidTests
//
//  The Home cards' (i) explanations state the dashboard's rules in numbers.
//  Each number must come from the constant the math uses, so these tests pin
//  the copy to `SpoolFillBucket` and `RunwayTuning` rather than to literals.
//

import Testing
@testable import SpoolKid

struct DashboardInfoTests {

    @Test func spoolStatusNamesEveryBucketWithItsBand() {
        let text = DashboardInfo.spoolStatus.joined(separator: " ")
        for bucket in SpoolFillBucket.allCases {
            #expect(text.contains("\(bucket.title) (\(bucket.rangeText))"), "missing \(bucket.title)")
        }
    }

    @Test func reorderSoonStatesTheRunwayTuning() {
        let text = DashboardInfo.reorderSoon.joined(separator: " ")
        #expect(text.contains("\(Int(RunwayTuning.reorderHorizonDays)) days"))
        #expect(text.contains("\(Int(RunwayTuning.minHistoryDays)) days of history"))
        #expect(text.contains("\(Int(RunwayTuning.minUsedGrams))\u{00A0}g used"))
    }

    /// Only a backend with a currency setting has one to name; everywhere
    /// else `formatCurrency` falls back to the device's region.
    @Test func totalValueNamesTheCurrencySourceByCapability() {
        for kind in BackendKind.allCases {
            let caps = BackendCapabilities.for(kind)
            let text = DashboardInfo.totalValue(caps).joined(separator: " ")
            if caps.supportsCurrencySetting {
                #expect(text.contains("currency set in \(caps.displayName)"), "\(kind)")
            } else {
                #expect(text.contains("region currency"), "\(kind)")
            }
        }
    }
}
