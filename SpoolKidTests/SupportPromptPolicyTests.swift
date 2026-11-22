//
//  SupportPromptPolicyTests.swift
//  SpoolKidTests
//
//  Purpose: Locks the support-prompt rules — counter ingestion, per-signal
//  qualification floors, gate order, and outcome bookkeeping.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

struct SupportPromptPolicyTests {

    // MARK: - Ingest

    @Test func scanIngestIncrementsTheScanCount() {
        let state = SupportPromptPolicy.ingest(
            .tagScanCompleted(matchedSpool: false),
            into: SupportPromptState()
        )
        #expect(state.scanCount == 1)
    }

    @Test func bulkWritesAddTheirWholeCount() {
        let state = SupportPromptPolicy.ingest(
            .backendWriteSucceeded(count: 8),
            into: SupportPromptState(editCount: 2)
        )
        #expect(state.editCount == 10)
    }

    @Test func ingestNeverWritesTheSeenVersion() {
        // decide() needs the OLD version to notice an upgrade; the service
        // persists the new one afterwards.
        let state = SupportPromptPolicy.ingest(
            .appBecameActive(version: "1.8"),
            into: SupportPromptState(lastSeenVersion: "1.7")
        )
        #expect(state.lastSeenVersion == "1.7")
    }

    // MARK: - Qualification

    @Test func theHundredthScanQualifiesAndItsNeighboursDoNot() {
        let signal = SupportSignal.tagScanCompleted(matchedSpool: false)
        #expect(SupportPromptPolicy.qualifyingReason(signal, state: SupportPromptState(scanCount: 99)) == nil)
        #expect(SupportPromptPolicy.qualifyingReason(signal, state: SupportPromptState(scanCount: 100)) == .scanMilestone(100))
        #expect(SupportPromptPolicy.qualifyingReason(signal, state: SupportPromptState(scanCount: 101)) == nil)
        #expect(SupportPromptPolicy.qualifyingReason(signal, state: SupportPromptState(scanCount: 200)) == .scanMilestone(200))
    }

    @Test func aBulkEditCrossingTheMilestoneStillQualifies() {
        // 98 + 5 = 103 never lands exactly on 100; crossing is what counts, or
        // the milestone would be silently lost.
        let reason = SupportPromptPolicy.qualifyingReason(
            .backendWriteSucceeded(count: 5),
            state: SupportPromptState(editCount: 103)
        )
        #expect(reason == .editMilestone(100))
    }

    @Test func oneBulkActionCrossingTwoMilestonesYieldsOnePrompt() {
        let reason = SupportPromptPolicy.qualifyingReason(
            .backendWriteSucceeded(count: 150),
            state: SupportPromptState(editCount: 210)
        )
        #expect(reason == .editMilestone(200))
    }

    @Test func upgradeNeedsRealUsageAndASeededVersion() {
        let signal = SupportSignal.appBecameActive(version: "1.8")

        // Never seeded: the first launch of the build that added this feature.
        let unseeded = SupportPromptState(scanCount: 50, lastSeenVersion: "")
        #expect(SupportPromptPolicy.qualifyingReason(signal, state: unseeded) == nil)

        // Seeded but the user has barely used the app.
        let light = SupportPromptState(scanCount: 19, lastSeenVersion: "1.7")
        #expect(SupportPromptPolicy.qualifyingReason(signal, state: light) == nil)

        let ready = SupportPromptState(scanCount: 20, lastSeenVersion: "1.7")
        #expect(SupportPromptPolicy.qualifyingReason(signal, state: ready) == .upgrade("1.8"))

        // Same version: nothing changed.
        let same = SupportPromptState(scanCount: 50, lastSeenVersion: "1.8")
        #expect(SupportPromptPolicy.qualifyingReason(signal, state: same) == nil)
    }

    @Test func successMomentsNeedTenScansFirst() {
        #expect(SupportPromptPolicy.qualifyingReason(.tagWriteSucceeded, state: SupportPromptState(scanCount: 9)) == nil)
        #expect(SupportPromptPolicy.qualifyingReason(.tagWriteSucceeded, state: SupportPromptState(scanCount: 10)) == .successMoment)
    }

    @Test func onlyAMatchedScanIsASuccessMoment() {
        let unmatched = SupportSignal.tagScanCompleted(matchedSpool: false)
        #expect(SupportPromptPolicy.qualifyingReason(unmatched, state: SupportPromptState(scanCount: 50)) == nil)

        let matched = SupportSignal.tagScanCompleted(matchedSpool: true)
        #expect(SupportPromptPolicy.qualifyingReason(matched, state: SupportPromptState(scanCount: 50)) == .successMoment)
    }

