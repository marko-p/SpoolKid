//
//  TagCloneService.swift
//  SpoolKid
//
//  Purpose: Clone Tag's decisions outside the NFC session — whether the hub
//  offers it, which tags a copy may not land on, and what to ask once it has.
//  The hub presents; this decides (A2). `NFCManager.cloneTag` does the write
//  and refuses what it is told to refuse.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

enum TagCloneService {

    /// What the scanned tag belongs to, as far as the hub resolved it. `uids`
    /// are the owner's tags, normalized — a copy landing on one of them is not
    /// taking a tag from anything else.
    nonisolated enum Owner: Equatable, Sendable {
        case none
        case spool(id: Int, label: String, uids: [String])
        case location(uuid: UUID, name: String, uids: [String])

        var uids: [String] {
            switch self {
            case .none: return []
            case .spool(_, _, let uids), .location(_, _, let uids): return uids
            }
        }
    }

    /// What to do about linking a copy that has landed.
    nonisolated enum LinkStep: Equatable, Sendable {
        case none
        case askToLinkSpool(spoolID: Int, label: String, uid: String)
        case askToAddToLocation(uuid: UUID, name: String, uid: String)
    }

    /// Everything that follows one `NFCManager.CloneWriteResult`.
    nonisolated enum FollowUp: Equatable, Sendable {
        case nothing
        case offerUnlink(uid: String)
        case releaseThenLink(uid: String, then: LinkStep)
        case link(LinkStep)
    }

    nonisolated struct LinkAlertCopy: Equatable, Sendable {
        let title: String
        let confirm: String
        let message: String
    }

    // MARK: - The button

    /// Hidden while the hub is still resolving: the button would sit above a
    /// spinner, and the owner it links to is not known yet.
    static func showsCloneButton(result: ScanResult, hubState: ScanResultHubView.HubState) -> Bool {
        guard let snapshot = result.tagSnapshot, snapshot.isCopyable else { return false }
        switch hubState {
        case .loading, .parsingWebUrl, .webChallenge:
            return false
        case .authoritativeSpool, .cardUIDSpool, .matchResults, .unknownTag, .noSpoolman, .locationTag, .filamentTag,
             .backendLabelProblem:
            return true
        }
    }

    /// The Clone Tag menu item's subtitle: only ELEGOO copies are untested on
    /// a printer, and that is the one thing a user must know before tapping.
    /// The rest of the old caption described the action; the menu title does.
    static func untestedWarning(for result: ScanResult) -> String? {
        result.format == .elegoo
            ? "Copies of ELEGOO tags haven't been tested on an ELEGOO printer yet."
            : nil
    }

    // MARK: - Whose tag it is

    /// The owner comes from what the hub resolved, not from the UID alone: a
    /// tag carrying an embedded spool id belongs to that spool even when its
    /// UID is mapped to nothing.
    ///
    /// `locationRecord` is `ScanResultHubView.registryRecord(for:scannedUID:registry:)`'s
    /// answer; `ledger` is `TagAssociationStore.shared.snapshot()`.
    /// `spools` is `store.spools`.
    static func sourceOwner(
        hubState: ScanResultHubView.HubState,
        locationRecord: LocationRecord?,
        ledger: [String: Int],
        spools: [Spool] = []
    ) -> Owner {
        switch hubState {
        case .authoritativeSpool(let resolved), .cardUIDSpool(let resolved):
            // The hub's spool is a copy taken at resolve time; `spools` is the
            // store's current list. A ledger row naming this spool for a tag the
            // backend now maps to another spool is stale, and must not exempt
            // that tag from being blocked.
            let spool = spools.first { $0.id == resolved.id } ?? resolved
            let mappedElsewhere = Set(normalized(spools.filter { $0.id != spool.id }.flatMap(\.mappedCardUIDs)))
            let ledgerUIDs = ledger
                .filter { $0.value == spool.id && !mappedElsewhere.contains(SpoolMappingService.normalizeUID($0.key)) }
                .keys.sorted()
            return .spool(id: spool.id, label: spool.listTitle, uids: normalized(spool.mappedCardUIDs + ledgerUIDs))
        case .locationTag:
            guard let locationRecord else { return .none }
            return .location(uuid: locationRecord.uuid, name: locationRecord.name, uids: normalized(locationRecord.tagUIDs))
        // A copy of a filament tag carries no link of its own to block.
        case .loading, .parsingWebUrl, .webChallenge, .matchResults, .unknownTag, .noSpoolman, .filamentTag,
             .backendLabelProblem:
            return .none
        }
    }

    /// Every claimed tag except the owner's own.
    static func blockedUIDs(claimed: Set<String>, owner: Owner) -> Set<String> {
        let own = Set(normalized(owner.uids))
        return Set(normalized(Array(claimed))).subtracting(own)
    }

