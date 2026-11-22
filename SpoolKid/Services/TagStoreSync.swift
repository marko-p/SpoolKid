//
//  TagStoreSync.swift
//  SpoolKid
//
//  Purpose: The one routine that copies tag links into a store. The Library
//  tab's "Copy to Spoolman Tags" and the delete flow's "copy first" both run
//  it.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// Writes through `SpoolDataStore`, so the repository's write plan decides the
/// actual calls. `target` must be a current write target — both callers
/// guarantee it, because the switch for that store is on.
@MainActor
enum TagStoreSync {
    struct TagCopyResult: Equatable {
        struct Failure: Hashable {
            let label: String
            let message: String
        }

        var copied = 0
        var failures: [Failure] = []
    }

    /// One failure per stale link, naming the spool whose `rfid_uid` holds it.
    nonisolated static func heldFailures(stale: [TagStoreAudit.Link], spools: [Spool]) -> [TagCopyResult.Failure] {
        stale.map { link in
            let holder = spools.first {
                $0.id != link.spoolId && $0.rfidUID.map(SpoolMappingService.normalizeUID) == link.uid
            }
            return .init(
                label: link.spoolLabel,
                message: TagStoreText.filamanHeldLine(uid: link.uid, holder: holder?.listTitle ?? "another spool")
            )
        }
    }

    /// A raw `rfid_uid` compared as a tag: normalized, "" and nil alike.
    nonisolated private static func normalizedRFID(_ raw: String?) -> String {
        SpoolMappingService.normalizeUID(raw ?? "")
    }

    /// A tag this iPhone's record ties to a spool, to be linked there.
    struct RecordLink: Equatable, Sendable {
        let uid: String
        let spoolId: Int
    }

    /// Issue #24: which record entries (UID → spool id, the active backend's
    /// scope) can be linked on the backend. Ordered by spool id, then UID.
    /// A spool that is gone or archived, or a tag something else now owns,
    /// is listed as skipped and never written; a tag its spool already
    /// holds is neither.
    nonisolated static func recordLinks(
        snapshot: [String: Int], spools: [Spool], owner: (String) -> TagOwner
    ) -> (copyable: [RecordLink], skipped: [TagCopyResult.Failure]) {
        let entries = snapshot
            .map { (uid: SpoolMappingService.normalizeUID($0.key), spoolId: $0.value) }
            .filter { !$0.uid.isEmpty }
            .sorted { ($0.spoolId, $0.uid) < ($1.spoolId, $1.uid) }
        var copyable: [RecordLink] = []
        var skipped: [TagCopyResult.Failure] = []
        for entry in entries {
            guard spools.contains(where: { $0.id == entry.spoolId && $0.archived != true }) else {
                skipped.append(.init(label: "Tag \(entry.uid)", message: TagStoreText.recordSpoolGoneLine(uid: entry.uid)))
                continue
            }
            switch owner(entry.uid) {
            case .none:
                copyable.append(RecordLink(uid: entry.uid, spoolId: entry.spoolId))
            case .spool(let id, _) where id == entry.spoolId:
                continue
            case let other:
                skipped.append(.init(
                    label: "Tag \(entry.uid)",
                    message: TagStoreText.recordOwnedElsewhereLine(uid: entry.uid, owner: other.label)
                ))
            }
        }
        return (copyable, skipped)
    }

    /// Links every copyable record entry through `TagLinkService.assign`, so
    /// the single-owner rule and the Tag Identity targets apply as for any
    /// link. Person-initiated only: the record identifies, it never links
    /// on its own.
    static func copyRecord(snapshot: [String: Int], in store: SpoolDataStore) async -> TagCopyResult {
        await store.fetchSpools()
        await store.fetchFilaments()
        guard store.tagIdentity.writesLinks else {
            return TagCopyResult(failures: [.init(
                label: "Tag links",
                message: TagStoreText.linksOffNote(connectionRowLabel: store.capabilities.connectionRowLabel)
            )])
        }
        let plan = recordLinks(snapshot: snapshot, spools: store.spools, owner: store.owner(ofTagUID:))
        var result = TagCopyResult(failures: plan.skipped)
        for link in plan.copyable {
            guard let spool = store.spools.first(where: { $0.id == link.spoolId }) else { continue }
            let outcome = await TagLinkService.assign(link.uid, to: spool, in: store)
            if outcome.didWrite { result.copied += 1 }
            if let note = outcome.followUpNote {
                result.failures.append(.init(label: spool.listTitle, message: note))
            }
        }
        WorkflowTraceStore.log(path: "tags", step: "record-copy", details: [
            "copied": String(result.copied),
            "failures": String(result.failures.count)
        ])
        return result
    }

    static func copy(into target: TagStore, in store: SpoolDataStore) async -> TagCopyResult {
        // SpoolLink may have been switched on moments ago, before the
        // foreground bootstrap could register the field; every write below
        // would then fail with "Unknown extra field card_uids". Idempotent.
        if target == .cardUIDs, store.capabilities.requiresCardUIDsFieldRegistration,
           await store.ensureCardUIDsField() == false {
            return TagCopyResult(failures: [.init(
                label: "card_uids",
                message: store.errorMessage ?? "The card_uids field could not be registered."
            )])
        }
        await store.fetchSpools()
        await store.fetchFilaments()
        let missing = TagStoreAudit.missingLinks(
            into: target, spools: store.spools, filaments: store.filaments
        )
        var result = TagCopyResult()
        // Never written: only the user can say which of the two owns the tag.
        result.failures = missing.filamentConflicts.map {
            .init(label: $0.link.spoolLabel, message: TagStoreText.filamentConflictLine($0))
        }

        // FilaMan Tags: a held tag is listed, never removed from card_uids and
        // never taken from its holder (ruling R1).
        if target == .filamanTags {
            result.failures += heldFailures(stale: missing.stale, spools: store.spools)
        }

        for (spoolId, stale) in Dictionary(grouping: target == .filamanTags ? [] : missing.stale, by: \.spoolId).sorted(by: { $0.key < $1.key }) {
            guard let spool = store.spools.first(where: { $0.id == spoolId }) else { continue }
            let remove = Set(stale.map(\.uid))
            let kept = spool.writableCardUIDs.filter { !remove.contains($0) }
            if await store.setCardUIDs(spoolId: spoolId, uids: kept) == false {
                result.failures.append(.init(
                    label: spool.listTitle,
                    message: store.errorMessage ?? "Its stale card_uids entries could not be removed."
                ))
            }
        }

        for (spoolId, links) in Dictionary(grouping: missing.copyable, by: \.spoolId).sorted(by: { $0.key < $1.key }) {
            guard let spool = store.spools.first(where: { $0.id == spoolId }) else { continue }
            if await store.setCardUIDs(spoolId: spoolId, uids: spool.writableCardUIDs) {
                if target == .filamanTags {
                    // A spool counts only when its rfid_uid actually changed:
                    // a write can succeed and leave the one slot as it was.
                    let after = store.spools.first { $0.id == spoolId }?.rfidUID
                    if Self.normalizedRFID(after) != Self.normalizedRFID(spool.rfidUID) { result.copied += 1 }
                } else {
                    result.copied += links.count
                }
            } else {
                result.failures.append(.init(
                    label: spool.listTitle,
                    message: store.errorMessage ?? "Its links could not be copied."
                ))
            }
        }

        WorkflowTraceStore.log(path: "tags", step: "store-copy", details: [
            "target": target.rawValue,
            "copied": String(result.copied),
            "failures": String(result.failures.count)
        ])
        return result
    }
}
