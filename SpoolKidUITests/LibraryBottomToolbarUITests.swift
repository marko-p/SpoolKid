//
//  LibraryBottomToolbarUITests.swift
//  SpoolKidUITests
//
//  Purpose: The Library root's actions live in a bottom toolbar that belongs
//  to the root only, and selection mode swaps them for the selection actions.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import XCTest

final class LibraryBottomToolbarUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-disableVocabularyRefresh", "YES", "-disableMessages", "YES", "-has_completed_welcome", "YES",
            "-changelog_auto_show", "NO",
            "-support_opted_out", "YES",
            "-backend_kind", "local",
            "-ui_start_spoolman_tab"
        ]
        app.launch()
        let close = app.popovers.buttons["Close"]
        // The Library shows five tips in a row, each after the last closes.
        for _ in 0..<6 where close.waitForExistence(timeout: 3) {
            close.tap()
            _ = close.waitForNonExistence(timeout: 2)
        }
        return app
    }

    @MainActor
    func testToolbarButtonsOpenTheirScreensAndLeaveNoToolbarBehind() {
        let app = launch()

        let locations = app.buttons["spoolman.manageLocations"]
        XCTAssertTrue(locations.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["spoolman.manageEmptySpools"].exists)
        XCTAssertTrue(app.buttons["Weigh Spools"].exists)
        XCTAssertTrue(app.buttons["library.addSpool"].exists)

        locations.tap()
        XCTAssertTrue(app.staticTexts["Manage Locations"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["library.addSpool"].exists)
    }

    /// The prominent Add Spool carries its tip on a transparent overlay; one
    /// tap must still open the flow (0.28 device report: tapping did nothing).
    @MainActor
    func testAddSpoolOpensOnTheFirstTap() {
        let app = launch()

        let addSpool = app.buttons["library.addSpool"]
        XCTAssertTrue(addSpool.waitForExistence(timeout: 5))
        addSpool.tap()
        XCTAssertTrue(app.navigationBars["Select Filament"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSelectModeSwapsTheBarForSelectionActions() {
        let app = launch()

        let select = app.buttons["Select"].firstMatch
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        select.tap()

        let count = app.staticTexts["0 selected"]
        let selectAll = app.buttons["Select All"]
        let archive = app.buttons["Archive"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertTrue(selectAll.exists)
        XCTAssertTrue(archive.exists)
        XCTAssertFalse(archive.isEnabled)
        XCTAssertFalse(app.buttons["library.addSpool"].exists)
        // Owner's order: the count, then Select All, then Archive.
        XCTAssertLessThan(count.frame.minX, selectAll.frame.minX)
        XCTAssertLessThan(selectAll.frame.maxX, archive.frame.minX)

        // An empty library has nothing to select.
        guard selectAll.isEnabled else { return }
        selectAll.tap()
        XCTAssertTrue(app.buttons["Deselect All"].waitForExistence(timeout: 3))
        XCTAssertTrue(archive.isEnabled)
    }

    @MainActor
    func testWeighSpoolsPutsFinishLeftOfEqualScanAndChooseIcons() {
        let app = launch()

        let weigh = app.buttons["Weigh Spools"]
        XCTAssertTrue(weigh.waitForExistence(timeout: 5))
        weigh.tap()
        let close = app.popovers.buttons["Close"]
        for _ in 0..<6 where close.waitForExistence(timeout: 3) {
            close.tap()
            _ = close.waitForNonExistence(timeout: 2)
        }

        let finish = app.buttons["Finish"]
        let choose = app.buttons["Choose"]
        let scan = app.buttons["Scan"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        XCTAssertTrue(choose.exists)
        XCTAssertTrue(scan.exists)
        // All icons: Finish, then Choose, then Scan.
        for title in ["Finish", "Choose", "Scan"] {
            XCTAssertFalse(app.staticTexts[title].exists, title)
        }
        XCTAssertLessThan(finish.frame.maxX, choose.frame.minX)
        XCTAssertLessThan(choose.frame.maxX, scan.frame.minX)
        // Finish lines up with the floating tab bar's left edge, not the
        // screen's 16-pt margin.
        XCTAssertGreaterThan(finish.frame.minX, 40)
    }
}
