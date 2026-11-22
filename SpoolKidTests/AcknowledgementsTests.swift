//
//  AcknowledgementsTests.swift
//  SpoolKidTests
//
//  Settings → SpoolKid → Acknowledgements carries the notices of the
//  third-party data SpoolKid ships. A source comment never reaches the App
//  Store build, so this page is where MIT's "include the notice" is met
//  (owner, 2026-10-05).
//

import Foundation
import Testing

struct AcknowledgementsTests {

    @Test func theSettingsAppLinksToTheAcknowledgements() throws {
        let rows = try Self.specifiers(in: "Root.plist")
        #expect(rows.contains {
            $0["Type"] as? String == "PSChildPaneSpecifier" && $0["File"] as? String == "Acknowledgements"
        })
    }

    @Test(arguments: [
        ("canvasspoolrfidprogrammer", "Copyright (c) 2025 Martin (iOS Implementation)"),
        ("canvasspoolrfidprogrammer", "Canvas format conversion and iOS adaptation: Matt Steuer, 2026"),
        ("FilamentDB", "Copyright (c) 2025 Manuel Weiser")
    ])
    func eachMITSourceShipsItsFullNotice(title: String, copyright: String) throws {
        let notice = try Self.footer(titled: title)
        #expect(notice.contains(copyright))
        #expect(notice.contains("The above copyright notice and this permission notice shall be included"))
        #expect(notice.contains("THE SOFTWARE IS PROVIDED \"AS IS\""))
    }

    /// CC0 asks for nothing; the credit is a courtesy.
    @Test func theTigerTagTablesAreCredited() throws {
        #expect(try Self.footer(titled: "TigerTag RFID Guide").contains("CC0"))
    }

    // MARK: - Helpers

    private static func specifiers(in file: String) throws -> [[String: Any]] {
        let url = try #require(Bundle.main.url(forResource: "Settings", withExtension: "bundle"))
            .appendingPathComponent(file)
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try #require((plist as? [String: Any])?["PreferenceSpecifiers"] as? [[String: Any]])
    }

    private static func footer(titled title: String) throws -> String {
        let group = try #require(try specifiers(in: "Acknowledgements.plist").first { $0["Title"] as? String == title })
        return try #require(group["FooterText"] as? String)
    }
}
