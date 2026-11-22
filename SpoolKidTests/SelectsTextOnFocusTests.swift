//
//  SelectsTextOnFocusTests.swift
//  SpoolKidTests
//
//  A form field that gains focus selects its whole value, so the first
//  keystroke replaces it instead of appending to it. Search fields are left
//  alone; multi-line fields are UITextViews and never reach the modifier.
//

import Testing
import UIKit
@testable import SpoolKid

@MainActor
struct SelectsTextOnFocusTests {

    @Test func theWholeValueIsSelected() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 200, height: 44))
        window.addSubview(field)
        window.makeKeyAndVisible()
        defer { field.resignFirstResponder(); window.isHidden = true }

        field.text = "1000"
        field.becomeFirstResponder()
        SelectsTextOnFocus.selectAllText(in: field)

        let range = try #require(field.selectedTextRange)
        #expect(field.offset(from: field.beginningOfDocument, to: range.start) == 0)
        #expect(field.offset(from: range.start, to: range.end) == 4)
    }

    @Test func plainFieldsAreSelected() {
        #expect(SelectsTextOnFocus.applies(to: UITextField()))
    }

    @Test func searchFieldsAreLeftAlone() {
        #expect(!SelectsTextOnFocus.applies(to: UISearchTextField()))
    }
}
