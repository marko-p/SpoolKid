//
//  TagLinkService.swift
//  SpoolKid
//
//  Purpose: The single-owner tag↔spool mapping write. A tag belongs to exactly
//  one spool, so attaching it to a new owner also has to release every other
//  spool still holding it — and say honestly which half of that landed.
//
//  Lifted out of `ScanResultHubView` on 2026-08-31 when `WriteTagView` needed
//  the same rule: writing a tag from an existing spool now links it, and a
//  second copy of the attach-then-detach ordering would have been a second
//  place for the invariant to drift.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

@MainActor
enum TagLinkService {
    /// One `setCardUIDs` call with its result kept instead of discarded (plan
    /// defect I3 — the same swallow Task 17b fixed in `SpoolFormView`).
    ///
    /// `store.errorMessage` is consulted ONLY on the failure branch. No backend
    /// leaves a caveat on a successful mapping write, but `SpoolmanService`'s
    /// mapping writes do not CLEAR the message either, so an unrelated failure
    /// from an earlier call is still sitting there; reading it on a success
    /// would report a mapping that landed cleanly as half-failed.
    static func writeCardUIDs(
        spoolId: Int, uids: [String], failureFallback: String, in store: SpoolDataStore
    ) async -> SaveOutcome {
        let didSave = await store.setCardUIDs(spoolId: spoolId, uids: uids)
        guard !didSave else { return .saved }
        return SaveOutcome.classify(didSave: false, message: store.errorMessage, failureFallback: failureFallback)
    }

