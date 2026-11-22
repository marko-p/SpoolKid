//
//  SupportPromptCopyTests.swift
//  SpoolKidTests
//
//  Purpose: Pins the support ask's tone — it names the milestone it is
//  celebrating and never leans on guilt or the licence.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Testing
@testable import SpoolKid

struct SupportPromptCopyTests {

    @Test func milestoneHeadlinesNameTheirNumber() {
        #expect(SupportPromptCopy.headline(for: .scanMilestone(100)).contains("100"))
        #expect(SupportPromptCopy.headline(for: .editMilestone(200)).contains("200"))
        #expect(SupportPromptCopy.headline(for: .upgrade("1.8")).contains("1.8"))
    }

    @Test func everyReasonHasNonEmptyCopy() {
        let reasons: [SupportPromptReason] = [
            .scanMilestone(100), .editMilestone(100), .upgrade("1.8"), .successMoment
        ]
        for reason in reasons {
            #expect(!SupportPromptCopy.headline(for: reason).isEmpty)
            #expect(!SupportPromptCopy.body(for: reason).isEmpty)
        }
    }

    /// Every user-facing string the prohibition rules apply to: the per-reason
    /// headline/body pairs plus every fixed string — the sheet, the thank-you,
    /// and the buttons. Missing any of these would let a banned word or
    /// "donate" slip in unnoticed by these tests.
    private static let allUserFacingStrings: [String] = {
        let reasons: [SupportPromptReason] = [
            .scanMilestone(100), .editMilestone(100), .upgrade("1.8"), .successMoment
        ]
        var strings = reasons.flatMap { [SupportPromptCopy.headline(for: $0), SupportPromptCopy.body(for: $0)] }
        strings.append(contentsOf: [
            SupportPromptCopy.sheetBody,
            SupportPromptCopy.thanksHeadline,
            SupportPromptCopy.thanksBody,
            SupportPromptCopy.supportButton,
            SupportPromptCopy.notNowButton,
            SupportPromptCopy.sheetDismissButton
        ])
        return strings
    }()

    @Test func theAskNeverLeansOnGuiltOrTheLicence() {
        // The 2026-08-11 README rewrite moved the pitch onto the app's value.
        // These are the words that move it back.
        let banned = ["MIT", "licence", "license", "please", "beg", "owe", "guilt"]
        for text in Self.allUserFacingStrings {
            let lowered = text.lowercased()
            for word in banned {
                #expect(!lowered.contains(word.lowercased()), "\"\(text)\" contains \"\(word)\"")
            }
        }
    }

    @Test func theCopyNeverSaysDonate() {
        // "Donation" means TipKit event donation in this codebase, and the
        // user-facing word is "support" throughout.
        for text in Self.allUserFacingStrings {
            #expect(!text.lowercased().contains("donat"), "\"\(text)\" says donate")
        }
    }
}
