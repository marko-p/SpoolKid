//
//  TagFormatServiceDecodeTests.swift
//  SpoolKidTests
//
//  A scan's format is the format whose decoder read the record. Reading it
//  off the MIME type alone left every OpenSpool tag formatless, because
//  OpenSpool rides on plain "application/json": Inspect Tag called it
//  "Unknown tag format" and Recent Tags remembered no format for it.
//

import Testing
import Foundation
@testable import SpoolKid

@MainActor
struct TagFormatServiceDecodeTests {

    /// The record of an NTAG215 written by an older SpoolKid (owner's scan,
    /// 2026-10-17), byte for byte.
    static let fieldOpenSpoolJSON = #"{"protocol":"openspool","version":"1.0","type":"PETG","subtype":"Basic","color_hex":"313131","brand":"AzureFilm","min_temp":"230","max_temp":"240","bed_min_temp":"80","bed_max_temp":"85","spool_id":30}"#

    static let sample = FilamentTagData(
        name: "Galaxy Black", material: "PLA", brand: "Prusament", colorHex: "3D3E3D",
        minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60
    )

    @Test func theFieldOpenSpoolTagIsReadAsOpenSpool() throws {
        let result = try #require(TagFormatService.shared.decodeDetectingFormat(
            payload: Data(Self.fieldOpenSpoolJSON.utf8), mimeType: "application/json"
        ))
        #expect(result.format == .openSpool)
        #expect(result.data.brand == "AzureFilm")
        #expect(result.data.spoolmanId == 30)
    }

    @Test(arguments: [TagFormat.openSpool, .openPrintTag, .openTag3D])
    func everyNDEFFormatSpoolKidWritesIsReadBackAsItself(format: TagFormat) throws {
        let payload = try #require(TagFormatService.shared.encode(data: Self.sample, format: format))
        let result = try #require(TagFormatService.shared.decodeDetectingFormat(
            payload: payload, mimeType: format.mimeType
        ))
        #expect(result.format?.tagFormat == format)
    }

    /// The pre-OpenSpool SpoolKid JSON decodes, but it is no format of its own.
    @Test func legacySpoolKidJSONDecodesWithoutAFormat() throws {
        let payload = try JSONEncoder().encode(Self.sample)
        let result = try #require(TagFormatService.shared.decodeDetectingFormat(
            payload: payload, mimeType: "application/json"
        ))
        #expect(result.format == nil)
        #expect(result.data.brand == "Prusament")
    }

    static let multiColorSample = FilamentTagData(
        material: "PLA", brand: "Prusament", colorHex: "2D39C9", additionalColorHexes: ["A51A52"],
        minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60
    )

    @Test func writesAdditionalColorsAfterColorHex() throws {
        let payload = try #require(TagFormatService.shared.encode(data: Self.multiColorSample, format: .openSpool))
        let json = try #require(String(data: payload, encoding: .utf8))
        #expect(json.contains(#""color_hex":"2D39C9","additional_color_hexes":["A51A52"]"#))
    }

    /// The single-color record is byte-identical to the one written before
    /// additional colors existed: no key, same field order.
    @Test func singleColorBytesAreUnchanged() throws {
        let single = FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "3D3E3D",
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60
        )
        let payload = try #require(TagFormatService.shared.encode(data: single, format: .openSpool))
        #expect(String(data: payload, encoding: .utf8) == #"{"protocol":"openspool","version":"1.0","type":"PLA","color_hex":"3D3E3D","brand":"Prusament","min_temp":"205","max_temp":"225","bed_min_temp":"50","bed_max_temp":"60"}"#)
    }

    /// Six colors in all: the primary and four more. The fifth extra is dropped.
    @Test func capsAdditionalColorsAtFour() throws {
        let six = FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "111111",
            additionalColorHexes: ["222222", "333333", "444444", "555555", "666666"],
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60
        )
        let payload = try #require(TagFormatService.shared.encode(data: six, format: .openSpool))
        let json = try #require(String(data: payload, encoding: .utf8))
        #expect(json.contains(#""additional_color_hexes":["222222","333333","444444","555555"]"#))
    }

    @Test func decodeReturnsWhatDecodeDetectingFormatRead() throws {
        let payload = Data(Self.fieldOpenSpoolJSON.utf8)
        let decoded = try #require(TagFormatService.shared.decode(payload: payload, mimeType: "application/json"))
        #expect(decoded.spoolmanId == 30)
    }

    @Test func aStoredAlphaExtraIsWrittenAsRGB() throws {
        let data = FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "2D39C9", additionalColorHexes: ["A51A52FF"],
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60
        )
        let payload = try #require(TagFormatService.shared.encode(data: data, format: .openSpool))
        let json = try #require(String(data: payload, encoding: .utf8))
        #expect(json.contains(#""additional_color_hexes":["A51A52"]"#))
        #expect(!json.contains("A51A52FF"))
    }
}
