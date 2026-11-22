//
//  TagStoreAudit.swift
//  SpoolKid
//
//  Purpose: Store-level questions about tag links — what a store holds, what
//  another store lacks, and whether deleting one would lose anything SpoolKid
//  resolves. Pure; `TagStoreSync` and the Tag Identity delete flow act on the
//  answers.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum TagStoreAudit {
    struct Link: Hashable, Sendable {
        let uid: String
        let spoolId: Int
        let spoolLabel: String
    }

    struct FilamentConflict: Hashable, Sendable {
        let link: Link
        let filamentLabel: String
    }

    struct MissingLinks: Equatable, Sendable {
        /// SpoolKid resolves uid→spool, and the target store lacks it.
        var copyable: [Link] = []
        /// Copies that do NOT resolve to their spool — another spool holds the
        /// UID natively, or an earlier spool claims it. They are removed, never
        /// copied.
        var stale: [Link] = []
        /// Spoolman lists the UID on a filament, so it cannot become a spool's
        /// native tag. Only the user can settle these.
        var filamentConflicts: [FilamentConflict] = []

        var isEmpty: Bool { copyable.isEmpty && stale.isEmpty && filamentConflicts.isEmpty }
    }

    enum DeletionCheck: Equatable, Sendable {
        case nothingToDelete
        /// FilaMan, Spoolman below 0.27: deleting loses every link.
        case noOtherStore(linkCount: Int)
        case blocked(MissingLinks)
        case ready(linkCount: Int, staleCount: Int)
    }

    /// The links a store holds. Filament tags are never links: they belong to
    /// no spool.
    static func links(in store: TagStore, spools: [Spool]) -> [Link] {
        spools.flatMap { spool in
            let uids: [String]
            switch store {
            case .cardUIDs: uids = spool.cardUIDs
            case .spoolmanTags: uids = spool.nativeTagUIDs
            case .filamanTags: uids = filamanUIDs(of: spool)
            }
            return uids.map { Link(uid: $0, spoolId: spool.id, spoolLabel: spool.listTitle) }
        }
    }

    /// FilaMan's `rfid_uid` as a normalized UID, or nothing when it is empty.
    /// A `""` stored by FilaMan is no tag at all.
    private static func filamanUIDs(of spool: Spool) -> [String] {
        guard let rfid = spool.rfidUID else { return [] }
        let normalized = SpoolMappingService.normalizeUID(rfid)
        return normalized.isEmpty ? [] : [normalized]
    }

    /// What `target` lacks: into Spoolman Tags, a spool's `card_uids` it does
    /// not hold natively; into `card_uids`, its native tags.
    static func missingLinks(
        into target: TagStore, spools: [Spool], filaments: [Filament]
    ) -> MissingLinks {
        var result = MissingLinks()
        // Indexed once: the Library tab asks this on every render, and a
        // lookup per UID would be quadratic on a large library.
        let resolvesTo = SpoolMappingService.resolvingSpoolIDs(in: spools)
        var nativeHolder: [String: Int] = [:]
        for spool in spools {
            for uid in spool.nativeTagUIDs where nativeHolder[uid] == nil { nativeHolder[uid] = spool.id }
        }
        var filamentLabel: [String: String] = [:]
        for filament in filaments {
            for uid in filament.nativeTagUIDs where filamentLabel[uid] == nil { filamentLabel[uid] = filament.listTitle }
        }
        var filamanHolder: [String: Int] = [:]
        for spool in spools {
            for uid in filamanUIDs(of: spool) where filamanHolder[uid] == nil { filamanHolder[uid] = spool.id }
        }

        for spool in spools {
            switch target {
            case .spoolmanTags:
                let native = Set(spool.nativeTagUIDs)
                for uid in spool.cardUIDs where !native.contains(uid) {
                    let link = Link(uid: uid, spoolId: spool.id, spoolLabel: spool.listTitle)
                    if nativeHolder[uid] == nil, let label = filamentLabel[uid] {
                        result.filamentConflicts.append(FilamentConflict(link: link, filamentLabel: label))
                    } else if resolvesTo[uid] == spool.id {
                        result.copyable.append(link)
                    } else {
                        result.stale.append(link)
                    }
                }
            case .cardUIDs:
                let cardUIDs = spool.cardUIDs
                let inCardUIDs = Set(cardUIDs)
                for uid in spool.nativeTagUIDs where !inCardUIDs.contains(uid) {
                    result.copyable.append(Link(uid: uid, spoolId: spool.id, spoolLabel: spool.listTitle))
                }
                for uid in cardUIDs {
                    if let holder = nativeHolder[uid], holder != spool.id {
                        result.stale.append(Link(uid: uid, spoolId: spool.id, spoolLabel: spool.listTitle))
                    }
                }
            case .filamanTags:
                // Only a spool with no FilaMan tag takes one, and only its
                // first card_uids UID that no other spool holds. Held ones
                // ahead of it are stale: reported, never taken.
                guard filamanUIDs(of: spool).isEmpty else { continue }
                for uid in spool.cardUIDs.map(SpoolMappingService.normalizeUID) where !uid.isEmpty {
                    let link = Link(uid: uid, spoolId: spool.id, spoolLabel: spool.listTitle)
                    if let holder = filamanHolder[uid], holder != spool.id {
                        result.stale.append(link)
                    } else {
                        result.copyable.append(link)
                        break
                    }
                }
            }
        }
        return result
    }

    static func deletionCheck(
        deleting: TagStore, available: Set<TagStore>, spools: [Spool], filaments: [Filament]
    ) -> DeletionCheck {
        // FilaMan Tags are not deleted from here (a non-goal): the store is
        // FilaMan's own rfid_uid, which SpoolKid never clears in bulk.
        guard deleting != .filamanTags else { return .nothingToDelete }
        let count = links(in: deleting, spools: spools).count
        guard count > 0 else { return .nothingToDelete }
        let other: TagStore = deleting == .cardUIDs ? .spoolmanTags : .cardUIDs
        guard available.contains(other) else { return .noOtherStore(linkCount: count) }
        let missing = missingLinks(into: other, spools: spools, filaments: filaments)
        switch deleting {
        case .cardUIDs:
            // A stale copy loses nothing: the native holder already wins.
            guard missing.copyable.isEmpty, missing.filamentConflicts.isEmpty else { return .blocked(missing) }
            return .ready(linkCount: count, staleCount: missing.stale.count)
        case .spoolmanTags:
            // A disagreeing card_uids copy would START winning once the native
            // link is gone, so it blocks until the copy fixes it.
            guard missing.copyable.isEmpty, missing.stale.isEmpty else { return .blocked(missing) }
            return .ready(linkCount: count, staleCount: 0)
        case .filamanTags:
            return .nothingToDelete // Returned above; kept so the switch is exhaustive.
        }
    }
}
