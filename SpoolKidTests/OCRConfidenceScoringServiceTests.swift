import Testing
@testable import SpoolKid

struct OCRConfidenceScoringServiceTests {
    @Test func scoreSetsHighConfidenceForStrongStructuredFields() {
        var candidate = OCRParsedCandidate(
            material: "ASA",
            brand: "Polymaker",
            colorHex: "000000",
            serialNumber: "PMK-12345",
            diameterMM: 1.75,
            minNozzleTemp: 250,
            maxNozzleTemp: 270,
            minBedTemp: 90,
            maxBedTemp: 110,
            wasNozzleExplicitlyLabeled: true,
            wasBedExplicitlyLabeled: true,
            confidenceByField: [:],
            rawLines: ["Nozzle 250-270C", "Bed 90-110C"]
        )

        candidate = OCRConfidenceScoringService.annotate(candidate: candidate)

        #expect(candidate.confidenceByField[.material] == .high)
        #expect(candidate.confidenceByField[.brand] == .high)
        #expect(candidate.confidenceByField[.serialNumber] == .high)
        #expect(candidate.confidenceByField[.diameterMM] == .medium)
        #expect(candidate.confidenceByField[.minNozzleTemp] == .high)
        #expect(candidate.confidenceByField[.minBedTemp] == .high)
    }

    @Test func scoreUsesMediumConfidenceForUnlabeledHeuristicTemperatures() {
        var candidate = OCRParsedCandidate(
            material: "PLA",
            brand: nil,
            colorHex: nil,
            minNozzleTemp: 190,
            maxNozzleTemp: 220,
            minBedTemp: 55,
            maxBedTemp: 55,
            confidenceByField: [:],
            rawLines: ["190-220C", "55C"]
        )

        candidate = OCRConfidenceScoringService.annotate(candidate: candidate)

        #expect(candidate.confidenceByField[.minNozzleTemp] == .medium)
        #expect(candidate.confidenceByField[.maxNozzleTemp] == .medium)
        #expect(candidate.confidenceByField[.minBedTemp] == .medium)
        #expect(candidate.confidenceByField[.maxBedTemp] == .medium)
    }

    @Test func scoreIncludesNewExpandedFields() {
        var candidate = OCRParsedCandidate(
            subtype: "PLA+",
            filamentName: "Pro PLA",
            netWeightG: 1000,
            confidenceByField: [:],
            rawLines: ["PLA+", "Pro PLA", "Net Wt 1000g"]
        )

        candidate = OCRConfidenceScoringService.annotate(candidate: candidate)

        #expect(candidate.confidenceByField[.subtype] == .high)
        #expect(candidate.confidenceByField[.filamentName] == .high)
        #expect(candidate.confidenceByField[.netWeightG] == .medium)
    }

    @Test func scoreUsesLowConfidenceForInferredBedTemperatures() {
        var candidate = OCRParsedCandidate(
            minNozzleTemp: 205,
            maxNozzleTemp: 215,
            minBedTemp: 60,
            maxBedTemp: 70,
            isBedTempInferred: true,
            wasNozzleExplicitlyLabeled: true,
            confidenceByField: [:],
            rawLines: ["Nozzle 205-215C", "60-70C"]
        )

        candidate = OCRConfidenceScoringService.annotate(candidate: candidate)

        #expect(candidate.confidenceByField[.minNozzleTemp] == .high)
        #expect(candidate.confidenceByField[.maxNozzleTemp] == .high)
        #expect(candidate.confidenceByField[.minBedTemp] == .low)
        #expect(candidate.confidenceByField[.maxBedTemp] == .low)
    }

    @Test func scoreSetsNoneForMissingTemperatureSideWhenOnlyOneValueParsed() {
        var candidate = OCRParsedCandidate(
            minNozzleTemp: 205,
            maxNozzleTemp: nil,
            minBedTemp: nil,
            maxBedTemp: 65,
            confidenceByField: [:],
            rawLines: ["Nozzle 205C", "Bed 65C"]
        )

        candidate = OCRConfidenceScoringService.annotate(candidate: candidate)

        #expect(candidate.confidenceByField[.minNozzleTemp] != nil)
        #expect(candidate.confidenceByField[.maxNozzleTemp] == OCRFieldConfidence.none)
        #expect(candidate.confidenceByField[.minBedTemp] == OCRFieldConfidence.none)
        #expect(candidate.confidenceByField[.maxBedTemp] != nil)
    }

    @Test func scoreTreatsLabeledBedRangeAsHighConfidence() {
        var candidate = OCRParsedCandidate(
            minBedTemp: 40,
            maxBedTemp: 100,
            wasBedExplicitlyLabeled: true,
            confidenceByField: [:],
            rawLines: ["Bed 40-100C"]
        )

        candidate = OCRConfidenceScoringService.annotate(candidate: candidate)

        #expect(candidate.confidenceByField[.minBedTemp] == .high)
        #expect(candidate.confidenceByField[.maxBedTemp] == .high)
    }

    @Test func scoreIncludesIsBedTempInferredConfidenceKey() {
        var candidate = OCRParsedCandidate(
            minBedTemp: 60,
            maxBedTemp: 70,
            isBedTempInferred: true,
            confidenceByField: [:],
            rawLines: ["60-70C"]
        )

        candidate = OCRConfidenceScoringService.annotate(candidate: candidate)

        #expect(candidate.confidenceByField[.isBedTempInferred] == .high)
    }
}
