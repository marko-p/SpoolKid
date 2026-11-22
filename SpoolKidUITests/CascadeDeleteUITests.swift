//
//  CascadeDeleteUITests.swift
//  SpoolKidUITests
//
//  Purpose: The cascade delete's dialog chain on a real presentation stack —
//  the dependents notice, then the final warning, then the delete. Runs on
//  the on-device Library with records it creates itself.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import XCTest

final class CascadeDeleteUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    /// The final warning is raised from the notice's own button. It must stay
    /// up until answered — not flash and vanish, leaving the record undeletable.
    @MainActor
    func testManufacturerWithFilamentsDeletesThroughBothDialogs() {
        let app = launch()
        let filamentName = "UITest Filament \(UUID().uuidString.prefix(6))"
        addFilament(filamentName, brand: "UITest Brand \(UUID().uuidString.prefix(6))", in: app)
        addSpool(of: filamentName, in: app)

        // A manufacturer's page is one tap from each of its filaments' pages.
        openFilamentPage(filamentName, in: app)
        let openManufacturer = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Open Manufacturer'")).firstMatch
        reveal(openManufacturer, in: app)
        tap(openManufacturer, until: app.navigationBars["Manufacturer"], in: app)
        deleteThroughBothDialogs(app.buttons["Delete Manufacturer"], in: app)

        XCTAssertTrue(app.navigationBars["Manufacturer"].waitForNonExistence(timeout: 5), "The page closes once the record is gone")
        XCTAssertTrue(app.staticTexts["Filament Not Found"].waitForExistence(timeout: 5),
                      "The cascade took the manufacturer's filament with it")
    }

    @MainActor
    func testFilamentWithSpoolsDeletesThroughBothDialogs() {
        let app = launch()
        let filamentName = "UITest Filament \(UUID().uuidString.prefix(6))"
        addFilament(filamentName, brand: "UITest Brand \(UUID().uuidString.prefix(6))", in: app)
        addSpool(of: filamentName, in: app)

        let header = openFilamentPage(filamentName, in: app)
        deleteThroughBothDialogs(app.buttons["Delete Filament"], in: app)

        XCTAssertTrue(app.navigationBars["Filament"].waitForNonExistence(timeout: 5), "The page closes once the record is gone")
        XCTAssertFalse(header.waitForExistence(timeout: 2), "The filament is deleted")
    }

    // MARK: - Helpers

    /// Creates a filament under a new manufacturer through Add Spool's Add New
    /// Filament, then cancels the spool form, which leaves the filament without
    /// a spool. Ends on the Library root.
    @MainActor
    func addFilament(_ name: String, brand: String, in app: XCUIApplication) {
        tap(app.buttons["library.addSpool"], until: app.navigationBars["Select Filament"], in: app)
        let addNew = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add New Filament'")).firstMatch
        tap(addNew, until: app.navigationBars["Add Filament"], in: app)
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        tap(app.buttons["filamentForm.manufacturer"], until: app.navigationBars["Manufacturer"], in: app)
        useTyped(brand, in: app)
        app.navigationBars["Add Filament"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Add Spool"].waitForExistence(timeout: 10),
                      "A created filament replaces the search with the spool form")
        app.navigationBars["Add Spool"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Add Spool"].waitForNonExistence(timeout: 5))
    }

    /// One spool of `filamentName`, added from the Library root: Add Spool opens
    /// on the filament search.
    @MainActor
    func addSpool(of filamentName: String, in app: XCUIApplication) {
        tap(app.buttons["library.addSpool"], until: app.navigationBars["Select Filament"], in: app)
        let search = app.collectionViews.textFields["Search filaments..."]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(filamentName)
        let pick = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", filamentName)).firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 5))
        pick.tap()
        let save = app.navigationBars["Add Spool"].buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled, "A filament is selected")
        save.tap()
        XCTAssertTrue(app.navigationBars["Add Spool"].waitForNonExistence(timeout: 5))
    }

    /// The Library root lists the filament under its own header: searches for it
    /// and opens its page. Returns the header.
    @MainActor
    @discardableResult
    func openFilamentPage(_ filamentName: String, in app: XCUIApplication) -> XCUIElement {
        let header = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", filamentName)).firstMatch
        // The list's own field: the nav bar carries a second, collapsed copy.
        let librarySearch = app.collectionViews.textFields["Search spools..."]
        XCTAssertTrue(librarySearch.waitForExistence(timeout: 5))
        librarySearch.tap()
        librarySearch.typeText(filamentName)
        tap(header, until: app.navigationBars["Filament"], in: app)
        return header
    }

    /// Delete → the dependents notice → the final warning → Delete Everything.
    @MainActor
    func deleteThroughBothDialogs(_ delete: XCUIElement, in app: XCUIApplication) {
        reveal(delete, in: app)
        delete.tap()

        let deleteAll = app.buttons["Delete All…"]
        XCTAssertTrue(deleteAll.waitForExistence(timeout: 5), "The dependents notice comes first")

        // Dismissed unanswered, the notice ends the flow: Delete raises it again.
        // The dialog hangs off the button, so tap the other half of the screen.
        let awayY = delete.frame.midY > app.frame.midY ? 0.15 : 0.85
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: awayY)).tap()
        XCTAssertTrue(deleteAll.waitForNonExistence(timeout: 5), "A tap outside dismisses the notice")
        delete.tap()
        XCTAssertTrue(deleteAll.waitForExistence(timeout: 5), "Delete starts the flow again")
        deleteAll.tap()

        let deleteEverything = app.buttons["Delete Everything"]
        XCTAssertTrue(deleteEverything.waitForExistence(timeout: 5), "The final warning follows the notice")
        // It must still be there once the notice's dismissal has played out.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(deleteEverything.exists && deleteEverything.isHittable, "The final warning must stay up until answered")
        deleteEverything.tap()
    }

    @MainActor
    func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-disableVocabularyRefresh", "YES", "-disableMessages", "YES", "-has_completed_welcome", "YES",
            "-changelog_auto_show", "NO",
            "-support_opted_out", "YES",
            "-backend_kind", "local",
            "-tag_identity_mode", "tagLinks",
            "-confirm_before_delete", "YES",
            "-ui_start_spoolman_tab"
        ]
        app.launch()
        return app
    }

    /// Types `name` into the picker's search field and takes its Use "…" row.
    @MainActor
    func useTyped(_ name: String, in app: XCUIApplication) {
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(name)
        let use = app.buttons["manufacturerPicker.useTyped"]
        XCTAssertTrue(use.waitForExistence(timeout: 5))
        use.tap()
        XCTAssertTrue(app.navigationBars["Manufacturer"].waitForNonExistence(timeout: 5))
    }

    /// Retried until the screen it leads to is up: a tip can appear between
    /// the check and the tap.
    @MainActor
    func tap(_ element: XCUIElement, until target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<3 where !target.exists {
            reveal(element, in: app)
            element.tap()
            _ = target.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(target.exists, "Expected \(target) after tapping \(element)")
    }

    /// Lists realize rows lazily: a row below the fold does not exist until
    /// it is scrolled to.
    @MainActor
    func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 3)
        closeTips(in: app)
        for _ in 0..<5 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Could not scroll to \(element)")
    }

    /// TipKit popovers lay a dismiss region over the screen that swallows taps.
    @MainActor
    func closeTips(in app: XCUIApplication) {
        let close = app.popovers.buttons["Close"]
        // The Library shows five tips in a row, each after the last closes.
        for _ in 0..<6 where close.waitForExistence(timeout: 1) {
            close.tap()
            _ = close.waitForNonExistence(timeout: 2)
        }
    }
}
