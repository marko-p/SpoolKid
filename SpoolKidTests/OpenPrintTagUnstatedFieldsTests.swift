//
//  OpenPrintTagUnstatedFieldsTests.swift
//  SpoolKidTests
//
//  0 means "this tag does not say" (`FilamentTagData.statedMeasurement`),
//  and the write form shows 0 in every field left untouched. Until
//  2026-10-18 OpenPrintTag alone wrote those zeros, so a tag told a printer
//  its spool weighed 0 g and preheated to 0 °C (owner's SLIX scan).
//

import Testing
import Foundation
@testable import SpoolKid

struct OpenPrintTagUnstatedFieldsTests {

    private static func tag(preheat: Int, weight: Double, empty: Double, dryTemp: Int, dryTime: Int) -> FilamentTagData {
        FilamentTagData(
            name: "Galaxy Black", material: "PLA", brand: "Prusament", colorHex: "3D3E3D",
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60,
            preheatTemp: preheat, dryingTemp: dryTemp, dryingTime: dryTime,
            nominalNetWeight: weight, actualNetWeight: weight, emptyContainerWeight: empty
        )
    }

    @Test func zeroFieldsAreNotWritten() throws {
        let payload = try #require(OpenPrintTagPayload.encode(from: Self.tag(preheat: 0, weight: 0, empty: 0, dryTemp: 0, dryTime: 0)))
        let decoded = try #require(OpenPrintTagPayload.decode(from: payload))
        #expect(decoded.preheatTemp == nil)
        #expect(decoded.nominalNetWeight == nil)
        #expect(decoded.actualNetWeight == nil)
        #expect(decoded.emptyContainerWeight == nil)
        #expect(decoded.dryingTemp == nil)
        #expect(decoded.dryingTime == nil)
    }

    @Test func statedFieldsAreStillWritten() throws {
        let payload = try #require(OpenPrintTagPayload.encode(from: Self.tag(preheat: 170, weight: 800, empty: 277, dryTemp: 55, dryTime: 240)))
        let decoded = try #require(OpenPrintTagPayload.decode(from: payload))
        #expect(decoded.preheatTemp == 170)
        #expect(decoded.nominalNetWeight == 800)
        #expect(decoded.actualNetWeight == 800)
        #expect(decoded.emptyContainerWeight == 277)
        #expect(decoded.dryingTemp == 55)
        #expect(decoded.dryingTime == 240)
    }
}
