//
//  SpoolPageUITests.swift
//  SpoolKidUITests
//
//  Purpose: A Library spool row opens the read-only Spool page, whose Edit
//  shows the spool form in place and whose Cancel returns to the page; a
//  Filament page reached from a Spool page does not push further (the
//  one-level page rule). Runs on the on-device Library backend; creates a
//  spool only when the library has none.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import XCTest

final class SpoolPageUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        // A lazy List does not realize rows below the fold in landscape.
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testLibraryRowOpensSpoolPageThenEdit() {
        let app = launch()
        let edit = app.buttons["spoolPage.edit"]
        openSpoolPage(in: app)

        XCTAssertTrue(app.buttons["Weigh"].exists)
        XCTAssertTrue(app.buttons["Write Tag"].exists)
        XCTAssertTrue(app.buttons["Location"].exists)

        tap(edit, until: app.navigationBars["Edit Spool"], in: app)
        closeTips(in: app)
        app.navigationBars["Edit Spool"].buttons["Cancel"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Cancel returns to the Spool page")
    }

    @MainActor
    func testNestedFilamentPageDoesNotPushSpools() {
        let app = launch()
        openSpoolPage(in: app)

        tap(app.buttons["spoolPage.filament"], until: app.navigationBars["Filament"], in: app)
        let spoolRow = app.descendants(matching: .any).matching(identifier: "filamentPage.spoolRow").firstMatch
        XCTAssertTrue(spoolRow.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["filamentPage.spoolRow"].exists, "A nested Filament page's spool rows are not buttons")
        // Scroll to the Manufacturer section so a missing link is a real
        // absence, not a lazily unrealized row.
        let change = app.buttons["Change"]
        for _ in 0..<6 where !(change.exists && change.isHittable) { app.swipeUp() }
        XCTAssertTrue(change.exists, "The nested page keeps its manufacturer's Change")
        XCTAssertFalse(app.buttons["Open Manufacturer"].exists, "A nested Filament page does not open its manufacturer")
    }

    /// Opens the first spool in the Library, adding one first when the
    /// library has none.
    @MainActor
    private func openSpoolPage(in app: XCUIApplication) {
        let row = app.buttons.matching(identifier: "library.spoolRow").firstMatch
        if !row.waitForExistence(timeout: 5) {
            tap(app.buttons["library.addSpool"], until: app.navigationBars["Select Filament"], in: app)
            pickFirstMyFilament(in: app)
            closeTips(in: app)
            app.navigationBars["Add Spool"].buttons["Save"].tap()
            XCTAssertTrue(row.waitForExistence(timeout: 10))
        }
        tap(row, until: app.buttons["spoolPage.edit"], in: app)
        closeTips(in: app)
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-disableVocabularyRefresh", "YES", "-disableMessages", "YES", "-has_completed_welcome", "YES",
            "-changelog_auto_show", "NO",
            "-support_opted_out", "YES",
            "-backend_kind", "local",
            "-tag_identity_mode", "tagLinks",
            "-ui_start_spoolman_tab"
        ]
        app.launch()
        return app
    }

    /// Takes Select Filament to the spool form: the first row under "My
    /// Filaments" when the library has one, otherwise a filament created through
    /// the sheet's own Add New Filament (which replaces the search with the form
    /// too), so the tests need nothing the simulator may not hold. That filament
    /// and its manufacturer stay, so later runs take the pick path.
    @MainActor
    private func pickFirstMyFilament(in app: XCUIApplication) {
        let header = app.staticTexts["My Filaments"]
        if header.waitForExistence(timeout: 5) {
            let rows = app.buttons.allElementsBoundByIndex.filter { $0.frame.minY > header.frame.maxY }
            if let first = rows.min(by: { $0.frame.minY < $1.frame.minY }) {
                tap(first, until: app.navigationBars["Add Spool"], in: app)
                return
            }
        }
        let addNew = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add New Filament'")).firstMatch
        tap(addNew, until: app.navigationBars["Add Filament"], in: app)
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("UITest Filament \(UUID().uuidString.prefix(6))")
        tap(app.buttons["filamentForm.manufacturer"], until: app.navigationBars["Manufacturer"], in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("UITest Brand \(UUID().uuidString.prefix(6))")
        let use = app.buttons["manufacturerPicker.useTyped"]
        XCTAssertTrue(use.waitForExistence(timeout: 5))
        use.tap()
        app.navigationBars["Add Filament"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Add Spool"].waitForExistence(timeout: 10),
                      "A created filament replaces the search with the spool form")
    }

    /// Retried until the screen it leads to is up: a tip can appear between
    /// the check and the tap.
    @MainActor
    private func tap(_ element: XCUIElement, until target: XCUIElement, in app: XCUIApplication) {
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
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 3)
        closeTips(in: app)
        for _ in 0..<5 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Could not scroll to \(element)")
    }

    /// First-run tips are popovers over whatever they point at, and on the
    /// simulator they can come back on every launch. While one is up, a
    /// full-screen dismiss region takes any tap meant for the screen, and
    /// everything under it reports not hittable. Closing it with its own
    /// button retires the tip.
    @MainActor
    private func closeTips(in app: XCUIApplication) {
        let close = app.popovers.buttons["Close"]
        // The Library shows five tips in a row, each after the last closes.
        for _ in 0..<6 where close.waitForExistence(timeout: 1) {
            close.tap()
            _ = close.waitForNonExistence(timeout: 2)
        }
    }
}
