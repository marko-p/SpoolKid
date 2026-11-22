import XCTest

final class SpoolmanLocationsUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        // SpoolKidUITestsLaunchTests runs for each UI configuration and can leave
        // the simulator in landscape; in compact-height landscape the Locations
        // row sits below the fold and the lazy List never realizes it.
        // Force portrait so this test is independent of prior-test orientation.
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testSpoolmanTabShowsManageLocationsEntry() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-disableVocabularyRefresh", "YES", "-disableMessages", "YES", "-has_completed_welcome", "YES",
            "-spoolman_connection_valid", "YES",
            "-ui_start_spoolman_tab"
        ]
        app.launch()

        let manageLocationsRow = app.descendants(matching: .any)
            .matching(identifier: "spoolman.manageLocations")
            .firstMatch
        XCTAssertTrue(
            manageLocationsRow.waitForExistence(timeout: 5),
            "Expected Locations row with stable accessibility identifier"
        )
    }
}
