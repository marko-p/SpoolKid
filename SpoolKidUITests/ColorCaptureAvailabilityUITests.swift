import XCTest

/// The camera button on the color editor appears only on a device with a back
/// camera. The Simulator has none, so the form shows the color editor without it.
final class ColorCaptureAvailabilityUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testCameraButtonIsAbsentWithoutACamera() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-disableVocabularyRefresh", "YES", "-disableMessages", "YES", "-has_completed_welcome", "YES",
            "-changelog_auto_show", "NO",
            "-support_opted_out", "YES"
        ]
        app.launch()

        let manually = app.buttons["Manually"]
        XCTAssertTrue(manually.waitForExistence(timeout: 10))
        // A first-run tip popover takes the first tap to dismiss itself.
        let close = app.popovers.buttons["Close"]
        if close.waitForExistence(timeout: 2) { close.tap() }
        let brand = app.textFields["Brand Name"]
        for _ in 0..<3 where !brand.exists {
            manually.tap()
            _ = brand.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(brand.exists)

        let mode = app.descendants(matching: .any)["filamentColorEditor.mode"]
        for _ in 0..<6 where !mode.exists {
            app.swipeUp()
        }
        XCTAssertTrue(mode.exists)
        XCTAssertFalse(app.descendants(matching: .any)["filamentColorEditor.capture"].exists)
    }
}
