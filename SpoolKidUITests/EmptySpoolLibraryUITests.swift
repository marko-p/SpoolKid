//
//  EmptySpoolLibraryUITests.swift
//  SpoolKidUITests
//
//  Purpose: An empty spool added under Manage Empty Spools can be picked in a
//  new spool's form, and fills Empty Spool Weight with its grams. Add Spool
//  opens on the filament search from the Library root, Cancel closes it, and
//  a pick takes it to the spool form. Runs on the on-device Library backend
//  and deletes its entry again, because the simulator's library persists
//  between runs.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import XCTest

final class EmptySpoolLibraryUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        // A lazy List does not realize rows below the fold in landscape.
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testAPickedEntryFillsTheNewSpoolsEmptyWeight() {
        let app = launch()

        let name = "UITest \(UUID().uuidString.prefix(6))"
        let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        let manageRow = app.descendants(matching: .any)
            .matching(identifier: "spoolman.manageEmptySpools").firstMatch
        let libraryScreen = app.navigationBars["Empty Spools"]

        // Add an entry under Manage Empty Spools.
        tap(manageRow, until: libraryScreen, in: app)
        tap(app.buttons["emptySpools.add"], until: app.textFields["emptySpoolEditor.name"], in: app)
        let nameField = app.textFields["emptySpoolEditor.name"]
        nameField.tap()
        nameField.typeText(name)
        let weightField = app.textFields["emptySpoolEditor.weight"]
        weightField.tap()
        weightField.typeText("173.5")
        app.buttons["emptySpoolEditor.save"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))

        // Back to the Library tab; Add Spool opens on the filament search, and
        // a filament takes it to the spool form, where the entry is picked.
        libraryScreen.buttons.element(boundBy: 0).tap()
        tap(app.buttons["library.addSpool"], until: app.navigationBars["Select Filament"], in: app)
        pickFirstMyFilament(in: app)
        tap(app.buttons["spoolForm.emptySpoolPicker"], until: entry, in: app)
        entry.tap()
        let emptyWeight = app.textFields["spoolForm.emptySpoolWeight"]
        reveal(emptyWeight, in: app)
        XCTAssertEqual(emptyWeight.value as? String, "173.5")

        // Leave the simulator's library as found.
        closeTips(in: app)
        app.navigationBars["Add Spool"].buttons["Cancel"].tap()
        tap(manageRow, until: libraryScreen, in: app)
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.swipeLeft()
        let swipeDelete = app.buttons["emptySpools.delete"]
        XCTAssertTrue(swipeDelete.waitForExistence(timeout: 5))
        swipeDelete.tap()
        let confirm = app.buttons["emptySpools.confirmDelete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(entry.waitForNonExistence(timeout: 5))
    }

    /// Add Spool opens on the filament search; Cancel closes it. A filament
    /// pick opens the spool form, and Cancel there closes the whole sheet.
    @MainActor
    func testAddSpoolStartsFromTheFilamentSearch() {
        let app = launch()
        let addSpool = app.buttons["library.addSpool"]

        tap(addSpool, until: app.navigationBars["Select Filament"], in: app)
        app.navigationBars["Select Filament"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Select Filament"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(addSpool.waitForExistence(timeout: 5), "Cancel leaves the Library showing")

        tap(addSpool, until: app.navigationBars["Select Filament"], in: app)
        pickFirstMyFilament(in: app)
        app.navigationBars["Add Spool"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Add Spool"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(addSpool.waitForExistence(timeout: 5), "Cancel closes the sheet and leaves the Library showing")
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
