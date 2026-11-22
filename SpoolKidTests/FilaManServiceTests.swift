//
//  FilaManServiceTests.swift
//  SpoolKidTests
//

import Testing
import Foundation
@testable import SpoolKid

struct FilaManServiceTests {
    // MARK: - deleteEndpoint

    /// Without `force` FilaMan answers 409 for a record still referenced;
    /// with it the server deletes the dependents in one commit (both measured
    /// live 2026-09-15).
    @Test func deleteEndpointOmitsForceForAPlainDelete() {
        #expect(FilaManService.deleteEndpoint(collection: "manufacturers", id: 7, force: false)
                == "/api/v1/manufacturers/7")
    }

    @Test func deleteEndpointAddsForceForACascade() {
        #expect(FilaManService.deleteEndpoint(collection: "filaments", id: 231, force: true)
                == "/api/v1/filaments/231?force=true")
    }

    // MARK: - mergedCustomFields (the read-modify-write merge)
    //
    // `custom_fields` PATCH REPLACES the whole object server-side (verified
    // live 2026-08-19) rather than merging. Every spool on a migrated FilaMan
    // instance carries `custom_fields: {"spoolman_id": N}` linking it back to
    // Spoolman, so `patchSpoolCustomFields` must merge locally before it
    // PATCHes — this is the pure decision logic that guarantees that.

    @Test func addsANewKeyToExistingFields() {
        let merged = FilaManService.mergedCustomFields(
            existing: ["spoolman_id": "43"],
            new: ["card_uids": "AABBCCDD"]
        )

        #expect(merged == ["spoolman_id": "43", "card_uids": "AABBCCDD"])
    }

    @Test func overwritesAnExistingKeyOnCollision() {
        let merged = FilaManService.mergedCustomFields(
            existing: ["card_uids": "OLD"],
            new: ["card_uids": "NEW"]
        )

        #expect(merged == ["card_uids": "NEW"])
    }

    @Test func mergingIntoNilExistingFieldsYieldsJustTheNewKeys() {
        let merged = FilaManService.mergedCustomFields(existing: nil, new: ["card_uids": "AABBCCDD"])

        #expect(merged == ["card_uids": "AABBCCDD"])
    }

    @Test func mergingIntoEmptyExistingFieldsYieldsJustTheNewKeys() {
        let merged = FilaManService.mergedCustomFields(existing: [:], new: ["card_uids": "AABBCCDD"])

        #expect(merged == ["card_uids": "AABBCCDD"])
    }

    /// The exact scenario the CRITICAL warning describes: a spool's link back
    /// to Spoolman (`spoolman_id`) and an unrelated field must both survive a
    /// `card_uids` write.
    @Test func preservesUnrelatedPreexistingKeys() {
        let merged = FilaManService.mergedCustomFields(
            existing: ["spoolman_id": "43", "comment": "from FilaMan UI"],
            new: ["card_uids": "AABBCCDD"]
        )

        #expect(merged["spoolman_id"] == "43")
        #expect(merged["comment"] == "from FilaMan UI")
        #expect(merged["card_uids"] == "AABBCCDD")
    }

    @Test func emptyNewFieldsLeavesExistingFieldsUnchanged() {
        let merged = FilaManService.mergedCustomFields(existing: ["a": "1"], new: [:])

        #expect(merged == ["a": "1"])
    }

    // MARK: - listPath (list query, incl. archived spools)
    //
    // FilaMan's spool list defaults `include_archived` to false, so an archived
    // spool never reached the app at all: "Show Archived" in Manage Spools
    // filters the FETCHED list, and a spool that was never fetched cannot be
    // opened to un-archive it (device finding, 2026-08-29).

    @Test func listPathCarriesPagingOnItsOwn() {
        #expect(FilaManService.listPath(endpoint: "/api/v1/filaments", page: 2, pageSize: 200)
                == "/api/v1/filaments?page=2&page_size=200")
    }

    @Test func listPathAppendsFiltersInStableOrder() {
        let path = FilaManService.listPath(
            endpoint: "/api/v1/spools",
            page: 1,
            pageSize: 200,
            query: ["include_archived": "true", "aaa": "1"]
        )

        #expect(path == "/api/v1/spools?page=1&page_size=200&aaa=1&include_archived=true")
    }

    // MARK: - hasMorePages (pagination termination, F22)
    //
    // `fetchSpools` et al. must page until every record is collected — a
    // truncated `spools` array makes a scanned tag on record 51+ report
    // "unmapped" even though the mapping exists on the server. These pin the
    // pure decision `fetchAllPages`'s loop makes after every page.

    @Test func noMorePagesWhenEverythingArrivedInOnePage() {
        // The exact F22 shape: 38 spools, single page, nothing left to fetch.
        #expect(FilaManService.hasMorePages(accumulatedCount: 38, total: 38, lastPageCount: 38) == false)
    }

    @Test func moreToFetchAfterTheFirstOfAnExactPageSizeMultiple() {
        // total=100, page_size=50: one full page in, one more remains.
        #expect(FilaManService.hasMorePages(accumulatedCount: 50, total: 100, lastPageCount: 50) == true)
    }

    @Test func noMorePagesAfterTheLastOfAnExactPageSizeMultiple() {
        // Same total/page_size, after the second (also full) page — must NOT
        // request a third, empty page. The classic off-by-one this guards.
        #expect(FilaManService.hasMorePages(accumulatedCount: 100, total: 100, lastPageCount: 50) == false)
    }

    @Test func noMorePagesAfterAPartialFinalPage() {
        #expect(FilaManService.hasMorePages(accumulatedCount: 130, total: 130, lastPageCount: 30) == false)
    }

    @Test func noMorePagesWhenThereAreZeroRecords() {
        #expect(FilaManService.hasMorePages(accumulatedCount: 0, total: 0, lastPageCount: 0) == false)
    }

    @Test func stopsRatherThanLoopingForeverWhenTheServersTotalOverstatesWhatItReturns() {
        // Defensive: total claims 100 but a page came back empty. What was
        // actually observed (an empty page) wins over what total claimed.
        #expect(FilaManService.hasMorePages(accumulatedCount: 50, total: 100, lastPageCount: 0) == false)
    }

    @Test func continuesWhenMoreRecordsRemainAndTheLastPageWasNonEmpty() {
        #expect(FilaManService.hasMorePages(accumulatedCount: 50, total: 130, lastPageCount: 50) == true)
    }

    // MARK: - hasMorePages: the two ways trusting `total` goes wrong
    //
    // The empty-page guard above covers a server that OVERSTATES `total`.
    // These cover the other direction and the unbounded loop itself.

    /// A page that came back FULL is evidence of its own, independent of what
    /// `total` claimed: the server handed over every record it was asked for,
    /// so there is no reason to believe that was the last of them. Without
    /// this, an understated `total` truncates the list silently — the same
    /// class of failure as F22, where a scanned tag on a record past the cut
    /// reports "unmapped" while the mapping sits on the server.
    @Test func continuesOnAFullPageEvenWhenTheServersTotalSaysItIsDone() {
        #expect(
            FilaManService.hasMorePages(
                accumulatedCount: 200, total: 150, lastPageCount: 200, pageSize: 200
            ) == true
        )
    }

    /// The cost of the rule above: a collection that is an exact multiple of
    /// the page size spends one extra request confirming it is finished. Pinned
    /// so the trade-off is a decision rather than a surprise.
    @Test func aFullFinalPageCostsOneConfirmingRequest() {
        #expect(
            FilaManService.hasMorePages(
                accumulatedCount: 200, total: 200, lastPageCount: 200, pageSize: 200
            ) == true
        )
        // …which comes back empty, and the empty-page guard ends it.
        #expect(
            FilaManService.hasMorePages(
                accumulatedCount: 200, total: 200, lastPageCount: 0, pageSize: 200
            ) == false
        )
    }

    /// A partial page still ends the loop — that is what makes the extra
    /// request above the exception rather than the rule.
    @Test func stopsOnAPartialPageOnceTheTotalIsReached() {
        #expect(
            FilaManService.hasMorePages(
                accumulatedCount: 130, total: 130, lastPageCount: 30, pageSize: 200
            ) == false
        )
    }

    /// The hard stop. `fetchAllPages` loops on `while true`, so a server that
    /// keeps answering with full pages and a growing `total` would page
    /// forever; the cap turns that into a bounded (if incomplete) fetch.
    @Test func stopsAtTheHardPageCapHoweverMuchTheServerClaims() {
        #expect(
            FilaManService.hasMorePages(
                accumulatedCount: 200, total: 1_000_000,
                lastPageCount: 200, pageSize: 200, pagesFetched: FilaManService.maxPages
            ) == false
        )
    }

    @Test func keepsGoingOnThePageBeforeTheCap() {
        #expect(
            FilaManService.hasMorePages(
                accumulatedCount: 200, total: 1_000_000,
                lastPageCount: 200, pageSize: 200, pagesFetched: FilaManService.maxPages - 1
            ) == true
        )
    }

    /// The cap has to be out of reach of any real filament collection, or it
    /// becomes the truncation it exists to prevent.
    @Test func theHardCapIsFarBeyondAnyRealCollection() {
        #expect(FilaManService.maxPages * FilaManService.maxPageSize >= 20_000)
    }

    // MARK: - healthCheck vs testConnection
    //
    // The Library tab's status dot is display-only: it must never disturb the
    // error banner or the sticky connection flag. `testConnection` deliberately
    // does disturb them, which is exactly why it could not be reused for the
    // status dot. These two tests pin that difference in place.
    //
    // Both probe a closed loopback port, so no server — live or otherwise — is
    // contacted: the connection is refused locally and immediately.

    private static let refusedAddress = "http://127.0.0.1:1"

    @MainActor
    @Test func healthCheckLeavesTheErrorBannerAlone() async {
        let service = FilaManService()
        service.errorMessage = "something the user has not read yet"

        let result = await service.healthCheck(baseUrl: Self.refusedAddress)

        #expect(result == .unreachable)
        #expect(service.errorMessage == "something the user has not read yet")
    }

    @MainActor
    @Test func testConnectionDoesReportItsFailure() async {
        let service = FilaManService()
        service.errorMessage = nil

        let ok = await service.testConnection(baseUrl: Self.refusedAddress)

        #expect(ok == false)
        #expect(service.errorMessage != nil)
    }

    @MainActor
    @Test func healthCheckOnAnUnusableAddressIsUnreachableNotNotFilaMan() async {
        let service = FilaManService()

        // No HTTP response was received, so nothing was learned about what the
        // server is. Reporting `.notFilaMan` here would point the user at the
        // wrong fix.
        #expect(await service.healthCheck(baseUrl: "not a url at all") == .unreachable)
        #expect(service.errorMessage == nil)
    }
}
