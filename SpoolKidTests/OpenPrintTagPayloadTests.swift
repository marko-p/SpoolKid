import Foundation
import Testing
@testable import SpoolKid

struct OpenPrintTagPayloadTests {
    @Test func mapsSpoolmanStyleMaterialAliasToOpenPrintTagType() {
        let source = FilamentTagData(
            name: "Alias material",
            material: "Flexible (TPU)",
            brand: "SpoolKid",
            colorHex: "000000",
            minNozzleTemp: 220,
            maxNozzleTemp: 240,
            minBedTemp: 45,
            maxBedTemp: 60,
            openPrintTagMaterialTypeID: nil
        )

        guard let encoded = OpenPrintTagPayload.encode(from: source),
              let decoded = OpenPrintTagPayload.decodeDataModel(from: encoded) else {
            Issue.record("Alias encode/decode failed")
            return
        }

        #expect(decoded.materialTypeID == 2)
        #expect(decoded.materialTypeName == "TPU")
    }

    @Test func encodesAndDecodesExtendedOptionalFields() {
        let payload = OpenPrintTagPayload.DataModel(
            materialClassID: 0,
            materialTypeID: 0,
            materialClassName: "FFF",
            materialTypeName: "PLA",
            materialName: "Test PLA",
            brandName: "SpoolKid",
            manufacturedDateUnix: 1_704_067_200,
            nominalNetWeightGrams: 1000,
            actualNetWeightGrams: 995.5,
            emptyContainerWeightGrams: 250,
            primaryColorRGBA: [0x12, 0x34, 0x56, 0xFF],
            transmissionDistance: 6.6,
            tags: [1, 4, 7],
            density: 1.24,
            minPrintTempC: 200,
            maxPrintTempC: 220,
            preheatTempC: 170,
            minBedTempC: 55,
            maxBedTempC: 65,
            gtin: "8594173675001",
            countryOfOrigin: "SI",
            certifications: [0, 1],
            dryingTempC: 45,
            dryingTimeMinutes: 480
        )

        guard let encoded = OpenPrintTagPayload.encode(dataModel: payload) else {
            Issue.record("Encoding failed")
            return
        }

        guard let decoded = OpenPrintTagPayload.decodeDataModel(from: encoded) else {
            Issue.record("Decoding failed")
            return
        }

        #expect(decoded.materialName == "Test PLA")
        #expect(decoded.manufacturedDateUnix == 1_704_067_200)
        #expect(decoded.nominalNetWeightGrams == 1000)
        #expect(decoded.actualNetWeightGrams == 995.5)
        #expect(decoded.emptyContainerWeightGrams == 250)
        #expect(approxEqual(decoded.transmissionDistance, 6.6, tolerance: 0.000_01))
        #expect(approxEqual(decoded.density, 1.24, tolerance: 0.000_01))
        #expect(decoded.tags == [1, 4, 7])
        #expect(decoded.certifications == [0, 1])
        #expect(decoded.gtin == "8594173675001")
        #expect(decoded.countryOfOrigin == "SI")
        #expect(decoded.preheatTempC == 170)
        #expect(decoded.dryingTempC == 45)
        #expect(decoded.dryingTimeMinutes == 480)
        #expect(decoded.materialClassID == 0)
        #expect(decoded.materialTypeID == 0)
        #expect(decoded.materialTypeName == "PLA")
    }

    @Test func expandsImpliedMaterialTagsAndCapsCertifications() {
        let payload = OpenPrintTagPayload.DataModel(
            materialClassID: 0,
            materialTypeID: 0,
            materialClassName: "FFF",
            materialTypeName: "PLA",
            materialName: "Implication Test",
            brandName: "SpoolKid",
            manufacturedDateUnix: nil,
            nominalNetWeightGrams: nil,
            actualNetWeightGrams: nil,
            emptyContainerWeightGrams: nil,
            primaryColorRGBA: [0x00, 0x00, 0x00, 0xFF],
            transmissionDistance: nil,
            tags: [42],
            density: nil,
            minPrintTempC: 200,
            maxPrintTempC: 220,
            preheatTempC: nil,
            minBedTempC: 50,
            maxBedTempC: 60,
            gtin: nil,
            countryOfOrigin: nil,
            certifications: [2, 1, 0, 2, 99, 1, 0, 2, 1],
            dryingTempC: nil,
            dryingTimeMinutes: nil
        )

        guard let encoded = OpenPrintTagPayload.encode(dataModel: payload),
              let decoded = OpenPrintTagPayload.decodeDataModel(from: encoded) else {
            Issue.record("Encode/decode failed")
            return
        }

        #expect(decoded.tags.contains(42))
        #expect(decoded.tags.contains(41))
        #expect(decoded.tags.contains(38))
        #expect(decoded.certifications == [2, 1, 0])
    }

    private func approxEqual(_ lhs: Double?, _ rhs: Double, tolerance: Double) -> Bool {
        guard let lhs else { return false }
        return abs(lhs - rhs) <= tolerance
    }
}
