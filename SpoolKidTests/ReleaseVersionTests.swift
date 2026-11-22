//
//  ReleaseVersionTests.swift
//  SpoolKidTests
//
//  Purpose: Locks version ordering. MARKETING_VERSION is two-component
//  ("0.17"), where string comparison would rank "0.9" higher.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

struct ReleaseVersionTests {

    @Test func seventeenSortsAboveNine() {
        #expect(ReleaseVersion("0.17") > ReleaseVersion("0.9"))
    }

    @Test func aMajorBumpOutranksAnyMinor() {
        #expect(ReleaseVersion("1.0") > ReleaseVersion("0.17"))
    }

    @Test func trailingZeroesDoNotChangeIdentity() {
        #expect(ReleaseVersion("0.17") == ReleaseVersion("0.17.0"))
        #expect(ReleaseVersion("1") == ReleaseVersion("1.0.0"))
    }

    @Test func thirdComponentBreaksTheTie() {
        #expect(ReleaseVersion("0.17.1") > ReleaseVersion("0.17"))
    }

    @Test func nonNumericComponentsCountAsZeroRatherThanCrashing() {
        #expect(ReleaseVersion("0.beta") == ReleaseVersion("0"))
        #expect(ReleaseVersion("1.beta") > ReleaseVersion("0.99"))
    }

    @Test func theEmptyVersionIsBelowEverything() {
        #expect(ReleaseVersion("") < ReleaseVersion("0.1"))
    }
}
