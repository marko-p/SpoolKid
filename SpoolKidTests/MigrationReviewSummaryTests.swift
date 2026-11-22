//
//  MigrationReviewSummaryTests.swift
//  SpoolKidTests
//
//  Purpose: Locks the human-readable summary strings used by MigrationReviewView.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

struct MigrationReviewSummaryTests {

    @Test func headerWithoutConflicts() {
        let text = MigrationReviewSummary.header(vendors: 3, filaments: 2, spools: 1, conflicts: 0)
        #expect(text == "3 manufacturers, 2 filaments, 1 spool")
    }

    @Test func headerWithConflicts() {
        let text = MigrationReviewSummary.header(vendors: 1, filaments: 2, spools: 3, conflicts: 4)
        #expect(text == "1 manufacturer, 2 filaments, 3 spools · 4 conflicts to review")
    }

    @Test func headerSingularEverything() {
        let text = MigrationReviewSummary.header(vendors: 1, filaments: 1, spools: 1, conflicts: 1)
        #expect(text == "1 manufacturer, 1 filament, 1 spool · 1 conflict to review")
    }

    @Test func createLineSingular() {
        #expect(MigrationReviewSummary.createLine(creates: 1, reuses: 0) == "+1 new item will be created")
    }

    @Test func createLinePlural() {
        #expect(MigrationReviewSummary.createLine(creates: 12, reuses: 0) == "+12 new items will be created")
    }

