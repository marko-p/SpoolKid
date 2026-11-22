//
//  OpenPrintTagAuxTests.swift
//  SpoolKidTests
//
//  What a Prusa printer leaves on an OpenPrintTag as it prints: aux-region
//  `consumed_weight` (aux key 0, grams), which SpoolKid reads next to the
//  main section's `filament_diameter` (key 30). The fixture is the owner's
//  Prusament record 2 (text-OpenPrintTag_Prusament.txt): meta `A1 02 18 D2`
//  puts the aux region at payload offset 210, where `A0` followed by zeros
//  runs to the payload's end at 245.
//

import Foundation
import Testing
@testable import SpoolKid

struct OpenPrintTagAuxTests {

    /// The owner's Prusament ASA Signal White, 245 bytes, aux region empty.
    static let prusament = Data(hex: "A10218D2BF041B000007D0FCAB4796056A34636533643337663162080009040A70415341205369676E616C2057686974650B6950727573616D656E740E1A69A537371019032011190332121901151343E3DFD9181C9FFF181DF93C48182218FA182319010E182418AA1825186418261878182718371829185A182A1843182B18C8182C1865182D183318351A0004E18018361A0004FE0FFF" + String(repeating: "00", count: 58) + "A0" + String(repeating: "00", count: 34))

    /// The same tag after a printer wrote `consumed_weight` = 200.0 (f32) into
    /// the aux region the way its firmware encodes it: an indefinite map.
    static let prusamentAfterPrinting: Data = {
        var bytes = prusament
        bytes.replaceSubrange(210..<218, with: [0xBF, 0x00, 0xFA, 0x43, 0x48, 0x00, 0x00, 0xFF])
        return bytes
    }()

