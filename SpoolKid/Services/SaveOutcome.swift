//
//  SaveOutcome.swift
//  SpoolKid
//
//  Purpose: The three things a form's save can actually have accomplished.
//  Turns the repository layer's `(Bool, errorMessage)` pair — which cannot
//  distinguish a clean success from a partial one — into a value that can.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// Which haptic a save earns, named without dragging UIKit into the service
/// layer. `SpoolFormView` maps these onto `UINotificationFeedbackGenerator`.
nonisolated enum SaveFeedback: Equatable, Sendable {
    case success
    case warning
}

/// What a save actually accomplished: **saved**, **saved with a caveat**, or
/// **not saved** (plan defect I1).
///
/// `SpoolDataRepository`'s write methods return a `Bool` and leave a message
/// on `errorMessage`, and on a partial success they return `true` WITH a
/// message — "the filament was saved without its colour", "the spool was saved
/// without its location", a dropped multi-colour direction. Both form views
/// read that message only on the `false` branch, so a partial success fired
/// the success haptic and dismissed in silence: Task 17 built honest partial
/// failure reporting in the repository and the UI threw it away.
///
/// Two booleans' worth of state does not fit in one, which is why this is an
/// enum rather than another optional. `SpoolDataStore.errorMessage` on a
/// success means something different from `errorMessage` on a failure, and a
/// caller reading it as one thing is exactly the "a value meaning two things"
/// defect F24/F25/F29/I1/I2 were each an instance of.
///
/// Backend-agnostic by construction: Spoolman and Local clear `errorMessage`
/// on every successful write, so they always classify as `.saved`. Nothing
/// here branches on backend identity.
nonisolated enum SaveOutcome: Equatable, Sendable {
    /// Joins every caveat one write produced, dropping the blanks. Two of them
    /// can arrive together — a location that could not be created AND a weight
    /// that could not be applied — and letting the second overwrite the first
    /// would lose one of them silently, which is the defect this task is about
    /// in miniature.
    ///
    /// Lived on `FilaManRepository` until 2026-08-27, when probing Spoolman
    /// gave that integration caveats of its own to combine. It was never
    /// FilaMan-specific — assembling a write's caveats is what this type is
    /// for.
    nonisolated static func combinedNote(_ notes: [String?]) -> String? {
        let stated = notes
            .compactMap { $0 }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return stated.isEmpty ? nil : stated.joined(separator: "\n")
    }

    case saved
    case savedWithCaveat(String)
    case notSaved(String)

    /// Classifies one write. `message` is the repository's `errorMessage` as
    /// it stood immediately after the call — read it before any follow-up
    /// write, which would overwrite it with its own result.
    ///
    /// `failureFallback` is the form's own wording for "it didn't work and the
    /// backend didn't say why"; it is never used on a success, because a
    /// success with no message is not a failure needing an explanation.
    static func classify(didSave: Bool, message: String?, failureFallback: String) -> SaveOutcome {
        let reported = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stated = (reported?.isEmpty == false) ? reported : nil
        guard didSave else { return .notSaved(stated ?? failureFallback) }
        guard let stated else { return .saved }
        return .savedWithCaveat(stated)
    }

    /// Whether the record reached the server. Both saved cases did, so both
    /// dismiss the form: the write is not undoable, and holding the user in a
    /// form over a swatch that failed is worse than letting them out with a
    /// note.
    var didWrite: Bool {
        switch self {
        case .saved, .savedWithCaveat: true
        case .notSaved: false
        }
    }

    /// The message to surface AFTER the form goes away, if any. Only a caveat
    /// lands here — a failure has a form still on screen to be shown in.
    var caveat: String? {
        switch self {
        case .savedWithCaveat(let message): message
        case .saved, .notSaved: nil
        }
    }

    /// The message to show in the form the user is still standing in, if any.
    var failure: String? {
        switch self {
        case .notSaved(let message): message
        case .saved, .savedWithCaveat: nil
        }
    }

    /// What this write leaves to report when it is a FOLLOW-UP to one that
    /// already landed — a tag mapping written after the spool itself, say
    /// (plan defect I3).
    ///
    /// A caveat and a failure collapse to the same thing here, and only here:
    /// the primary record is already on the server, so there is no form left
    /// to hold the user in and nothing to retry into. Either way the user is
    /// told, through the same banner, and the save is downgraded off the
    /// success haptic. `nil` means the follow-up has nothing to say — which
    /// includes a follow-up that had nothing to do.
    ///
    /// This is deliberately NOT `failure`: reading a follow-up's failure as
    /// the whole save's failure would report a saved spool as unsaved.
    var followUpNote: String? {
        caveat ?? failure
    }

    /// A caveat must not borrow the success haptic — the whole point of I1.
    /// A failure gets none here: the form raises its own error alert.
    var feedback: SaveFeedback? {
        switch self {
        case .saved: .success
        case .savedWithCaveat: .warning
        case .notSaved: nil
        }
    }
}
