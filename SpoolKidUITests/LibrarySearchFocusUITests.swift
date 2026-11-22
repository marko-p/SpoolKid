//
//  LibrarySearchFocusUITests.swift
//  SpoolKidUITests
//
//  Purpose: The Library root's search field keeps the keyboard when the first
//  letter turns the screen into search mode (the rows above the spools leave).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import XCTest

final class LibrarySearchFocusUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testTypingIntoTheLibrarySearchKeepsFocus() {
        let app = launch()

        let field = app.collectionViews.textFields["Search spools..."].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()

        // One keystroke at a time, as fast as XCUITest types: each must land in
        // the field the first one put into search mode.
        for letter in ["z", "q", "x"] {
            app.typeText(letter)
        }

        let focused = app.textFields.element(matching: NSPredicate(format: "hasKeyboardFocus == true"))
        XCTAssertTrue(focused.exists, "The search field lost the keyboard")
        XCTAssertEqual(focused.value as? String, "zqx")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        // Search mode still narrows the screen to spools.
        let counts = app.descendants(matching: .any)
            .matching(identifier: "library.counts").firstMatch
        XCTAssertFalse(counts.exists && counts.isHittable)
    }

    /// The field docked in the bar: the first letter empties the rows above the
    /// list, which then fits on screen and settles back at the top, taking the
    /// field out of the bar.
    @MainActor
    func testTypingIntoTheDockedSearchKeepsFocus() throws {
        let app = launch()

        let docked = app.navigationBars.textFields["Search spools..."].firstMatch
        for _ in 0..<6 where !docked.isHittable {
            app.collectionViews.firstMatch.swipeUp()
        }
        // A fresh simulator's library may be too short to scroll, and the
        // suite has no way to seed one.
        if !docked.isHittable {
            throw XCTSkip("The library is too short to dock the search field")
        }
        docked.tap()

        for letter in ["z", "q", "x"] {
            app.typeText(letter)
        }

        let focused = app.textFields.element(matching: NSPredicate(format: "hasKeyboardFocus == true"))
        XCTAssertTrue(focused.exists, "The search field lost the keyboard")
        XCTAssertEqual(focused.value as? String, "zqx")
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
}
