//
//  ScanHubTagTargetTests.swift
//  SpoolKidTests
//
//  Which hub choosers offer filaments (spec 2026-10-11 §2).
//

import Testing
@testable import SpoolKid

struct ScanHubTagTargetTests {
    @Test func transferAndLinkOfferFilamentsWhereFilamentLinksAreWritten() {
        #expect(ScanResultHubView.offersFilamentTargets(intent: .mapUIDToSpool, writesFilamentLinks: true))
    }

    @Test func noFilamentsWhereFilamentLinksAreNotWritten() {
        #expect(!ScanResultHubView.offersFilamentTargets(intent: .mapUIDToSpool, writesFilamentLinks: false))
    }

    @Test func theWriteOntoTagChooserNeverOffersFilaments() {
        #expect(!ScanResultHubView.offersFilamentTargets(intent: .overwriteTag, writesFilamentLinks: true))
        #expect(!ScanResultHubView.offersFilamentTargets(intent: nil, writesFilamentLinks: true))
    }
}
