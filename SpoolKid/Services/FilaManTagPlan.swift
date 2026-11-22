//
//  FilaManTagPlan.swift
//  SpoolKid
//
//  Purpose: What a FilaMan spool's tag fields should become when a caller
//  asks for a tag list: the card_uids list, and which one UID the writable
//  rfid_uid should hold. Pure — the FilaMan repository executes the plan.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// Turns "this spool's tags should be X" into the `card_uids` list and the
/// `rfid_uid` change for FilaMan with FilaMan Tags on. `rfid_uid` holds one
/// tag, so when the list names several it takes the first that no other
/// spool holds.
nonisolated enum FilaManTagPlan {
    enum RFIDChange: Equatable, Sendable {
        case keep
        /// Carries the normalized UID.
        case set(String)
        case clear
    }

    struct Result: Equatable, Sendable {
        /// nil = card_uids unchanged.
        var cardUIDs: [String]?
        var rfid: RFIDChange
        /// Candidates skipped because another spool's rfid_uid holds them.
        var heldElsewhere: [String]

        var isEmpty: Bool { cardUIDs == nil && rfid == .keep }
    }

    /// `rfidHolder` answers which other spool's `rfid_uid` holds a normalized
    /// UID, or nil. Its answer for `spool` itself is ignored.
    static func make(
        spool: Spool,
        desired: [String],
        targets: Set<TagStore>,
        rfidHolder: (String) -> Int?
    ) -> Result {
        var seen = Set<String>()
        let wanted = desired.map(SpoolMappingService.normalizeUID).filter { !$0.isEmpty && seen.insert($0).inserted }
        let wantedSet = Set(wanted)

        // card_uids is written only when it is a target. Removals apply to it
        // whatever the targets say, so an unlink never leaves a copy behind.
        let proposedCardUIDs: [String]
        if targets.contains(.cardUIDs) {
            proposedCardUIDs = wanted
        } else {
            proposedCardUIDs = spool.cardUIDs.filter { wantedSet.contains($0) }
        }
        let cardUIDs = proposedCardUIDs == spool.cardUIDs ? nil : proposedCardUIDs

        // rfid_uid follows writability for removals: it is a store of its own
        // while FilaMan Tags is on. A NEW tag goes into it only when it is a
        // target, or when the tag it holds is being removed (promotion) — a
        // removal elsewhere (Spool ID mode) never fills an empty slot.
        guard spool.rfidUIDWritable else {
            return Result(cardUIDs: cardUIDs, rfid: .keep, heldElsewhere: [])
        }
        let current = normalizedRFID(spool.rfidUID)
        if let current, wantedSet.contains(current) {
            return Result(cardUIDs: cardUIDs, rfid: .keep, heldElsewhere: [])
        }
        if current == nil, !targets.contains(.filamanTags) {
            return Result(cardUIDs: cardUIDs, rfid: .keep, heldElsewhere: [])
        }

        var heldElsewhere: [String] = []
        for uid in wanted {
            if let holder = rfidHolder(uid), holder != spool.id {
                heldElsewhere.append(uid)
                continue
            }
            return Result(cardUIDs: cardUIDs, rfid: .set(uid), heldElsewhere: heldElsewhere)
        }
        // Every candidate is held elsewhere, or there were none: free the
        // slot only if the spool holds one now.
        return Result(
            cardUIDs: cardUIDs,
            rfid: current == nil ? .keep : .clear,
            heldElsewhere: heldElsewhere
        )
    }

    /// Wanted UIDs that are new to `spool` and that `result` stores nowhere:
    /// not in the card_uids list it leaves, and not the rfid_uid it sets.
    /// A write with any of these would report success and lose the tag.
    static func unplaced(spool: Spool, desired: [String], result: Result) -> [String] {
        let known = Set(spool.mappedCardUIDs.map(SpoolMappingService.normalizeUID))
        let inList = Set((result.cardUIDs ?? spool.cardUIDs).map(SpoolMappingService.normalizeUID))
        var placedRFID: String?
        if case .set(let uid) = result.rfid { placedRFID = uid }
        var seen = Set<String>()
        return desired.map(SpoolMappingService.normalizeUID).filter { uid in
            !uid.isEmpty && seen.insert(uid).inserted
                && !known.contains(uid) && !inList.contains(uid) && uid != placedRFID
        }
    }

    /// The form a UID takes on the wire for `rfid_uid`: normalized, then
    /// lowercased. Callers clear with JSON null, never with "".
    static func wireValue(_ uid: String) -> String {
        SpoolMappingService.normalizeUID(uid).lowercased()
    }

    /// A raw `rfid_uid` as a normalized UID, or nil when there is no tag.
    /// FilaMan can store "" for no tag, which is never a tag.
    private static func normalizedRFID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = SpoolMappingService.normalizeUID(raw)
        return normalized.isEmpty ? nil : normalized
    }
}