    private static func normalized(_ uids: [String]) -> [String] {
        var seen = Set<String>()
        return uids
            .map(SpoolMappingService.normalizeUID)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: - After the write

    /// A UID the owner already holds needs no step, and outside Tag Links a
    /// spool's copy is not linked (it carries the same bytes, `spool_id`
    /// included). A location's tag list lives on the device, so the mode does
    /// not gate it.
    static func linkStep(owner: Owner, uid: String, writesLinks: Bool) -> LinkStep {
        let target = SpoolMappingService.normalizeUID(uid)
        guard !target.isEmpty, !normalized(owner.uids).contains(target) else { return .none }
        switch owner {
        case .none:
            return .none
        case .spool(let id, let label, _):
            return writesLinks ? .askToLinkSpool(spoolID: id, label: label, uid: target) : .none
        case .location(let uuid, let name, _):
            return .askToAddToLocation(uuid: uuid, name: name, uid: target)
        }
    }

    /// Nothing is released unless the copy landed on exactly the tag the user
    /// agreed to take: a cancelled second session, one refused before writing, or
    /// a different tag presented to it, changes nothing. A raw copy cut short
    /// part-way is `.failed` too — its message says so, and the claim stays.
    static func followUp(
        after result: NFCManager.CloneWriteResult?,
        pendingUnlinkUID: String?,
        owner: Owner,
        writesLinks: Bool
    ) -> FollowUp {
        switch result {
        case nil, .sameTag, .failed:
            return .nothing
        case .blocked(let uid):
            return .offerUnlink(uid: uid)
        case .written(let uid):
            guard let uid else { return .nothing }
            let target = SpoolMappingService.normalizeUID(uid)
            guard !target.isEmpty else { return .nothing }
            let step = linkStep(owner: owner, uid: target, writesLinks: writesLinks)
            if let pendingUnlinkUID, SpoolMappingService.normalizeUID(pendingUnlinkUID) == target {
                return .releaseThenLink(uid: target, then: step)
            }
            return step == .none ? .nothing : .link(step)
        }
    }

    // MARK: - Copy

    /// A tag only the on-device ledger claims has no name to give.
    static func ownerName(_ owner: TagOwner) -> String {
        switch owner {
        case .spool(_, let label): return label
        case .filament(_, let label): return label
        case .location(let name): return name
        case .none: return "a spool"
        }
    }

    static func linkAlertCopy(for step: LinkStep) -> LinkAlertCopy? {
        switch step {
        case .askToLinkSpool(_, let label, _):
            return LinkAlertCopy(
                title: "Link the Copy to \(label)?",
                confirm: "Link",
                message: "The copy carries the same data. Linking also records its tag ID on \(label), so either tag finds the spool."
            )
        case .askToAddToLocation(_, let name, _):
            return LinkAlertCopy(
                title: "Add the Copy to \(name)?",
                confirm: "Add",
                message: "The copy already reads as \(name). Adding it lists it among \(name)'s tags, so renaming the shelf offers to rewrite it too."
            )
        case .none:
            return nil
        }
    }

    // MARK: - Store steps

    /// Takes the tag from whatever claimed it before the copy landed. Both
    /// releases are idempotent, and running both frees a tag that was claimed
    /// twice rather than keeping the broken half. Nil once nothing claims it;
    /// otherwise the notice to post.
    static func releasePreviousOwner(uid: String, store: SpoolDataStore) async -> String? {
        store.locationRegistry?.detachTag(uid: uid)
        let unlinked = await store.unlinkTag(uid: uid)
        // A filament's link too (spec 4); its result is re-asked below, like
        // the spool's.
        if case .filament(let id, _) = store.owner(ofTagUID: uid) {
            _ = await store.unlinkFilamentTag(filamentId: id, uid: uid)
        }
        return releaseNote(unlinked: unlinked, ownerAfterRelease: store.owner(ofTagUID: uid))
    }

    /// What to tell the user after a release. `unlinkTag` removes the tag from
    /// Spoolman's native tags and `card_uids`, never FilaMan's `rfid_uid`, so
    /// a spool can still hold the tag through `rfid_uid` after a write that
    /// succeeded — so success is re-asked of
    /// `owner(ofTagUID:)` rather than taken from the write.
    static func releaseNote(unlinked: Bool, ownerAfterRelease: TagOwner) -> String? {
        guard unlinked else {
            return "The copy was written, but another spool still claims that tag."
        }
        switch ownerAfterRelease {
        case .none:
            return nil
        case .spool(_, let label):
            return "The copy was written, but \(label) still holds that tag in a field SpoolKid cannot change."
        case .filament(_, let label):
            return "The copy was written, but the filament \(label) still claims that tag."
        case .location(let name):
            return "The copy was written, but \(name) still claims that tag."
        }
    }

    /// Carries out a link the user said yes to. Nil when there is nothing to
    /// report.
    static func link(_ step: LinkStep, store: SpoolDataStore) async -> String? {
        switch step {
        case .none:
            return nil
        case .askToLinkSpool(let spoolID, let label, let uid):
            guard let spool = store.spools.first(where: { $0.id == spoolID }) else {
                return "\(label) could not be found, so the copy was not linked to it."
            }
            return await TagLinkService.assign(uid, to: spool, in: store).followUpNote
        case .askToAddToLocation(let uuid, let name, let uid):
            // Every claim site asks `owner(ofTagUID:)`. After a release that
            // could not clear a spool's claim, adding the tag to a shelf would
            // give it two owners.
            if let refusal = locationLinkRefusal(currentOwner: store.owner(ofTagUID: uid), name: name) {
                return refusal
            }
            // No `setLocationTagUID` mirror: FilaMan's `identifier` holds one
            // value and already names the original tag.
            store.recordWrittenLocationTag(uid: uid, to: uuid, locationName: name)
            return nil
        }
    }

    /// The refusal for adding a copy to a shelf while a spool still holds its
    /// tag. Nil otherwise — a tag moving between shelves is
    /// `LocationRegistry.attach`'s ordinary job.
    static func locationLinkRefusal(currentOwner: TagOwner, name: String) -> String? {
        switch currentOwner {
        case .spool, .filament: currentOwner.claimRefusal(attemptedBy: .location(name: name))
        case .location, .none: nil
        }
    }
}
