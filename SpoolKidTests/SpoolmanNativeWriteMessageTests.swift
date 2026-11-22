//
//  SpoolmanNativeWriteMessageTests.swift
//  SpoolKidTests
//
//  A native-tag write is several calls, so it can land part-way. The message
//  has to say so — "failed" alone would hide what did land, and "saved" would
//  claim what did not.
//

import Foundation
import Testing
@testable import SpoolKid

struct SpoolmanNativeWriteMessageTests {
    @Test func aFailureWithNothingLandedIsJustTheReasons() {
        #expect(SpoolmanRepository.nativeWriteFailureMessage(landed: 0, failures: ["A.", "B."]) == "A. B.")
    }

    @Test func aPartialWriteSaysSomethingLanded() {
        #expect(SpoolmanRepository.nativeWriteFailureMessage(landed: 2, failures: ["card_uids could not be updated: x"])
            == "Partly saved: card_uids could not be updated: x Saving again finishes it.")
    }

    @Test func aSpoolmanMessageBodyIsRecognised() {
        #expect(SpoolmanService.hasSpoolmanMessage(Data(#"{"message":"Spool 1 has no tag with UID AA."}"#.utf8)))
        #expect(SpoolmanService.hasSpoolmanMessage(Data(#"{"detail":"Not Found"}"#.utf8)) == false)
        #expect(SpoolmanService.hasSpoolmanMessage(Data("oops".utf8)) == false)
    }
}
