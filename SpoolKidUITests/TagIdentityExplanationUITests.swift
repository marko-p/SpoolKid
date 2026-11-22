import XCTest

final class TagIdentityExplanationUITests: XCTestCase {
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-disableVocabularyRefresh", "YES", "-disableMessages", "YES", "-has_completed_welcome", "YES", "-changelog_auto_show", "NO", "-support_opted_out", "YES"] + extra
        app.launch()
        return app
    }

    /// Seeded as an upgrade that owes the explanation; answering it dismisses
    /// the sheet. Persistence is unit-tested (`TagIdentityMigrationTests`: the
    /// persisted mode and pending flag) — the launch-argument seed shadows
    /// those keys, so this test cannot observe a write.
    ///
    /// Answers with Keep Tag Links, which writes only the pending flag: Use
    /// Spool ID Instead would write `tag_identity_mode` into the app's own
    /// domain and leave the simulator in Spool ID mode for every later run.
    func testTheExplanationAppearsAndDismisses() {
        let app = launch(["-backend_kind", "local", "-tag_identity_mode", "tagLinks", "-tag_identity_explanation_pending", "YES"])
        let keep = app.buttons["tagIdentityKeep"]
        XCTAssertTrue(keep.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tagIdentityUseSpoolID"].exists)
        keep.tap()
        XCTAssertFalse(keep.waitForExistence(timeout: 2))
    }
}