    /// Single-owner assign: put `uid` on `target`'s `card_uids` (deduped), then
    /// take it off every *other* spool that still holds it, so a tag belongs to
    /// exactly one spool (the auto-move). Unlimited cardinality.
    ///
    /// Returns what the writes accomplished rather than discarding it. Until
    /// Task 19 both calls were fail-closed stubs on FilaMan, so mapping a tag
    /// there wrote nothing and said nothing; now that they are real the failure
    /// is *conditional*, which is harder to notice rather than easier.
    ///
    /// ## Why the target is written FIRST
    ///
    /// There is no transaction across the two writes and no rollback between
    /// them, so one can land alone. The order decides which half-state the user
    /// is left standing in:
    ///
    /// - **attach first** (this order): a failed detach leaves the tag on the
    ///   new spool *and* on its old one. Single-owner is broken, but nothing is
    ///   lost — the tag still resolves, both owners are visible in the app, and
    ///   repeating the assign clears it.
    /// - **detach first** (what this did before Task 19): a failed attach
    ///   leaves the tag on NO spool. It reads as a blank, unmapped tag, and the
    ///   only surviving record of where it came from is the local scan ledger.
    ///
    /// Recoverable beats lost, so the attach goes first — which is also the
    /// order `moveReusableUIDs` already uses for the same transfer.
    ///
    /// That rationale holds for `card_uids`. It does NOT hold for FilaMan's
    /// `rfid_uid` (FilaMan Tags): the server keeps it unique, so claiming a
    /// tag another spool still holds there is refused. A person's link
    /// therefore RELEASES the holder first, and if the claim then fails the
    /// holder is put back once. When that restore fails too, the tag is on no
    /// spool and the outcome says so (spec, Live facts).
    ///
    /// - `replacing`: the person chose Replace Tag, so the target's links
    ///   become exactly `[uid]`. Without it a spool that already holds a
    ///   different tag is refused when FilaMan Tags is the only store.
    /// - `personInitiated`: false for writes nobody is watching (the lazy
    ///   spool-ID migration, scan repair). Those never replace a tag and
    ///   never take an `rfid_uid` from another spool; they refuse and say so.
    static func assign(
        _ uid: String, to target: Spool, in store: SpoolDataStore,
        replacing: Bool = false, personInitiated: Bool = true
    ) async -> SaveOutcome {
        let normalized = SpoolMappingService.normalizeUID(uid)
        guard !normalized.isEmpty else {
            return .notSaved("That tag has no readable ID, so it could not be mapped.")
        }

        // A tag belongs to one spool OR one location, never both. Checked here
        // rather than at each caller: this is the funnel every spool claim
        // passes through, and the two callers that DID check looked at the
        // scanned payload, which says nothing about a tag whose NDEF was wiped
        // while the registry still holds the claim.
        //
        // Refused rather than taken. Releasing the shelf silently would
        // un-label it with no prompt, and the screens that legitimately move a
        // tag between the two kinds of owner — the location write, the spool
        // form's link scan — each ask first.
        let owner = store.owner(ofTagUID: normalized)
        if let refusal = owner.claimRefusal(attemptedBy: .spool(id: target.id, label: target.listTitle)) {
            switch owner {
            case .location, .filament: return .notSaved(refusal)
            case .spool, .none: break
            }
        }

        // Hidden controls are the first line; this is the second. Outside Tag
        // Links a plan would add nothing and still report a save.
        guard store.tagIdentity.writesLinks else {
            return .notSaved(TagStoreText.linksOffNote(connectionRowLabel: store.capabilities.connectionRowLabel))
        }

        // The caller's copy can be older than the store's; a list built from
        // it would undo whatever changed since. Writes start from the current
        // one. On a server with native tags, "already mapped" means mapped in
        // every store a new link goes to.
        let current = store.spools.first { $0.id == target.id } ?? target
        let available = store.availableTagStores
        let targets = store.tagIdentity.linkTargets

        // FilaMan keeps one tag per spool. Replacing needs a person's say-so.
        if let existing = replacementConflict(uid: normalized, spool: current, targets: targets),
           !replacing || !personInitiated {
            return .notSaved(TagStoreText.filamanOneTagNote(existing: existing))
        }

        // `rfid_uid` is unique on the server: whoever holds it must let go
        // before the target can claim it. Nobody takes it in the background.
        let holders = store.spools.filter {
            $0.id != target.id && $0.rfidUIDWritable
                && $0.rfidUID.map(SpoolMappingService.normalizeUID) == normalized
        }
        if !personInitiated, let holder = holders.first {
            return .notSaved(TagStoreText.heldElsewhereNote(holder: holder.listTitle))
        }
        var released: [(spool: Spool, previous: [String])] = []
        for holder in holders {
            let releasedNow = await writeCardUIDs(
                spoolId: holder.id,
                uids: holder.writableCardUIDs.filter { $0 != normalized },
                failureFallback: "\(holder.listTitle) could not be updated.",
                in: store
            )
            guard releasedNow.didWrite else {
                _ = await restore(released, in: store)
                return releasedNow
            }
            released.append((holder, holder.writableCardUIDs))
        }

        // A Replace with leftovers still to drop must write even when the tag
        // is already linked everywhere.
        let replaceHasLeftovers = replacing && current.writableCardUIDs != [normalized]
        if replaceHasLeftovers
            || !TagWriteTargets.isFullyLinked(uid: normalized, on: current, targets: targets, available: available) {
            let attached = await writeCardUIDs(
                spoolId: current.id,
                uids: replacing ? [normalized] : current.writableCardUIDs + [normalized],
                failureFallback: "The tag could not be mapped to this spool.",
                in: store
            )
            guard attached.didWrite else {
                guard !released.isEmpty else { return attached }
                let restored = await restore(released, in: store)
                return .notSaved(TagStoreText.claimFailedNote(
                    holder: released.map { $0.spool.listTitle }.joined(separator: ", "), restored: restored
                ))
            }
        }

        // Runs even when `target` already held the tag: another spool can still
        // be holding it from an earlier assign that failed at exactly this step.
        var stillHolding: [String] = []
        var undetachable: [String] = []
        for other in store.spools where other.id != target.id && other.mappedCardUIDs.contains(normalized) {
            // Spoolman's native tags and `card_uids` are writable; FilaMan's
            // `rfid_uid` is not. A UID living there survives this write,
            // which still succeeds — so the detach has to be reported, not
            // assumed (I1). The write below runs when there is a writable
            // copy to remove, and removes a native link whatever the store
            // switches say; removing the `rfid_uid` copy needs a policy
            // decision and is filed as debt.
            if other.cardUIDs.contains(normalized) || other.nativeTagUIDs.contains(normalized) {
                let detached = await writeCardUIDs(
                    spoolId: other.id,
                    uids: other.writableCardUIDs.filter { $0 != normalized },
                    failureFallback: "\(other.listTitle) could not be updated.",
                    in: store
                )
                if !detached.didWrite {
                    stillHolding.append(other.listTitle)
                    continue
                }
            }
            if other.undetachableCardUIDs.contains(normalized) {
                undetachable.append(other.listTitle)
            }
        }
        return assignOutcome(unclearedOwners: stillHolding, undetachableOwners: undetachable)
    }

    /// Moves each of `uids` onto `destination` through `assign`, one at a
    /// time. The hub's tag move uses this while FilaMan Tags is a target: a
    /// bulk destination-then-source write would find the source still holding
    /// a tag in `rfid_uid`, so the tag would end in no spool's `rfid_uid`.
    /// `assign` releases first and runs the single-owner pass. Stops at the
    /// first refusal and returns it; caveats from the landed moves are joined.
    static func moveTags(_ uids: [String], to destination: Spool, in store: SpoolDataStore) async -> SaveOutcome {
        var caveats: [String?] = []
        for uid in uids {
            let current = store.spools.first { $0.id == destination.id } ?? destination
            let outcome = await assign(uid, to: current, in: store)
            guard outcome.didWrite else { return outcome }
            caveats.append(outcome.caveat)
        }
        return SaveOutcome.combinedNote(caveats).map(SaveOutcome.savedWithCaveat) ?? .saved
    }

    /// One best-effort attempt to put each released holder's list back.
    /// True when every write landed.
    private static func restore(
        _ released: [(spool: Spool, previous: [String])], in store: SpoolDataStore
    ) async -> Bool {
        var allRestored = true
        for entry in released {
            let outcome = await writeCardUIDs(
                spoolId: entry.spool.id, uids: entry.previous,
                failureFallback: "\(entry.spool.listTitle) could not be updated.", in: store
            )
            if !outcome.didWrite { allRestored = false }
        }
        return allRestored
    }

