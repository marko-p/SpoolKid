import XCTest

/// Every other UI test launches with `-has_completed_welcome YES`, so none of
/// them builds the welcome guide. The guide's printer step reads
/// `PrinterService` from the environment, and the cover it lives in sits
/// outside the modifiers that inject it — a fresh install trapped on launch
/// (2026-11-21) and nothing caught it.
final class WelcomeGuideUITests: XCTestCase {
    /// Reaches the printer step without writing settings: the first step's
    /// Continue writes back the stored tag format unchanged, and the backend
    /// step is swiped past because its Continue would store the on-device
    /// Library as the backend, in the app's own domain, for every later run.
    func testTheGuideShowsAndReachesThePrinterStep() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-has_completed_welcome", "NO",
            "-disableVocabularyRefresh", "YES",
            "-disableMessages", "YES",
            "-changelog_auto_show", "NO",
            "-support_opted_out", "YES",
            "-backend_kind", "local",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Welcome to SpoolKid"].waitForExistence(timeout: 10))

        app.buttons["Continue"].firstMatch.tap()
        let backendTitle = app.staticTexts["Use This iPhone"]
        XCTAssertTrue(backendTitle.waitForExistence(timeout: 5))

        backendTitle.swipeLeft()
        XCTAssertTrue(app.staticTexts["Connect Your Snapmaker U1"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
    }
}
