//
//  SupportPromptState.swift
//  SpoolKid
//
//  Purpose: The value types behind the support ask — what the app remembers,
//  what can trigger a prompt, what it decides, and what the user did about it.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// Everything the support prompts remember between launches.
///
/// Deliberately free of `UserDefaults`: `SupportPromptPolicy` operates on this
/// type alone, so every rule is testable without a defaults suite or a clock.
///
/// `nonisolated`: the target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
/// which would make the synthesized `Equatable` main-actor-isolated and unusable
/// from nonisolated test contexts. These are pure policy value types — opt out at
/// the type level, as `Entitlement` and `QuotaEntity` already do.
nonisolated struct SupportPromptState: Equatable, Sendable {
    var scanCount: Int = 0
    var editCount: Int = 0
    var promptsShown: Int = 0
    /// The user is done being asked — set by the sheet's "Don't show again", by
    /// tapping through to a support link, or by the toggle in the iOS Settings
    /// app, which is the only way back off. Never a claim that money changed
    /// hands: the app can see a tap and nothing more.
    var optedOut: Bool = false
    var lastPromptAt: Date? = nil
    /// "" means the support state has never seen a version — the first launch of
    /// the build that introduced this feature, which must never prompt.
    var lastSeenVersion: String = ""
}

/// Something the user did that the policy may care about.
nonisolated enum SupportSignal: Equatable, Sendable {
    case tagScanCompleted(matchedSpool: Bool)
    case tagWriteSucceeded
    /// `count` is the number of successful writes in one action, so a bulk
    /// delete of eight rows counts as eight edits rather than one.
    case backendWriteSucceeded(count: Int)
    case appBecameActive(version: String)
}

/// Why a prompt is being shown. Drives the copy.
nonisolated enum SupportPromptReason: Equatable, Sendable {
    case scanMilestone(Int)
    case editMilestone(Int)
    case upgrade(String)
    case successMoment
}

nonisolated enum SupportPromptDecision: Equatable, Sendable {
    case show(SupportPromptReason)
    case suppress
}

nonisolated enum SupportPromptOutcome: Equatable, Sendable {
    case shown(SupportPromptReason)
    /// Tapped through to a support destination. Stops the asks for good — the
    /// owner's call: someone who went looking for the donate page has answered
    /// the question, and asking again is the way to sour it.
    case tapped
    /// The user tapped "Not now". Deliberately has no lasting effect: the
    /// 45-day cooldown already governs when the next ask arrives, and the only
    /// thing that buys longer quiet is tapping through to support (owner's
    /// call, 2026-08-30). Kept distinct from `.autoHidden` so the outcome
    /// vocabulary stays honest about who closed the banner.
    case dismissed
    case autoHidden
    /// "Don't show again", from the sheet or the iOS Settings toggle.
    case optedOut
}

/// What the root banner is currently saying, if anything.
nonisolated enum SupportBannerContent: Equatable, Sendable {
    case ask(SupportPromptReason)
    case thanks
}
