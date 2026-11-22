//
//  LocationWriteCollisionTests.swift
//  SpoolKidTests
//
//  Purpose: A location write must not overwrite a tag a spool still claims —
//  card_uids is keyed by the hardware UID and survives any rewrite.
//

import Foundation
import Testing
@testable import SpoolKid

struct LocationWriteCollisionTests {
    @Test func anUnclaimedTagProceeds() {
        #expect(NFCManager.locationWriteDecision(
            uid: "AABBCCDD", blockedUIDs: ["11223344"]
        ) == .proceed)
    }

    @Test func aClaimedTagIsBlockedAndNamesTheUID() {
        #expect(NFCManager.locationWriteDecision(
            uid: "AABBCCDD", blockedUIDs: ["AABBCCDD"]
        ) == .blocked(uid: "AABBCCDD"))
    }

    @Test func theComparisonIsNormalizedNotLiteral() {
        #expect(NFCManager.locationWriteDecision(
            uid: "aabbccdd", blockedUIDs: ["AABBCCDD"]
        ) == .blocked(uid: "AABBCCDD"))
    }

    @Test func aTagWhoseUIDCouldNotBeReadProceeds() {
        // ISO 15693 tags can arrive without a UID. Refusing every such write
        // would make location tags unwritable on Type 5 hardware; the read-side
        // heal still covers the rarer mistake.
        #expect(NFCManager.locationWriteDecision(uid: nil, blockedUIDs: ["AABBCCDD"]) == .proceed)
    }
}
