//
//  SupportPromptPolicy.swift
//  SpoolKid
//
//  Purpose: Every rule behind the support ask, as pure functions over
//  SupportPromptState — when a signal qualifies, whether a prompt may be shown,
//  and what each user response does to the state.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// The support-prompt rules. Pure: no `UserDefaults`, no `Date()`, no `Bundle` —
/// callers pass `now` and the app version in, which is what makes every rule
/// below a table test rather than a UI test.
///
/// `nonisolated` for the reason given on `SupportPromptState`.
nonisolated enum SupportPromptPolicy {

    // MARK: - Tunables
    //
    // Policy, not settings — the same shape as `Entitlement.localCapacity`.
    // These are the knobs to turn if the cadence needs re-balancing.

    /// Every 100th completed scan.
    static let scanMilestone = 100
    /// Every 100th successful backend write.
    static let editMilestone = 100
    /// An upgrade only asks a user who has actually used the app.
    static let upgradeScanFloor = 20
    /// Success moments carry the lowest floor, but still enough that a new user
    /// is not asked twice in their first week.
    static let successMomentScanFloor = 10
    static let cooldown: TimeInterval = 45 * 86_400

    // MARK: - Ingest

    /// Folds a signal's counters into the state. Runs BEFORE `decide`, so
    /// `decide` sees the post-increment counts.
    ///
    /// Deliberately does not touch `lastSeenVersion`: `decide` needs the old
    /// value to notice an upgrade at all. The service persists the new one after
    /// the decision.
    static func ingest(
        _ signal: SupportSignal,
        into state: SupportPromptState
    ) -> SupportPromptState {
        var next = state
        switch signal {
        case .tagScanCompleted:
            next.scanCount += 1
        case .backendWriteSucceeded(let count):
            next.editCount += max(0, count)
        case .tagWriteSucceeded, .appBecameActive:
            break
        }
        return next
    }

    // MARK: - Qualification

    /// Why this signal deserves an ask, or nil. Ignores cooldown, credits and
    /// opt-out — those are `decide`'s job.
    static func qualifyingReason(
        _ signal: SupportSignal,
        state: SupportPromptState
    ) -> SupportPromptReason? {
        switch signal {
        case .tagScanCompleted(let matchedSpool):
            if state.scanCount > 0, state.scanCount % scanMilestone == 0 {
                return .scanMilestone(state.scanCount)
            }
            guard matchedSpool, state.scanCount >= successMomentScanFloor else { return nil }
            return .successMoment

        case .backendWriteSucceeded(let count):
            // A bulk action can jump the counter clean over a multiple, so the
            // test is "crossed", not "landed on".
            let previous = state.editCount - max(0, count)
            guard state.editCount / editMilestone > previous / editMilestone else { return nil }
            return .editMilestone((state.editCount / editMilestone) * editMilestone)

        case .tagWriteSucceeded:
            guard state.scanCount >= successMomentScanFloor else { return nil }
            return .successMoment

        case .appBecameActive(let version):
            // An empty stored version is the first launch of the build that
            // introduced this feature. Seeding it silently is what stops every
            // existing user being asked on update day.
            guard !state.lastSeenVersion.isEmpty,
                  state.lastSeenVersion != version,
                  state.scanCount >= upgradeScanFloor else { return nil }
            return .upgrade(version)
        }
    }

    // MARK: - Decision

    /// The gate order:
    ///
    /// 1. opted out — nothing else matters
    /// 2. does the signal qualify at all
    /// 3. cooldown
    static func decide(
        _ signal: SupportSignal,
        state: SupportPromptState,
        now: Date
    ) -> SupportPromptDecision {
        guard !state.optedOut else { return .suppress }
        guard let reason = qualifyingReason(signal, state: state) else { return .suppress }
        if let last = state.lastPromptAt, now.timeIntervalSince(last) < cooldown {
            return .suppress
        }
        return .show(reason)
    }

    // MARK: - Outcomes

    /// Applies what the user did. `now` is passed in for the same reason
    /// `decide` takes it: `.shown` stamps the cooldown, and a stamped clock is
    /// not testable.
    static func applying(
        _ outcome: SupportPromptOutcome,
        to state: SupportPromptState,
        now: Date
    ) -> SupportPromptState {
        var next = state
        switch outcome {
        case .shown:
            next.promptsShown += 1
            next.lastPromptAt = now
        case .tapped, .optedOut:
            // Tapping through to a support page and pressing "Don't show
            // again" land in the same place. The app cannot tell whether money
            // changed hands, only that the user went and looked — and asking
            // someone who did that again is how you sour it.
            next.optedOut = true
        case .dismissed, .autoHidden:
            // Neither changes state. "Not now" is soft by design and the
            // auto-hide is not even an answer; the cooldown alone decides when
            // the next ask arrives.
            break
        }
        return next
    }
}
