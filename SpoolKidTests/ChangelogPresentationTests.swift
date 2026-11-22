//
//  ChangelogPresentationTests.swift
//  SpoolKidTests
//
//  Purpose: Locks which entries a launch owes the user — including the two
//  cases that must show nothing: a fresh install, and an opted-out user.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

struct ChangelogPresentationTests {

    private static func entry(_ version: String) -> ChangelogEntry {
        ChangelogEntry(version: version, date: nil, headline: nil, changes: [])
    }

    private static let catalogue = [
        entry("0.18"), entry("0.17"), entry("0.16"), entry("0.9")
    ]

    private static func present(
        installed: String,
        lastShown: String,
        autoShow: Bool = true
    ) -> [String] {
        ChangelogService.entriesToPresent(
            installed: installed,
            lastShown: lastShown,
            autoShow: autoShow,
            entries: catalogue
        ).map(\.version)
    }

    @Test func aFreshInstallIsOwedNothing() {
        // "" means no version has ever been recorded. This also covers the
        // first launch of the build that introduces the feature: nobody gets
        // the whole history dumped on them.
        #expect(Self.present(installed: "0.18", lastShown: "").isEmpty)
    }

    @Test func anOptedOutUserIsOwedNothing() {
        #expect(Self.present(installed: "0.18", lastShown: "0.16", autoShow: false).isEmpty)
    }

    @Test func oneVersionOfProgressShowsThatOneVersion() {
        #expect(Self.present(installed: "0.18", lastShown: "0.17") == ["0.18"])
    }

    @Test func aUserWhoSkippedReleasesGetsEveryOneOfThem() {
        #expect(Self.present(installed: "0.18", lastShown: "0.9") == ["0.18", "0.17", "0.16"])
    }

    @Test func theSameVersionTwiceShowsNothing() {
        #expect(Self.present(installed: "0.18", lastShown: "0.18").isEmpty)
    }

    @Test func aRollbackShowsNothing() {
        // TestFlight can install an older build over a newer one.
        #expect(Self.present(installed: "0.16", lastShown: "0.18").isEmpty)
    }

    @Test func entriesNewerThanTheInstalledBuildAreWithheld() {
        // The remote file may describe a release this build is not yet.
        #expect(Self.present(installed: "0.17", lastShown: "0.16") == ["0.17"])
    }

    @Test func anEmptyCatalogueIsOwedNothing() {
        let result = ChangelogService.entriesToPresent(
            installed: "0.18", lastShown: "0.17", autoShow: true, entries: []
        )
        #expect(result.isEmpty)
    }

    @Test func theResultIsNewestFirst() {
        #expect(Self.present(installed: "0.18", lastShown: "0.9").first == "0.18")
    }
}
