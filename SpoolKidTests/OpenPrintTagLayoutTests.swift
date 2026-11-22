//
//  OpenPrintTagLayoutTests.swift
//  SpoolKidTests
//
//  Prusa's OpenPrintTag layout at write time: meta -> main -> zero padding ->
//  aux (the spool's consumed weight), filling the tag. The golden numbers
//  (245 / 210 / 303, and 269 / 234 without a URL) are the owner's Prusament
//  tag: CoreNFC capacity 304, meta `A1 02 18 D2`, a 245-byte payload.
//

import CoreNFC
import Foundation
import Testing
@testable import SpoolKid

struct OpenPrintTagLayoutTests {

    static let url = "https://3dtag.org/s/4ce3d37f1b"
    private static let mime = "application/vnd.openprinttag"

    /// A Prusament-like spool: 1 kg of 1.24 g/cm3, 1.75 mm filament, 388 g used.
    private static func sample(density: Double? = 1.24, consumed: Double? = 388) -> FilamentTagData {
        FilamentTagData(
            name: "PLA Galaxy Black", material: "PLA", brand: "Prusament", colorHex: "3D3E3D",
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 40, maxBedTemp: 60,
            density: density, diameter: 1.75, nominalNetWeight: 1000, consumedWeight: consumed
        )
    }

    /// The owner's SLIX tag: temperatures only, no weights, density or diameter.
    private static let small = FilamentTagData(
        name: "Galaxy Black", material: "PLA", brand: "Prusament", colorHex: "3D3E3D",
        minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 50, maxBedTemp: 60
    )

    static func prusa(url: String? = OpenPrintTagLayoutTests.url, capacity: Int = 304, slix2: Bool = true,
                      density: Double? = 1.24, consumed: Double? = 388) -> OpenPrintTagLayout.Result? {
        OpenPrintTagLayout.layout(for: sample(density: density, consumed: consumed),
                                  urlString: url, capacity: capacity, isSLIX2: slix2)
    }

    /// The main map's keys, found the way a reader finds them: meta first,
    /// main right after it.
    private static func mainMap(of payload: Data) -> [Int: CBORReader.Value]? {
        var reader = CBORReader(payload)
        guard reader.readMap() != nil else { return nil }
        return reader.readMap()
    }

    // MARK: - The owner's Prusament numbers

    @Test func matchesThePrusamentLayout() throws {
        let result = try #require(Self.prusa())
        #expect(result.payload.count == 245)
        #expect(result.auxOffset == 210)
        #expect(result.messageLength == 303)
        #expect(result.payload.prefix(4) == Data([0xA1, 0x02, 0x18, 0xD2]))
    }

    @Test func withoutAURLTheLongHeaderIsUsed() throws {
        let result = try #require(Self.prusa(url: nil))
        #expect(result.payload.count == 269)
        #expect(result.auxOffset == 234)
        #expect(result.messageLength == 303)
    }

    @Test func slix2CapacityIsCappedAtTheCounterBlock() throws {
        let capped = try #require(Self.prusa(capacity: 312, slix2: true))
        #expect(capped == (try #require(Self.prusa(capacity: 304, slix2: true))))
        let uncapped = try #require(Self.prusa(capacity: 312, slix2: false))
        #expect(uncapped.messageLength == 311)
        #expect(OpenPrintTagLayout.messageCeiling(capacity: 312, isSLIX2: true) == 303)
        #expect(OpenPrintTagLayout.messageCeiling(capacity: 312, isSLIX2: false) == 311)
        #expect(OpenPrintTagLayout.messageCeiling(capacity: 106, isSLIX2: false) == 105)
    }

