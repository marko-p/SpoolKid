//
//  ManufacturerPickerUITests.swift
//  SpoolKidUITests
//
//  Purpose: The shared manufacturer picker in each place that uses it. Every
//  test takes the Use "…" path with a unique name, so none needs the network
//  catalogue, and none saves anything.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import XCTest

final class ManufacturerPickerUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testEmptySpoolEditorTakesATypedManufacturer() {
        let app = launch()
        let brand = "UITest Brand \(UUID().uuidString.prefix(6))"

        let manageRow = app.descendants(matching: .any)
            .matching(identifier: "spoolman.manageEmptySpools").firstMatch
        tap(manageRow, until: app.navigationBars["Empty Spools"], in: app)
        tap(app.buttons["emptySpools.add"], until: app.textFields["emptySpoolEditor.name"], in: app)

        let row = app.buttons["emptySpoolEditor.manufacturer"]
        tap(row, until: app.navigationBars["Manufacturer"], in: app)
        XCTAssertTrue(app.buttons["manufacturerPicker.none"].exists, "The empty-spool picker offers None")
        useTyped(brand, in: app)

        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains(brand), "Row reads \(row.label)")

        app.navigationBars.buttons["Cancel"].tap()
    }

    /// Picking a manufacturer that is not in the backend holds it pending;
    /// Cancel creates nothing. Coming back from the picker keeps what was
    /// typed in the form.
    @MainActor
    func testFilamentFormHoldsANewManufacturerUntilSave() {
        let app = launch()
        let brand = "UITest Brand \(UUID().uuidString.prefix(6))"
        let filamentName = "UITest Filament \(UUID().uuidString.prefix(6))"

        openAddFilamentForm(in: app)

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(filamentName)

        let row = app.buttons["filamentForm.manufacturer"]
        tap(row, until: app.navigationBars["Manufacturer"], in: app)
        XCTAssertFalse(app.buttons["manufacturerPicker.none"].exists, "A filament's manufacturer cannot be None")
        useTyped(brand, in: app)

        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains(brand), "Row reads \(row.label)")
        XCTAssertTrue(app.staticTexts["Added to your manufacturers when you save."].exists)
        XCTAssertEqual(nameField.value as? String, filamentName, "Returning from the picker must keep the form's edits")

        app.navigationBars["Add Filament"].buttons["Cancel"].tap()
        // Cancel returns to Select Filament, whose own Cancel closes the sheet.
        let selectFilament = app.navigationBars["Select Filament"]
        XCTAssertTrue(selectFilament.waitForExistence(timeout: 5))
        selectFilament.buttons["Cancel"].tap()
        XCTAssertTrue(selectFilament.waitForNonExistence(timeout: 5))

        // Nothing was created: the picker offers the brand only as a new name,
        // not among My Manufacturers.
        openAddFilamentForm(in: app)
        tap(app.buttons["filamentForm.manufacturer"], until: app.navigationBars["Manufacturer"], in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(brand)
        XCTAssertTrue(app.buttons["manufacturerPicker.useTyped"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[brand].exists, "The brand is not one of My Manufacturers")
    }

    /// Leaving the picker after a search must not leave the search bar and
    /// keyboard over the form, hiding its navigation bar.
    @MainActor
    func testBackFromAnActiveSearchLeavesTheFormUsable() {
        let app = launch()
        let filamentName = "UITest Filament \(UUID().uuidString.prefix(6))"

        openAddFilamentForm(in: app)

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(filamentName)

        tap(app.buttons["filamentForm.manufacturer"], until: app.navigationBars["Manufacturer"], in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Sun")

        // An active search replaces the navigation bar's Back button with its
        // own Close, and iOS does not pop on an edge swipe meanwhile: leaving
        // takes Close, then Back.
        let bar = app.navigationBars["Manufacturer"]
        bar.buttons["Close"].tap()
        XCTAssertTrue(bar.buttons["Close"].waitForNonExistence(timeout: 5), "Close ends the search")
        bar.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Manufacturer"].waitForNonExistence(timeout: 5))

        let cancel = app.navigationBars["Add Filament"].buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "The form's navigation bar must be back")
        XCTAssertTrue(cancel.isHittable, "Cancel must be tappable, not covered by a stranded search bar")
        cancel.tap()
    }

    /// Write Tag's brand takes a typed manufacturer through the shared picker,
    /// and the field reads it back.
    @MainActor
    func testWriteTagTakesATypedBrand() {
        let app = launch()
        let brand = "UITest Brand \(UUID().uuidString.prefix(6))"

        let tagsTab = app.tabBars.buttons["Tags"]
        XCTAssertTrue(tagsTab.waitForExistence(timeout: 10))
        tagsTab.tap()
        tap(app.buttons["Manually"], until: app.textFields["writeTag.brand"], in: app)

        // A value typed before the picker opens must survive the sheet: the
        // form is not reset when the picker closes.
        let filamentName = "UITest Filament \(UUID().uuidString.prefix(6))"
        let nameField = app.textFields["Filament Name"]
        reveal(nameField, in: app)
        nameField.tap()
        nameField.typeText(filamentName)
        nameField.typeText(XCUIKeyboardKey.return.rawValue)

        let chooser = app.buttons["writeTag.brandPicker"]
        tap(chooser, until: app.navigationBars["Manufacturer"], in: app)
        useTyped(brand, in: app)

        XCTAssertEqual(app.textFields["writeTag.brand"].value as? String, brand)
        XCTAssertEqual(app.textFields["Filament Name"].value as? String, filamentName,
                       "Closing the picker must keep the form's other edits")
    }

    // MARK: - Helpers

    @MainActor
    func launch() -> XCUIApplication {
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

    /// Library root → Add Spool → Add New Filament…: the filament form, with no
    /// spool started. Cancelling it leaves the filament uncreated.
    @MainActor
    func openAddFilamentForm(in app: XCUIApplication) {
        tap(app.buttons["library.addSpool"], until: app.navigationBars["Select Filament"], in: app)
        let addNew = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add New Filament'")).firstMatch
        tap(addNew, until: app.navigationBars["Add Filament"], in: app)
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
