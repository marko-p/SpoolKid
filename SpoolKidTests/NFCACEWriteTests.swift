//
//  NFCACEWriteTests.swift
//  SpoolKidTests
//
//  The decisions an Anycubic ACE write takes around its pages. GET_VERSION does
//  not size Ultralight EV1 48-byte or NTAG210, which keep CFG0, CFG1, PWD and
//  PACK at pages 16-19 and accept writes there; an ACE write that went lowest
//  page first put its page-16/17 bytes into that configuration before page 20
//  was refused. The codec's own tests pin the bytes; these pin the order they
//  go out in, and what a write that stops says.
//

import Foundation
import Testing
@testable import SpoolKid

struct NFCACEWriteTests {

    // MARK: - Write order

    /// Page 31 goes first, so a 20-page chip refuses the first WRITE before
    /// anything lands on its configuration pages.
    @Test func anACEWriteGoesHighestPageFirst() {
        let order = NFCManager.rawWriteOrder(AnycubicACEPayload.encodePages(from: sample))

        #expect(order.map(\.page) == Array((4...31).reversed()))
    }

    /// The order changes nothing written: every page carries the bytes the
    /// codec encoded for it.
    @Test func theWriteOrderChangesNoBytes() {
        let encoded = AnycubicACEPayload.encodePages(from: sample)
        let order = NFCManager.rawWriteOrder(encoded)

        let byPage = Dictionary(uniqueKeysWithValues: order.map { ($0.page, $0.data) })
        #expect(byPage.count == encoded.count)
        for page in encoded {
            #expect(byPage[page.page] == page.data)
        }
    }

    // MARK: - Pages 0-3

    /// A factory Anycubic tag has no lock bits set and a writable capability
    /// container, so it still reaches the password check and keeps its own
    /// refusal ("password-protected, as factory Anycubic tags are").
    @Test func aFactoryAnycubicHeaderIsNotRefusedAsLocked() {
        let header = hex("53440798" + "07740001" + "72480000" + "E1101200")
        #expect(NFCManager.rawWriteHeaderAllowsWrite(header) == true)
    }

    // MARK: - What a stopped write says

    @Test func anACEWriteCutShortSaysItIsPartlyWritten() {
        #expect(NFCManager.rawWriteFailureMessage(
            pagesWritten: 14, totalPages: 28,
            cause: "Write failed at page 17: Tag connection lost"
        ) == "The write was cut short after 14 of 28 pages, so the tag is only partly written. Write it again.")
    }

    /// Nothing landed, so the existing message stands, word for word.
    @Test func aRefusedFirstPageKeepsItsMessage() {
        let cause = "The tag refused page 31, so it was not fully written."
        #expect(NFCManager.rawWriteFailureMessage(pagesWritten: 0, totalPages: 28, cause: cause) == cause)
    }

    /// A lost connection on the first WRITE cannot say whether that page landed.
    @Test func aLostTagOnTheFirstPageKeepsItsMessage() {
        let cause = "Write failed at page 31: Tag connection lost"
        #expect(NFCManager.rawWriteFailureMessage(pagesWritten: 0, totalPages: 28, cause: cause) == cause)
    }

    // MARK: - Fixtures

    private let sample = FilamentTagData(
        name: "White PETG Basic",
        material: "PETG",
        subtype: nil,
        brand: "Polar Filament",
        colorHex: "1A2B3C",
        minNozzleTemp: 250,
        maxNozzleTemp: 260,
        minBedTemp: 70,
        maxBedTemp: 75,
        diameter: 1.75,
        nominalNetWeight: 1000
    )

    private func hex(_ string: String) -> Data {
        var bytes: [UInt8] = []
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            bytes.append(UInt8(string[index..<next], radix: 16) ?? 0)
            index = next
        }
        return Data(bytes)
    }
}
