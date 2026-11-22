import Foundation

enum OCRConfidenceScoringService {
    static func annotate(candidate: OCRParsedCandidate) -> OCRParsedCandidate {
        var updated = candidate

        updated.confidenceByField[.material] = candidate.material == nil ? OCRFieldConfidence.none : .high
        updated.confidenceByField[.subtype] = candidate.subtype == nil ? OCRFieldConfidence.none : .high
        updated.confidenceByField[.brand] = candidate.brand == nil ? OCRFieldConfidence.none : .high
        updated.confidenceByField[.filamentName] = candidate.filamentName == nil ? OCRFieldConfidence.none : .high
        updated.confidenceByField[.colorHex] = candidate.colorHex == nil ? OCRFieldConfidence.none : .medium
        updated.confidenceByField[.serialNumber] = candidate.serialNumber == nil ? OCRFieldConfidence.none : .high
        updated.confidenceByField[.diameterMM] = candidate.diameterMM == nil ? OCRFieldConfidence.none : .medium
        updated.confidenceByField[.netWeightG] = candidate.netWeightG == nil ? OCRFieldConfidence.none : .medium
        updated.confidenceByField[.isBedTempInferred] = .high

        let nozzleConfidence = temperatureConfidence(
            min: candidate.minNozzleTemp,
            max: candidate.maxNozzleTemp,
            wasExplicitlyLabeled: candidate.wasNozzleExplicitlyLabeled
        )
        let bedConfidence: OCRFieldConfidence
        if candidate.isBedTempInferred {
            bedConfidence = (candidate.minBedTemp != nil || candidate.maxBedTemp != nil) ? .low : .none
        } else {
            bedConfidence = temperatureConfidence(
                min: candidate.minBedTemp,
                max: candidate.maxBedTemp,
                wasExplicitlyLabeled: candidate.wasBedExplicitlyLabeled
            )
        }

        updated.confidenceByField[.minNozzleTemp] = candidate.minNozzleTemp == nil ? .none : nozzleConfidence
        updated.confidenceByField[.maxNozzleTemp] = candidate.maxNozzleTemp == nil ? .none : nozzleConfidence
        updated.confidenceByField[.minBedTemp] = candidate.minBedTemp == nil ? .none : bedConfidence
        updated.confidenceByField[.maxBedTemp] = candidate.maxBedTemp == nil ? .none : bedConfidence

        return updated
    }

    private static func temperatureConfidence(
        min: Int?,
        max: Int?,
        wasExplicitlyLabeled: Bool
    ) -> OCRFieldConfidence {
        guard min != nil || max != nil else { return .none }
        return wasExplicitlyLabeled ? .high : .medium
    }
}