    /// The tag that stops `spool` taking `uid` when FilaMan Tags is the only
    /// store links go to: it keeps one tag per spool, so any other tag the
    /// spool holds is in the way. Nil when links also go to `card_uids`
    /// (which holds many), or nothing else is held.
    nonisolated static func replacementConflict(uid: String, spool: Spool, targets: Set<TagStore>) -> String? {
        guard targets == [.filamanTags] else { return nil }
        let normalized = SpoolMappingService.normalizeUID(uid)
        // Linking a tag the spool already has is not a conflict.
        guard !spool.mappedCardUIDs.map(SpoolMappingService.normalizeUID).contains(normalized) else { return nil }
        return spool.mappedCardUIDs.first { SpoolMappingService.normalizeUID($0) != normalized }
    }

    /// What a single-owner assign amounts to once the tag IS on its new spool.
    ///
    /// A previous owner that could not be released is a caveat and never a
    /// failure: the mapping the user asked for exists. But it is not a clean
    /// success either — the single-owner invariant is broken and only the user
    /// can settle which spool the tag belongs to — so it must not borrow the
    /// silence a clean save gets.
    ///
    /// The two kinds of leftover owner need different advice, which is why they
    /// arrive separately. `unclearedOwners` is a write that FAILED — retrying
    /// can fix it. `undetachableOwners` is a write that cannot succeed: the UID
    /// lives in a field SpoolKid does not write, so telling the user to scan
    /// again would loop them forever (I1).
    nonisolated static func assignOutcome(unclearedOwners: [String], undetachableOwners: [String]) -> SaveOutcome {
        var sentences: [String] = []
        if !unclearedOwners.isEmpty {
            sentences.append(
                "The tag is mapped to this spool, but it is still mapped to "
                + unclearedOwners.joined(separator: ", ")
                + ". Scan it again to finish moving it."
            )
        }
        if !undetachableOwners.isEmpty {
            sentences.append(
                "The tag is mapped to this spool, but "
                + undetachableOwners.joined(separator: ", ")
                + " still holds it in FilaMan's own tag binding, which SpoolKid cannot change. "
                + "Clear it in FilaMan to finish the move."
            )
        }
        guard !sentences.isEmpty else { return .saved }
        return .savedWithCaveat(sentences.joined(separator: " "))
    }

    /// What an unlink leaves behind on the spool it released.
    ///
    /// SpoolKid writes Spoolman's native tags and `card_uids`, never FilaMan's
    /// `rfid_uid`. A UID that ALSO lives in `rfid_uid` survives the unlink —
    /// the write succeeds and the spool still resolves the tag (I1) — so
    /// that case must not report a clean success. The direction is the mirror of
    /// `assignOutcome`'s: there the tag arrives on a new spool while an old
    /// one cannot let go; here it leaves a spool that cannot fully let IT go.
    nonisolated static func unlinkCaveat(uid: String, spool: Spool) -> String? {
        let normalized = SpoolMappingService.normalizeUID(uid)
        guard spool.undetachableCardUIDs.map(SpoolMappingService.normalizeUID).contains(normalized)
        else { return nil }
        return "\(spool.listTitle) still holds this tag in FilaMan's own tag binding, which SpoolKid cannot change. "
            + "Clear it in FilaMan to finish unlinking."
    }

    /// Links a tag just scanned to a spool already chosen: the hub's Add
    /// Another Tag and the Spool page's Link Tag. Returns what to show, nil
    /// when the link landed cleanly or the scan carried no UID.
    ///
    /// A location tag is still labelling a shelf. Letting a spool claim its
    /// UID would break the single-owner invariant silently, and the read-side
    /// heal cannot recover it — that heal only runs on a scan that decoded as
    /// filament data.
    static func linkScanned(
        _ result: ScanResult, to spool: Spool, in store: SpoolDataStore, replacing: Bool = false
    ) async -> String? {
        if let payload = result.locationTag {
            let name = ScanResultHubView.resolvedLocationName(
                for: payload, scannedUID: result.cardUID, registry: store.locationRegistry
            )
            return "That tag labels \(name). A location tag can't also be a spool tag."
        }
        guard let uid = result.cardUID else { return nil }
        return await assign(uid, to: spool, in: store, replacing: replacing).followUpNote
    }

    /// Unlinks `uid` from `spool`: the hub's and the Spool page's Unlink.
    /// Returns what to show, nil for a clean release. A UID the spool ALSO
    /// holds undetachably (FilaMan's rfid_uid) survives the write — the caveat
    /// says so rather than letting a 200 claim a clean release (I1).
    static func unlink(_ uid: String, from spool: Spool, in store: SpoolDataStore) async -> String? {
        let didUnlink = await store.unlinkTag(uid: uid)
        let outcome = SaveOutcome.classify(
            didSave: didUnlink,
            message: store.errorMessage,
            failureFallback: "The tag could not be unlinked from \(spool.listTitle)."
        )
        return SaveOutcome.combinedNote([
            outcome.followUpNote,
            didUnlink ? unlinkCaveat(uid: uid, spool: spool) : nil
        ])
    }
}
