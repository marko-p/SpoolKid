//
//  CascadeDeleteCopyTests.swift
//  SpoolKidTests
//
//  Purpose: The wording of the two cascade dialogs — the only part of
//  CascadeDeleteButton that is not SwiftUI plumbing.
//

import Testing
import Foundation
@testable import SpoolKid

struct CascadeDeleteCopyTests {
    private let vendorImpact = DeletionImpact(filamentIDs: [5, 6, 7, 8], spoolIDs: Set(20...30), archivedSpoolCount: 1)
    private let filamentImpact = DeletionImpact(filamentIDs: [], spoolIDs: [20], archivedSpoolCount: 0)

    @Test func dependentsNoticeNamesTheRecordAndWhatUsesIt() {
        #expect(CascadeDeleteDialogs.dependentsMessage(subject: "Polymaker", isPlural: false, impact: vendorImpact)
                == "Polymaker is used by 4 filaments and 11 spools (1 archived). Deleting it deletes them too.")
    }

    @Test func finalWarningTitleCountsTheRecordWithItsDependents() {
        #expect(CascadeDeleteDialogs.finalWarningTitle(impact: vendorImpact, selectedCount: 1) == "Permanently Delete 16 Items?")
        #expect(CascadeDeleteDialogs.finalWarningTitle(impact: filamentImpact, selectedCount: 1) == "Permanently Delete 2 Items?")
    }

    @Test func finalWarningWarnsAboutTagsWhenSpoolsGo() {
        #expect(CascadeDeleteDialogs.finalWarningMessage(subject: "PolyTerra", impact: filamentImpact, storageNoun: "Spoolman")
                == "PolyTerra, along with 1 spool, will be permanently deleted from Spoolman. "
                + "Tags mapped to those spools will no longer find them. This cannot be undone.")
    }

    /// A selection speaks in the plural, and counts itself into the total.
    @Test func aSelectionReadsAsPlural() {
        #expect(CascadeDeleteDialogs.dependentsMessage(subject: "3 vendors", isPlural: true, impact: vendorImpact)
                == "3 vendors are used by 4 filaments and 11 spools (1 archived). Deleting them deletes them too.")
        #expect(CascadeDeleteDialogs.finalWarningTitle(impact: vendorImpact, selectedCount: 3) == "Permanently Delete 18 Items?")
    }

    @Test func partialBulkFailureNamesTheBackendsReason() {
        let result = BulkActionResult(succeeded: 2, failed: 1)
        #expect(result.partialFailureMessage(reason: "Spoolman refused spool #54.")
                == "Deleted 2 of 3. 1 could not be deleted: Spoolman refused spool #54.")
        #expect(result.partialFailureMessage() == "Deleted 2 of 3. 1 could not be deleted.")
    }

    /// A vendor whose filaments have no spools takes no tags with it, so the
    /// tag sentence is not there to be ignored.
    @Test func finalWarningOmitsTheTagSentenceWithoutSpools() {
        let noSpools = DeletionImpact(filamentIDs: [5], spoolIDs: [], archivedSpoolCount: 0)
        #expect(CascadeDeleteDialogs.finalWarningMessage(subject: "Polymaker", impact: noSpools, storageNoun: "your library")
                == "Polymaker, along with 1 filament, will be permanently deleted from your library. This cannot be undone.")
    }
}
