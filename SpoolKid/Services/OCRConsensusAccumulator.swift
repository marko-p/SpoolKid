import Foundation

/// Accumulates per-frame OCR candidates over a sliding window and emits a consensus
/// by per-field weighted voting. Weight for a unique field value = sum of confidence
/// ranks across all window frames where that value appeared (high=3, medium=2, low=1,
/// none=0). Ties resolved by most-recent observation. `rawLines` (and the index-aligned
/// `rawLineBoxes`) come from the frame with the highest total confidence rank. `isStable`
/// is true when material and colorHex have not changed for the last `stabilityThreshold`
/// consecutive frames (with at least one non-nil among them).
///
/// `nonisolated`: the target sets SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor; this pure
/// value type must remain callable from non-isolated contexts (tests, sessionQueue).
nonisolated struct OCRConsensusAccumulator {
    static let windowSize = 8
    static let stabilityThreshold = 3
    /// How long after the first real reading an unsettled vote is OFFERED
    /// (never accepted) — owner's choice, 2026-09-24.
    static let fallbackDelay: TimeInterval = 4

    private var window: [OCRParsedCandidate] = []
    private var consecutiveStableCount = 0
    private var prevMaterial: String? = nil
    private var prevColor: String? = nil
    private var initialized = false
    private var firstSignalAt: Date?

    var isStable: Bool { consecutiveStableCount >= Self.stabilityThreshold }

    var consensus: OCRParsedCandidate? {
        window.isEmpty ? nil : buildConsensus()
    }

    mutating func ingest(_ candidate: OCRParsedCandidate, at now: Date = Date()) {
        if firstSignalAt == nil, candidate.material != nil || candidate.colorHex != nil {
            firstSignalAt = now
        }
        window.append(candidate)
        if window.count > Self.windowSize {
            window.removeFirst()
        }
        trackStability(material: candidate.material, color: candidate.colorHex)
    }

    /// Whether the scanner should offer the vote so far. A label whose
    /// material or colour never reads the same `stabilityThreshold` frames in
    /// a row never becomes stable, and the scan used to wait for it forever.
    /// The clock starts at the first frame that read either, so a camera still
    /// finding the label does not use up the wait.
    func offersFallback(now: Date) -> Bool {
        guard !isStable, let firstSignalAt else { return false }
        return now.timeIntervalSince(firstSignalAt) >= Self.fallbackDelay
    }

    // MARK: - Stability

    private mutating func trackStability(material: String?, color: String?) {
        let hasSignal = material != nil || color != nil
        if initialized && material == prevMaterial && color == prevColor && hasSignal {
            consecutiveStableCount += 1
        } else {
            consecutiveStableCount = hasSignal ? 1 : 0
        }
        prevMaterial = material
        prevColor = color
        initialized = true
    }

    // MARK: - Consensus building

    private func buildConsensus() -> OCRParsedCandidate {
        let material     = winningValue(for: .material)      { $0.material }
        let subtype      = winningValue(for: .subtype)       { $0.subtype }
        let brand        = winningValue(for: .brand)         { $0.brand }
        let filamentName = winningValue(for: .filamentName)  { $0.filamentName }
        let colorHex     = winningValue(for: .colorHex)      { $0.colorHex }
        let serialNumber = winningValue(for: .serialNumber)  { $0.serialNumber }
        let diameterMM   = winningValue(for: .diameterMM)    { $0.diameterMM }
        let netWeightG   = winningValue(for: .netWeightG)    { $0.netWeightG }
        let minNozzle    = winningValue(for: .minNozzleTemp) { $0.minNozzleTemp }
        let maxNozzle    = winningValue(for: .maxNozzleTemp) { $0.maxNozzleTemp }
        let minBed       = winningValue(for: .minBedTemp)    { $0.minBedTemp }
        let maxBed       = winningValue(for: .maxBedTemp)    { $0.maxBedTemp }

        let majority: (KeyPath<OCRParsedCandidate, Bool>) -> Bool = { [window] kp in
            window.filter { $0[keyPath: kp] }.count * 2 >= window.count
        }

        let confidenceByField: [OCRParsedCandidate.Field: OCRFieldConfidence] = [
            .material:      material.confidence,
            .subtype:       subtype.confidence,
            .brand:         brand.confidence,
            .filamentName:  filamentName.confidence,
            .colorHex:      colorHex.confidence,
            .serialNumber:  serialNumber.confidence,
            .diameterMM:    diameterMM.confidence,
            .netWeightG:    netWeightG.confidence,
            .minNozzleTemp: minNozzle.confidence,
            .maxNozzleTemp: maxNozzle.confidence,
            .minBedTemp:    minBed.confidence,
            .maxBedTemp:    maxBed.confidence,
        ]

        let best = bestConfidenceCandidate()
        var candidate = OCRParsedCandidate(
            material: material.value,
            brand: brand.value,
            colorHex: colorHex.value,
            minNozzleTemp: minNozzle.value,
            maxNozzleTemp: maxNozzle.value,
            minBedTemp: minBed.value,
            maxBedTemp: maxBed.value,
            confidenceByField: confidenceByField,
            rawLines: best?.rawLines ?? []
        )
        // Boxes come from the same frame as rawLines so the two stay index-aligned.
        candidate.rawLineBoxes = best?.rawLineBoxes ?? []
        candidate.subtype = subtype.value
        candidate.filamentName = filamentName.value
        candidate.serialNumber = serialNumber.value
        candidate.diameterMM = diameterMM.value
        candidate.netWeightG = netWeightG.value
        candidate.isBedTempInferred = majority(\.isBedTempInferred)
        candidate.wasNozzleExplicitlyLabeled = majority(\.wasNozzleExplicitlyLabeled)
        candidate.wasBedExplicitlyLabeled = majority(\.wasBedExplicitlyLabeled)
        return candidate
    }

    // MARK: - Field voting

    private func winningValue<T: Hashable>(
        for field: OCRParsedCandidate.Field,
        extracting: (OCRParsedCandidate) -> T?
    ) -> (value: T?, confidence: OCRFieldConfidence) {
        var weightMap: [T: (totalWeight: Int, maxConfidence: OCRFieldConfidence, lastIndex: Int)] = [:]

        for (index, frame) in window.enumerated() {
            guard let value = extracting(frame) else { continue }
            let conf = frame.confidenceByField[field] ?? .none
            let w = conf.rank
            if let existing = weightMap[value] {
                let newMax = existing.maxConfidence.rank >= conf.rank ? existing.maxConfidence : conf
                weightMap[value] = (existing.totalWeight + w, newMax, index)
            } else {
                weightMap[value] = (w, conf, index)
            }
        }

        guard !weightMap.isEmpty else { return (nil, .none) }

        let winner = weightMap.max {
            $0.value.totalWeight != $1.value.totalWeight
                ? $0.value.totalWeight < $1.value.totalWeight
                : $0.value.lastIndex < $1.value.lastIndex
        }!
        return (winner.key, winner.value.maxConfidence)
    }

    private func bestConfidenceCandidate() -> OCRParsedCandidate? {
        window.max { totalRank($0) < totalRank($1) }
    }

    private func totalRank(_ candidate: OCRParsedCandidate) -> Int {
        OCRParsedCandidate.Field.allCases.reduce(0) { sum, field in
            sum + (candidate.confidenceByField[field]?.rank ?? 0)
        }
    }
}

private extension OCRFieldConfidence {
    nonisolated var rank: Int {
        switch self {
        case .high:   return 3
        case .medium: return 2
        case .low:    return 1
        case .none:   return 0
        }
    }
}
