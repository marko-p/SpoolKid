import Foundation
import Testing
import CoreGraphics
@testable import SpoolKid

struct OCRConsensusAccumulatorTests {

    // MARK: - Empty accumulator

    @Test func emptyAccumulatorReturnsNilConsensus() {
        let acc = OCRConsensusAccumulator()
        #expect(acc.consensus == nil)
    }

    @Test func emptyAccumulatorIsNotStable() {
        let acc = OCRConsensusAccumulator()
        #expect(!acc.isStable)
    }

    // MARK: - Majority voting

    @Test func minorityFlipYieldsMajorityValue() {
        // 3 frames say "PLA", 1 says "PETG" — PLA wins
        var acc = OCRConsensusAccumulator()
        acc.ingest(makeCandidate(material: "PLA"))
        acc.ingest(makeCandidate(material: "PETG"))
        acc.ingest(makeCandidate(material: "PLA"))
        acc.ingest(makeCandidate(material: "PLA"))
        #expect(acc.consensus?.material == "PLA")
    }

    // Documented case: 2 high-confidence frames (weight=6) beat 3 low-confidence frames (weight=3)
    @Test func confidenceWeightingBeatsRawFrequency() {
        var acc = OCRConsensusAccumulator()
        for _ in 0..<3 {
            acc.ingest(makeCandidate(material: "PLA", confidenceByField: [.material: .low]))
        }
        for _ in 0..<2 {
            acc.ingest(makeCandidate(material: "PETG", confidenceByField: [.material: .high]))
        }
        #expect(acc.consensus?.material == "PETG")
    }

    @Test func tiedWeightSelectsMostRecent() {
        // "PLA" at medium (weight=2), then "PETG" at medium (weight=2); PETG is more recent
        var acc = OCRConsensusAccumulator()
        acc.ingest(makeCandidate(material: "PLA",  confidenceByField: [.material: .medium]))
        acc.ingest(makeCandidate(material: "PETG", confidenceByField: [.material: .medium]))
        #expect(acc.consensus?.material == "PETG")
    }

    // MARK: - rawLines source

    @Test func rawLinesFromBestConfidenceFrame() {
        var acc = OCRConsensusAccumulator()
        acc.ingest(makeCandidate(material: "PLA", rawLines: ["low frame"],
                                 confidenceByField: [.material: .low]))
        acc.ingest(makeCandidate(material: "PLA", rawLines: ["high frame"],
                                 confidenceByField: [.material: .high]))
        #expect(acc.consensus?.rawLines == ["high frame"])
    }

    @Test func rawLineBoxesFollowBestConfidenceFrame() {
        let lowBox = CGRect(x: 0, y: 0.1, width: 0.2, height: 0.05)
        let highBox = CGRect(x: 0, y: 0.9, width: 0.2, height: 0.05)
        var acc = OCRConsensusAccumulator()
        acc.ingest(makeCandidate(material: "PLA", rawLines: ["low frame"], rawLineBoxes: [lowBox],
                                 confidenceByField: [.material: .low]))
        acc.ingest(makeCandidate(material: "PLA", rawLines: ["high frame"], rawLineBoxes: [highBox],
                                 confidenceByField: [.material: .high]))
        // Boxes come from the same (highest-confidence) frame as rawLines, staying index-aligned.
        #expect(acc.consensus?.rawLineBoxes == [highBox])
    }

    // MARK: - Stability

    @Test func notStableBeforeThreshold() {
        var acc = OCRConsensusAccumulator()
        let needed = OCRConsensusAccumulator.stabilityThreshold
        for _ in 0..<(needed - 1) {
            acc.ingest(makeCandidate(material: "PLA", colorHex: "FF0000"))
        }
        #expect(!acc.isStable)
    }

    @Test func stableAfterThresholdConsistentFrames() {
        var acc = OCRConsensusAccumulator()
        let needed = OCRConsensusAccumulator.stabilityThreshold
        for _ in 0..<needed {
            acc.ingest(makeCandidate(material: "PLA", colorHex: "FF0000"))
        }
        #expect(acc.isStable)
    }

    @Test func stabilityResetsOnMaterialChange() {
        var acc = OCRConsensusAccumulator()
        let needed = OCRConsensusAccumulator.stabilityThreshold
        for _ in 0..<needed {
            acc.ingest(makeCandidate(material: "PLA", colorHex: "FF0000"))
        }
        #expect(acc.isStable)
        acc.ingest(makeCandidate(material: "PETG", colorHex: "FF0000"))
        #expect(!acc.isStable)
    }

    // MARK: - Helpers

    // MARK: - Fallback offer (2026-09-24)
    //
    // A label whose material or colour never reads the same three frames in a
    // row never becomes stable, and the scan used to wait forever. Four
    // seconds after the first real reading, the scanner offers the vote so far
    // as a button — never accepts it by itself.

    private static let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func noFallbackBeforeTheWait() {
        var acc = OCRConsensusAccumulator()
        acc.ingest(makeCandidate(material: "PLA"), at: Self.t0)
        acc.ingest(makeCandidate(material: "PETG"), at: Self.t0 + 1)
        #expect(!acc.offersFallback(now: Self.t0 + 3.9))
    }

    @Test func anUnsettledReadingIsOfferedAfterTheWait() {
        var acc = OCRConsensusAccumulator()
        for (i, material) in ["PLA", "PETG", "PLA", "PETG", "PLA"].enumerated() {
            acc.ingest(makeCandidate(material: material), at: Self.t0 + Double(i))
        }
        #expect(!acc.isStable)
        #expect(acc.offersFallback(now: Self.t0 + 4))
    }

    @Test func theWaitStartsAtTheFirstRealReading() {
        var acc = OCRConsensusAccumulator()
        acc.ingest(makeCandidate(), at: Self.t0)
        acc.ingest(makeCandidate(material: "PLA"), at: Self.t0 + 3)
        #expect(!acc.offersFallback(now: Self.t0 + 5))
        #expect(acc.offersFallback(now: Self.t0 + 7))
    }

    @Test func aStableReadingNeedsNoFallback() {
        var acc = OCRConsensusAccumulator()
        for i in 0..<3 {
            acc.ingest(makeCandidate(material: "PLA", colorHex: "000000"), at: Self.t0 + Double(i))
        }
        #expect(acc.isStable)
        #expect(!acc.offersFallback(now: Self.t0 + 10))
    }

    @Test func nothingReadNothingOffered() {
        var acc = OCRConsensusAccumulator()
        acc.ingest(makeCandidate(), at: Self.t0)
        acc.ingest(makeCandidate(), at: Self.t0 + 1)
        #expect(!acc.offersFallback(now: Self.t0 + 10))
    }

    private func makeCandidate(
        material: String? = nil,
        colorHex: String? = nil,
        rawLines: [String] = [],
        rawLineBoxes: [CGRect] = [],
        confidenceByField: [OCRParsedCandidate.Field: OCRFieldConfidence] = [:]
    ) -> OCRParsedCandidate {
        var candidate = OCRParsedCandidate(
            material: material,
            brand: nil,
            colorHex: colorHex,
            minNozzleTemp: nil,
            maxNozzleTemp: nil,
            minBedTemp: nil,
            maxBedTemp: nil,
            confidenceByField: confidenceByField,
            rawLines: rawLines
        )
        candidate.rawLineBoxes = rawLineBoxes
        return candidate
    }
}
