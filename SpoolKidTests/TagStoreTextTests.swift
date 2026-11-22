//
//  TagStoreTextTests.swift
//  SpoolKidTests
//
//  The tag-store screens explain irreversible actions to people whose
//  printers read these links. The wording is pinned here.
//

import Foundation
import Testing
@testable import SpoolKid

struct TagStoreTextTests {
    @Test func theFooterNamesWhoReadsEachStore() {
        #expect(TagStoreText.bothStoresFooter.contains("Spoolman's own Tags section"))
        #expect(TagStoreText.bothStoresFooter.contains("Snapmaker U1"))
        #expect(TagStoreText.bothStoresFooter.contains("at least one"))
    }

    @Test func identityFooterPerState() {
        let bothStores: Set<TagStore> = [.cardUIDs, .spoolmanTags]
        let both = TagIdentityPolicy(mode: .tagLinks, linkTargets: [.spoolmanTags, .cardUIDs])
        #expect(TagStoreText.identityFooter(both, available: bothStores, capabilities: .spoolman)
            == TagStoreText.bothStoresFooter)

        // Both switches are on screen whenever both stores are available,
        // one of them off included: the footer explains both (final review M3).
        let cardUIDsOnly = TagIdentityPolicy(mode: .tagLinks, linkTargets: [.cardUIDs])
        #expect(TagStoreText.identityFooter(cardUIDsOnly, available: bothStores, capabilities: .spoolman)
            == TagStoreText.bothStoresFooter)

        #expect(TagStoreText.identityFooter(cardUIDsOnly, available: [.cardUIDs], capabilities: .filaman)
            == TagStoreText.mappingFooter(.filaman))

        // Tag Links with no store: a server whose connection is not validated.
        let none = TagIdentityPolicy(mode: .tagLinks, linkTargets: [])
        #expect(TagStoreText.identityFooter(none, available: [], capabilities: .spoolman)
            == "\(BackendCapabilities.spoolman.storageNoun.localizedCapitalized) can't keep tag links yet, so SpoolKid writes neither a spool ID nor a link here. ACE tags still carry the spool's ID in their SKU.")

        #expect(TagStoreText.identityFooter(.init(mode: .spoolID, linkTargets: []), available: bothStores, capabilities: .spoolman)
            == "SpoolKid writes the spool's ID onto each tag it writes, and a tag's spool ID identifies its spool. Existing tag links are still read.")
        #expect(TagStoreText.identityFooter(.init(mode: .neither, linkTargets: []), available: bothStores, capabilities: .spoolman)
            == "SpoolKid writes neither a spool ID nor a tag link. Existing tag links are still read. ACE tags still carry the spool's ID in their SKU.")
    }

    @Test func filamanFooterFollowsTheSwitch() {
        let on = TagIdentityPolicy(mode: .tagLinks, linkTargets: [.filamanTags, .cardUIDs])
        let off = TagIdentityPolicy(mode: .tagLinks, linkTargets: [.cardUIDs])
        let available: Set<TagStore> = [.cardUIDs, .filamanTags]
        #expect(TagStoreText.identityFooter(on, available: available, capabilities: .filaman)
            == TagStoreText.filamanTagsFooter)
        #expect(TagStoreText.identityFooter(off, available: available, capabilities: .filaman)
            == TagStoreText.mappingFooter(.filaman))
        #expect(TagStoreText.copyRowLabel(count: 2, target: .filamanTags) == "Copy 2 Tag Links to FilaMan Tags")
        #expect(TagStoreText.copyIntoFilamanIntro(count: 1).contains("1 spool"))
    }

    /// Every other path names the backend's own row (audit S3); the note
    /// said "Library → Backend → Tag Identity" on every backend (final
    /// review M4).
    @Test func theLinksOffNoteNamesTheBackendsRow() {
        #expect(TagStoreText.linksOffNote(connectionRowLabel: BackendCapabilities.spoolman.connectionRowLabel)
            == "SpoolKid isn't set to link tags, so no tag was linked. To link one, choose Tag Links in Library → Spoolman → Tag Identity, then scan the tag and tap Link Tag…")
        #expect(TagStoreText.linksOffNote(connectionRowLabel: BackendCapabilities.local.connectionRowLabel)
            .contains("Library → Library Mode → Tag Identity"))
    }

    @Test func copyRowCountsLinks() {
        #expect(TagStoreText.copyRowLabel(count: 1) == "Copy 1 Tag Link to Spoolman Tags")
        #expect(TagStoreText.copyRowLabel(count: 3) == "Copy 3 Tag Links to Spoolman Tags")
    }

    @Test func copyResultSaysHowManyLanded() {
        #expect(TagStoreText.copyResultSummary(copied: 0) == "Nothing was copied.")
        #expect(TagStoreText.copyResultSummary(copied: 1) == "Copied 1 tag link.")
        #expect(TagStoreText.copyResultSummary(copied: 2) == "Copied 2 tag links.")
    }

    @Test func theMigrationIntroSaysCardUIDsIsKept() {
        let intro = TagStoreText.copyIntoNativeIntro(count: 2)
        #expect(intro.contains("copies 2 links"))
        #expect(intro.contains("card_uids stays as it is"))
        #expect(!intro.contains("lot"))
    }

    // MARK: - Deleting a store

    @Test func deleteRowsNameTheStore() {
        #expect(TagStoreText.deleteRowLabel(.cardUIDs, displayName: "Spoolman") == "Delete card_uids from Spoolman…")
        #expect(TagStoreText.deleteRowLabel(.spoolmanTags, displayName: "Spoolman") == "Delete Spoolman Tag Links…")
    }

    @Test func deletingCardUIDsWithASecondStoreSaysEveryLinkIsSafe() {
        let text = TagStoreText.deleteMessage(.cardUIDs, check: .ready(linkCount: 3, staleCount: 0), displayName: "Spoolman")
        #expect(text.contains("Every link is already in Spoolman Tags"))
        #expect(text.contains("cannot be undone"))
    }

    @Test func deletingCardUIDsWithoutASecondStoreKeepsTodaysWarning() {
        #expect(TagStoreText.deleteMessage(.cardUIDs, check: .noOtherStore(linkCount: 3), displayName: "FilaMan")
            == "This permanently removes the Card UIDs field and every spool's tag mapping from FilaMan. Your Snapmaker U1 / SpoolLink app will no longer recognise these tags. This cannot be undone.")
    }

    @Test func deletingNativeWarnsItMayComeBack() {
        let text = TagStoreText.deleteMessage(.spoolmanTags, check: .ready(linkCount: 1, staleCount: 0), displayName: "Spoolman")
        #expect(text.hasPrefix("This unlinks 1 tag from its spool in Spoolman."))
        #expect(text.contains("may add them back"))
        #expect(text.contains("Filament tags are not touched"))
    }

    @Test func blockedIntroCountsWhatMustBeCopiedFirst() {
        var missing = TagStoreAudit.MissingLinks()
        missing.copyable = [
            .init(uid: "AA", spoolId: 1, spoolLabel: "A"),
            .init(uid: "BB", spoolId: 1, spoolLabel: "A"),
        ]
        #expect(TagStoreText.blockedIntro(deleting: .cardUIDs, missing: missing)
            == "2 tag links are not in Spoolman Tags yet. Copy them before deleting card_uids, so no link is lost.")
        #expect(TagStoreText.copyableCount(deleting: .cardUIDs, missing: missing) == 2)
    }

    @Test func aBlockOfOnlyFilamentConflictsOffersNoCopy() {
        var missing = TagStoreAudit.MissingLinks()
        let link = TagStoreAudit.Link(uid: "FF", spoolId: 1, spoolLabel: "Spool A")
        missing.filamentConflicts = [.init(link: link, filamentLabel: "Silk")]
        #expect(TagStoreText.copyableCount(deleting: .cardUIDs, missing: missing) == 0)
        #expect(TagStoreText.blockedIntro(deleting: .cardUIDs, missing: missing)
            == "Spoolman lists FF on the filament Silk. Unlink it from the filament in Spoolman, or unlink it from Spool A here, then try again.")
    }

    @Test func disagreeingCopiesBlockDeletingNativeAndCount() {
        var missing = TagStoreAudit.MissingLinks()
        missing.stale = [.init(uid: "AA", spoolId: 2, spoolLabel: "B")]
        #expect(TagStoreText.copyableCount(deleting: .spoolmanTags, missing: missing) == 1)
        #expect(TagStoreText.copyableCount(deleting: .cardUIDs, missing: missing) == 0)
        #expect(TagStoreText.blockedIntro(deleting: .spoolmanTags, missing: missing)
            == "1 tag link is not in card_uids yet. Copy it before deleting Spoolman Tags, so no link is lost.")
    }

    @Test func explanationNamesTheStoresAndWhereToChange() {
        #expect(TagStoreText.storeNames([.spoolmanTags, .cardUIDs], capabilities: .spoolman) == "Spoolman Tags and SpoolLink")
        #expect(TagStoreText.storeNames([.cardUIDs], capabilities: .spoolman) == "SpoolLink")
        #expect(TagStoreText.storeNames([.cardUIDs], capabilities: .local) == "Tags")
        #expect(TagStoreText.explanationLines(storeNames: "SpoolLink", connectionRowLabel: "Spoolman") == [
            "SpoolKid used to write each spool's ID onto its tags and also link them in SpoolLink. It now does one of the two.",
            "It will use Tag Links: tags are linked in SpoolLink, and spool IDs are no longer written onto tags.",
            "Tags that already carry a spool ID are linked the next time you scan them — automatically when the tag's filament matches the spool, otherwise SpoolKid asks.",
            "You can change this any time in Library → Spoolman → Tag Identity.",
        ])
    }

    /// The explanation never reads "link them in ." — the decision's
    /// targets, else the backend's stores, else SpoolLink.
    @Test func explanationStoreNamesAreNeverEmpty() {
        #expect(TagStoreText.explanationStoreNames(
            targets: [.spoolmanTags], available: [.cardUIDs, .spoolmanTags], capabilities: .spoolman
        ) == "Spoolman Tags")
        #expect(TagStoreText.explanationStoreNames(
            targets: [], available: [.cardUIDs, .spoolmanTags], capabilities: .spoolman
        ) == "Spoolman Tags and SpoolLink")
        #expect(TagStoreText.explanationStoreNames(targets: [], available: [], capabilities: .spoolman) == "SpoolLink")
        #expect(TagStoreText.explanationStoreNames(targets: [], available: [], capabilities: .local) == "Tags")
    }

    @Test func welcomeLineForEachMode() {
        #expect(TagStoreText.welcomeModeLine(.tagLinks, capabilities: .spoolman)
            == "Each tag you link is recorded in Spoolman, so SpoolKid and tag-reading printers find its spool.")
        #expect(TagStoreText.welcomeModeLine(.spoolID, capabilities: .spoolman)
            == "SpoolKid writes the spool's ID onto each tag it writes, and reads it back.")
        #expect(TagStoreText.welcomeModeLine(.neither, capabilities: .spoolman)
            == "SpoolKid writes neither a link nor a spool ID. Links made elsewhere still work. ACE tags still carry the spool's ID in their SKU.")
    }

    /// The Library keeps links since spec 2, but no printer reads them: its
    /// line promises SpoolKid, not tag-reading printers.
    @Test func theLibraryWelcomeLinePromisesOnlySpoolKid() {
        #expect(TagStoreText.welcomeModeLine(.tagLinks, capabilities: .local)
            == "Each tag you link is kept with its spool in your library, so SpoolKid finds the spool when you scan it.")
        #expect(TagStoreText.welcomeModeLine(.tagLinks, capabilities: .filaman).contains("recorded in FilaMan"))
    }

    /// Issue #24: the owner's wording for the record copy row.
    @Test func recordCopyRowLabelNamesTheBackend() {
        #expect(TagStoreText.recordCopyRowLabel(displayName: "Spoolman")
            == "Copy tag links from on-device Library to Spoolman")
    }

    /// Final review I-2: outside Tag Links the section says why its record
    /// row is disabled.
    @Test func migrationFooterExplainsLinksOff() {
        #expect(TagStoreText.migrationManagementFooter(writesLinks: false, connectionRowLabel: "Spoolman")
            == TagStoreText.linksOffNote(connectionRowLabel: "Spoolman"))
        #expect(TagStoreText.migrationManagementFooter(writesLinks: true, connectionRowLabel: "Spoolman")
            .hasPrefix("Fixes tag links"))
    }
}
