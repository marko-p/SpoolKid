//
//  SpoolFormAlertTests.swift
//  SpoolKidTests
//
//  The spool form's one alert (2026-10-11) keeps every former alert's title
//  and text.
//

import Testing
@testable import SpoolKid

struct SpoolFormAlertTests {
    @Test func plainAlertsKeepTheirTitles() {
        #expect(SpoolFormAlert.nfcError("x").title == "NFC Error")
        #expect(SpoolFormAlert.invalidInput("x").title == "Invalid Input")
        #expect(SpoolFormAlert.saveFailed("x").title == "Could Not Save Spool")
        #expect(SpoolFormAlert.actionFailed(title: "Could Not Archive Spool", message: "x").title == "Could Not Archive Spool")
        #expect(SpoolFormAlert.limitReached("x").title == "Limit Reached")
        #expect(SpoolFormAlert.invalidInput("Price cannot be negative.").message == "Price cannot be negative.")
        #expect(SpoolFormAlert.actionFailed(title: "T", message: "The spool could not be archived.").message == "The spool could not be archived.")
    }

    @Test func aShelfTagSaysWhatContinuingDoes() {
        let alert = SpoolFormAlert.shelfTag(uid: "04AA", name: "Shelf A")
        #expect(alert.title == "That's a Location Tag")
        #expect(alert.message == "This tag labels Shelf A. Continuing clears the tag and links it to this spool — you will be asked to hold it against the phone once more.")
    }

    @Test func aMoveAsksTheSpoolFormsQuestion() {
        let holder = TagOwner.filament(id: 5, label: "PLA Basic")
        let alert = SpoolFormAlert.moveTag(uid: "04AA", holder: holder)
        let confirmation = TagHolderMove.confirmationToSpool(uid: "04AA", holder: holder)
        #expect(alert.title == confirmation.title)
        #expect(alert.message == confirmation.message)
    }
}
