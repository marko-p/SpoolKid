import Foundation
import CoreNFC
import Testing
@testable import SpoolKid

struct TagCapacityEstimatorTests {

    private func sampleData() -> FilamentTagData {
        WriteTagFormAssembler.buildTagData(
            format: .openPrintTag,
            name: "PLA Galaxy", material: "PLA", subtype: "", brand: "Prusament",
            colorHex: "3D3E3D", minNozzleTemp: 205, maxNozzleTemp: 225,
            minBedTemp: 40, maxBedTemp: 60, spoolmanId: nil, writeSpoolID: false,
            preheatTemp: 170, nominalNetWeight: 1000, emptyContainerWeight: 280,
            density: 1.24, dryingTemp: 55, dryingTime: 480,
            gtin: "8594173675001", countryOfOrigin: "CZ",
            manufacturedDateUnix: 1758709719, tagURL: nil
        )
    }

    private let urlString = "https://3dtag.org/s/abc"

    private func layout(urlString: String?) throws -> OpenPrintTagLayout.Result {
        try #require(OpenPrintTagLayout.layout(
            for: sampleData(), urlString: urlString,
            capacity: TagCapacityEstimator.slix2Capacity, isSLIX2: true))
    }

    @Test func budgetIsWhatCoreNFCReportsForASLIX2() {
        #expect(TagCapacityEstimator.slix2Capacity == 304)
    }

    /// The segments plus the zero padding between main and aux are the whole
    /// NDEF message the write would send.
    @Test func segmentsAddUp() throws {
        for url in [urlString, nil] {
            let laid = try layout(urlString: url)
            let breakdown = try #require(TagCapacityEstimator.breakdown(
                for: sampleData(), format: .openPrintTag, urlString: url))

            let padding = try #require(laid.auxOffset) - laid.sectionsLength
            #expect(breakdown.overhead + breakdown.material + breakdown.url + breakdown.aux + padding
                    == laid.messageLength)
            #expect(breakdown.total == laid.messageLength - padding)
            #expect(breakdown.capacity == 304)

            let message = NFCNDEFMessage(records: NFCManager.ndefRecords(
                mimePayload: laid.payload, mimeType: "application/vnd.openprinttag", urlString: url))
            #expect(message.length == laid.messageLength)
        }
    }

    @Test func materialIsMetaPlusMain() throws {
        let laid = try layout(urlString: nil)
        let breakdown = try #require(TagCapacityEstimator.breakdown(
            for: sampleData(), format: .openPrintTag, urlString: nil))
        #expect(breakdown.material == laid.sectionsLength)
    }

    @Test func theCountdownIsTheAuxRegion() throws {
        let laid = try layout(urlString: urlString)
        let breakdown = try #require(TagCapacityEstimator.breakdown(
            for: sampleData(), format: .openPrintTag, urlString: urlString))
        #expect(breakdown.aux == laid.payload.count - (try #require(laid.auxOffset)))
        #expect(breakdown.aux >= OpenPrintTagLayout.auxRegionSize)
    }

    @Test func aURLSegmentAppearsOnlyWithAURL() throws {
        let noURL = try #require(TagCapacityEstimator.breakdown(
            for: sampleData(), format: .openPrintTag, urlString: nil))
        let withURL = try #require(TagCapacityEstimator.breakdown(
            for: sampleData(), format: .openPrintTag, urlString: urlString))

        #expect(noURL.url == 0)
        #expect(withURL.url > 0)
        #expect(noURL.material == withURL.material)
    }

    @Test func overheadIsSmallPositiveConstant() throws {
        let breakdown = try #require(TagCapacityEstimator.breakdown(
            for: sampleData(), format: .openPrintTag, urlString: nil))
        #expect(breakdown.overhead > 0)
        #expect(breakdown.overhead < 64)
    }

    @Test func aRecordThatFitsLeavesFreeSpaceAndNeverGoesOver() throws {
        let breakdown = try #require(TagCapacityEstimator.breakdown(
            for: sampleData(), format: .openPrintTag, urlString: urlString))
        #expect(breakdown.fits)
        #expect(breakdown.over == 0)
        #expect(breakdown.free == breakdown.capacity - breakdown.total)
    }

    @Test func anOverlongRecordFallsBackToTheUnpaddedMessage() throws {
        var data = sampleData()
        data.name = String(repeating: "x", count: 400)
        let breakdown = try #require(TagCapacityEstimator.breakdown(
            for: data, format: .openPrintTag, urlString: nil))
        let cbor = try #require(TagFormatService.shared.encode(data: data, format: .openPrintTag))
        #expect(breakdown.aux == 0)
        #expect(breakdown.material == cbor.count)
        #expect(!breakdown.fits)
        #expect(breakdown.over > 0)
    }

    /// The orange segment only counts down when the layout wrote a length: the
    /// printer refuses to track a spool whose tag has an aux region but no
    /// length (OpenPrintTagCannotTrack).
    @Test func theAuxSegmentCountsDownOnlyWithALength() throws {
        var tracked = sampleData()
        tracked.diameter = 1.75
        let withLength = try #require(TagCapacityEstimator.breakdown(
            for: tracked, format: .openPrintTag, urlString: nil))
        #expect(withLength.aux > 0)
        #expect(withLength.countsDown)

        // sampleData() has a density but no diameter, so no length is computable.
        let withoutLength = try #require(TagCapacityEstimator.breakdown(
            for: sampleData(), format: .openPrintTag, urlString: nil))
        #expect(withoutLength.aux > 0)
        #expect(!withoutLength.countsDown)
    }

    /// A nil layout means the write refuses, so the unpadded record is judged
    /// against the layout's ceiling (303 on a SLIX2), not CoreNFC's 304.
    @Test func aFallbackRecordOfExactlyTheOldBudgetDoesNotFit() throws {
        var found: TagCapacityEstimator.Breakdown?
        for length in 150...400 {
            var data = sampleData()
            data.name = String(repeating: "x", count: length)
            if let breakdown = TagCapacityEstimator.breakdown(
                for: data, format: .openPrintTag, urlString: nil),
               breakdown.aux == 0, breakdown.total == TagCapacityEstimator.slix2Capacity {
                found = breakdown
                break
            }
        }
        let record = try #require(found)
        #expect(!record.fits)
        #expect(record.over == 1)
        #expect(!record.countsDown)
    }

    @Test func fitsFreeAndOverAtBoundary() {
        let exact = TagCapacityEstimator.Breakdown(material: 304, url: 0, overhead: 0, capacity: 304)
        #expect(exact.fits)
        #expect(exact.free == 0)
        #expect(exact.over == 0)

        let oneOver = TagCapacityEstimator.Breakdown(material: 305, url: 0, overhead: 0, capacity: 304)
        #expect(!oneOver.fits)
        #expect(oneOver.free == 0)
        #expect(oneOver.over == 1)
    }

    @Test func theCountdownCountsTowardTheTotal() {
        let full = TagCapacityEstimator.Breakdown(material: 200, url: 0, overhead: 31, capacity: 304, aux: 73)
        #expect(full.total == 304)
        #expect(full.fits)

        let over = TagCapacityEstimator.Breakdown(material: 200, url: 0, overhead: 31, capacity: 304, aux: 74)
        #expect(over.total == 305)
        #expect(over.over == 1)

        let noAux = TagCapacityEstimator.Breakdown(material: 200, url: 0, overhead: 31, capacity: 304)
        #expect(noAux.aux == 0)
        #expect(noAux.total == 231)
    }

    @Test func returnsNilForNonNDEFFormat() {
        #expect(TagCapacityEstimator.breakdown(
            for: sampleData(), format: .anycubicACE, urlString: nil) == nil)
    }
}
