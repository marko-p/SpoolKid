//
//  TagMoveOffer.swift
//  SpoolKid
//
//  Purpose: The tags a new spool or a transfer takes from the spool the
//  scanned tag belongs to. The user ticks which move; every tag starts
//  ticked (owner, 2026-09-27 — the default of the toggle this replaces).
//  Spec: 2026-09-27-scan-hub-simplification-design.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct TagMoveOffer: Equatable, Sendable {
    let sourceSpoolID: Int
    let sourceTitle: String
    /// Normalized, de-duplicated, the scanned UID first.
    let uids: [String]
    let scannedUID: String

    /// Nil unless `source` holds the scanned UID: only a known tag's spool
    /// has tags to move. Lists Spoolman's native tags and `card_uids`
    /// (`writableCardUIDs`): a removal clears a tag from every store that
    /// holds it (`TagWriteTargets`), so both kinds can move (spec
    /// 2026-10-11 §4). Never a UID FilaMan's `rfid_uid` also holds: that
    /// copy would stay on the source after the move, so the scanned tag gets
    /// no offer and any other such tag is left off the checklist (final
    /// review FR-3).
    static func make(scannedUID: String?, source: Spool) -> TagMoveOffer? {
        guard let scannedUID else { return nil }
        let scanned = SpoolMappingService.normalizeUID(scannedUID)
        guard !scanned.isEmpty else { return nil }

        let undetachable = Set(source.undetachableCardUIDs.map(SpoolMappingService.normalizeUID))
        var seen = Set<String>()
        let mapped = source.writableCardUIDs.compactMap { uid -> String? in
            let normalized = SpoolMappingService.normalizeUID(uid)
            guard !normalized.isEmpty, !undetachable.contains(normalized),
                  seen.insert(normalized).inserted else { return nil }
            return normalized
        }
        guard mapped.contains(scanned) else { return nil }

        return TagMoveOffer(
            sourceSpoolID: source.id,
            sourceTitle: source.listTitle,
            uids: [scanned] + mapped.filter { $0 != scanned },
            scannedUID: scanned
        )
    }

    /// D4: every tag starts ticked.
    var defaultSelection: Set<String> { Set(uids) }

    /// The ticked UIDs in offer order — what the destination receives.
    func movedUIDs(selection: Set<String>) -> [String] {
        uids.filter { selection.contains($0) }
    }

    /// What the source keeps: its native tags and `card_uids` minus the moved
    /// ones. Never `mappedCardUIDs`, which would write an `rfid_uid` into
    /// `card_uids` (I1); never `cardUIDs` alone, which would unlink a native
    /// tag `card_uids` does not mirror (P-1).
    static func remainingSourceUIDs(of source: Spool, moved: [String]) -> [String] {
        let movedSet = Set(moved.map(SpoolMappingService.normalizeUID))
        return source.writableCardUIDs.filter { !movedSet.contains(SpoolMappingService.normalizeUID($0)) }
    }

    /// What the destination holds after the move: its own native tags and
    /// `card_uids` (minus any it is receiving again) followed by the moved ones.
    static func destinationUIDs(of destination: Spool, adding moved: [String]) -> [String] {
        let movedSet = Set(moved.map(SpoolMappingService.normalizeUID))
        return destination.writableCardUIDs.filter { !movedSet.contains(SpoolMappingService.normalizeUID($0)) } + moved
    }
}
