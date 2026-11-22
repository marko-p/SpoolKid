//
//  SpoolmanServerVersionTests.swift
//  SpoolKidTests
//
//  Native tags arrived in Spoolman 0.27.0, and an older server silently
//  ignores `?tag=` (answering with every spool), so the version gate is the
//  one thing standing between SpoolKid and a wrong lookup.
//

import Testing
@testable import SpoolKid

struct SpoolmanServerVersionTests {
    @Test(arguments: [
        ("0.27.0", true), ("v0.27.1", true), ("0.28.0", true), ("1.0.0", true),
        ("0.27.0-rc1", true), ("0.26.1", false), ("0.23.1", false), ("", false), ("dev", false),
    ])
    func nativeTagsArriveIn0_27(version: String, expected: Bool) {
        #expect(SpoolmanService.supportsNativeTags(version: version) == expected)
    }

    @Test func noVersionMeansNoNativeTags() {
        #expect(SpoolmanService.supportsNativeTags(version: nil) == false)
    }

    @Test func storeNamesMatchTheSwitches() {
        #expect(TagStore.cardUIDs.displayName == "SpoolLink")
        #expect(TagStore.spoolmanTags.displayName == "Spoolman Tags")
    }
}
