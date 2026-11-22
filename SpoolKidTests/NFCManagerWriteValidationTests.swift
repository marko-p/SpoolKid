//
//  NFCManagerWriteValidationTests.swift
//  SpoolKidTests
//
//  A raw page write must never report success for pages the tag refused. The
//  fixtures are real configuration pages: a factory Anycubic tag, which is
//  password-protected against writes (issue #5, 2026-09-12), and an ELEGOO
//  tag, which is not (issue #4, 2026-09-10).
//

import Foundation
import Testing
@testable import SpoolKid

struct NFCManagerWriteValidationTests {

    // MARK: - The tag's reply to each page

    @Test func anACKIsAcceptance() {
        #expect(NFCManager.isAcknowledgedWriteResponse(Data([0x0A])))
    }

    /// NTAG NAK codes: invalid argument, CRC error, auth counter overflow,
    /// EEPROM write error. Each one used to be read as "carry on".
    @Test(arguments: [0x00, 0x01, 0x04, 0x05] as [UInt8])
    func aNAKIsRefusal(_ nak: UInt8) {
        #expect(!NFCManager.isAcknowledgedWriteResponse(Data([nak])))
    }

    /// CoreNFC may consume the ACK itself and hand back nothing.
    @Test func anEmptyReplyIsNotARefusal() {
        #expect(NFCManager.isAcknowledgedWriteResponse(Data()))
    }

    // MARK: - Asking the tag first

    @Test(arguments: [(45, 41), (135, 131), (231, 227)])
    func configurationStartsFourPagesBeforeTheEnd(pageCount: Int, configPage: Int) {
        #expect(NFCManager.configPage(forPageCount: pageCount) == configPage)
    }

    /// CFG0 `04000004` — AUTH0 = 4: every page from the first data page on
    /// needs Anycubic's password to write.
    @Test func aFactoryAnycubicTagCannotTakeAnACEWrite() {
        let reply = hex("04000004" + "47000000" + "00000000" + "00000000")
        #expect(NFCManager.writeNeedsPassword(configRead: reply, throughPage: 31) == true)
    }

    /// CFG0 `040000FF` — AUTH0 = 0xFF: no page is protected.
    @Test func anUnprotectedTagCanTakeAnACEWrite() {
        let reply = hex("040000FF" + "00050000" + "00000000" + "00000000")
        #expect(NFCManager.writeNeedsPassword(configRead: reply, throughPage: 31) == false)
    }

    @Test func protectionThatStartsPastTheLastPageWrittenDoesNotBlockTheWrite() {
        #expect(NFCManager.writeNeedsPassword(configRead: config(auth0: 32), throughPage: 31) == false)
        #expect(NFCManager.writeNeedsPassword(configRead: config(auth0: 31), throughPage: 31) == true)
    }

    /// A reply that is not a full READ says nothing either way; the per-page
    /// check still stands behind it.
    @Test func aShortReplyIsNoAnswer() {
        #expect(NFCManager.writeNeedsPassword(configRead: Data([0x04, 0x00]), throughPage: 31) == nil)
    }

    // MARK: - OpenPrintTag: the countdown that did not fit

    private func opt(consumed: Double? = nil, net: Double? = nil, density: Double? = nil,
                     diameter: Double? = nil) -> FilamentTagData {
        FilamentTagData(
            material: "PLA", brand: "Prusament", colorHex: "000000",
            minNozzleTemp: 200, maxNozzleTemp: 220, minBedTemp: 50, maxBedTemp: 60,
            density: density, diameter: diameter, nominalNetWeight: net, consumedWeight: consumed)
    }

    /// With an aux region written the printer has its place to count in, so
    /// the write has nothing to apologise for.
    @Test func anAuxRegionWrittenNeedsNoNote() {
        let data = opt(consumed: 200, net: 1000, density: 1.24, diameter: 1.75)
        #expect(!NFCManager.countdownDidNotFit(data: data, auxWritten: true))
    }

    @Test func aConsumptionWithNoRoomIsSaid() {
        #expect(NFCManager.countdownDidNotFit(data: opt(consumed: 200), auxWritten: false))
    }

    @Test func aComputableLengthWithNoRoomIsSaid() {
        let data = opt(net: 1000, density: 1.24, diameter: 1.75)
        #expect(NFCManager.countdownDidNotFit(data: data, auxWritten: false))
    }

    /// Nothing to count, nothing lost: a full spool whose density or diameter
    /// is unstated never had a countdown to write.
    @Test func nothingToCountNeedsNoNote() {
        #expect(!NFCManager.countdownDidNotFit(data: opt(), auxWritten: false))
        #expect(!NFCManager.countdownDidNotFit(data: opt(net: 1000, density: 1.24), auxWritten: false))
        #expect(!NFCManager.countdownDidNotFit(data: opt(consumed: 0), auxWritten: false))
    }

    // MARK: - Fixtures

    private func config(auth0: UInt8) -> Data {
        Data([0x04, 0x00, 0x00, auth0] + [UInt8](repeating: 0, count: 12))
    }

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
