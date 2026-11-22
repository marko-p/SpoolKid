//
//  TagInspectorHubTests.swift
//  SpoolKidTests
//
//  The Inspect Tag screen is a snapshot of one scan, so the hub must tell it
//  when a write may have changed the tag since. These pin that one decision.
//

import Foundation
import Testing
@testable import SpoolKid

struct TagInspectorHubTests {

    @Test func writingTheScannedTagChangesIt() {
        #expect(ScanResultHubView.writeChangesScannedTag(writtenUID: "04A2", scannedUID: "04a2"))
    }

    @Test func writingADifferentTagLeavesItAlone() {
        #expect(!ScanResultHubView.writeChangesScannedTag(writtenUID: "04A2", scannedUID: "0499"))
    }

    /// A write that reported no UID may have been this tag, and the notice is
    /// the safe side of "may have".
    @Test func aWriteToAnUnknownTagMayHaveChangedIt() {
        #expect(ScanResultHubView.writeChangesScannedTag(writtenUID: nil, scannedUID: "04a2"))
    }

    @Test func aScanWithoutAUIDMayHaveBeenChanged() {
        #expect(ScanResultHubView.writeChangesScannedTag(writtenUID: "04A2", scannedUID: nil))
    }
}
