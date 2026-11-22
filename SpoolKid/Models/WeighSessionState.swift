//
//  WeighSessionState.swift
//  SpoolKid
//
//  Purpose: The state of one batch weighing session — the spool currently on
//  the scale, and the log of those already saved. Pure and synchronous on
//  purpose: the loop's rules are the part worth testing, and none of them need
//  SwiftUI or a network.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct WeighSessionState: Equatable {

    /// The spool currently on the scale.
    struct Pending: Equatable {
        let spoolID: Int
        let spoolName: String
        /// Nil when the spool has no core weight recorded. The session refuses
        /// to guess it — see `CommitOutcome.blockedNeedsEmptySpoolWeight`.
        var emptySpoolWeight: Double?
        var weightInput: String = ""
        /// Material · vendor · id, composed by the view. Carried here beside
        /// `spoolName` rather than looked up at render time so the row keeps
        /// naming the spool that was actually loaded, even after a refresh
        /// reorders or drops it from `store.spools`.
        var detail: String = ""
        var colors = FilamentColors(hexes: [])
        /// The spool's brand, for the empty-spool picker's brand section;
        /// carried for the same reason as `detail`.
        var manufacturer: String? = nil
    }

    /// A spool this session has already written.
    struct Entry: Identifiable, Equatable {
        let spoolID: Int
        let spoolName: String
        var grossWeight: Double
        var netWeight: Double
        /// What the write actually accomplished — a `SaveOutcome` rather than a
        /// `Bool`, because a repository returns `true` WITH a caveat when the
        /// spool landed but something it carried did not (a FilaMan measurement
        /// that was never filed, a remaining weight the backend could not
        /// compute). Rendering that as a clean save is the "never report
        /// success for work you did not do" invariant broken. A `Bool` plus a
        /// caveat string would make `notSaved`-with-a-caveat representable;
        /// this cannot.
        var outcome: SaveOutcome

        /// Whether the spool reached the backend at all. Both saved cases did.
        var didWrite: Bool { outcome.didWrite }

        var id: Int { spoolID }
    }

    enum CommitOutcome: Equatable {
        /// No pending spool, or its weight box is blank. Blank means "skipped",
        /// not "record zero", so advancing writes nothing and is not an error.
        case nothingToSave
        /// A gross reading cannot become a remaining weight without the spool's
        /// core weight. `SpoolFormView` treats a missing core as weighing
        /// nothing; the session must NOT, because in a fast loop that silently
        /// records ~200 g of cardboard as filament.
        case blockedNeedsEmptySpoolWeight
        case ready(spoolID: Int, gross: Double, net: Double)
    }

    /// What a "Scan"/"Choose" tap should do. Separate from `CommitOutcome`
    /// because the same reading means different things depending on who owns
    /// the decision to save — and because "advance" and "save" stopped being
    /// the same gesture when the auto-save toggle arrived.
    enum AdvanceIntent: Equatable {
        /// Nothing worth saving is on screen; just move on.
        case advance
        /// Same guard as `CommitOutcome`, and deliberately NOT bypassable by
        /// turning auto-save off: a gross reading with no core weight is
        /// unsaveable, not merely unsaved.
        case blockedNeedsEmptySpoolWeight
        /// Auto-save on: write it, then move on.
        case commitThenAdvance(spoolID: Int, gross: Double, net: Double)
        /// Auto-save off: ask before either saving or discarding it. Advancing
        /// silently would drop a reading the user is still looking at.
        case confirmUnsaved(spoolID: Int, gross: Double, net: Double)
    }

    private(set) var pending: Pending?
    private(set) var log: [Entry] = []

    mutating func setPending(_ pending: Pending) {
        self.pending = pending
    }

    mutating func updateWeightInput(_ input: String) {
        pending?.weightInput = input
    }

    mutating func setEmptySpoolWeight(_ grams: Double) {
        pending?.emptySpoolWeight = grams
    }

    mutating func clearPending() {
        pending = nil
    }

    func commitOutcome() -> CommitOutcome {
        guard let pending,
              let gross = SpoolWeightMath.parseWeight(pending.weightInput) else {
            return .nothingToSave
        }
        guard let empty = pending.emptySpoolWeight else {
            return .blockedNeedsEmptySpoolWeight
        }
        return .ready(
            spoolID: pending.spoolID,
            gross: gross,
            net: SpoolWeightMath.netFromGross(gross: gross, emptySpoolWeight: empty)
        )
    }

    func advanceIntent(autoSave: Bool) -> AdvanceIntent {
        switch commitOutcome() {
        case .nothingToSave:
            return .advance
        case .blockedNeedsEmptySpoolWeight:
            return .blockedNeedsEmptySpoolWeight
        case .ready(let spoolID, let gross, let net):
            return autoSave
                ? .commitThenAdvance(spoolID: spoolID, gross: gross, net: net)
                : .confirmUnsaved(spoolID: spoolID, gross: gross, net: net)
        }
    }

    /// Files the result of a write. A spool already in the log is UPDATED in
    /// place rather than appended: a stack often contains a spool already
    /// handled, and two rows for one spool would make the log unreadable. This
    /// is also how a retry clears a failed row.
    mutating func recordWrite(
        spoolID: Int,
        spoolName: String,
        gross: Double,
        net: Double,
        outcome: SaveOutcome
    ) {
        let entry = Entry(
            spoolID: spoolID,
            spoolName: spoolName,
            grossWeight: gross,
            netWeight: net,
            outcome: outcome
        )
        if let index = log.firstIndex(where: { $0.spoolID == spoolID }) {
            log[index] = entry
        } else {
            log.append(entry)
        }
    }
}
