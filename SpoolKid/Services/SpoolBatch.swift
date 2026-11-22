//
//  SpoolBatch.swift
//  SpoolKid
//
//  Purpose: Creates several identical spools from one draft (Add Spools, Count).
//  Each spool goes through the store's single-spool create, in order. A batch
//  never rolls back: what landed stays, and the result says where it stopped
//  and why, so nothing reports more spools than exist.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// How much of a batch exists. `nonisolated` so its Equatable works outside the main actor.
nonisolated enum SpoolBatchCompleteness: Equatable, Sendable {
    /// Nothing was created.
    case none
    /// A failure after some spools were created.
    case partial
    /// Every spool was created.
    case complete
}

/// What a batch create left behind: the spools that exist, in order, and why it stopped.
struct SpoolBatchResult {
    let created: [Spool]
    let failure: SpoolBatchFailure?
    /// Caveats of the creates that landed (a create's `errorMessage` on success), each once, in order.
    let caveats: [String]

    /// `.notSaved(failure.reason)` when nothing was created. A partial batch (a
    /// failure after some creates landed) is `.savedWithCaveat` whose first line
    /// is the stop message, so it never reads as plain success (C7); any create
    /// caveats follow it. A complete batch is `.savedWithCaveat(combined caveats)`
    /// when any, otherwise `.saved`. Uses `SaveOutcome.combinedNote`.
    var outcome: SaveOutcome {
        if created.isEmpty, let failure { return .notSaved(failure.reason) }
        if let failure {
            let stop = SpoolBatch.incompleteMessage(createdIDs: created.map(\.id), failure: failure)
            return .savedWithCaveat(SaveOutcome.combinedNote([stop] + caveats) ?? stop)
        }
        if let note = SaveOutcome.combinedNote(caveats) { return .savedWithCaveat(note) }
        return .saved
    }

    /// What the form gates its write or scan on: only a complete batch goes on.
    var completeness: SpoolBatchCompleteness {
        if failure == nil { return .complete }
        return created.isEmpty ? .none : .partial
    }

    /// The caveat a complete batch shows as a banner. A partial batch's caveat
    /// is its alert's message instead, so it is never shown twice.
    var bannerCaveat: String? {
        failure == nil ? outcome.caveat : nil
    }

    /// The "Saving Stopped Early" alert's message. Only a batch that stopped
    /// after creating something raises it; with nothing created the form shows
    /// its failure alert instead.
    var stopAlertMessage: String? {
        failure != nil && !created.isEmpty ? outcome.caveat : nil
    }
}

/// Where a batch stopped. `nonisolated` so its Equatable works outside the main
/// actor, as it does for `QuotaError`.
nonisolated struct SpoolBatchFailure: Equatable, Sendable {
    let position: Int   // 1-based: the spool that did not confirm
    let total: Int
    let reason: String  // the store's errorMessage, else "The spool could not be saved."
}

enum SpoolBatch {
    static let countRange: ClosedRange<Int> = 1...50

    /// `count` copies of `draft`; only the first keeps `cardUIDs` (D4: before saving only Spool 1 holds tags).
    static func drafts(from draft: SpoolDraft, count: Int) -> [SpoolDraft] {
        (0..<count).map { index in
            var copy = draft
            if index > 0 { copy.cardUIDs = nil }
            return copy
        }
    }

    /// The partial-failure alert's message (C7, C12). Never says the failed spool was not created.
    static func incompleteMessage(createdIDs: [Int], failure: SpoolBatchFailure) -> String {
        let created = createdIDs.isEmpty ? "" : "Created \(idList(createdIDs)). "
        let remaining = failure.total - failure.position
        let rest: String
        if remaining > 1 {
            rest = " The last \(remaining) spools were not created."
        } else if remaining == 1 {
            rest = " The last spool was not created."
        } else {
            rest = ""
        }
        return "\(created)Spool \(failure.position) of \(failure.total): \(sentence(failure.reason))\(rest)"
    }

    /// "#a", "#a and #b", or "#a, #b and #c".
    private static func idList(_ ids: [Int]) -> String {
        let tags = ids.map { "#\($0)" }
        guard tags.count > 1, let last = tags.last else { return tags.joined() }
        return tags.dropLast().joined(separator: ", ") + " and " + last
    }

    /// A reason the backend already wrote as a sentence keeps its own punctuation.
    private static func sentence(_ reason: String) -> String {
        guard let last = reason.last, ".!?".contains(last) else { return reason + "." }
        return reason
    }
}
