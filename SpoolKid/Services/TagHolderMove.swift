//
//  TagHolderMove.swift
//  SpoolKid
//
//  Purpose: Moves tags between holders of different kinds — a spool and a
//  filament — or between two filaments (spec 4 §5); several at once to a
//  filament from the hub's picker (spec 2026-10-11). `TagMoveOffer` still
//  moves a spool's tags to another spool. Unlink first, then link: a link
//  that fails after the unlink says so, and never reads as a move.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// What a move confirmation says.
nonisolated struct TagMoveConfirmation: Equatable, Sendable {
    let title: String
    let message: String
}

enum TagHolderMove {
    /// How copy names a holder. A spool goes by its number as well as its
    /// name, because a spool and its filament often share the name.
    nonisolated static func holderPhrase(_ owner: TagOwner) -> String {
        switch owner {
        case .spool(let id, let label): "spool #\(id), \(label)"
        case .filament(_, let label): "the filament \(label)"
        case .location(let name): name
        case .none: ""
        }
    }

    /// The filament form's question; the move runs when the user taps Move.
    nonisolated static func confirmationToFilament(uid: String, holder: TagOwner) -> TagMoveConfirmation {
        if case .filament = holder {
            return TagMoveConfirmation(
                title: "Move Tag to This Filament?",
                message: "\(uid) is linked to \(holderPhrase(holder)). Moving it unlinks it from that filament and links it to this one."
            )
        }
        return TagMoveConfirmation(
            title: "Move Tag from Spool to Filament?",
            message: "\(uid) is linked to \(holderPhrase(holder)). Moving it unlinks it from the spool and links it to this filament."
        )
    }

    /// The spool form's question; the move runs when the form is saved.
    nonisolated static func confirmationToSpool(uid: String, holder: TagOwner) -> TagMoveConfirmation {
        if case .filament = holder {
            return TagMoveConfirmation(
                title: "Move Tag from Filament to Spool?",
                message: "\(uid) is linked to \(holderPhrase(holder)). Saving unlinks it from the filament and links it to this spool."
            )
        }
        return TagMoveConfirmation(
            title: "Move Tag to This Spool?",
            message: "\(uid) is linked to \(holderPhrase(holder)). Saving unlinks it from that spool and links it to this one."
        )
    }

    static func moveToFilament(uid: String, from holder: TagOwner, to filament: Filament, in store: SpoolDataStore) async -> SaveOutcome {
        guard await release(uid, from: holder, in: store) else {
            return .notSaved(store.errorMessage ?? "\(uid) could not be unlinked from \(holderPhrase(holder)), so nothing moved.")
        }
        let reason: String
        switch await store.linkFilamentTag(filamentId: filament.id, uid: uid) {
        case .linked: return .saved
        case .failed(let message): reason = message
        case .heldBySpool(let id): reason = "Spool #\(id) holds it."
        case .heldByFilament(let id): reason = "Filament #\(id) holds it."
        }
        let target = TagOwner.filament(id: filament.id, label: filament.listTitle)
        // Nothing held it, so nothing was unlinked: say only that the link failed.
        if case .none = holder {
            return .notSaved("\(uid) could not be linked to \(holderPhrase(target)): \(reason)")
        }
        return .notSaved(unlinkedNotRelinked(uid, from: holder, to: target, because: reason))
    }

    /// The hub picker's Filaments tab (spec 2026-10-11). Each tag moves from
    /// whatever holds it now, read just before its own move. One tag's
    /// failure never stops the rest. All moved → `.saved`; some →
    /// `.savedWithCaveat` naming the rest; none → `.notSaved` naming each.
    static func moveToFilament(uids: [String], to filament: Filament, in store: SpoolDataStore) async -> SaveOutcome {
        var movedCount = 0
        var notes: [String] = []
        for uid in uids {
            switch await moveToFilament(uid: uid, from: store.owner(ofTagUID: uid), to: filament, in: store) {
            case .saved:
                movedCount += 1
            case .savedWithCaveat(let note):
                movedCount += 1
                notes.append(note)
            case .notSaved(let note):
                notes.append(note)
            }
        }
        guard let note = SaveOutcome.combinedNote(notes) else { return .saved }
        return movedCount == 0 ? .notSaved(note) : .savedWithCaveat(note)
    }

    static func moveToSpool(uid: String, from holder: TagOwner, to spool: Spool, in store: SpoolDataStore) async -> SaveOutcome {
        guard await release(uid, from: holder, in: store) else {
            return .notSaved(store.errorMessage ?? "\(uid) could not be unlinked from \(holderPhrase(holder)), so nothing moved.")
        }
        let outcome = await TagLinkService.assign(uid, to: spool, in: store)
        if case .notSaved(let message) = outcome {
            return .notSaved(unlinkedNotRelinked(uid, from: holder, to: .spool(id: spool.id, label: spool.listTitle), because: message))
        }
        return outcome
    }

    nonisolated static func unlinkedNotRelinked(_ uid: String, from holder: TagOwner, to target: TagOwner, because reason: String) -> String {
        "\(uid) was unlinked from \(holderPhrase(holder)), but could not be linked to \(holderPhrase(target)): \(reason)"
    }

    /// The spool form's moves, run on Save before the form's own link write
    /// (2026-10-11). Each tag is released from its holder. One that cannot be
    /// released stays where it is: it is returned in `kept`, so the save does
    /// not write it too — two owners — and a note says so.
    static func releaseForSave(
        _ moves: [(uid: String, holder: TagOwner)], in store: SpoolDataStore
    ) async -> (kept: Set<String>, notes: [String]) {
        var kept: Set<String> = []
        var notes: [String] = []
        for move in moves {
            if await release(move.uid, from: move.holder, in: store) { continue }
            kept.insert(move.uid)
            notes.append("\(move.uid) could not be unlinked from \(holderPhrase(move.holder)), so it stays there.")
        }
        return (kept, notes)
    }

    /// A shelf's tag never moves this way.
    private static func release(_ uid: String, from holder: TagOwner, in store: SpoolDataStore) async -> Bool {
        switch holder {
        case .none: return true
        case .spool: return await store.unlinkTag(uid: uid)
        case .filament(let id, _): return await store.unlinkFilamentTag(filamentId: id, uid: uid)
        case .location: return false
        }
    }
}