    @Test func payloadNeverCrossesTheCeilingAtTheHeaderBoundary() throws {
        for capacity in 250...330 {
            for url in [Self.url, nil] {
                for slix2 in [true, false] {
                    let ceiling = OpenPrintTagLayout.messageCeiling(capacity: capacity, isSLIX2: slix2)
                    let result = try #require(Self.prusa(url: url, capacity: capacity, slix2: slix2))
                    #expect(result.messageLength <= ceiling)
                    if let aux = result.auxOffset {
                        let tlv: Int = result.messageLength > 254 ? 4 : 2
                        let payloadStart: Int = 4 + tlv + result.messageLength - result.payload.count
                        #expect((payloadStart + aux) % 4 == 0)
                        #expect(result.payload.count - aux >= 32)
                    }
                }
            }
        }
    }

    @Test func theMeasuredMessageIsTheRealAssembly() throws {
        let result = try #require(Self.prusa())
        let message = NFCNDEFMessage(records: NFCManager.ndefRecords(
            mimePayload: result.payload, mimeType: Self.mime, urlString: Self.url))
        #expect(message.length == result.messageLength)
        #expect(TagFormat.openPrintTag.mimeType == Self.mime)
    }

    // MARK: - The aux region

    @Test func theConsumedWeightLandsInAux() throws {
        let result = try #require(Self.prusa())
        let aux = try #require(result.auxOffset)
        #expect(Array(result.payload[aux...].prefix(8)) == [0xBF, 0x00, 0xFA, 0x43, 0xC2, 0x00, 0x00, 0xFF])
        #expect(result.payload[(aux + 8)...].allSatisfy { $0 == 0 })

        let untouched = try #require(Self.prusa(consumed: nil))
        #expect(untouched.payload[try #require(untouched.auxOffset)] == 0xA0)
    }

    @Test func auxSectionBytes() {
        #expect(OpenPrintTagLayout.auxSection(consumedWeight: nil) == Data([0xA0]))
        #expect(OpenPrintTagLayout.auxSection(consumedWeight: 0) == Data([0xA0]))
        #expect(OpenPrintTagLayout.auxSection(consumedWeight: -3) == Data([0xA0]))
        #expect(OpenPrintTagLayout.auxSection(consumedWeight: 388) == Data([0xBF, 0x00, 0xFA, 0x43, 0xC2, 0x00, 0x00, 0xFF]))
        #expect(OpenPrintTagLayout.auxSection(consumedWeight: 1e40) == Data([0xA0]))
    }

    @Test func decodeReadsBackWhatWasLaidOut() throws {
        let result = try #require(Self.prusa())
        let decoded = try #require(OpenPrintTagPayload.decode(from: result.payload))
        #expect(decoded.consumedWeight == 388)
        #expect(abs(try #require(decoded.diameter) - 1.75) < 0.0001)
        #expect(decoded.material == "PLA")
        #expect(decoded.nominalNetWeight == 1000)
    }

    // MARK: - Length needs aux

    @Test func theLengthIsWrittenWithTheAux() throws {
        let result = try #require(Self.prusa())
        #expect(result.writesLength)
        #expect(try #require(Self.mainMap(of: result.payload))[53]?.intValue == 335284)
    }

    @Test func noLengthWithoutAux() throws {
        let small = try #require(OpenPrintTagLayout.layout(for: Self.small, urlString: nil, capacity: 106, isSLIX2: false))
        #expect(small.auxOffset == nil)
        #expect(!small.writesLength)
        #expect(small.payload.count == 74)
        #expect(small.payload.first == 0xA0)

        if let crowded = Self.prusa(url: nil, capacity: 106, slix2: false) {
            #expect(crowded.auxOffset == nil)
            #expect(!crowded.writesLength)
            #expect(Self.mainMap(of: crowded.payload)?[53] == nil)
        }
    }

    @Test func aTagThatFitsMainButNotAuxWritesNeitherAuxNorLength() throws {
        // Every capacity between "main fits" and "aux fits" drops the length
        // together with the aux region.
        var sawNoAux = false
        for capacity in 100...304 {
            guard let result = Self.prusa(url: nil, capacity: capacity, slix2: false) else { continue }
            if result.auxOffset == nil {
                sawNoAux = true
                #expect(!result.writesLength)
                #expect(result.payload.first == 0xA0)
                #expect(Self.mainMap(of: result.payload)?[53] == nil)
            } else {
                #expect(result.writesLength)
            }
        }
        #expect(sawNoAux)
    }

