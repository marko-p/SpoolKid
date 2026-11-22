//
//  TagsBottomToolbarUITests.swift
//  SpoolKidUITests
//
//  Purpose: The Tags tab's scan actions are named icon buttons in its floating
//  bottom bar, Scan Label left of Scan Tag.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import XCTest

final class TagsBottomToolbarUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testScanButtonsAreIconsInTheBottomBar() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-disableVocabularyRefresh", "YES", "-disableMessages", "YES", "-has_completed_welcome", "YES",
            "-changelog_auto_show", "NO",
            "-support_opted_out", "YES"
        ]
        app.launch()
        let close = app.popovers.buttons["Close"]
        for _ in 0..<6 where close.waitForExistence(timeout: 3) {
            close.tap()
            _ = close.waitForNonExistence(timeout: 2)
        }

        let scanTag = app.buttons["Scan Tag"]
        let scanLabel = app.buttons["Scan Label"]
        XCTAssertTrue(scanTag.waitForExistence(timeout: 5))
        XCTAssertTrue(scanLabel.exists)
        // The name under each icon is part of its button, not a second
        // element VoiceOver would read on its own.
        XCTAssertFalse(app.staticTexts["Scan Tag"].exists)
        XCTAssertFalse(app.staticTexts["Scan Label"].exists)
        XCTAssertLessThan(scanLabel.frame.maxX, scanTag.frame.minX)
    }
}
