//
//  SupportPromptService.swift
//  SpoolKid
//
//  Purpose: The persistence and publishing half of the support ask. Holds no
//  rules — every decision comes from SupportPromptPolicy — and publishes one
//  optional banner for the root view to render.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Combine

/// Owns the six `support_*` keys and turns signals into a visible banner.
///
/// Small and stateful, so an `ObservableObject` rather than a static enum (A3).
/// Every rule lives in `SupportPromptPolicy`; this type only reads, writes and
/// publishes.
@MainActor
final class SupportPromptService: ObservableObject {

    /// What the root banner is saying, if anything. `nil` most of the time.
    @Published private(set) var visibleBanner: SupportBannerContent?

    /// Exposed for tests and for nothing else — no view reads it.
    private(set) var state: SupportPromptState

    private let defaults: UserDefaults
    private let now: () -> Date

    /// Guards against counting one banner twice. The banner's `onAppear` can run
    /// again — it is withdrawn while a `SaveNoticeBanner` is up and returns when
    /// that clears — and each appearance would otherwise re-stamp the cooldown.
    private var markedCurrentAsk = false

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        self.state = Self.load(from: defaults)
    }

    // MARK: - Signals

    func record(_ signal: SupportSignal) {
        // `optedOut` is also a Settings.bundle toggle, so the user can flip it
        // while the app is backgrounded. Re-read it rather than trusting the
        // copy loaded at init.
        state.optedOut = defaults.bool(forKey: AppConfig.supportOptedOutKey)
        var next = SupportPromptPolicy.ingest(signal, into: state)

        switch SupportPromptPolicy.decide(signal, state: next, now: now()) {
        case .show(let reason):
            visibleBanner = .ask(reason)
            markedCurrentAsk = false
        case .suppress:
            break
        }

        // Written AFTER the decision, which needs the previous value to notice
        // an upgrade at all. Written whether or not the prompt qualified, so an
        // upgrade can fire at most once per version.
        if case .appBecameActive(let version) = signal {
            next.lastSeenVersion = version
        }

        persist(next)
    }

    /// Called from the banner's own `onAppear`, not from `record` — a prompt
    /// decided but never rendered must not spend the user's cooldown.
    func markShown() {
        guard case .ask(let reason) = visibleBanner, !markedCurrentAsk else { return }
        markedCurrentAsk = true
        apply(.shown(reason))
    }

    // MARK: - Responses

    /// The user tapped through to a support destination. Mutes the asks for
    /// good — see `SupportPromptOutcome.tapped`. The thank-you still shows; the
    /// Settings toggle is the way back.
    func openedSupport() {
        apply(.tapped)
        visibleBanner = .thanks
    }

    /// "Don't show again", from the sheet's own button.
    func optOut() {
        apply(.optedOut)
        visibleBanner = nil
    }

    func dismissed() {
        apply(.dismissed)
        visibleBanner = nil
    }

    /// Called from the banner's own auto-hide timer. `.thanks` just clears —
    /// it was never an ask, so there is no outcome to record; an `.ask` applies
    /// `.autoHidden`, which is a no-op on state but keeps the outcome
    /// vocabulary honest about what happened.
    func autoHidden() {
        if visibleBanner == .thanks {
            visibleBanner = nil
            return
        }
        apply(.autoHidden)
        visibleBanner = nil
    }

    private func apply(_ outcome: SupportPromptOutcome) {
        persist(SupportPromptPolicy.applying(outcome, to: state, now: now()))
    }

    // MARK: - Persistence

    private func persist(_ next: SupportPromptState) {
        state = next
        defaults.set(next.scanCount, forKey: AppConfig.supportScanCountKey)
        defaults.set(next.editCount, forKey: AppConfig.supportEditCountKey)
        defaults.set(next.promptsShown, forKey: AppConfig.supportPromptsShownKey)
        defaults.set(next.optedOut, forKey: AppConfig.supportOptedOutKey)
        defaults.set(next.lastPromptAt?.timeIntervalSince1970 ?? 0,
                     forKey: AppConfig.supportLastPromptAtKey)
        defaults.set(next.lastSeenVersion, forKey: AppConfig.supportLastSeenVersionKey)
    }

    private static func load(from defaults: UserDefaults) -> SupportPromptState {
        // A stored 0 means "never prompted"; a genuine 1970 timestamp is not a
        // case worth handling.
        let stamp = defaults.double(forKey: AppConfig.supportLastPromptAtKey)
        return SupportPromptState(
            scanCount: defaults.integer(forKey: AppConfig.supportScanCountKey),
            editCount: defaults.integer(forKey: AppConfig.supportEditCountKey),
            promptsShown: defaults.integer(forKey: AppConfig.supportPromptsShownKey),
            optedOut: defaults.bool(forKey: AppConfig.supportOptedOutKey),
            lastPromptAt: stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil,
            lastSeenVersion: defaults.string(forKey: AppConfig.supportLastSeenVersionKey) ?? ""
        )
    }
}
