//
//  FilamentOpacityWriteTests.swift
//  SpoolKidTests
//
//  What alpha each write path gives a tag, with the preference on and off.
//

import Testing
import Foundation
@testable import SpoolKid

struct FilamentOpacityWriteTests {
    private func built(
        format: TagFormat, td: Double? = 5, carried: Int? = nil, enabled: Bool = true
    ) -> FilamentTagData {
        WriteTagFormAssembler.buildTagData(
            format: format, name: "Clear", material: "PETG", subtype: "", brand: "Polar",
            colorHex: "1A2B3C", minNozzleTemp: 230, maxNozzleTemp: 250, minBedTemp: 70, maxBedTemp: 80,
            spoolmanId: nil, writeSpoolID: false,
            transmissionDistance: td, carriedAlpha: carried, writesOpacity: enabled
        )
    }

    @Test func theFormCarriesTDAndItsAlpha() {
        let data = built(format: .tigerTag)
        #expect(data.colorAlpha == 94)
        #expect(data.transmissionDistance == 5)
    }

    @Test func preferenceOffWritesOpaqueButKeepsTD() {
        let data = built(format: .tigerTag, enabled: false)
        #expect(data.colorAlpha == nil)
        #expect(data.transmissionDistance == 5)
    }

    @Test func rewritingATranslucentTagWithNoTDKeepsItsAlpha() {
        #expect(built(format: .openSpool, td: nil, carried: 140).colorAlpha == 140)
    }

    @Test(arguments: [TagFormat.anycubicACE, .elegoo])
    func aFormatWithoutAlphaRecordsNone(format: TagFormat) {
        #expect(built(format: format).colorAlpha == nil)
    }

    @Test func aSpoolWriteCarriesItsFilamentsAlpha() {
        let filament = Filament(id: 1, material: "PETG", colorHex: "1A2B3C", extra: ["td": "5"])
        let spool = Spool(
            id: 9, filament: filament, remainingWeight: 500, initialWeight: 1000,
            spoolWeight: 200, statusId: nil, externalId: nil, purchaseDate: nil
        )
        func written(_ format: TagFormat, enabled: Bool) -> Int? {
            WriteTagFormAssembler.spoolWriteData(
                for: spool, format: format, writesSpoolID: false, spoolIDsResolveViaSpoolLink: true,
                writesOpacity: enabled
            ).colorAlpha
        }
        #expect(written(.openSpool, enabled: true) == 94)
        #expect(written(.openSpool, enabled: false) == nil)
        #expect(written(.elegoo, enabled: true) == nil)
    }
}
