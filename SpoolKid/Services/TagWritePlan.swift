//
//  TagWritePlan.swift
//  SpoolKid
//
//  Purpose: Where a tag link goes on a backend with two tag stores, and the
//  calls that make a spool's tag list what a caller asked for. Pure — the
//  Spoolman repository executes the plan.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// Which tag stores receive NEW links. Removals ignore this: a link is
/// cleaned out of every store that holds it, or an unlink would leave a copy
/// that still resolves.
nonisolated enum TagWriteTargets {
    static func resolve(
        available: Set<TagStore>, nativeEnabled: Bool, spoolLinkEnabled: Bool, filamanTagsEnabled: Bool = false
    ) -> Set<TagStore> {
        // FilaMan: its rfid_uid is a store of its own, beside card_uids. With
        // both switches off the answer is the old one, card_uids alone.
        if available.contains(.filamanTags) {
            var targets: Set<TagStore> = []
            if filamanTagsEnabled { targets.insert(.filamanTags) }
            if spoolLinkEnabled { targets.insert(.cardUIDs) }
            return targets.isEmpty ? [.cardUIDs] : targets
        }
        // Below Spoolman 0.27 (and on FilaMan) card_uids is the only place a
        // link can go, and it has always been written whatever the SpoolLink
        // switch says. Unchanged.
        guard available.contains(.spoolmanTags) else { return [.cardUIDs] }
        var targets: Set<TagStore> = []
        if nativeEnabled { targets.insert(.spoolmanTags) }
        if spoolLinkEnabled { targets.insert(.cardUIDs) }
        // The settings never allow both off; a hand-edited default must still
        // leave somewhere to write.
        return targets.isEmpty ? [.spoolmanTags] : targets
    }

    /// Whether `spool` already holds `uid` everywhere a new link would go.
    /// Without native tags this is exactly the old `mappedCardUIDs` test, so
    /// older servers and FilaMan skip the same writes they always did.
    static func isFullyLinked(uid: String, on spool: Spool, targets: Set<TagStore>, available: Set<TagStore>) -> Bool {
        let normalized = SpoolMappingService.normalizeUID(uid)
        // FilaMan: card_uids when it is a target, and rfid_uid when that is.
        // A target rfid_uid must hold this tag, unless card_uids is also a
        // target and keeps its own copy (R + S keeps tag A in card_uids).
        // With FilaMan Tags off the old test stands: a tag in the read-only
        // rfid_uid already resolves here, so no card_uids copy is written.
        if available.contains(.filamanTags) {
            guard targets.contains(.filamanTags) else { return spool.mappedCardUIDs.contains(normalized) }
            if targets.contains(.cardUIDs), !spool.cardUIDs.contains(normalized) { return false }
            if targets.contains(.filamanTags) {
                let rfid = SpoolMappingService.normalizeUID(spool.rfidUID ?? "")
                if rfid.isEmpty { return false }
                if rfid != normalized, !targets.contains(.cardUIDs) { return false }
            }
            return spool.mappedCardUIDs.contains(normalized)
        }
        guard available.contains(.spoolmanTags) else { return spool.mappedCardUIDs.contains(normalized) }
        if targets.contains(.spoolmanTags), !spool.nativeTagUIDs.contains(normalized) { return false }
        if targets.contains(.cardUIDs), !spool.cardUIDs.contains(normalized) { return false }
        return spool.mappedCardUIDs.contains(normalized)
    }

    /// Whether a scan that resolved `uid` to `resolved` should repair the
    /// stores: a target store lacks the link, or another spool still carries
    /// a stale `card_uids` copy. paxx12's SpoolLink does the same on every
    /// resolve, which is how links made before the upgrade become native.
    static func needsRepair(
        uid: String, resolved: Spool, spools: [Spool], targets: Set<TagStore>, available: Set<TagStore>
    ) -> Bool {
        guard available.contains(.spoolmanTags) else { return false }
        let normalized = SpoolMappingService.normalizeUID(uid)
        if !isFullyLinked(uid: normalized, on: resolved, targets: targets, available: available) { return true }
        return spools.contains { $0.id != resolved.id && $0.cardUIDs.contains(normalized) }
    }
}

/// Turns "this spool's tag list should be X" into the native link/unlink
/// calls and the single `card_uids` PATCH that make it so, on a server with
/// native tags.
nonisolated enum TagWritePlan {
    enum NativeTagHolder: Equatable, Sendable {
        case spool(id: Int)
        case filament(id: Int, label: String)
    }

    enum Op: Equatable, Sendable {
        /// `moveFromSpool` is set only for a UID the caller is newly adding: a
        /// 409 from that holder then means "take it", as paxx12's SpoolLink
        /// does. A UID merely carried over is never moved.
        case link(uid: String, moveFromSpool: Int?)
        case unlink(uid: String)
        case setCardUIDs([String])
    }

    enum Skip: Equatable, Sendable {
        /// A `card_uids` copy of a UID another spool holds natively.
        /// The native holder wins every read, so the copy is dropped, not
        /// linked.
        case staleHeldBySpool(uid: String, spoolId: Int)
        /// `requested`: the caller asked for it (a failure); otherwise a
        /// pre-existing conflict this write leaves alone.
        case heldByFilament(uid: String, label: String, requested: Bool)
    }

    struct Result: Equatable, Sendable {
        var ops: [Op]
        var skips: [Skip]
    }

    /// `nativeHolder` answers who else holds a UID natively — never `spool`
    /// itself.
    static func make(
        spool: Spool,
        desired: [String],
        targets: Set<TagStore>,
        nativeHolder: (String) -> NativeTagHolder?
    ) -> Result {
        var seen = Set<String>()
        let wanted = desired.map(SpoolMappingService.normalizeUID).filter { !$0.isEmpty && seen.insert($0).inserted }
        let current = Set(spool.writableCardUIDs)
        let native = Set(spool.nativeTagUIDs)

        var links: [Op] = []
        var skips: [Skip] = []
        // The UIDs every store may keep: everything wanted except what step
        // one sets aside.
        var surviving: [String] = []

        for uid in wanted {
            if native.contains(uid) {
                surviving.append(uid)
                continue
            }
            let isNew = !current.contains(uid)
            switch nativeHolder(uid) {
            case .spool(let other)? where !isNew:
                skips.append(.staleHeldBySpool(uid: uid, spoolId: other))
            case .filament(_, let label)?:
                skips.append(.heldByFilament(uid: uid, label: label, requested: isNew))
                if !isNew { surviving.append(uid) }
            case .spool(let other)?:
                surviving.append(uid)
                if targets.contains(.spoolmanTags) { links.append(.link(uid: uid, moveFromSpool: other)) }
            case nil:
                surviving.append(uid)
                if targets.contains(.spoolmanTags) { links.append(.link(uid: uid, moveFromSpool: nil)) }
            }
        }

        let wantedSet = Set(wanted)
        let unlinks = spool.nativeTagUIDs.filter { !wantedSet.contains($0) }.map { Op.unlink(uid: $0) }

        let cardList: [String]
        if targets.contains(.cardUIDs) {
            cardList = surviving
        } else {
            // Not a target: removals still apply, additions never do.
            let keep = Set(surviving)
            cardList = spool.cardUIDs.filter { keep.contains($0) }
        }

        var ops = links + unlinks
        if cardList != spool.cardUIDs { ops.append(.setCardUIDs(cardList)) }
        return Result(ops: ops, skips: skips)
    }
}
