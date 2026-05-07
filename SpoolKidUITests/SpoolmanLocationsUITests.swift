import XCTest

final class SpoolmanLocationsUITests: XCTestCase {
    @MainActor
    func testSpoolmanTabShowsManageLocationsEntry() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-has_completed_welcome", "YES",
            "-spoolman_connection_valid", "YES",
            "-ui_start_spoolman_tab"
        ]
        app.launch()

        let manageLocationsRow = app.descendants(matching: .any)
            .matching(identifier: "spoolman.manageLocations")
            .firstMatch
        XCTAssertTrue(
            manageLocationsRow.waitForExistence(timeout: 5),
            "Expected Manage Locations row with stable accessibility identifier"
        )
    }
}
