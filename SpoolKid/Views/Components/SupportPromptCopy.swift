//
//  SupportPromptCopy.swift
//  SpoolKid
//
//  Purpose: Every user-facing string in the support ask, in one place so the
//  tone can be reviewed as a whole and the views stay render-only.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// Short, kind, and specific to the moment. The pitch stands on what the app
/// just did for the user — never on the licence, never on guilt (the tone the
/// 2026-08-11 README rewrite settled on).
nonisolated enum SupportPromptCopy {

    static func headline(for reason: SupportPromptReason) -> String {
        switch reason {
        case .scanMilestone(let count):
            return "That's \(count) tags."
        case .editMilestone(let count):
            return "\(count) changes to your library."
        case .upgrade(let version):
            return "SpoolKid \(version) is here."
        case .successMoment:
            return "Nicely tagged."
        }
    }

    static func body(for reason: SupportPromptReason) -> String {
        switch reason {
        case .scanMilestone:
            return "Every one of them free. If SpoolKid saves you time at the bench, a contribution keeps it going."
        case .editMilestone:
            return "Keeping SpoolKid running has real costs. If it's pulling its weight, a contribution helps."
        case .upgrade:
            return "New work, same price. If it's useful, a contribution helps fund the next one."
        case .successMoment:
            return "SpoolKid is free and stays free. If it saves you time, a contribution keeps it going."
        }
    }

    static let thanksHeadline = "Thank you."
    static let thanksBody = "That means a lot. We won't ask again — there's a switch in the iOS Settings app if you ever change your mind."

    static let sheetBody = "SpoolKid is free to use. Subscriptions and services, an Apple Developer account, test hardware and the tags themselves all cost money — a contribution helps keep it going."

    static let supportButton = "Support SpoolKid"
    static let notNowButton = "Not now"
    static let sheetDismissButton = "Maybe later"
    static let sheetOptOutButton = "Don't show again"
}
