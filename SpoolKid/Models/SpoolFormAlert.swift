//
//  SpoolFormAlert.swift
//  SpoolKid
//
//  Purpose: Every plain alert the spool form shows, one at a time
//  (2026-10-11). One `.alert` instead of seven keeps the form's modifier
//  chain short enough to grow; "New Location" keeps its own alert, because
//  it has a text field.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum SpoolFormAlert: Equatable, Sendable {
    case nfcError(String)
    case invalidInput(String)
    case saveFailed(String)
    case actionFailed(title: String, message: String)
    case limitReached(String)
    /// An Add batch that stopped after some spools were created. The message
    /// names what was created and what was not, so the form stays open with it.
    case batchIncomplete(String)
    /// A tag that labels a shelf: Unlink and Continue clears it first.
    case shelfTag(uid: String, name: String)
    /// A tag another spool or a filament holds: Move takes it on Save.
    case moveTag(uid: String, holder: TagOwner)

    var title: String {
        switch self {
        case .nfcError: "NFC Error"
        case .invalidInput: "Invalid Input"
        case .saveFailed: "Could Not Save Spool"
        case .actionFailed(let title, _): title
        case .limitReached: "Limit Reached"
        case .batchIncomplete: "Saving Stopped Early"
        case .shelfTag: "That's a Location Tag"
        case .moveTag(let uid, let holder): TagHolderMove.confirmationToSpool(uid: uid, holder: holder).title
        }
    }

    var message: String {
        switch self {
        case .nfcError(let message), .invalidInput(let message), .saveFailed(let message), .limitReached(let message),
             .batchIncomplete(let message):
            message
        case .actionFailed(_, let message):
            message
        case .shelfTag(_, let name):
            "This tag labels \(name). Continuing clears the tag and links it to this spool — "
                + "you will be asked to hold it against the phone once more."
        case .moveTag(let uid, let holder):
            TagHolderMove.confirmationToSpool(uid: uid, holder: holder).message
        }
    }
}
