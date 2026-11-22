//
//  BackendReachabilityTests.swift
//  SpoolKidTests
//
//  Purpose: The Library tab's status dot. Covers the presentational mapping and
//  the probe decision itself — in particular that an unconfigured address is
//  answered WITHOUT a network call, so the row can never report "Unreachable"
//  for a server nobody ever asked it to reach.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI
import Testing
@testable import SpoolKid

@MainActor
struct BackendReachabilityTests {
    // MARK: - Presentation

    @Test func connectedIsGreen() {
        #expect(BackendReachability.statusText(for: .reachable) == "Connected")
        #expect(BackendReachability.statusColor(for: .reachable) == .statusSuccess)
    }

    @Test func unreachableIsRed() {
        #expect(BackendReachability.statusText(for: .unreachable) == "Unreachable")
        #expect(BackendReachability.statusColor(for: .unreachable) == .statusError)
    }

    @Test func neutralStatesAreNotColoured() {
        #expect(BackendReachability.statusColor(for: .alwaysAvailable) == .secondary)
        #expect(BackendReachability.statusColor(for: .notConfigured) == .secondary)
        #expect(BackendReachability.statusText(for: .alwaysAvailable) == "Local")
        #expect(BackendReachability.statusText(for: .notConfigured) == "Not configured")
    }

    @Test func noAnswerYetReadsAsChecking() {
        // `nil` is "the probe has not answered yet" — deliberately absent from
        // the enum the repository returns, because the repository never has
        // that answer to give.
        #expect(BackendReachability.statusText(for: nil) == "Checking…")
        #expect(BackendReachability.statusColor(for: nil) == .secondary)
    }

    @Test func statesAreDistinct() {
        #expect(BackendReachability.unreachable != BackendReachability.reachable)
        #expect(BackendReachability.notConfigured != BackendReachability.unreachable)
    }

    // MARK: - The probe decision

    @Test func anUnconfiguredAddressIsNotConfiguredAndNeverProbes() async {
        let spy = ProbeSpy(answer: true)

        let result = await BackendReachability.probing(address: "", using: spy.run)

        #expect(result == .notConfigured)
        // The whole point: "nothing is configured" is reported without pretending
        // to have contacted anything.
        #expect(spy.ranCount == 0)
    }

    @Test func aWhitespaceOnlyAddressIsAlsoNotConfigured() async {
        let spy = ProbeSpy(answer: true)

        let result = await BackendReachability.probing(address: "   \n", using: spy.run)

        #expect(result == .notConfigured)
        #expect(spy.ranCount == 0)
    }

    @Test func aConfiguredAddressReportsWhatTheProbeFound() async {
        let reachable = ProbeSpy(answer: true)
        #expect(await BackendReachability.probing(address: "http://host:7912", using: reachable.run) == .reachable)
        #expect(reachable.ranCount == 1)

        let refused = ProbeSpy(answer: false)
        #expect(await BackendReachability.probing(address: "http://host:7912", using: refused.run) == .unreachable)
        #expect(refused.ranCount == 1)
    }

    @MainActor
    private final class ProbeSpy {
        private let answer: Bool
        private(set) var ranCount = 0

        init(answer: Bool) { self.answer = answer }

        func run() async -> Bool {
            ranCount += 1
            return answer
        }
    }
}
