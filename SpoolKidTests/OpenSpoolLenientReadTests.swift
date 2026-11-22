//
//  OpenSpoolLenientReadTests.swift
//  SpoolKidTests
//
//  OpenSpool requires only protocol, version, type and color_hex (the
//  Snapmaker U1 firmware's rule). Tags from other writers leave the
//  temperatures off or write them as numbers; SpoolKid read neither (#19).
//  What SpoolKid writes is unchanged and covered by the round-trip tests.
//

import Testing
import Foundation
@testable import SpoolKid

@MainActor
struct OpenSpoolLenientReadTests {

    private func read(_ json: String) -> (data: FilamentTagData, format: ScanResult.DetectedFormat?)? {
        TagFormatService.shared.decodeDetectingFormat(payload: Data(json.utf8), mimeType: "application/json")
    }

    /// A tag with no temperatures: the one Spoolman GO wrote in #19, pretty-printed as it was.
    static let noTemperaturesJSON = """
    {
      "protocol": "openspool",
      "version": "1.0",
      "type": "PETG",
      "color_hex": "F5F5F4",
      "brand": "Overture",
      "sm_id": 25,
      "spool_id": 25
    }
    """

    @Test func aTagWithoutTemperaturesIsReadAndStatesNone() throws {
        let result = try #require(read(Self.noTemperaturesJSON))

        #expect(result.format == .openSpool)
        #expect(result.data.material == "PETG")
        #expect(result.data.brand == "Overture")
        #expect(result.data.colorHex == "F5F5F4")
        #expect(result.data.spoolmanId == 25)
        #expect(result.data.statedExtruderTemp == nil)
        #expect(result.data.statedBedTemp == nil)
    }

    @Test func numericTemperaturesAreRead() throws {
        let json = #"{"protocol":"openspool","version":"1.0","type":"PLA","color_hex":"FFFFFF","brand":"Sunlu","min_temp":190,"max_temp":220,"bed_min_temp":50,"bed_max_temp":70}"#
        let data = try #require(read(json)).data

        #expect(data.minNozzleTemp == 190)
        #expect(data.maxNozzleTemp == 220)
        #expect(data.minBedTemp == 50)
        #expect(data.maxBedTemp == 70)
        #expect(data.statedExtruderTemp == 205)
        #expect(data.statedBedTemp == 60)
    }

    @Test func stringTemperaturesStillStateTheirAverage() throws {
        let data = try #require(read(TagFormatServiceDecodeTests.fieldOpenSpoolJSON)).data

        #expect(data.statedExtruderTemp == 235)
        #expect(data.statedBedTemp == 85)  // 80–85: 82.5 rounds up to the nearest 5
    }

    @Test func oneEndOfARangeStandsForBoth() throws {
        let json = #"{"protocol":"openspool","version":"1.0","type":"PLA","color_hex":"FFFFFF","brand":"Sunlu","max_temp":"215"}"#
        let data = try #require(read(json)).data

        #expect(data.minNozzleTemp == 215)
        #expect(data.maxNozzleTemp == 215)
        #expect(data.statedExtruderTemp == 215)
        #expect(data.statedBedTemp == nil)
    }

    @Test func aTagWithoutABrandReadsAsGeneric() throws {
        let json = #"{"protocol":"openspool","version":"1.0","type":"PLA","color_hex":"FFFFFF"}"#
        let result = try #require(read(json))

        #expect(result.format == .openSpool)
        #expect(result.data.brand == "Generic")
    }

    @Test func readsLenientAdditionalColors() throws {
        let json = ##"{"protocol":"openspool","version":"1.0","type":"PLA","color_hex":"FF0000","additional_color_hexes":["#00ff00","zz","0000FF"]}"##
        let data = try #require(read(json)).data

        #expect(data.additionalColorHexes == ["00FF00", "0000FF"])
        #expect(data.colors.isMulti)
    }

    @Test func ignoresNonArrayAdditionalColors() throws {
        let json = #"{"protocol":"openspool","version":"1.0","type":"PLA","color_hex":"FF0000","additional_color_hexes":"00FF00"}"#
        let data = try #require(read(json)).data

        #expect(data.additionalColorHexes == nil)
        #expect(!data.colors.isMulti)
    }

    @Test func aJunkEntryDoesNotVoidTheOthers() throws {
        let json = #"{"protocol":"openspool","version":"1.0","type":"PLA","color_hex":"FF0000","additional_color_hexes":["00FF00",5]}"#
        let data = try #require(read(json)).data

        #expect(data.additionalColorHexes == ["00FF00"])
    }
}
