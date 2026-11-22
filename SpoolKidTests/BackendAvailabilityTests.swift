//
//  BackendAvailabilityTests.swift
//  SpoolKidTests
//
//  Purpose: Locks the fix for F34 — the Library tab and Home dashboard read the
//  ACTIVE backend's validated-connection flag, not Spoolman's. A FilaMan-only
//  install rendered "No Spoolman Connection" over a perfectly healthy server
//  because every gate read `spoolman_connection_valid`, a key FilaMan never
//  writes.
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
struct BackendAvailabilityTests {
    /// A private defaults suite per test, so flipping a connection flag never
    /// races another test reading `UserDefaults.standard`.
    private func makeDefaults(_ name: String) throws -> UserDefaults {
        let suite = "BackendAvailabilityTests.\(name)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - The showstopper this exists for

    @Test func aConnectedFilaManInstallSeesItsLibrary() throws {
        let defaults = try makeDefaults("filaManOnly")
        // A FilaMan-only install: FilaMan validated, Spoolman never configured.
        defaults.set(true, forKey: AppConfig.filamanConnectionValidKey)

        let availability = BackendAvailability(store: defaults)

        #expect(availability.isAvailable(.filaman))
    }

    @Test func anUnvalidatedFilaManInstallStillGetsTheConfigurePrompt() throws {
        let defaults = try makeDefaults("filaManUnvalidated")
        // Spoolman validated is NOT permission to show FilaMan's library:
        // reading the wrong flag is wrong in both directions.
        defaults.set(true, forKey: AppConfig.spoolmanConnectionValidKey)

        let availability = BackendAvailability(store: defaults)

        #expect(availability.isAvailable(.filaman) == false)
    }

    @Test func spoolmanStillReadsItsOwnFlag() throws {
        let defaults = try makeDefaults("spoolmanOnly")
        defaults.set(true, forKey: AppConfig.spoolmanConnectionValidKey)

        let availability = BackendAvailability(store: defaults)

        #expect(availability.isAvailable(.spoolman))
        #expect(availability.isAvailable(.filaman) == false)
    }

    @Test func onDeviceStorageNeedsNoValidatedConnection() throws {
        let defaults = try makeDefaults("localNoFlags")
        // Both server flags false, and the local backend declares no flag at all.

        let availability = BackendAvailability(store: defaults)

        #expect(availability.isAvailable(.local))
    }

    // MARK: - Honesty of the lookup

    @Test func everyBackendsConnectionFlagIsActuallyReadable() throws {
        let defaults = try makeDefaults("coverage")
        let availability = BackendAvailability(store: defaults)
        let all: [BackendCapabilities] = [.local, .spoolman, .filaman]

        // Adding a fourth backend fails here until it is listed above, and then
        // fails below until its flag is declared in BackendAvailability — so a
        // new backend can never quietly read as "not connected" forever.
        #expect(Set(all.map(\.kind)) == Set(BackendKind.allCases))

        for caps in all {
            let flag = availability.connectionFlag(for: caps)
            #expect(flag != .unreadable(key: caps.connectionValidKey ?? ""), "\(caps.kind) flag is unreadable")
        }
    }

    @Test func anUnreadableFlagIsNeitherConnectedNorSilent() {
        // "I cannot see this backend's flag" must be representable rather than
        // collapsing into the same `false` as "nobody has connected yet" — the
        // caller logs it, because only one of the two is the user's to fix.
        #expect(BackendAvailability.isAvailable(.unreadable(key: "some_future_backend")) == false)
        #expect(BackendAvailability.isAvailable(.notApplicable))
        #expect(BackendAvailability.isAvailable(.read(true)))
        #expect(BackendAvailability.isAvailable(.read(false)) == false)
    }

    @Test func aBackendWithNoFlagKeyReportsNotApplicableRatherThanUnreadable() throws {
        let defaults = try makeDefaults("notApplicable")
        let availability = BackendAvailability(store: defaults)

        // The distinction matters: `.local` has nothing to validate, which is
        // not the same as a backend whose flag this reader cannot find.
        #expect(availability.connectionFlag(for: .local) == .notApplicable)
    }
}
