//
//  SpoolWeightAdjustService.swift
//  SpoolKid
//
//  Purpose: Saves an adjustment to a spool's remaining weight made from the
//  Scan Result Hub — grams a print used, or a scale reading. Turns the stated
//  input into a draft and reports what was actually written, so the hub never
//  claims a save it did not make.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

@MainActor
enum SpoolWeightAdjustService {

    /// What the save accomplished. `.saved` carries the remaining weight that
    /// was written, read back from the fresh spool, not the preview.
    enum Result: Equatable {
        case saved(remaining: Double, caveat: String?)
        case refused(String)
        case failed(String)
    }

    /// What the save decides once the spool has been read. Pure, so the rule
    /// is tested without a store.
    nonisolated enum Plan: Equatable {
        case write(remaining: Double)
        case refused(String)
        case failed(String)
    }

    nonisolated static let readFailedMessage = "Could not read the spool's current weight. Check the connection and try again."

    /// The draft for an adjustment whose new remaining weight is already
    /// known. A Used amount writes `remainingWeight` only; a Measured reading
    /// also carries its gross figure (see `SpoolDraft.measuredWeight`).
    static func draft(for input: SpoolWeightAdjustment.Input, newRemaining: Double) -> SpoolDraft {
        var draft = SpoolDraft()
        draft.remainingWeight = .set(newRemaining)
        if case .measured(let gross) = input {
            draft.measuredWeight = gross
        }
        return draft
    }

    /// The decision for an adjustment against the spool as read. `spool` must
    /// be the FRESH copy for a Used amount; `freshReadFailed` says whether that
    /// read reported a failure, in which case nothing may be written.
    nonisolated static func decide(
        _ input: SpoolWeightAdjustment.Input,
        spool: Spool?,
        freshReadFailed: Bool
    ) -> Plan {
        if freshReadFailed { return .failed(readFailedMessage) }
        guard let spool else { return .failed("The spool could not be found.") }
        switch SpoolWeightAdjustment.outcome(
            of: input,
            currentRemaining: spool.remainingWeight,
            emptySpoolWeight: spool.spoolWeight
        ) {
        case .remaining(let value):
            return .write(remaining: value)
        case .negative:
            return .refused(SpoolWeightAdjustment.negativeNote)
        case .needsEmptySpoolWeight:
            return .refused(SpoolWeightAdjustment.needsEmptySpoolWeightNote)
        case .needsCurrentRemaining:
            return .refused(SpoolWeightAdjustment.needsCurrentRemainingNote)
        }
    }

    /// Applies `input` to the spool and writes the result. A Used amount is
    /// taken off a fresh re-read, since a Klipper printer may have reported
    /// consumption since the hub loaded; if that read fails nothing is written.
    /// A Measured reading is absolute and needs no re-read.
    ///
    /// The read's failure signal is `store.errorMessage` after `fetchSpools`.
    /// Every backend clears it on a successful spool fetch and sets it on a
    /// failed one (Spoolman `fetchData`, FilaMan `run`, Local `reload`), and
    /// `deletionImpact` already relies on the same signal.
    static func save(
        _ input: SpoolWeightAdjustment.Input,
        spoolID: Int,
        store: SpoolDataStore
    ) async -> Result {
        var freshReadFailed = false
        if case .used = input {
            await store.fetchSpools()
            freshReadFailed = store.errorMessage != nil
        }
        let spool = store.spools.first(where: { $0.id == spoolID })

        let remaining: Double
        switch decide(input, spool: spool, freshReadFailed: freshReadFailed) {
        case .write(let value):
            remaining = value
        case .refused(let message):
            return .refused(message)
        case .failed(let message):
            return .failed(message)
        }

        let didWrite = await store.updateSpool(
            id: spoolID,
            draft: draft(for: input, newRemaining: remaining)
        )
        // `updateSpool`'s Bool is half the contract: a PATCH can land while a
        // side-effect does not. Classified immediately, before any follow-up
        // write could overwrite `errorMessage`, as `WeighSessionView.write` does.
        let saveOutcome = SaveOutcome.classify(
            didSave: didWrite,
            message: store.errorMessage,
            failureFallback: "The spool's weight could not be saved."
        )
        if let caveat = saveOutcome.caveat {
            store.postSaveNotice(caveat, record: spool?.listTitle)
        }
        switch saveOutcome {
        case .saved:
            return .saved(remaining: remaining, caveat: nil)
        case .savedWithCaveat(let caveat):
            return .saved(remaining: remaining, caveat: caveat)
        case .notSaved(let message):
            return .failed(message)
        }
    }

    /// The confirmation shown under the button after a save.
    static func savedMessage(remaining: Double) -> String {
        "Saved — \(SpoolWeightMath.displayWeight(remaining)) g remaining"
    }
}
