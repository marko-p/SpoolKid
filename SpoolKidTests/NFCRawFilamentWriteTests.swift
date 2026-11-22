//
//  NFCRawFilamentWriteTests.swift
//  SpoolKidTests
//
//  TigerTag and ELEGOO share one raw filament write. The TigerTag strings
//  below are the ones it shipped with before the two were joined (2026-10-05):
//  joining them must not change a word the user sees.
//

import Foundation
import Testing
@testable import SpoolKid

struct NFCRawFilamentWriteTests {

    // MARK: - What a refused write says

    @Test func tigerTagRefusalsReadAsTheyAlwaysHave() {
        #expect(NFCManager.rawWriteRefusalMessage(.encodeFailed, formatName: "TigerTag")
                == "Failed to encode data for TigerTag.")
        #expect(NFCManager.rawWriteRefusalMessage(.tooSmall, formatName: "TigerTag")
                == "This tag is too small for TigerTag (needs NTAG213 or larger).")
        #expect(NFCManager.rawWriteRefusalMessage(.locked, formatName: "TigerTag")
                == "This tag is locked or read-only, so SpoolKid cannot write it. Use a blank NTAG213 or NTAG215.")
        #expect(NFCManager.rawWriteRefusalMessage(.passwordProtected, formatName: "TigerTag")
                == "This tag is password-protected, so SpoolKid cannot write it.")
    }

    @Test func anELEGOORefusalNamesELEGOO() {
        #expect(NFCManager.rawWriteRefusalMessage(.encodeFailed, formatName: "ELEGOO")
                == "Failed to encode data for ELEGOO.")
        #expect(NFCManager.rawWriteRefusalMessage(.tooSmall, formatName: "ELEGOO")
                == "This tag is too small for ELEGOO (needs NTAG213 or larger).")
    }

    // MARK: - What each format writes

    /// Data pages 4-23 plus zeroed signature pages 24-39, so a reused signed
    /// chip reads unsigned, never invalid.
    @Test func tigerTagWritesItsDataAndZeroesTheSignature() throws {
        let pages = try #require(NFCManager.rawFilamentWritePages(for: sample(), format: .tigerTag))

        #expect(pages.map(\.page).sorted() == Array(4...39))
        let signature = pages.filter { $0.page >= 24 }
        #expect(signature.count == 16)
        #expect(signature.allSatisfy { $0.data == Data(repeating: 0, count: 4) })
    }

    @Test func elegooWritesTheFactoryImage() throws {
        let data = sample()
        let pages = try #require(NFCManager.rawFilamentWritePages(for: data, format: .elegoo))

        #expect(pages.map(\.page) == ElegooPayload.encodePages(from: data).map(\.page))
        #expect(pages.map(\.data) == ElegooPayload.encodePages(from: data).map(\.data))
    }

    /// An ELEGOO filament the Canvas has no entry for encodes to nothing, and
    /// nothing must reach the tag.
    @Test func anELEGOOFilamentWithoutACanvasEntryWritesNoPages() throws {
        var data = sample()
        data.material = "Nylon"

        let pages = try #require(NFCManager.rawFilamentWritePages(for: data, format: .elegoo))

        #expect(pages.isEmpty)
    }

    // MARK: - Refused before the session opens

    /// Issue #14: a filament with no Canvas entry used to fail only after the
    /// user held the tag to the phone.
    @Test func anELEGOOFilamentWithoutACanvasEntryIsRefusedBeforeTheSession() {
        var data = sample()
        data.material = "Nylon"

        #expect(NFCManager.writeRefusal(for: data, format: .elegoo)
                == "Nylon has no Canvas filament, so it cannot be written as an ELEGOO tag. Choose a Canvas filament in Write Tag, or write another format.")
    }

    @Test(arguments: TagFormat.allCases)
    func aWritableFilamentIsNotRefused(format: TagFormat) {
        #expect(NFCManager.writeRefusal(for: sample(), format: format) == nil)
    }

    // MARK: - What a finished write says

    /// The Canvas filament is chosen for the user on the spool form's Write Tag, so the
    /// success message names it.
    @Test func anELEGOOWriteNamesItsCanvasFilament() {
        var data = sample()
        data.subtype = "PLA Matte"

        #expect(NFCManager.writtenNote(for: data, format: .elegoo) == "\nCanvas filament: PLA Matte")
        #expect(NFCManager.writtenNote(for: sample(), format: .elegoo) == "\nCanvas filament: PLA")
        #expect(NFCManager.writtenNote(for: data, format: .tigerTag) == "")
    }

    /// The NDEF formats and the ACE write by their own paths.
    @Test(arguments: [TagFormat.openSpool, .openPrintTag, .openTag3D, .anycubicACE])
    func otherFormatsAreNotWrittenThisWay(format: TagFormat) {
        #expect(NFCManager.rawFilamentWritePages(for: sample(), format: format) == nil)
    }

    private func sample() -> FilamentTagData {
        FilamentTagData(
            material: "PLA", brand: "ELEGOO", colorHex: "29D464",
            minNozzleTemp: 190, maxNozzleTemp: 230, minBedTemp: 50, maxBedTemp: 60,
            diameter: 1.75, nominalNetWeight: 1000
        )
    }
}
