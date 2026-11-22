//
//  SupportPromptServiceTests.swift
//  SpoolKidTests
//
//  Purpose: Covers the persistence side of the support ask — that counters and
//  outcomes survive a relaunch, that a prompt counts only once it is actually
//  rendered, and that the seen-version seeds silently.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct SupportPromptServiceTests {

    /// A throwaway defaults domain per test, so nothing touches the real app's.
    private func makeDefaults() -> UserDefaults {
        let name = "support-prompt-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func scanCountsSurviveANewServiceInstance() {
        let defaults = makeDefaults()
        let first = SupportPromptService(defaults: defaults, now: { self.epoch })
        first.record(.tagScanCompleted(matchedSpool: false))
        first.record(.tagScanCompleted(matchedSpool: false))

        let second = SupportPromptService(defaults: defaults, now: { self.epoch })
        #expect(second.state.scanCount == 2)
    }

    @Test func theHundredthScanRaisesABanner() {
        let defaults = makeDefaults()
        defaults.set(99, forKey: AppConfig.supportScanCountKey)
        let service = SupportPromptService(defaults: defaults, now: { self.epoch })

        service.record(.tagScanCompleted(matchedSpool: false))
        #expect(service.visibleBanner == .ask(.scanMilestone(100)))
    }

    @Test func decidingToShowDoesNotYetStampTheCooldown() {
        // The banner may be held back behind a SaveNoticeBanner. Until it is
        // really on screen it must not count against the user.
        let defaults = makeDefaults()
        defaults.set(99, forKey: AppConfig.supportScanCountKey)
        let service = SupportPromptService(defaults: defaults, now: { self.epoch })

        service.record(.tagScanCompleted(matchedSpool: false))
        #expect(service.state.promptsShown == 0)
        #expect(service.state.lastPromptAt == nil)

        service.markShown()
        #expect(service.state.promptsShown == 1)
        #expect(service.state.lastPromptAt == epoch)
    }

    @Test func aBannerIsCountedOnlyOnceHoweverOftenItAppears() {
        let defaults = makeDefaults()
        defaults.set(99, forKey: AppConfig.supportScanCountKey)
        let service = SupportPromptService(defaults: defaults, now: { self.epoch })

        service.record(.tagScanCompleted(matchedSpool: false))
        service.markShown()
        service.markShown()
        #expect(service.state.promptsShown == 1)
    }

    @Test func tappingThroughMutesTheAsksAndThanksTheUser() {
        let defaults = makeDefaults()
        let service = SupportPromptService(defaults: defaults, now: { self.epoch })

        service.openedSupport()
        #expect(service.state.optedOut == true)
        #expect(defaults.bool(forKey: AppConfig.supportOptedOutKey) == true)
        #expect(service.visibleBanner == .thanks)
    }

    @Test func dontShowAgainMutesAndClearsTheBanner() {
        let defaults = makeDefaults()
        let service = SupportPromptService(defaults: defaults, now: { self.epoch })

        service.optOut()
        #expect(service.state.optedOut == true)
        #expect(service.visibleBanner == nil)
    }

    @Test func theSettingsToggleIsReadFreshOnEverySignal() {
        // `support_opted_out` is also a Settings.bundle switch, so it can change
        // while the app is backgrounded. A service that trusted its cached copy
        // would keep prompting until the next launch.
        let defaults = makeDefaults()
        defaults.set(99, forKey: AppConfig.supportScanCountKey)
        let service = SupportPromptService(defaults: defaults, now: { self.epoch })
        #expect(service.state.optedOut == false)

        defaults.set(true, forKey: AppConfig.supportOptedOutKey)
        service.record(.tagScanCompleted(matchedSpool: false))
        #expect(service.visibleBanner == nil)
    }

    @Test func dismissingClearsTheBanner() {
        let defaults = makeDefaults()
        defaults.set(99, forKey: AppConfig.supportScanCountKey)
        let service = SupportPromptService(defaults: defaults, now: { self.epoch })

        service.record(.tagScanCompleted(matchedSpool: false))
        service.dismissed()
        #expect(service.visibleBanner == nil)
    }

    @Test func theFirstLaunchSeedsTheVersionAndSaysNothing() {
        let defaults = makeDefaults()
        defaults.set(50, forKey: AppConfig.supportScanCountKey)
        let service = SupportPromptService(defaults: defaults, now: { self.epoch })

        service.record(.appBecameActive(version: "1.8"))
        #expect(service.visibleBanner == nil)
        #expect(service.state.lastSeenVersion == "1.8")
    }

    @Test func anUpgradePromptsOnceAndThenSettles() {
        let defaults = makeDefaults()
        defaults.set(50, forKey: AppConfig.supportScanCountKey)
        defaults.set("1.7", forKey: AppConfig.supportLastSeenVersionKey)
        let service = SupportPromptService(defaults: defaults, now: { self.epoch })

        service.record(.appBecameActive(version: "1.8"))
        #expect(service.visibleBanner == .ask(.upgrade("1.8")))

        service.markShown()
        service.dismissed()
        service.record(.appBecameActive(version: "1.8"))
        #expect(service.visibleBanner == nil)
    }
}
