//
//  WeighInfoButtonAccessibilityUITests.swift
//  SpoolKidUITests
//
//  Purpose: Weigh Spools' (i) beside "Save automatically" is its own
//  accessibility element. Inside the Toggle's label it was part of the
//  switch, which VoiceOver does not look into. The scale row is built the
//  same way but needs a paired scale, which the Simulator cannot have.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import XCTest

final class WeighInfoButtonAccessibilityUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testTheSaveAutomaticallyInfoButtonIsOutsideItsSwitch() {
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

        let weighRow = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Weigh Spools'")).firstMatch
        XCTAssertTrue(weighRow.waitForExistence(timeout: 10))
        closeTips(in: app)
        weighRow.tap()
        XCTAssertTrue(app.navigationBars["Weigh Spools"].waitForExistence(timeout: 10))
        closeTips(in: app)

        let toggle = app.switches["Save automatically"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.buttons.count, 0, "The (i) must not sit inside the switch")
        XCTAssertTrue(app.buttons["About Save automatically"].exists)
    }

    /// TipKit popovers lay a dismiss region over the screen that swallows taps.
    @MainActor
    private func closeTips(in app: XCUIApplication) {
        // The Library shows five tips in a row, each after the last closes.
        for _ in 0..<6 {
            let close = app.popovers.buttons["Close"]
            guard close.waitForExistence(timeout: 2) else { return }
            close.tap()
        }
    }
}
