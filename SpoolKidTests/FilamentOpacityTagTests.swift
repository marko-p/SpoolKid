//
//  FilamentOpacityTagTests.swift
//  SpoolKidTests
//
//  Alpha on each tag format that carries one, per the 2026-11-07 filament
//  opacity spec: translucent data writes it, opaque data writes today's bytes.
//

import Testing
import Foundation
@testable import SpoolKid

struct FilamentOpacityTagTests {
    private func filament(alpha: Int?, extras: [String]? = nil, td: Double? = 5) -> FilamentTagData {
        FilamentTagData(
            material: "PLA", brand: "Polar", colorHex: "1A2B3C", additionalColorHexes: extras,
            minNozzleTemp: 200, maxNozzleTemp: 220, minBedTemp: 55, maxBedTemp: 65,
            transmissionDistance: td, colorAlpha: alpha
        )
    }

    private func tigerBytes(_ data: FilamentTagData) -> [UInt8] {
        TigerTagPayload.encodePages(from: data, date: Date(timeIntervalSince1970: 1_800_000_000))
            .sorted { $0.page < $1.page }.flatMap { Array($0.data) }
    }

    private func openSpoolText(_ data: FilamentTagData) throws -> String {
        let payload = try #require(TagFormatService.shared.encode(data: data, format: .openSpool))
        return try #require(String(data: payload, encoding: .utf8))
    }

    private func openSpoolRead(_ json: String) -> FilamentTagData? {
        TagFormatService.shared.decode(payload: Data(json.utf8), mimeType: "application/json")
    }

    // MARK: TigerTag

    @Test func tigerTagWritesAndReadsAlpha() throws {
        let bytes = tigerBytes(filament(alpha: 94))
        #expect(bytes[19] == 0x5E)
        let read = try #require(TigerTagPayload.decode(from: bytes))
        #expect(read.colorAlpha == 94)
        #expect(read.transmissionDistance == 5)
    }

    @Test func tigerTagOpaqueIsUnchanged() throws {
        let bytes = tigerBytes(filament(alpha: nil))
        #expect(bytes[19] == 0xFF)
        #expect(try #require(TigerTagPayload.decode(from: bytes)).colorAlpha == nil)
    }

    @Test func tigerTagExtraColorsLeaveTheirNeighboursAlone() {
        let bytes = tigerBytes(filament(alpha: 94, extras: ["112233", "445566"]))
        #expect(bytes[39] == tigerBytes(filament(alpha: nil, extras: ["112233", "445566"]))[39])
        #expect(bytes[43] == 0)
    }

    @Test func aBlankAlphaByteReadsOpaque() throws {
        var bytes = tigerBytes(filament(alpha: nil))
        bytes[19] = 0
        #expect(try #require(TigerTagPayload.decode(from: bytes)).colorAlpha == nil)
    }

    // MARK: OpenTag3D

    @Test func openTag3DWritesAlphaOnEveryColor() throws {
        let data = filament(alpha: 94, extras: ["112233"])
        let bytes = Array(try #require(OpenTag3DPayload.encode(from: data)))
        #expect(bytes[0x3F] == 0x5E)
        #expect(bytes[0x43] == 0x5E)
        #expect(bytes[0x47] == 0)
        #expect(try #require(OpenTag3DPayload.decode(from: Data(bytes))).colorAlpha == 94)
    }

    @Test func openTag3DOpaqueIsUnchanged() throws {
        let bytes = Array(try #require(OpenTag3DPayload.encode(from: filament(alpha: nil))))
        #expect(bytes[0x3F] == 0xFF)
        #expect(try #require(OpenTag3DPayload.decode(from: Data(bytes))).colorAlpha == nil)
    }

    // MARK: OpenPrintTag

    @Test func openPrintTagWritesFourByteColors() throws {
        let payload = try #require(OpenPrintTagPayload.encode(from: filament(alpha: 94)))
        // Key 19, then a four-byte string.
        #expect(payload.range(of: Data([0x13, 0x44, 0x1A, 0x2B, 0x3C, 0x5E])) != nil)
        let read = try #require(OpenPrintTagPayload.decode(from: payload))
        #expect(read.colorAlpha == 94)
        #expect(read.colorHex == "1A2B3C")
        #expect(read.transmissionDistance == 5)
    }

    @Test func openPrintTagMultiColorCarriesAlphaOnEachColor() throws {
        let payload = try #require(OpenPrintTagPayload.encode(from: filament(alpha: 94, extras: ["112233"])))
        #expect(payload.range(of: Data([0x14, 0x44, 0x1A, 0x2B, 0x3C, 0x5E])) != nil)
        #expect(payload.range(of: Data([0x15, 0x44, 0x11, 0x22, 0x33, 0x5E])) != nil)
        #expect(try #require(OpenPrintTagPayload.decode(from: payload)).colorAlpha == 94)
    }

    @Test func openPrintTagOpaqueKeepsThreeBytes() throws {
        let payload = try #require(OpenPrintTagPayload.encode(from: filament(alpha: nil)))
        #expect(payload.range(of: Data([0x13, 0x43, 0x1A, 0x2B, 0x3C])) != nil)
        #expect(try #require(OpenPrintTagPayload.decode(from: payload)).colorAlpha == nil)
    }

    // MARK: OpenSpool

    @Test func openSpoolWritesAHexString() throws {
        let text = try openSpoolText(filament(alpha: 94))
        #expect(text.contains("\"alpha\":\"5E\""))
        #expect(openSpoolRead(text)?.colorAlpha == 94)
    }

    @Test func openSpoolOpaqueHasNoAlphaKey() throws {
        #expect(!(try openSpoolText(filament(alpha: nil))).contains("alpha"))
    }

    @Test(arguments: [
        ("\"8C\"", 140), ("\"8c\"", 140), ("\"140\"", 140), ("140", 140),
        ("\"FF\"", nil), ("255", nil), ("\"ZZ\"", nil), ("true", nil), ("300", nil), ("\"\"", nil)
    ] as [(String, Int?)])
    func openSpoolReadsEveryWritersAlpha(raw: String, expected: Int?) throws {
        let json = #"{"protocol":"openspool","version":"1.0","type":"PLA","color_hex":"1A2B3C","alpha":\#(raw)}"#
        let read = try #require(openSpoolRead(json))
        #expect(read.colorAlpha == expected)
        #expect(read.material == "PLA")
    }

    // MARK: Model

    // FilamentTagData's Codable conformance is main-actor isolated.
    @MainActor @Test func recentTagsSavedBeforeAlphaStillLoad() throws {
        let saved = try JSONEncoder().encode(filament(alpha: nil))
        let read = try JSONDecoder().decode(FilamentTagData.self, from: saved)
        #expect(read.colorAlpha == nil)
        #expect(String(data: saved, encoding: .utf8)?.contains("color_alpha") == false)
    }

    @MainActor @Test func recentTagsKeepTheirAlpha() throws {
        let saved = try JSONEncoder().encode(filament(alpha: 94))
        #expect(try JSONDecoder().decode(FilamentTagData.self, from: saved).colorAlpha == 94)
    }

    @Test func opacityTextOnlyForTranslucentData() {
        #expect(filament(alpha: 140).opacityText == "Opacity 55%")
        #expect(filament(alpha: nil).opacityText == nil)
    }
}
