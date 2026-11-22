import XCTest

/// Tapping a filled form field selects its value, so typing replaces it —
/// and with the setting off, typing appends as it always did.
final class SelectTextOnFocusUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testTypingReplacesAFilledFieldWhenOn() {
        retypeBrand(selectTextOnFocus: true) { _, typed in typed }
    }

    @MainActor
    func testTypingAppendsWhenOff() {
        retypeBrand(selectTextOnFocus: false) { held, typed in held + typed }
    }

    /// Types "Generic" into the Write Tag form's Brand field, leaves it, taps
    /// it again and types "Sunlu", checking after each that the field holds
    /// `typing(what it held, what was typed)`. The form prefills a default
    /// brand, which is the first value the field holds.
    @MainActor
    private func retypeBrand(
        selectTextOnFocus: Bool,
        typing: (_ held: String, _ typed: String) -> String
    ) {
        let app = XCUIApplication()
        app.launchArguments += [
            "-disableVocabularyRefresh", "YES", "-disableMessages", "YES", "-has_completed_welcome", "YES",
            "-changelog_auto_show", "NO",
            "-support_opted_out", "YES",
            "-select_text_on_focus", selectTextOnFocus ? "YES" : "NO"
        ]
        app.launch()

        let manually = app.buttons["Manually"]
        XCTAssertTrue(manually.waitForExistence(timeout: 10))
        // A first-run tip popover takes the first tap to dismiss itself.
        let brand = app.textFields["Brand Name"]
        for _ in 0..<3 where !brand.exists {
            manually.tap()
            _ = brand.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(brand.exists)
        // An empty field reports its placeholder as its value.
        let shown = brand.value as? String ?? ""
        var held = shown == brand.placeholderValue ? "" : shown

        focus(brand)
        held = typing(held, "Generic")
        type("Generic", into: brand, expecting: held)

        // Return, not the Done bar: the bar shows only with an on-screen
        // keyboard, and a headless simulator (the parallel-testing clones) has
        // a hardware keyboard connected. Return ends editing on either.
        brand.typeText(XCUIKeyboardKey.return.rawValue)
        // Selecting answers to editing BEGINNING, so the next tap must start
        // a new session, not land before Return has ended this one.
        XCTAssertTrue(waitUntil(brand, "hasKeyboardFocus == false"))

        focus(brand)
        held = typing(held, "Sunlu")
        type("Sunlu", into: brand, expecting: held)
    }

    /// Taps `field` until it has keyboard focus. The tip popover can outlive
    /// the tap on "Manually" and stay up over the form, and the tap it catches
    /// only dismisses it.
    @MainActor
    private func focus(_ field: XCUIElement) {
        for _ in 0..<3 {
            field.tap()
            if waitUntil(field, "hasKeyboardFocus == true") { return }
        }
        XCTFail("\(field) never took keyboard focus")
    }

    /// `typeText` returns once the keystrokes are sent, not once the field has
    /// them: on a loaded simulator the keyboard delivers them seconds later.
    @MainActor
    private func type(_ text: String, into field: XCUIElement, expecting expected: String) {
        field.typeText(text)
        _ = waitUntil(field, "value == %@", expected, timeout: 15)
        XCTAssertEqual(field.value as? String, expected)
    }

    @MainActor
    private func waitUntil(
        _ element: XCUIElement, _ format: String, _ arguments: Any...,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate(format: format, argumentArray: arguments)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
