import Testing
@testable import SpoolKid

@MainActor
struct OCRReviewRoutingTests {
    @Test func reviewOutcomeRetakeSmartScanMapsToRetakeDestination() {
        let outcome = OCRReviewOutcome.retakeSmartScan
        #expect(outcome.destination == .retakeSmartScan)
    }

    @Test func reviewOutcomeScanHubCarriesScanResult() {
        let tagData = FilamentTagData(
            name: "Matte PLA",
            material: "PLA",
            subtype: "Matte",
            brand: "Polymaker",
            colorHex: "112233",
            minNozzleTemp: 200,
            maxNozzleTemp: 220,
            minBedTemp: 55,
            maxBedTemp: 65,
            nominalNetWeight: 1000
        )
        let result = ScanResult(
            cardUID: nil,
            tagData: tagData,
            format: .ocr,
            ocrSerialNumber: "SN-12345",
            ocrDiameterMM: 2.85,
            ocrFilamentName: "Matte PLA",
            ocrSubtype: "Matte",
            ocrNominalNetWeightG: 1000
        )
        let outcome = OCRReviewOutcome.proceedToScanHub(result)
        #expect(outcome.destination == .scanHub)

        switch outcome {
        case .proceedToScanHub(let carried):
            #expect(carried.ocrSerialNumber == "SN-12345")
            #expect(carried.ocrDiameterMM == 2.85)
            #expect(carried.ocrFilamentName == "Matte PLA")
            #expect(carried.ocrSubtype == "Matte")
            #expect(carried.ocrNominalNetWeightG == 1000)
            #expect(carried.tagData?.name == "Matte PLA")
            #expect(carried.tagData?.subtype == "Matte")
            #expect(carried.tagData?.nominalNetWeight == 1000)
        default:
            Issue.record("Expected proceedToScanHub outcome")
        }
    }

    @Test func scanResultOCRMetadataDefaultsToNil() {
        let result = ScanResult(cardUID: nil, tagData: nil, format: .ocr)

        #expect(result.ocrSerialNumber == nil)
        #expect(result.ocrDiameterMM == nil)
        #expect(result.ocrFilamentName == nil)
        #expect(result.ocrSubtype == nil)
        #expect(result.ocrNominalNetWeightG == nil)
    }

    @Test func autoRegisterResultNormalizesNetWeightConsistentlyAcrossOutputs() {
        let candidate = OCRParsedCandidate(confidenceByField: [:], rawLines: [])
        let tagData = FilamentTagData(
            name: "Matte PLA",
            material: "PLA",
            subtype: "Matte",
            brand: "Polymaker",
            colorHex: "112233",
            minNozzleTemp: 200,
            maxNozzleTemp: 220,
            minBedTemp: 55,
            maxBedTemp: 65,
            nominalNetWeight: nil
        )

        let result = OCRReviewView.buildScanResult(
            candidate: candidate,
            tagData: tagData,
            serialNumber: "SN-12345",
            diameterMM: "2.85",
            filamentName: "Matte PLA",
            subtype: "Matte",
            netWeightG: " 1000 "
        )

        #expect(result.tagData?.nominalNetWeight == 1000)
        #expect(result.ocrNominalNetWeightG == 1000)
        #expect(result.tagData?.nominalNetWeight == result.ocrNominalNetWeightG)
    }

    @Test func candidateSupportsExpandedOCRFields() {
        let candidate = OCRParsedCandidate(
            subtype: "PLA+",
            filamentName: "Basic PLA",
            netWeightG: 1000,
            isBedTempInferred: true,
            confidenceByField: [
                .subtype: .high,
                .filamentName: .medium,
                .netWeightG: .low,
                .isBedTempInferred: .high
            ],
            rawLines: ["PLA+", "Basic PLA", "Net Wt 1000g"]
        )

        #expect(candidate.subtype == "PLA+")
        #expect(candidate.filamentName == "Basic PLA")
        #expect(candidate.netWeightG == 1000)
        #expect(candidate.isBedTempInferred == true)
        #expect(candidate.confidenceByField[.subtype] == .high)
        #expect(candidate.confidenceByField[.filamentName] == .medium)
        #expect(candidate.confidenceByField[.netWeightG] == .low)
        #expect(candidate.confidenceByField[.isBedTempInferred] == .high)
    }

    @Test func candidateExpandedOCRFieldsDefaultToNilOrFalse() {
        let candidate = OCRParsedCandidate(confidenceByField: [:], rawLines: [])

        #expect(candidate.subtype == nil)
        #expect(candidate.filamentName == nil)
        #expect(candidate.netWeightG == nil)
        #expect(candidate.isBedTempInferred == false)
    }
}
