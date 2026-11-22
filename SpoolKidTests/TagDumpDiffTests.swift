//
//  TagDumpDiffTests.swift
//  SpoolKidTests
//
//  The whole point of a before/after pair is the handful of pages that moved.
//  Finding them by eye across 135 pages of hex is what this replaces.
//

import Testing
import Foundation
@testable import SpoolKid

struct TagDumpDiffTests {

    private func dump(_ pages: [String]) -> TagDump {
        TagDump(
            capturedAt: Date(timeIntervalSince1970: 1_788_000_000),
            uid: "04A1B2C3D4E580",
            tagType: "MIFARE Ultralight",
            chipVersion: "NTAG213",
            pagesRead: pages.count,
            endedBy: .wrap,
            pages: pages,
            decodedAs: "anycubicACE",
            note: "",
            appVersion: "0.18 (42)"
        )
    }

    @Test func identicalDumpsHaveNoChanges() {
        let pages = ["04A1B2C3", "D4E58000", "FFFFFFFF"]
        #expect(TagDumpDiff.changes(from: dump(pages), to: dump(pages)).isEmpty)
    }

    @Test func oneChangedPageIsReportedWithBothSides() {
        let before = dump(["04A1B2C3", "D4E58000", "FFFFFFFF"])
        let after = dump(["04A1B2C3", "D4E58000", "E8030000"])
        #expect(
            TagDumpDiff.changes(from: before, to: after)
                == [TagDumpDiff.PageChange(page: 2, before: "FFFFFFFF", after: "E8030000")]
        )
    }

    /// Two dumps of the same tag can differ in length when one walk ended
    /// early. The pages only one side has are changes, not omissions.
    @Test func aPageOnlyOneSideHasIsStillAChange() {
        let before = dump(["04A1B2C3"])
        let after = dump(["04A1B2C3", "E8030000"])
        #expect(
            TagDumpDiff.changes(from: before, to: after)
                == [TagDumpDiff.PageChange(page: 1, before: nil, after: "E8030000")]
        )
        #expect(
            TagDumpDiff.changes(from: after, to: before)
                == [TagDumpDiff.PageChange(page: 1, before: "E8030000", after: nil)]
        )
    }

    @Test func changesComeBackInPageOrder() {
        let before = dump(["AAAAAAAA", "BBBBBBBB", "CCCCCCCC"])
        let after = dump(["11111111", "BBBBBBBB", "33333333"])
        #expect(TagDumpDiff.changes(from: before, to: after).map(\.page) == [0, 2])
    }

    @Test func twoEmptyDumpsDifferInNothing() {
        #expect(TagDumpDiff.changes(from: dump([]), to: dump([])).isEmpty)
    }
}
