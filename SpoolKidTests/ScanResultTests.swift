//
//  ScanResultTests.swift
//  SpoolKidTests
//
//  A new user scanned an empty NTAG215 and the hub called it "Unknown tag
//  format" (test-user report, 2026-09-30). An empty tag is not a mystery.
//

import Testing
@testable import SpoolKid

struct ScanResultTests {

    @Test func aBlankTagIsCalledEmpty() {
        let result = ScanResult(cardUID: "04A1B2C3D4E5F6", tagData: nil, format: nil, isBlankTag: true)
        #expect(result.undecodedTagNote == "Empty tag")
    }

    @Test func anUndecodedTagThatIsNotBlankIsStillUnknown() {
        let result = ScanResult(cardUID: "04A1B2C3D4E5F6", tagData: nil, format: nil)
        #expect(result.undecodedTagNote == "Unknown tag format")
    }

    @Test func aDecodedTagHasNoNote() {
        let result = ScanResult(
            cardUID: "04A1B2C3D4E5F6",
            tagData: FilamentTagData(
                material: "PLA", brand: "Generic", colorHex: "FF0000",
                minNozzleTemp: 200, maxNozzleTemp: 220, minBedTemp: 60, maxBedTemp: 60
            ),
            format: .openSpool
        )
        #expect(result.undecodedTagNote == nil)
    }
}
