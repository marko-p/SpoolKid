//
//  TagSpoolWeightsTests.swift
//  SpoolKidTests
//
//  What a scanned tag says about the physical spool it is on, for Add Spool
//  from the Scan Result hub. Reported 2026-10-21: a Prusament OpenPrintTag
//  stating 800 g nominal / 818 g actual opened Add Spool at the 1000 g
//  default. Owner: the actual weight, else the nominal; a printer's recorded
//  consumption becomes the remaining weight.
//

import Foundation
import Testing
@testable import SpoolKid

struct TagSpoolWeightsTests {

    private func tag(nominal: Double?, actual: Double?, empty: Double? = nil, consumed: Double? = nil) -> FilamentTagData {
        FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "000000",
            minNozzleTemp: 200, maxNozzleTemp: 220, minBedTemp: 50, maxBedTemp: 60,
            nominalNetWeight: nominal, actualNetWeight: actual, emptyContainerWeight: empty,
            consumedWeight: consumed
        )
    }

    /// The owner's Prusament tag: actual 818 g beats the label's 800 g.
    @Test func anOpenPrintTagStartsFromItsActualNetWeight() throws {
        let data = try #require(OpenPrintTagPayload.decode(from: OpenPrintTagAuxTests.prusament))
        let weights = TagSpoolWeights(tagData: data, format: .openPrintTag)
        #expect(weights == TagSpoolWeights(empty: 277, initial: 818, remaining: nil))
    }

    @Test func anOpenPrintTagWithoutAnActualWeightUsesTheNominal() {
        let weights = TagSpoolWeights(tagData: tag(nominal: 800, actual: 0), format: .openPrintTag)
        #expect(weights.initial == 800)
    }

    /// A printer wrote 200 g consumed: 618 g of 818 g left.
    @Test func aPrintersConsumptionBecomesTheRemainingWeight() throws {
        let data = try #require(OpenPrintTagPayload.decode(from: OpenPrintTagAuxTests.prusamentAfterPrinting))
        let weights = TagSpoolWeights(tagData: data, format: .openPrintTag)
        #expect(weights.initial == 818)
        #expect(weights.remaining == 618)
    }

    /// Zero consumed is a fresh spool: it stays full rather than stating it.
    @Test func noConsumptionLeavesTheSpoolFull() {
        let weights = TagSpoolWeights(tagData: tag(nominal: 800, actual: 818, consumed: 0), format: .openPrintTag)
        #expect(weights.remaining == nil)
    }

    /// TigerTag's second weight is what is left, not the fill: never the initial weight.
    @Test func otherFormatsUseTheNominalWeightOnly() {
        let tiger = TagSpoolWeights(tagData: tag(nominal: 1000, actual: 600), format: .tigerTag)
        #expect(tiger == TagSpoolWeights(empty: nil, initial: 1000, remaining: nil))
        let elegoo = TagSpoolWeights(tagData: tag(nominal: 1000, actual: nil), format: .elegoo)
        #expect(elegoo.initial == 1000)
        #expect(TagSpoolWeights(tagData: tag(nominal: 1000, actual: 818, consumed: 200), format: nil).remaining == nil)
    }

    @Test func aTagStatingNoWeightsStatesNothing() {
        let weights = TagSpoolWeights(tagData: tag(nominal: 0, actual: nil, empty: 0), format: .openPrintTag)
        #expect(weights == TagSpoolWeights(empty: nil, initial: nil, remaining: nil))
    }

    // The form's use of `initial`: SpoolFormInitialWeightTests.
}
