//
//  BackendKindTests.swift
//  SpoolKidTests
//

import Testing
@testable import SpoolKid

struct BackendKindTests {
    // MARK: - Upgrade path (no stored kind yet)

    @Test func existingSpoolmanInstallResolvesToSpoolman() {
        let kind = SpoolDataStore.resolveBackendKind(
            stored: nil,
            spoolmanUrl: "http://spoolman.local:7912",
            spoolmanConnectionValid: true
        )

        #expect(kind == .spoolman)
    }

    @Test func configuredButUnvalidatedSpoolmanResolvesToLocal() {
        let kind = SpoolDataStore.resolveBackendKind(
            stored: nil,
            spoolmanUrl: "http://spoolman.local:7912",
            spoolmanConnectionValid: false
        )

        #expect(kind == .local)
    }

    @Test func emptyUrlResolvesToLocal() {
        let kind = SpoolDataStore.resolveBackendKind(
            stored: nil,
            spoolmanUrl: "",
            spoolmanConnectionValid: true
        )

        #expect(kind == .local)
    }

    // MARK: - Explicit choice wins once stored

    @Test func storedKindTakesPrecedenceOverDerivation() {
        let kind = SpoolDataStore.resolveBackendKind(
            stored: "filaman",
            spoolmanUrl: "http://spoolman.local:7912",
            spoolmanConnectionValid: true
        )

        #expect(kind == .filaman)
    }

    @Test func unrecognisedStoredValueFallsBackToDerivation() {
        let kind = SpoolDataStore.resolveBackendKind(
            stored: "postgres",
            spoolmanUrl: "http://spoolman.local:7912",
            spoolmanConnectionValid: true
        )

        #expect(kind == .spoolman)
    }

    @Test func storedLocalIsHonouredEvenWithValidSpoolman() {
        let kind = SpoolDataStore.resolveBackendKind(
            stored: "local",
            spoolmanUrl: "http://spoolman.local:7912",
            spoolmanConnectionValid: true
        )

        #expect(kind == .local)
    }

    // MARK: - seedBackendKindSelection (Task 11 picker seed + idempotency guard)

    @Test func seedDerivesSpoolmanWhenCurrentEmptyStoredAbsentAndSpoolmanValid() {
        let selection = SpoolDataStore.seedBackendKindSelection(
            current: "",
            stored: nil,
            spoolmanUrl: "http://spoolman.local:7912",
            spoolmanConnectionValid: true
        )

        #expect(selection == BackendKind.spoolman.rawValue)
    }

    @Test func seedDerivesLocalWhenCurrentEmptyAndNoValidConnection() {
        let selection = SpoolDataStore.seedBackendKindSelection(
            current: "",
            stored: nil,
            spoolmanUrl: "",
            spoolmanConnectionValid: false
        )

        #expect(selection == BackendKind.local.rawValue)
    }

    @Test func seedReturnsNonEmptyCurrentUnchanged() {
        // The idempotency guard: a value already picked (or already seeded
        // this session) must never be overwritten by re-derivation, even
        // when the derived inputs would disagree with it.
        let selection = SpoolDataStore.seedBackendKindSelection(
            current: BackendKind.filaman.rawValue,
            stored: nil,
            spoolmanUrl: "http://spoolman.local:7912",
            spoolmanConnectionValid: true
        )

        #expect(selection == BackendKind.filaman.rawValue)
    }

    @Test func seedHonoursStoredValueOverDerivationWhenCurrentEmpty() {
        let selection = SpoolDataStore.seedBackendKindSelection(
            current: "",
            stored: BackendKind.local.rawValue,
            spoolmanUrl: "http://spoolman.local:7912",
            spoolmanConnectionValid: true
        )

        #expect(selection == BackendKind.local.rawValue)
    }
}
