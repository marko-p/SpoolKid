//
//  LocationCreateOutcomeTests.swift
//  SpoolKidTests
//
//  Purpose: The shared pre-check every backend's `addLocation` runs, and the
//  copy each outcome carries. FilaMan's actual POST has no network seam and is
//  not unit-testable — see FilaManRepositoryTests' header.
//

import Foundation
import Testing
@testable import SpoolKid

struct LocationCreateOutcomeTests {
    @Test func precheckRefusesABlankName() {
        #expect(LocationCreateOutcome.precheck(name: "   ", existing: []) == .failed("A location needs a name."))
    }

    @Test func precheckReportsAnExistingNameIgnoringCaseAndWhitespace() {
        let existing = ["Shelf A", "Bin C"]

        #expect(LocationCreateOutcome.precheck(name: " shelf a ", existing: existing) == .alreadyExists)
    }

    @Test func precheckReturnsNilWhenTheCallerShouldGoAhead() {
        #expect(LocationCreateOutcome.precheck(name: "Shelf D", existing: ["Shelf A"]) == nil)
    }

    @Test func createdCarriesNoCaveat() {
        #expect(LocationCreateOutcome.created.note(locationName: "Shelf D", storageNoun: "FilaMan") == nil)
    }

    @Test func onDeviceOnlyExplainsWhereTheLocationLives() {
        let note = LocationCreateOutcome.registeredOnDeviceOnly.note(locationName: "Shelf D", storageNoun: "Spoolman")

        #expect(note == "Shelf D is saved on this device. It appears in Spoolman once you assign a spool to it.")
    }

    @Test func onDeviceOnlyUsesThePossessiveNounForTheLocalLibrary() {
        let note = LocationCreateOutcome.registeredOnDeviceOnly.note(locationName: "Shelf D", storageNoun: "your library")

        #expect(note == "Shelf D is saved on this device. It appears in your library once you assign a spool to it.")
    }

    @Test func onlyFailureIsNotASuccess() {
        #expect(LocationCreateOutcome.created.isSuccess)
        #expect(LocationCreateOutcome.alreadyExists.isSuccess)
        #expect(LocationCreateOutcome.registeredOnDeviceOnly.isSuccess)
        #expect(LocationCreateOutcome.failed("nope").isSuccess == false)
    }
}
