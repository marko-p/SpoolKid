//
//  AiLinkScaleZero.swift
//  SpoolKid
//
//  Purpose: Work out which two bytes the scale means by "nothing on the pan",
//  without asking the user to run a calibration step. Pure and synchronous so
//  the rule can be tested against the captured sessions it was derived from.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// Learns a scale's zero mask by watching it, rather than by asking.
///
/// The weight field is the gram value XORed with a per-device mask, so the mask
/// is simply what the scale sends with an empty pan (see `AiLinkScaleFrame`).
/// The problem is knowing *when* the pan is empty.
///
/// Four rules were tried against the eight captured sessions before this one.
/// The first settled reading, the first frame of a connection and the most
/// common value all scored 0–1 out of 8; a constrained search over every
/// observed value scored 2 out of 8, and its misses were 2–8 g off rather than
/// wild, which is worse than useless — a silently near-right weight.
///
/// What DOES separate an empty pan from a load, cleanly, is the pair of facts
/// the captures agree on:
///
/// - **The scale only marks a reading settled when something is on it.** Across
///   343 frames the lowest settled weight was 239 g; it never once marked zero
///   as settled.
/// - **When it goes quiet, it is resting.** Every quiet moment that was not
///   marked settled decoded to exactly 0 g — nine of them across the captures.
///
/// So: quiet AND settled is a load sitting on the pan; quiet AND *not* settled
/// is an empty pan. That is the whole rule.
///
/// It is not infallible on its own. One resting moment in ten was a link
/// dropping in the middle of a weighing, which looks the same — and the link
/// drops every five seconds while SpoolKid cannot answer the scale's
/// handshake. So a quiet moment only counts when the link stayed up long
/// enough after the last frame for the scale's follow-up to have arrived
/// (`heldFrame(at:)`); in the owner's captures a drop 29 ms after a 34 g frame
/// had been adopted as zero (2026-09-25). The screens that use the mask still
/// show the weight for the user to compare against the scale's own display,
/// and offer a one-tap correction.
nonisolated struct AiLinkScaleZero: Equatable {

    /// A resting reading this light is the pan drifting, not a load. The
    /// captures show drift of 0–8 g and no load lighter than 239 g, so
    /// anything in between separates them with room to spare.
    static let driftTolerance = 60

    /// How long the scale must be silent before it counts as resting. It
    /// bursts while a weight changes and stops when nothing does; the shortest
    /// gap between bursts in the captures was 8 s.
    static let restingSilence: TimeInterval = 4

    /// How long after a frame the scale's next one can still arrive. With the
    /// link up, the captures show a burst's follow-up — the settled frame, or
    /// an empty pan's next drift — within 1.3 s every time.
    static let followUpWindow: TimeInterval = 1.5

    /// What SpoolKid can say about the last frame it received.
    enum HeldFrame: Equatable {
        /// No frame on this link.
        case none
        /// The scale may still be sending: its follow-up is not due yet.
        case arriving
        /// The link outlived the follow-up window, so nothing came after it.
        /// This is what the scale is showing.
        case final
        /// The link dropped before the follow-up was due, and whatever the
        /// scale sent while it was down is gone. It may not be what the scale
        /// is showing, and nothing will correct it until the load changes.
        case cutOff
    }

    private(set) var mask: UInt16?

    private var lastValue: UInt16?
    private var lastWasSettled = false
    private var lastAt: Date?
    /// The first drop after the last frame. A later drop changes nothing.
    private var droppedAt: Date?

    init(mask: UInt16? = nil) {
        self.mask = mask
        self.learnsZero = true
    }

    /// For a scale that sends plain grams and zeroes itself (`CAScaleFrame`):
    /// the mask is 0 and nothing here may move it — not a resting drift, and
    /// not a "pan is empty" correction, which the scale's Tare button makes.
    /// The held-frame timing still applies.
    static let selfZeroing: AiLinkScaleZero = {
        var zero = AiLinkScaleZero(mask: 0)
        zero.learnsZero = false
        return zero
    }()

    private(set) var learnsZero: Bool

    /// The grams a frame reports, or nil while the scale's zero is still
    /// unknown. Nil rather than a guess: a weight nobody can check is the one
    /// thing a scale integration must never produce.
    func grams(of value: UInt16) -> Int? {
        guard let mask else { return nil }
        return Int(value ^ mask)
    }

    /// Every weight frame, in arrival order.
    mutating func observe(value: UInt16, isSettled: Bool, at time: Date = Date()) {
        lastValue = value
        lastWasSettled = isSettled
        lastAt = time
        droppedAt = nil
    }

    /// The link to the scale dropped.
    mutating func observeLinkDrop(at time: Date = Date()) {
        guard lastAt != nil, droppedAt == nil else { return }
        droppedAt = time
    }

    func heldFrame(at now: Date) -> HeldFrame {
        guard let lastAt else { return .none }
        if isCutOff { return .cutOff }
        return now.timeIntervalSince(lastAt) < Self.followUpWindow ? .arriving : .final
    }

    /// The value "Pan is empty — zero it" may take, or nil when the frame held
    /// cannot be the empty pan: still arriving, cut off, or settled — the scale
    /// marks a reading settled only when something is on it. The person is
    /// right that the pan is empty; the frame SpoolKid holds may not show it.
    func zeroCandidate(at now: Date) -> UInt16? {
        guard learnsZero, heldFrame(at: now) == .final, !lastWasSettled else { return nil }
        return lastValue
    }

    /// The scale has stopped talking for `restingSilence`.
    ///
    /// Idempotent: once the mask matches the resting value the reading is 0 and
    /// there is nothing left to adopt, so repeated calls change nothing.
    mutating func observeSilence() {
        guard learnsZero, let resting = lastValue, !lastWasSettled, !isCutOff else { return }
        guard let mask else {
            self.mask = resting
            return
        }
        let drift = Int(resting ^ mask)
        if drift > 0 && drift <= Self.driftTolerance {
            self.mask = resting
        }
    }

    /// The user says the pan is empty now. Unconditional, because a person
    /// looking at the scale beats every inference in this file — the value is
    /// what needs checking, which is `zeroCandidate(at:)`'s job.
    mutating func setZero(_ value: UInt16) {
        mask = value
    }

    private var isCutOff: Bool {
        guard let lastAt, let droppedAt else { return false }
        return droppedAt.timeIntervalSince(lastAt) < Self.followUpWindow
    }
}
