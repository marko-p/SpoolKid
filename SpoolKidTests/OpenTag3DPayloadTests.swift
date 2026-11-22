//
//  OpenTag3DPayloadTests.swift
//  SpoolKidTests
//
//  Pins the OpenTag3D binary memory map to the published specification
//  (github.com/GooborgStudios/OpenTag3D, `_data/spec.json`, version 2.001).
//  Every offset below is quoted from that file — these tests are the reason
//  the map cannot drift again, and they may not be edited without a matching
//  change in the spec itself.
//

import Testing
import Foundation
@testable import SpoolKid

struct OpenTag3DPayloadTests {

    /// Temperatures chosen so the ÷5 encoding is lossless in both directions,
    /// and so the target temps (the midpoints) are distinct from min and max.
    private static let sample = FilamentTagData(
        name: "Galaxy Black",
        material: "PLA",
        subtype: "CF",
        brand: "Polar Filament",
        colorHex: "1A2B3C",
        minNozzleTemp: 200,
        maxNozzleTemp: 220,
        minBedTemp: 55,
        maxBedTemp: 65,
        density: 1.24,
        diameter: 1.75,
        nominalNetWeight: 1000
    )

    private func encoded(_ data: FilamentTagData = sample) throws -> [UInt8] {
        Array(try #require(OpenTag3DPayload.encode(from: data)))
    }

    private func uint16(_ bytes: [UInt8], at offset: Int) -> Int {
        Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
    }

    private func string(_ bytes: [UInt8], at offset: Int, length: Int) -> String {
        let slice = Array(bytes[offset..<(offset + length)])
        let end = slice.firstIndex(of: 0) ?? slice.count
        return String(bytes: slice[0..<end], encoding: .utf8) ?? ""
    }

    // MARK: - Tag version

    /// The reported bug: the version is "an int with 3 implied decimal points",
    /// so v2.001 is the integer 2001. SpoolKid used to write 0x0100 — 256,
    /// which reads as version 0.256 and is refused by conformant parsers.
    @Test func tagVersionIsAnIntegerWithThreeImpliedDecimals() throws {
        let bytes = try encoded()
        #expect(uint16(bytes, at: 0x00) == 2001)
    }

    // MARK: - Memory map

    @Test func stringFieldsSitAtTheirSpecOffsets() throws {
        let bytes = try encoded()
        #expect(string(bytes, at: 0x02, length: 5) == "PLA")            // material
        #expect(string(bytes, at: 0x07, length: 5) == "CF")             // material_mod
        #expect(string(bytes, at: 0x0C, length: 16) == "Polar Filament") // manufacturer
        #expect(string(bytes, at: 0x1C, length: 32) == "Galaxy Black")  // color_name
    }

    @Test func colorOneIsRGBAAtItsSpecOffset() throws {
        let bytes = try encoded()
        #expect(Array(bytes[0x3C..<0x40]) == [0x1A, 0x2B, 0x3C, 0xFF])
    }

    @Test func temperaturesSitAtTheirSpecOffsetsScaledByFive() throws {
        let bytes = try encoded()
        #expect(bytes[0x90] == 42)  // print_temp: target 210°C
        #expect(bytes[0x91] == 40)  // min_print_temp: 200°C
        #expect(bytes[0x92] == 44)  // max_print_temp: 220°C
        #expect(bytes[0x93] == 0)   // chamber_temp: not modelled — no heated chamber
        #expect(bytes[0x94] == 12)  // bed_temp: target 60°C
        #expect(bytes[0x95] == 11)  // min_bed_temp: 55°C
        #expect(bytes[0x96] == 13)  // max_bed_temp: 65°C
    }

    /// The target is the range's midpoint to the nearest 5 °C, not truncated:
    /// 185–200 °C targets 195 (byte 39), where it used to write 190.
    @Test func targetTemperatureIsTheRoundedMidpoint() throws {
        var data = Self.sample
        data.minNozzleTemp = 185
        data.maxNozzleTemp = 200
        data.minBedTemp = 80
        data.maxBedTemp = 85
        let bytes = try encoded(data)
        #expect(bytes[0x90] == 39)  // print_temp: 195°C
        #expect(bytes[0x94] == 17)  // bed_temp: 85°C
    }

    @Test func measurementsUseTheSpecScalingOfOneThousandth() throws {
        let bytes = try encoded()
        #expect(uint16(bytes, at: 0x8C) == 1750)  // diameter: 1.750 mm
        #expect(uint16(bytes, at: 0x9C) == 1240)  // density: 1.240 g/cm³
        #expect(uint16(bytes, at: 0x9E) == 1000)  // weight: 1000 g, unscaled
    }

    /// Every field the spec marks required must carry a non-zero value, or a
    /// reader is entitled to treat the tag as incomplete.
    @Test func everyRequiredFieldIsWritten() throws {
        let bytes = try encoded()
        #expect(uint16(bytes, at: 0x00) != 0)                    // tag_version
        #expect(!string(bytes, at: 0x02, length: 5).isEmpty)     // material
        #expect(!string(bytes, at: 0x0C, length: 16).isEmpty)    // manufacturer
        #expect(Array(bytes[0x3C..<0x40]) != [0, 0, 0, 0])       // color_1
        #expect(uint16(bytes, at: 0x8C) != 0)                    // diameter
        #expect(bytes[0x90] != 0)                                // print_temp
        #expect(bytes[0x94] != 0)                                // bed_temp
        #expect(uint16(bytes, at: 0x9C) != 0)                    // density
        #expect(uint16(bytes, at: 0x9E) != 0)                    // weight
    }

    /// The payload must reach the last required field (weight, 0x9E–0x9F).
    @Test func payloadCoversEveryRequiredField() throws {
        #expect(try encoded().count >= 0xA0)
    }

    /// Fields SpoolKid does not carry are left as 0x00, which the spec defines
    /// as the value of an absent byte — not filled with a guess.
    @Test func unwrittenFieldsAreLeftZero() throws {
        let bytes = try encoded()
        #expect(Array(bytes[0x40..<0x4C]).allSatisfy { $0 == 0 })  // colors 2–4
        #expect(Array(bytes[0x4C..<0x6C]).allSatisfy { $0 == 0 })  // serial
        #expect(Array(bytes[0x84..<0x8C]).allSatisfy { $0 == 0 })  // mfg date/time
    }

    // MARK: - Defaults for fields the write form does not collect

    @Test(arguments: [nil, 0.0] as [Double?])
    func diameterDensityAndWeightFallBackToDefaults(_ blank: Double?) throws {
        var data = Self.sample
        data.diameter = blank
        data.nominalNetWeight = blank
        data.density = blank
        let bytes = try encoded(data)
        #expect(uint16(bytes, at: 0x8C) == Int((AppConfig.Defaults.diameter * 1000).rounded()))
        #expect(uint16(bytes, at: 0x9C) == Int((AppConfig.Defaults.density * 1000).rounded()))
        #expect(uint16(bytes, at: 0x9E) == Int(AppConfig.Defaults.nominalNetWeight.rounded()))
    }

    // MARK: - Round trip

    @Test func roundTripsEveryFieldItWrites() throws {
        let payload = try #require(OpenTag3DPayload.encode(from: Self.sample))
        let decoded = try #require(OpenTag3DPayload.decode(from: payload))

        #expect(decoded.material == "PLA")
        #expect(decoded.subtype == "CF")
        #expect(decoded.brand == "Polar Filament")
        #expect(decoded.name == "Galaxy Black")
        #expect(decoded.colorHex == "1A2B3C")
        #expect(decoded.minNozzleTemp == 200)
        #expect(decoded.maxNozzleTemp == 220)
        #expect(decoded.minBedTemp == 55)
        #expect(decoded.maxBedTemp == 65)
        #expect(decoded.diameter == 1.75)
        #expect(decoded.density == 1.24)
        #expect(decoded.nominalNetWeight == 1000)
    }

    // MARK: - Version handling on read

    @Test func acceptsAVersionOneTag() throws {
        var bytes = try encoded()
        bytes[0x00] = 0x03; bytes[0x01] = 0xE8      // 1000 = v1.000
        #expect(OpenTag3DPayload.decode(from: Data(bytes)) != nil)
    }

    /// "Readers should reject tags with newer major versions."
    @Test func rejectsANewerMajorVersion() throws {
        var bytes = try encoded()
        bytes[0x00] = 0x0B; bytes[0x01] = 0xB8      // 3000 = v3.000
        #expect(OpenTag3DPayload.decode(from: Data(bytes)) == nil)
    }

    /// Tags written by SpoolKid before this fix carry 0x0100 (256, "v0.256")
    /// and an entirely different field layout. Decoding them with the spec
    /// offsets would report someone's colour name as their manufacturer, so
    /// they are refused outright and read as an unrecognised tag.
    @Test func rejectsThePreSpecLayoutSpoolKidUsedToWrite() throws {
        var bytes = [UInt8](repeating: 0, count: 0xB8)
        bytes[0x00] = 0x01; bytes[0x01] = 0x00
        bytes[0x02] = 0x50; bytes[0x03] = 0x4C; bytes[0x04] = 0x41  // "PLA"
        #expect(OpenTag3DPayload.decode(from: Data(bytes)) == nil)
    }

    @Test func rejectsAPayloadWithNoMaterial() throws {
        var bytes = try encoded()
        for i in 0x02..<0x07 { bytes[i] = 0 }
        #expect(OpenTag3DPayload.decode(from: Data(bytes)) == nil)
    }

    // MARK: - Short payloads

    /// "For any missing bytes … treat them as 0x00" — a tag that stops before
    /// the end of the map is legal, not a decode failure.
    @Test func treatsMissingTrailingBytesAsZero() throws {
        let bytes = try encoded()
        let truncated = Data(bytes[0..<0x40])
        let decoded = try #require(OpenTag3DPayload.decode(from: truncated))
        #expect(decoded.material == "PLA")
        #expect(decoded.brand == "Polar Filament")
        #expect(decoded.colorHex == "1A2B3C")
    }

    @Test func rejectsAPayloadTooShortToHoldAVersionAndMaterial() {
        #expect(OpenTag3DPayload.decode(from: Data([0x07, 0xD1, 0x50])) == nil)
    }

    // MARK: - Optional fields written since 2026-09-24
    //
    // Quoted from `_data/spec.json` (version 2.003; all four added in 1.000):
    //   mfg_date            0x84, 4 B — year (2 B), month (1 B), day (1 B)
    //   max_dry_temp        0x9A, 1 B — °C ÷ 5
    //   dry_time            0x9B, 1 B — hours
    //   empty_spool_weight  0xA0, 2 B — grams
    // SpoolKid's model keeps drying time in MINUTES (the write form's unit and
    // OpenPrintTag's), so the codec converts at the tag boundary.

    private static let withOptionalFields: FilamentTagData = {
        var data = sample
        data.dryingTemp = 70
        data.dryingTime = 240
        data.emptyContainerWeight = 105
        // 2024-01-23 00:00:00 UTC — the spec's own example date.
        data.manufacturedDateUnix = 1_705_968_000
        return data
    }()

    @Test func writesMaxDryTempAsCelsiusOverFive() throws {
        let bytes = try encoded(Self.withOptionalFields)
        #expect(bytes[0x9A] == 14)
    }

    @Test func writesDryTimeInWholeHours() throws {
        let bytes = try encoded(Self.withOptionalFields)
        #expect(bytes[0x9B] == 4)
    }

    /// A drying time under an hour is still a drying time: rounding it to 0
    /// would write "this tag does not say" for a value the user entered.
    @Test func aDryTimeUnderAnHourIsWrittenAsOneHour() throws {
        var data = Self.withOptionalFields
        data.dryingTime = 20
        let bytes = try encoded(data)
        #expect(bytes[0x9B] == 1)
    }

    @Test func writesManufactureDateAsYearMonthDay() throws {
        let bytes = try encoded(Self.withOptionalFields)
        #expect(uint16(bytes, at: 0x84) == 2024)
        #expect(bytes[0x86] == 1)
        #expect(bytes[0x87] == 23)
    }

    @Test func writesEmptySpoolWeightPastTheRequiredFields() throws {
        let bytes = try encoded(Self.withOptionalFields)
        try #require(bytes.count == 0xA2)
        #expect(uint16(bytes, at: 0xA0) == 105)
    }

    /// Without an empty-spool weight the payload stays exactly the size it
    /// was — tags written before this change are byte-identical to new ones.
    @Test func withoutAnEmptySpoolWeightThePayloadEndsAtTheRequiredFields() throws {
        let bytes = try encoded()
        #expect(bytes.count == 0xA0)
        #expect(bytes[0x84..<0x88].allSatisfy { $0 == 0 })
        #expect(bytes[0x9A] == 0)
        #expect(bytes[0x9B] == 0)
    }

    @Test func roundTripsTheOptionalFields() throws {
        let data = try #require(OpenTag3DPayload.encode(from: Self.withOptionalFields))
        let decoded = try #require(OpenTag3DPayload.decode(from: data))
        #expect(decoded.dryingTemp == 70)
        #expect(decoded.dryingTime == 240)
        #expect(decoded.emptyContainerWeight == 105)
        #expect(decoded.manufacturedDateUnix == 1_705_968_000)
    }

    @Test func absentOptionalFieldsDecodeAsNil() throws {
        let data = try #require(OpenTag3DPayload.encode(from: Self.sample))
        let decoded = try #require(OpenTag3DPayload.decode(from: data))
        #expect(decoded.dryingTemp == nil)
        #expect(decoded.dryingTime == nil)
        #expect(decoded.emptyContainerWeight == nil)
        #expect(decoded.manufacturedDateUnix == nil)
    }

    // MARK: - Colors 2-4

    private static let multiSample = FilamentTagData(
        material: "PLA", brand: "Prusament", colorHex: "2D39C9", additionalColorHexes: ["A51A52", "112233"],
        minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60
    )

    @Test func multiColorRoundTrips() throws {
        let payload = try #require(OpenTag3DPayload.encode(from: Self.multiSample))
        let decoded = try #require(OpenTag3DPayload.decode(from: payload))
        #expect(decoded.colors.hexes == ["2D39C9", "A51A52", "112233"])
    }

    @Test func colorTwoAndThreeAreRGBAAtTheirSpecOffsets() throws {
        let bytes = try encoded(Self.multiSample)
        #expect(Array(bytes[0x40..<0x44]) == [0xA5, 0x1A, 0x52, 0xFF])
        #expect(Array(bytes[0x44..<0x48]) == [0x11, 0x22, 0x33, 0xFF])
    }

    @Test func unusedSlotsAreTransparentBlack() throws {
        let bytes = try encoded()
        #expect(bytes[0x40..<0x4C].allSatisfy { $0 == 0 })
    }

    @Test func capsAtFourColors() throws {
        let six = FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "111111",
            additionalColorHexes: ["222222", "333333", "444444", "555555", "666666"],
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60
        )
        let payload = try #require(OpenTag3DPayload.encode(from: six))
        let decoded = try #require(OpenTag3DPayload.decode(from: payload))
        #expect(decoded.colors.hexes == ["111111", "222222", "333333", "444444"])
    }

    @Test func aStoredAlphaExtraIsWrittenAsRGB() throws {
        let data = FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "2D39C9", additionalColorHexes: ["A51A52FF"],
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60
        )
        let bytes = try encoded(data)
        #expect(Array(bytes[0x40..<0x44]) == [0xA5, 0x1A, 0x52, 0xFF])
        let decoded = try #require(OpenTag3DPayload.decode(from: Data(bytes)))
        #expect(decoded.colors.hexes == ["2D39C9", "A51A52"])
    }
}