    @Test func aMilestoneScanOutranksItsSuccessMoment() {
        let matched = SupportSignal.tagScanCompleted(matchedSpool: true)
        #expect(SupportPromptPolicy.qualifyingReason(matched, state: SupportPromptState(scanCount: 100)) == .scanMilestone(100))
    }

    // MARK: - Gate order

    private static let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    private func qualifyingScanState(_ overrides: (inout SupportPromptState) -> Void = { _ in })
        -> SupportPromptState {
        var state = SupportPromptState(scanCount: 100)
        overrides(&state)
        return state
    }

    @Test func aQualifyingSignalWithNoHistoryShows() {
        let decision = SupportPromptPolicy.decide(
            .tagScanCompleted(matchedSpool: false), state: qualifyingScanState(), now: Self.epoch
        )
        #expect(decision == .show(.scanMilestone(100)))
    }

    @Test func theCooldownBoundaryIsFortyFiveDays() {
        func decide(daysAgo: Double) -> SupportPromptDecision {
            let state = qualifyingScanState { $0.lastPromptAt = Self.epoch.addingTimeInterval(-daysAgo * 86_400) }
            return SupportPromptPolicy.decide(
                .tagScanCompleted(matchedSpool: false), state: state, now: Self.epoch
            )
        }
        #expect(decide(daysAgo: 44) == .suppress)
        #expect(decide(daysAgo: 45) == .show(.scanMilestone(100)))
        #expect(decide(daysAgo: 46) == .show(.scanMilestone(100)))
    }

    @Test func showingAPromptStampsTheCooldown() {
        let state = SupportPromptPolicy.applying(
            .shown(.scanMilestone(100)), to: SupportPromptState(), now: Self.epoch
        )
        #expect(state.promptsShown == 1)
        #expect(state.lastPromptAt == Self.epoch)
    }

    @Test func notNowIsSoftAndChangesNothing() {
        // "Not now" means not now, not never. The 45-day cooldown alone decides
        // when the next ask arrives; only tapping through to support, the
        // sheet's "Don't show again", or the Settings toggle ever stops them.
        let before = SupportPromptState(scanCount: 100, lastPromptAt: Self.epoch)
        let after = SupportPromptPolicy.applying(.dismissed, to: before, now: Self.epoch)
        #expect(after == before)
    }

    @Test func anAutoHideChangesNothingEither() {
        let before = SupportPromptState(scanCount: 100, lastPromptAt: Self.epoch)
        let after = SupportPromptPolicy.applying(.autoHidden, to: before, now: Self.epoch)
        #expect(after == before)
    }

    @Test func noSequenceOfDismissalsEverSilencesTheFeature() {
        // Refusals never accumulate toward a mute. Twenty of them later, a
        // qualifying signal past the cooldown must still show — only an
        // explicit opt-out stops the asks.
        var state = SupportPromptState(scanCount: 100)
        for _ in 0..<20 {
            state = SupportPromptPolicy.applying(.dismissed, to: state, now: Self.epoch)
        }
        let decision = SupportPromptPolicy.decide(
            .tagScanCompleted(matchedSpool: false), state: state, now: Self.epoch
        )
        #expect(decision == .show(.scanMilestone(100)))
    }

    // MARK: - Opting out

    @Test func optingOutSilencesEvenAQualifyingSignal() {
        let state = qualifyingScanState { $0.optedOut = true }
        let decision = SupportPromptPolicy.decide(
            .tagScanCompleted(matchedSpool: false), state: state, now: Self.epoch
        )
        #expect(decision == .suppress)
    }

    @Test func tappingThroughToSupportStopsTheAsksForGood() {
        // The app cannot tell whether money changed hands, only that the user
        // went and looked. Asking them again is how you sour it.
        let state = SupportPromptPolicy.applying(.tapped, to: SupportPromptState(), now: Self.epoch)
        #expect(state.optedOut == true)
    }

    @Test func dontShowAgainStopsTheAsksForGood() {
        let state = SupportPromptPolicy.applying(.optedOut, to: SupportPromptState(), now: Self.epoch)
        #expect(state.optedOut == true)
    }

    @Test func anOptedOutStateIgnoresEverySignalKind() {
        let signals: [SupportSignal] = [
            .tagScanCompleted(matchedSpool: true),
            .tagWriteSucceeded,
            .backendWriteSucceeded(count: 100),
            .appBecameActive(version: "9.9")
        ]
        var state = SupportPromptState(scanCount: 100, optedOut: true)
        state.lastSeenVersion = "1.0"
        for signal in signals {
            let ingested = SupportPromptPolicy.ingest(signal, into: state)
            #expect(SupportPromptPolicy.decide(signal, state: ingested, now: Self.epoch) == .suppress)
        }
    }
}