    private func blackPLA(nominal: Double?, actual: Double?, consumed: Double?) -> FilamentTagData {
        FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "000000",
            minNozzleTemp: 200, maxNozzleTemp: 220, minBedTemp: 50, maxBedTemp: 60,
            nominalNetWeight: nominal, actualNetWeight: actual, consumedWeight: consumed
        )
    }

    @Test func prusamentStillDecodesAndHasNoConsumption() throws {
        #expect(Self.prusament.count == 245)
        let tag = try #require(OpenPrintTagPayload.decode(from: Self.prusament))
        #expect(tag.material == "ASA")
        #expect(tag.brand == "Prusament")
        #expect(tag.nominalNetWeight == 800)
        #expect(tag.actualNetWeight == 818)
        #expect(tag.emptyContainerWeight == 277)
        #expect(tag.consumedWeight == nil)
        #expect(tag.remainingOnTag == nil)
    }

    @Test func auxConsumedWeightIsRead() throws {
        let tag = try #require(OpenPrintTagPayload.decode(from: Self.prusamentAfterPrinting))
        #expect(tag.consumedWeight == 200)
        #expect(tag.fullWeightOnTag == 818)
        #expect(tag.remainingOnTag == 618)
    }

    @Test func consumedWeightRules() {
        #expect(FilamentTagData.consumption(fullWeight: 1000, remaining: 600) == 400)
        #expect(FilamentTagData.consumption(fullWeight: 1000, remaining: 0) == 1000)
        #expect(FilamentTagData.consumption(fullWeight: 1000, remaining: 1000) == nil)
        #expect(FilamentTagData.consumption(fullWeight: 1000, remaining: 1200) == nil)
        #expect(FilamentTagData.consumption(fullWeight: 1000, remaining: nil) == nil)
        #expect(FilamentTagData.consumption(fullWeight: nil, remaining: 600) == nil)
        #expect(FilamentTagData.consumption(fullWeight: 0, remaining: 600) == nil)
        #expect(FilamentTagData.consumption(fullWeight: 1000, remaining: -5) == nil)
    }

    @Test func diameterRoundTripsOnOpenPrintTag() throws {
        let data = FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "FF0000",
            minNozzleTemp: 200, maxNozzleTemp: 220, minBedTemp: 50, maxBedTemp: 60,
            diameter: 1.75
        )
        let encoded = try #require(OpenPrintTagPayload.encode(from: data))
        let decoded = try #require(OpenPrintTagPayload.decode(from: encoded))
        let diameter = try #require(decoded.diameter)
        #expect(abs(diameter - 1.75) < 0.0001)
        #expect(decoded.consumedWeight == nil)
    }

    @Test func anUnstatedDiameterIsNotWritten() throws {
        let data = FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "FF0000",
            minNozzleTemp: 200, maxNozzleTemp: 220, minBedTemp: 50, maxBedTemp: 60,
            diameter: 0
        )
        let encoded = try #require(OpenPrintTagPayload.encode(from: data))
        #expect(try #require(OpenPrintTagPayload.decode(from: encoded)).diameter == nil)
    }

    @Test func hubCaption() throws {
        let us = Locale(identifier: "en_US")
        let printed = try #require(OpenPrintTagPayload.decode(from: Self.prusamentAfterPrinting))
        #expect(ScanResultHubView.tagRemainingCaption(for: printed, locale: us) == "On tag: 618 g of 818 g left")

        let nominalOnly = blackPLA(nominal: 1000, actual: nil, consumed: 388)
        #expect(ScanResultHubView.tagRemainingCaption(for: nominalOnly, locale: us) == "On tag: 612 g of 1,000 g left")

        let untouched = try #require(OpenPrintTagPayload.decode(from: Self.prusament))
        #expect(ScanResultHubView.tagRemainingCaption(for: untouched, locale: us) == nil)
        #expect(ScanResultHubView.tagRemainingCaption(for: nil, locale: us) == nil)
    }

    /// A half-float NaN or infinity in the aux map is a damaged tag, not a
    /// weight: it reads as no consumption rather than reaching the caption.
    @Test func aNonFiniteConsumedWeightReadsAsNone() throws {
        for aux in [[0xBF, 0x00, 0xF9, 0x7E, 0x00, 0xFF], [0xBF, 0x00, 0xF9, 0x7C, 0x00, 0xFF]] as [[UInt8]] {
            var bytes = Self.prusament
            bytes.replaceSubrange(210..<(210 + aux.count), with: aux)
            let tag = try #require(OpenPrintTagPayload.decode(from: bytes))
            #expect(tag.consumedWeight == nil)
            #expect(ScanResultHubView.tagRemainingCaption(for: tag, locale: Locale(identifier: "en_US")) == nil)
        }
    }

    /// A negative consumption would put the remaining above the full weight
    /// ("1,050 g of 1,000 g left"), so it reads as no consumption.
    @Test func aNegativeConsumedWeightReadsAsNone() throws {
        var bytes = Self.prusament
        // consumed_weight = -50.0 (f32 C2480000).
        bytes.replaceSubrange(210..<218, with: [0xBF, 0x00, 0xFA, 0xC2, 0x48, 0x00, 0x00, 0xFF])
        let tag = try #require(OpenPrintTagPayload.decode(from: bytes))
        #expect(tag.consumedWeight == nil)
        #expect(tag.remainingOnTag == nil)
    }

    /// A half-float NaN as a meta offset is a damaged tag, not a reason to
    /// trap: the aux offset reads as absent and the main section still decodes.
    @Test func aNaNMetaOffsetDoesNotCrashTheReader() throws {
        // meta {2: NaN}, then main {10: "PLA"}.
        let bytes = Data([0xA1, 0x02, 0xF9, 0x7E, 0x00, 0xA1, 0x0A, 0x63, 0x50, 0x4C, 0x41])
        let tag = try #require(OpenPrintTagPayload.decode(from: bytes))
        #expect(tag.material == "PLA")
        #expect(tag.consumedWeight == nil)
    }

    @Test func remainingNeverGoesBelowZero() {
        #expect(blackPLA(nominal: 1000, actual: nil, consumed: 1200).remainingOnTag == 0)
    }

    @Test func remainingNeedsAFullWeight() {
        #expect(blackPLA(nominal: nil, actual: nil, consumed: 200).remainingOnTag == nil)
        #expect(blackPLA(nominal: 0, actual: 0, consumed: 200).remainingOnTag == nil)
    }
}

private extension Data {
    /// Hex-string initializer for fixtures; whitespace is ignored.
    init(hex: String) {
        self.init([UInt8](hex: hex))
    }
}