    @Test func createLineAccountsForLinkedRows() {
        #expect(MigrationReviewSummary.createLine(creates: 1, reuses: 1)
                == "+1 new item will be created · 1 will be linked to a record the server already has")
        #expect(MigrationReviewSummary.createLine(creates: 2, reuses: 3)
                == "+2 new items will be created · 3 will be linked to records the server already has")
    }

    @Test func uploadTitleSingular() {
        #expect(MigrationReviewSummary.uploadTitle(creates: 1, reuses: 0) == "Upload 1 item")
    }

    @Test func uploadTitlePlural() {
        #expect(MigrationReviewSummary.uploadTitle(creates: 5, reuses: 0) == "Upload 5 items")
    }

    @Test func uploadTitleCountsCreatesNotPlannedRows() {
        // The device finding: one filament to create beside one manufacturer
        // being reused read "Upload 2 items" over "+1 new item will be created".
        #expect(MigrationReviewSummary.uploadTitle(creates: 1, reuses: 1) == "Upload 1 item")
    }

    @Test func withNothingToCreateEverythingIsLinked() {
        #expect(MigrationReviewSummary.uploadTitle(creates: 0, reuses: 1) == "Link 1 item")
        #expect(MigrationReviewSummary.uploadTitle(creates: 0, reuses: 4) == "Link 4 items")
    }

    @Test func discardCopyNamesTheCountAndTheBackend() {
        #expect(MigrationReviewSummary.discardTitle(result: Self.result(failed: 1)) == "Discard 1 item?")
        #expect(MigrationReviewSummary.discardTitle(result: Self.result(failed: 1, skipped: 1)) == "Discard 2 items?")
        #expect(MigrationReviewSummary.discardMessage(backend: "FilaMan", result: Self.result(failed: 1))
                .contains("FilaMan"))
    }

    @Test func missingLineNamesTheFieldsTheSheetWillRender() {
        #expect(MigrationReviewSummary.missingLine([.manufacturer]) == "Needs Manufacturer")
        #expect(MigrationReviewSummary.missingLine([.material, .manufacturer])
                == "Needs Material, Manufacturer")
    }

    @Test func blockedLineCounts() {
        #expect(MigrationReviewSummary.blockedLine(count: 1) == "1 item can't be uploaded yet")
        #expect(MigrationReviewSummary.blockedLine(count: 3) == "3 items can't be uploaded yet")
    }

    @Test func outcomeLineTalliesEveryBucket() {
        let result = MigrationResult(
            created: 2,
            reused: 1,
            failed: [MigrationFailure(label: "PLA", reason: "A filament needs a manufacturer on FilaMan.")],
            skipped: [MigrationFailure(label: "Spool #1", reason: "Its filament was not uploaded.")]
        )

        #expect(MigrationReviewSummary.outcomeLine(result: result)
                == "2 created, 1 reused · 1 failed, 1 skipped")
    }

    // MARK: - Discarding from the review form

    /// The review form's discard covers the WHOLE pending library, not the
    /// leftovers of a partial run, so it must not borrow the counted wording —
    /// "Discard 2 items?" over a button that deletes everything on the device
    /// is the wrong question.
    @Test func discardingFromTheReviewFormSaysEverythingNotACount() {
        let title = MigrationReviewSummary.discardEverythingTitle()

        #expect(title == "Discard your on-device library?")
        #expect(!title.contains("item"))
    }

    /// It is unrecoverable, and it names the backend it is declining to reach —
    /// the same rule the rest of this screen follows.
    @Test func theDiscardWarningNamesTheBackendAndTheFinality() {
        let message = MigrationReviewSummary.discardEverythingMessage(backend: "FilaMan")

        #expect(message.contains("FilaMan"))
        #expect(message.contains("cannot be undone"))
    }

    /// The partial-run wording is untouched: it still counts, because there it
    /// really is only the leftovers.
    @Test func thePartialRunDiscardStillCounts() {
        #expect(MigrationReviewSummary.discardTitle(result: Self.result(failed: 1)) == "Discard 1 item?")
        #expect(MigrationReviewSummary.discardTitle(result: Self.result(failed: 2, skipped: 1)) == "Discard 3 items?")
    }

    // MARK: - Uploaded, but some fields stayed behind (2026-09-24)

    @Test func outcomeLineCountsRowsThatLeftFieldsBehind() {
        let result = Self.result(notStored: 2)

        #expect(MigrationReviewSummary.outcomeLine(result: result)
                == "0 created, 0 reused · 0 failed, 0 skipped · 2 saved without some details")
    }

    @Test func aRunThatOnlyLeftFieldsBehindIsNotCalledIncomplete() {
        #expect(MigrationReviewSummary.resultTitle(result: Self.result(notStored: 1)) == "Some Details Not Uploaded")
        #expect(MigrationReviewSummary.resultTitle(result: Self.result(failed: 1, notStored: 1)) == "Upload Incomplete")
    }

    /// Everything is on the server; what the discard deletes is the only copy
    /// of the listed details. "Discard 0 items?" or "items that were uploaded
    /// are not affected" would both be false.
    @Test func discardingLeftBehindDetailsSaysWhatIsDeleted() {
        let result = Self.result(notStored: 2)

        #expect(MigrationReviewSummary.discardTitle(result: result) == "Delete the on-device copies?")
        let message = MigrationReviewSummary.discardMessage(backend: "FilaMan", result: result)
        #expect(message.contains("FilaMan"))
        #expect(message.contains("cannot be undone"))
        #expect(!message.contains("not affected"))
    }

    @Test func discardingBothKindsNamesTheLeftBehindDetailsToo() {
        let message = MigrationReviewSummary.discardMessage(
            backend: "FilaMan", result: Self.result(failed: 1, notStored: 1)
        )

        #expect(message.contains("could not store"))
        #expect(!message.contains("not affected"))
    }

    private static func result(failed: Int = 0, skipped: Int = 0, notStored: Int = 0) -> MigrationResult {
        func rows(_ n: Int, _ kind: String) -> [MigrationFailure] {
            (0..<n).map { MigrationFailure(label: "\(kind) \($0)", reason: nil) }
        }
        return MigrationResult(
            created: 0, reused: 0,
            failed: rows(failed, "failed"), skipped: rows(skipped, "skipped"),
            notStored: rows(notStored, "notStored")
        )
    }
}
