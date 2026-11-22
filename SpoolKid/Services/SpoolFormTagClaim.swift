//
//  SpoolFormTagClaim.swift
//  SpoolKid
//
//  Purpose: What the spool form does with a tag scanned to link — the one
//  decision its "Scan tag to link" makes, kept out of the view (2026-10-11).
//  One tag, one owner: a shelf's tag is refused with a way through, and a tag
//  another spool or a filament holds is offered as a move that runs on Save.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum SpoolFormTagClaim: Equatable, Sendable {
    /// Nothing to do: no UID, or the tag is already listed.
    case ignore
    /// Free, or already this spool's: list it.
    case take(uid: String)
    /// One of the Move Tags offer's own tags: list it and tick it.
    case takeOffered(uid: String)
    /// A shelf's label: refused, with Unlink and Continue (clear the tag first).
    case refuseShelf(uid: String, name: String)
    /// Another spool's or a filament's: asked first; the move runs on Save.
    case offerMove(uid: String, holder: TagOwner)

    /// - Parameters:
    ///   - payloadShelfName: the shelf a location payload on the tag names, if
    ///     the tag carries one. The registry's claim arrives through `owner`.
    ///   - owner: `SpoolDataStore.owner(ofTagUID:)` for the scanned UID.
    ///   - editingSpoolID: the spool the form edits; nil when creating.
    ///   - offeredUIDs: the Move Tags offer's UIDs; empty without an offer.
    ///   - listedUIDs: the UIDs the form already lists.
    static func decide(
        uid rawUID: String?,
        payloadShelfName: String?,
        owner: TagOwner,
        editingSpoolID: Int?,
        offeredUIDs: [String],
        listedUIDs: [String]
    ) -> SpoolFormTagClaim {
        let uid = SpoolMappingService.normalizeUID(rawUID ?? "")
        // Two ways a tag can still be a shelf label: it says so, or the
        // registry says so. The payload alone missed a tag whose NDEF had been
        // wiped while the claim stood.
        if let payloadShelfName { return .refuseShelf(uid: uid, name: payloadShelfName) }
        if case .location(let name) = owner { return .refuseShelf(uid: uid, name: name) }
        guard !uid.isEmpty, !listedUIDs.contains(uid) else { return .ignore }
        // An offered tag is listed only in the Move Tags section, so one
        // scanned here is ticked, not asked about: the offer already moves it.
        if offeredUIDs.contains(uid) { return .takeOffered(uid: uid) }
        switch owner {
        case .spool(let id, _) where id != editingSpoolID:
            return .offerMove(uid: uid, holder: owner)
        case .filament:
            return .offerMove(uid: uid, holder: owner)
        case .none, .spool, .location:
            return .take(uid: uid)
        }
    }
}
