//
//  TagStoreText.swift
//  SpoolKid
//
//  Purpose: Every sentence the tag-store screens show, in one place so the
//  wording is tested and stays consistent between the copy and delete flows.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum TagStoreText {
    /// Linking a second tag to a spool when FilaMan Tags is the only store.
    static func filamanOneTagNote(existing: String) -> String {
        "FilaMan keeps one tag per spool, and this spool already has tag \(existing). Unlink it first, or link again and choose Replace Tag."
    }

    /// An Add with several tags listed when FilaMan Tags is the only store:
    /// the create links the first, and names the rest. Nil when nothing was
    /// left out.
    static func filamanCreateUnlinkedNote(listed: [String], targets: Set<TagStore>) -> String? {
        guard targets == [.filamanTags], listed.count > 1 else { return nil }
        let left = Array(listed.dropFirst())
        let tags = left.count == 1 ? "tag \(left[0]) was" : "tags \(left.joined(separator: ", ")) were"
        return "FilaMan keeps one tag per spool; \(tags) not linked."
    }

    /// The Replace Tag / Cancel prompt for FilaMan's one-tag limit.
    static let replacePromptTitle = "FilaMan Holds One Tag per Spool"

    static func replacePromptMessage(spool: String, existing: String) -> String {
        "\(spool) is linked to tag \(existing). Replace it with this tag? The old tag will no longer identify the spool in FilaMan or on its scale."
    }

    /// A claim that failed after the tag was released from its holder.
    static func claimFailedNote(holder: String, restored: Bool) -> String {
        restored
            ? "The tag could not be linked to this spool. It was put back on \(holder)."
            : "The tag was removed from \(holder) but could not be linked to this spool. Scan it again to link it."
    }

    /// A write nobody is watching met a tag FilaMan has bound to another
    /// spool; only a person's link moves it.
    static func heldElsewhereNote(holder: String) -> String {
        "This tag is linked to \(holder) in FilaMan, so it was not moved. Scan it and choose Link Tag to move it."
    }

    /// A link control reached while the mode writes no links. The controls
    /// are hidden then; this is the honest answer if one is reached anyway.
    /// Names the backend's own row, like every other path (audit S3). The
    /// remedy is scanning the tag again, not just switching modes: the
    /// migration shows this note too, and a migrated row is not retried.
    static func linksOffNote(connectionRowLabel: String) -> String {
        "SpoolKid isn't set to link tags, so no tag was linked. To link one, choose Tag Links in Library → \(connectionRowLabel) → Tag Identity, then scan the tag and tap Link Tag…"
    }

    /// A filament link on a backend with nowhere to keep one (FilaMan,
    /// Spoolman before 0.27). Not `linksOffNote`: the mode is not the cause.
    static func noFilamentStoreNote(displayName: String) -> String {
        "\(displayName) can't keep a tag linked to a filament, so no tag was linked. Spoolman 0.27 or later and the on-device Library can."
    }

    /// Backend → Tag Identity footer when the server has both stores.
    static let bothStoresFooter = "Spoolman Tags appear in Spoolman's own Tags section and work with other tag readers. "
        + "SpoolLink also keeps each tag in the card_uids field, which the Snapmaker U1 extended firmware and "
        + "SpoolLink apps read. SpoolKid needs at least one of them on."

    /// Backend → Tag Identity footer while FilaMan Tags is on.
    static let filamanTagsFooter = "FilaMan Tags stores a tag in the spool's own tag field, which FilaMan's scale reads. "
        + "FilaMan holds one tag per spool; with SpoolLink also on, extra tags go to card_uids only. "
        + "Unlinking a tag here also removes it from the scale."

    /// A tag the copy did not take because another spool is FilaMan's holder.
    static func filamanHeldLine(uid: String, holder: String) -> String {
        "Tag \(uid) is already FilaMan's tag for \(holder)."
    }

    /// ACE tags carry the spool's ID in their SKU (`SM<id>`) in every mode
    /// (owner, 2026-10-09), so every "writes neither" line says so.
    static let aceSKUNote = "ACE tags still carry the spool's ID in their SKU."

    /// Tag Links where the backend has nowhere to keep a link (a server not
    /// connected).
    static func noTagStoreLine(_ capabilities: BackendCapabilities) -> String {
        "\(capabilities.storageNoun.localizedCapitalized) can't keep tag links yet, so SpoolKid writes neither a spool ID nor a link here. \(aceSKUNote)"
    }

    /// The welcome guide's one line under the identity picker, for the
    /// backend the guide has chosen. The Library keeps links since spec 2,
    /// but no printer reads them, so its line promises SpoolKid only.
    static func welcomeModeLine(_ mode: TagIdentityMode, capabilities: BackendCapabilities) -> String {
        switch mode {
        case .tagLinks where capabilities.isOnDeviceStorage:
            "Each tag you link is kept with its spool in \(capabilities.storageNoun), so SpoolKid finds the spool when you scan it."
        case .tagLinks:
            "Each tag you link is recorded in \(capabilities.displayName), so SpoolKid and tag-reading printers find its spool."
        case .spoolID: "SpoolKid writes the spool's ID onto each tag it writes, and reads it back."
        case .neither: "SpoolKid writes neither a link nor a spool ID. Links made elsewhere still work. \(aceSKUNote)"
        }
    }

    /// Settings → Tag Identity footer, per spec §4. `available` is the
    /// backend's stores: both switches show whenever Spoolman Tags is among
    /// them, so the footer explaining both does too.
    static func identityFooter(
        _ identity: TagIdentityPolicy, available: Set<TagStore>, capabilities: BackendCapabilities
    ) -> String {
        switch identity.effectiveMode {
        case .spoolID:
            return "SpoolKid writes the spool's ID onto each tag it writes, and a tag's spool ID identifies its spool. Existing tag links are still read."
        case .neither where identity.mode == .tagLinks:
            return noTagStoreLine(capabilities)
        case .neither:
            return "SpoolKid writes neither a spool ID nor a tag link. Existing tag links are still read. \(aceSKUNote)"
        case .tagLinks:
            if identity.linkTargets.contains(.filamanTags) { return filamanTagsFooter }
            return available.contains(.spoolmanTags) ? bothStoresFooter : mappingFooter(capabilities)
        }
    }

    /// The SpoolLink explainer. It named Spoolman's `card_uids` field on every
    /// backend until this fix — on a FilaMan install it described a server the
    /// user does not run, and the screen it sits on is the shared backend
    /// configuration home, not Spoolman's (I4).
    ///
    /// The Library keeps its links in `card_uids` too (spec 2), but no
    /// SpoolLink client reads them there: its footer says what the links do.
    static func mappingFooter(_ capabilities: BackendCapabilities) -> String {
        guard !capabilities.isOnDeviceStorage else {
            return "SpoolKid keeps each tag you link with its spool in \(capabilities.storageNoun), "
                + "and finds the spool when you scan the tag."
        }
        return "SpoolLink stores each tag's UID in the card_uids field on "
            + "\(capabilities.storageNoun) so your Snapmaker U1 can recognise spools by tag."
    }

    // MARK: - The one-time explanation

    static let explanationTitle = "One Way to Identify Spools"
    static let keepTagLinks = "Keep Tag Links"
    static let useSpoolIDInstead = "Use Spool ID Instead"
    static let spoolIDKeepsLinks = "Existing links still identify their tags."

    /// What the UI calls `store` on this backend. The Library keeps links in
    /// `card_uids` too, but no SpoolLink client reads them there, so it
    /// calls them Tags (spec 2).
    static func storeName(_ store: TagStore, capabilities: BackendCapabilities) -> String {
        store == .cardUIDs && capabilities.isOnDeviceStorage ? "Tags" : store.displayName
    }

    /// "Spoolman Tags and SpoolLink" — Spoolman Tags first, like the switches.
    static func storeNames(_ targets: Set<TagStore>, capabilities: BackendCapabilities) -> String {
        [TagStore.spoolmanTags, .cardUIDs].filter(targets.contains)
            .map { storeName($0, capabilities: capabilities) }
            .joined(separator: " and ")
    }

    /// The stores the explanation names: the decision's targets, else the
    /// backend's stores (a server offline at the next launch has no targets),
    /// else `card_uids`, where every link before Spoolman 0.27 went. Never
    /// empty, so the copy never reads "link them in .".
    static func explanationStoreNames(
        targets: Set<TagStore>, available: Set<TagStore>, capabilities: BackendCapabilities
    ) -> String {
        [targets, available, [.cardUIDs]]
            .map { storeNames($0, capabilities: capabilities) }
            .first { !$0.isEmpty } ?? ""
    }

    static func explanationLines(storeNames: String, connectionRowLabel: String) -> [String] {
        [
            "SpoolKid used to write each spool's ID onto its tags and also link them in \(storeNames). It now does one of the two.",
            "It will use Tag Links: tags are linked in \(storeNames), and spool IDs are no longer written onto tags.",
            "Tags that already carry a spool ID are linked the next time you scan them — automatically when the tag's filament matches the spool, otherwise SpoolKid asks.",
            "You can change this any time in Library → \(connectionRowLabel) → Tag Identity.",
        ]
    }

    static func copyRowLabel(count: Int, target: TagStore = .spoolmanTags) -> String {
        "Copy \(count == 1 ? "1 Tag Link" : "\(count) Tag Links") to \(target.displayName)"
    }

    static func copyIntoFilamanIntro(count: Int) -> String {
        "FilaMan's scale reads a spool's own tag field. This gives \(count == 1 ? "1 spool" : "\(count) spools") "
            + "without a FilaMan tag its first SpoolLink tag. A spool whose scale already set a tag keeps it, "
            + "and a tag another spool already holds is listed, not taken. card_uids stays as it is while SpoolLink is on."
    }

    static func copyIntoNativeIntro(count: Int) -> String {
        "Spoolman keeps tag links in its own Tags section, where Spoolman and other tag readers see them. "
            + "This copies \(count == 1 ? "1 link" : "\(count) links") SpoolKid knows only from card_uids "
            + "into Spoolman Tags. card_uids stays as it is while SpoolLink is on."
    }

    // MARK: - Copying this iPhone's tag record (issue #24)

    /// Outside Tag Links the record row is disabled; the footer says why.
    static func migrationManagementFooter(writesLinks: Bool, connectionRowLabel: String) -> String {
        guard writesLinks else { return linksOffNote(connectionRowLabel: connectionRowLabel) }
        return "Fixes tag links that are missing on the server or in one of its stores. Each copy shows what it will do first."
    }

    static func recordCopyRowLabel(displayName: String) -> String {
        "Copy tag links from on-device Library to \(displayName)"
    }

    static func recordCopyIntro(count: Int, displayName: String) -> String {
        "This iPhone remembers which spool each tag you scanned or wrote belongs to. "
            + "\(count == 1 ? "1 of those tags isn't" : "\(count) of those tags aren't") linked on \(displayName), "
            + "so other apps and printers can't find \(count == 1 ? "it" : "them"). This links "
            + "\(count == 1 ? "it" : "them") to the same spools. A tag that now belongs to something else is listed, not taken."
    }

    static func recordSpoolGoneLine(uid: String) -> String {
        "Tag \(uid): its spool is archived or no longer on the server."
    }

    static func recordOwnedElsewhereLine(uid: String, owner: String) -> String {
        "Tag \(uid) now belongs to \(owner)."
    }

    static func copyIntoCardUIDsIntro(count: Int) -> String {
        "Snapmaker U1 firmware and other SpoolLink readers look for tag links in card_uids. "
            + "This copies \(count == 1 ? "1 link" : "\(count) links") from Spoolman Tags into card_uids. "
            + "Spoolman Tags stays as it is."
    }

    static func copyResultSummary(copied: Int) -> String {
        switch copied {
        case 0: "Nothing was copied."
        case 1: "Copied 1 tag link."
        default: "Copied \(copied) tag links."
        }
    }

    // MARK: - Deleting a store

    static func storeNoun(_ store: TagStore) -> String {
        store == .cardUIDs ? "card_uids" : "Spoolman Tags"
    }

    static func deleteRowLabel(_ store: TagStore, displayName: String) -> String {
        store == .cardUIDs ? "Delete card_uids from \(displayName)…" : "Delete Spoolman Tag Links…"
    }

    static func deleteTitle(_ store: TagStore) -> String {
        store == .cardUIDs ? "Delete card_uids?" : "Delete Spoolman Tag Links?"
    }

    /// Names who stops seeing the links. Without a second store the card_uids
    /// wording is the one the retired Library-tab alert used.
    static func deleteMessage(_ store: TagStore, check: TagStoreAudit.DeletionCheck, displayName: String) -> String {
        switch (store, check) {
        case (.cardUIDs, .noOtherStore):
            return "This permanently removes the Card UIDs field and every spool's tag mapping from \(displayName). "
                + "Your Snapmaker U1 / SpoolLink app will no longer recognise these tags. This cannot be undone."
        case (.cardUIDs, _):
            return "This permanently removes the card_uids field and every spool's card_uids value from \(displayName). "
                + "Every link is already in Spoolman Tags. A Snapmaker U1 whose firmware does not read Spoolman Tags, "
                + "and SpoolLink apps, will no longer recognise these tags. This cannot be undone."
        case (.spoolmanTags, .ready(let count, _)), (.spoolmanTags, .noOtherStore(let count)):
            let what = count == 1 ? "1 tag from its spool" : "\(count) tags from their spools"
            return "This unlinks \(what) in Spoolman. Every link is already in card_uids. Spoolman's Tags section "
                + "and other tag readers will no longer recognise them, and a printer or app that writes Spoolman Tags "
                + "may add them back. Filament tags are not touched. This cannot be undone."
        case (.spoolmanTags, _):
            return "This unlinks every spool's tag in Spoolman. This cannot be undone."
        case (.filamanTags, _):
            // Never offered: `deletionCheck` returns `.nothingToDelete` for FilaMan Tags.
            return "This unlinks every spool's FilaMan tag. This cannot be undone."
        }
    }

    /// How many links a "copy first" would fix. For deleting Spoolman Tags a
    /// disagreeing card_uids copy counts: the copy is what corrects it.
    static func copyableCount(deleting: TagStore, missing: TagStoreAudit.MissingLinks) -> Int {
        missing.copyable.count + (deleting == .spoolmanTags ? missing.stale.count : 0)
    }

    static func blockedIntro(deleting: TagStore, missing: TagStoreAudit.MissingLinks) -> String {
        let other: TagStore = deleting == .cardUIDs ? .spoolmanTags : .cardUIDs
        let count = copyableCount(deleting: deleting, missing: missing)
        var parts: [String] = []
        if count > 0 {
            parts.append(count == 1
                ? "1 tag link is not in \(storeNoun(other)) yet."
                : "\(count) tag links are not in \(storeNoun(other)) yet.")
            parts.append("Copy \(count == 1 ? "it" : "them") before deleting \(storeNoun(deleting)), so no link is lost.")
        }
        parts += missing.filamentConflicts.map(filamentConflictLine)
        return parts.joined(separator: " ")
    }

    static func filamentConflictLine(_ conflict: TagStoreAudit.FilamentConflict) -> String {
        "Spoolman lists \(conflict.link.uid) on the filament \(conflict.filamentLabel). "
            + "Unlink it from the filament in Spoolman, or unlink it from \(conflict.link.spoolLabel) here, then try again."
    }
}