    @Test func noLengthWithoutDensityOrDiameter() throws {
        let noDensity = try #require(Self.prusa(density: nil))
        #expect(noDensity.auxOffset != nil)
        #expect(!noDensity.writesLength)
        #expect(Self.mainMap(of: noDensity.payload)?[53] == nil)

        var noDiameter = Self.sample()
        noDiameter.diameter = nil
        let result = try #require(OpenPrintTagLayout.layout(for: noDiameter, urlString: Self.url, capacity: 304, isSLIX2: true))
        #expect(result.auxOffset != nil)
        #expect(!result.writesLength)
    }

    @Test func fullLengthFormula() {
        #expect(OpenPrintTagLayout.fullLength(netWeight: 1000, density: 1.24, diameter: 1.75) == 335284)
        #expect(OpenPrintTagLayout.fullLength(netWeight: 800, density: 1.07, diameter: 1.75) == 310842)
        #expect(OpenPrintTagLayout.fullLength(netWeight: 1000, density: 1.24, diameter: 2.85) == 126415)
        #expect(OpenPrintTagLayout.fullLength(netWeight: nil, density: 1.24, diameter: 1.75) == nil)
        #expect(OpenPrintTagLayout.fullLength(netWeight: 1000, density: nil, diameter: 1.75) == nil)
        #expect(OpenPrintTagLayout.fullLength(netWeight: 1000, density: 1.24, diameter: nil) == nil)
        #expect(OpenPrintTagLayout.fullLength(netWeight: 0, density: 1.24, diameter: 1.75) == nil)
        #expect(OpenPrintTagLayout.fullLength(netWeight: 1000, density: 0, diameter: 1.75) == nil)
        #expect(OpenPrintTagLayout.fullLength(netWeight: 1000, density: 1.24, diameter: 0) == nil)
    }

    // MARK: - Capacity unknown, impossible

    @Test func anUnknownCapacityHasNoLayout() {
        #expect(OpenPrintTagLayout.layout(for: Self.sample(), urlString: nil, capacity: 0, isSLIX2: false) == nil)
        #expect(OpenPrintTagLayout.layout(for: Self.sample(), urlString: nil, capacity: -1, isSLIX2: true) == nil)
    }

    @Test func aTagTooSmallForTheMaterialHasNoLayout() {
        #expect(OpenPrintTagLayout.layout(for: Self.sample(), urlString: Self.url, capacity: 60, isSLIX2: false) == nil)
    }

    // MARK: - Invariants at every size

    /// The anti-goals, swept over every capacity a tag can plausibly report:
    /// no length without aux, aux inside the payload and after main, the
    /// message within the ceiling, a SLIX2 never past its counter block.
    @Test func invariantsHoldAtEveryCapacity() throws {
        for capacity in 1...520 {
            for slix2 in [true, false] {
                for url in [Self.url, nil] {
                    for data in [Self.sample(), Self.small] {
                        guard let r = OpenPrintTagLayout.layout(for: data, urlString: url, capacity: capacity, isSLIX2: slix2) else { continue }
                        let ceiling = OpenPrintTagLayout.messageCeiling(capacity: capacity, isSLIX2: slix2)
                        #expect(r.messageLength <= ceiling)
                        if slix2 { #expect(r.messageLength <= 303) }
                        if r.writesLength { #expect(r.auxOffset != nil) }
                        #expect(r.sectionsLength <= r.payload.count)
                        if let aux = r.auxOffset {
                            #expect(r.sectionsLength <= aux)
                            #expect(aux < r.payload.count)
                            #expect(r.payload.count - aux >= OpenPrintTagLayout.auxRegionSize)
                        } else {
                            #expect(r.payload.first == 0xA0)
                        }
                        #expect(OpenPrintTagPayload.decode(from: r.payload) != nil)
                    }
                }
            }
        }
    }
}
