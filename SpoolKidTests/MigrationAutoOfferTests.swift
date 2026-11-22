//
//  MigrationAutoOfferTests.swift
//  SpoolKidTests
//
//  The migration sheet opens by itself once per backend; after it is closed,
//  the Library tab's Migrate row is the way back (audit L2). It waits for
//  the server to answer, and an unreachable server is not a "no".
//

import Testing
@testable import SpoolKid

struct MigrationAutoOfferTests {

    @Test func offersWhenThereIsSomethingToMigrateAndItWasNeverClosed() {
        #expect(ContentView.autoOffersMigration(shouldOffer: true, dismissedFor: "", active: .spoolman))
    }

    @Test func staysClosedForTheBackendItWasClosedFor() {
        #expect(!ContentView.autoOffersMigration(shouldOffer: true, dismissedFor: "spoolman", active: .spoolman))
    }

    @Test func offersAgainAfterSwitchingBackend() {
        #expect(ContentView.autoOffersMigration(shouldOffer: true, dismissedFor: "spoolman", active: .filaman))
    }

    @Test func neverOffersWithNothingToMigrate() {
        #expect(!ContentView.autoOffersMigration(shouldOffer: false, dismissedFor: "", active: .spoolman))
    }

    @Test func waitsForTheServer() {
        #expect(ContentView.migrationOffer(wanted: true, serverAnswered: nil) == .waitingForServer)
    }

    @Test func showsOnceTheServerAnswers() {
        #expect(ContentView.migrationOffer(wanted: true, serverAnswered: true) == .shown)
    }

    @Test func anUnreachableServerShowsNothing() {
        #expect(ContentView.migrationOffer(wanted: true, serverAnswered: false) == .none)
    }

    @Test func nothingWantedNeedsNoServer() {
        #expect(ContentView.migrationOffer(wanted: false, serverAnswered: nil) == .none)
    }
}
