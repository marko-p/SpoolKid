//
//  NFCCloneWriteTests.swift
//  SpoolKidTests
//
//  What a clone may be written onto. The session needs a tag; these pin the
//  decisions it takes before writing a byte, so a copy can never land on the
//  tag it came from, on a tag another spool or shelf owns, or past the end of
//  a chip's user memory.
//

import Foundation
import Testing
@testable import SpoolKid

struct NFCCloneWriteTests {

    // MARK: - Which tag

    @Test func presentingTheScannedTagAgainIsRefused() {
        #expect(NFCManager.cloneWriteDecision(
            targetUID: "04a1b2c3", sourceUID: "04:A1:B2:C3", blockedUIDs: [], allowedUID: nil
        ) == .sameTag)
    }

    @Test func aTagSomethingElseOwnsIsBlocked() {
        #expect(NFCManager.cloneWriteDecision(
            targetUID: "aabbccdd", sourceUID: "04A1B2C3", blockedUIDs: ["AABBCCDD"], allowedUID: nil
        ) == .blocked(uid: "AABBCCDD"))
    }

    @Test func blockedUIDsAreNormalizedBeforeComparing() {
        #expect(NFCManager.cloneWriteDecision(
            targetUID: "AABBCCDD", sourceUID: nil, blockedUIDs: ["aa:bb:cc:dd"], allowedUID: nil
        ) == .blocked(uid: "AABBCCDD"))
    }

    @Test func theOneTagTheUserAgreedToTakeProceeds() {
        #expect(NFCManager.cloneWriteDecision(
            targetUID: "AABBCCDD", sourceUID: "04A1B2C3", blockedUIDs: ["AABBCCDD"], allowedUID: "aabbccdd"
        ) == .proceed)
    }

    @Test func allowingOneTagDoesNotAllowAnother() {
        #expect(NFCManager.cloneWriteDecision(
            targetUID: "11223344", sourceUID: "04A1B2C3", blockedUIDs: ["AABBCCDD", "11223344"], allowedUID: "AABBCCDD"
        ) == .blocked(uid: "11223344"))
    }

    /// The source tag is never a target, whatever else is true of it.
    @Test func theSourceTagIsRefusedEvenWhenAllowed() {
        #expect(NFCManager.cloneWriteDecision(
            targetUID: "04A1B2C3", sourceUID: "04A1B2C3", blockedUIDs: ["04A1B2C3"], allowedUID: "04A1B2C3"
        ) == .sameTag)
    }

    /// ISO 15693 tags can arrive without a UID. Refusing them would make Type 5
    /// tags unusable as copies — the same reasoning as `locationWriteDecision`.
    @Test func aTagWithoutAUIDProceeds() {
        #expect(NFCManager.cloneWriteDecision(
            targetUID: nil, sourceUID: "04A1B2C3", blockedUIDs: ["AABBCCDD"], allowedUID: nil
        ) == .proceed)
    }

    @Test func anUnclaimedTagProceeds() {
        #expect(NFCManager.cloneWriteDecision(
            targetUID: "55667788", sourceUID: "04A1B2C3", blockedUIDs: ["AABBCCDD"], allowedUID: nil
        ) == .proceed)
    }

    // MARK: - Whether it fits

    /// User memory ends six pages before the end of an NTAG213/215/216: a
    /// dynamic lock page, then CFG0, CFG1, PWD and PACK.
    @Test(arguments: [
        (35, 45, true), (39, 45, true), (40, 45, false),
        (35, 135, true), (129, 135, true), (130, 135, false),
        (225, 231, true), (226, 231, false)
    ])
    func aRawCopyFitsOnlyInUserMemory(lastPage: Int, pageCount: Int, fits: Bool) {
        #expect(NFCManager.rawCloneFits(lastPage: lastPage, pageCount: pageCount) == fits)
    }

    /// A chip that does not report its size is written anyway, because a clone
    /// writes its highest page first: a chip without that page refuses before
    /// anything lands (see `rawWriteOrder`).
    @Test func anUnknownChipSizeLetsTheWriteDecide() {
        #expect(NFCManager.rawCloneFits(lastPage: 35, pageCount: nil))
    }

    // MARK: - What gets written

    @Test func aRawSnapshotWritesOnePagePerFourBytesInOrder() {
        let snapshot = TagSnapshot.rawPages(firstPage: 4, bytes: [
            0x7B, 0x00, 0x65, 0x00,
            0x41, 0x48, 0x50, 0x4C,
            0x56, 0x4F, 0x2D, 0x31
        ])
        let writes = snapshot.pageWrites

        #expect(writes.map(\.page) == [4, 5, 6])
        #expect(writes.map(\.data) == [
            Data([0x7B, 0x00, 0x65, 0x00]),
            Data([0x41, 0x48, 0x50, 0x4C]),
            Data([0x56, 0x4F, 0x2D, 0x31])
        ])
    }

    /// Highest page first, so a chip smaller than the copy refuses the first
    /// WRITE — before the config pages a 20-page chip keeps at 16-19 are reached.
    @Test func aRawCloneWritesItsHighestPageFirst() {
        let snapshot = TagSnapshot.rawPages(firstPage: 4, bytes: [
            0x7B, 0x00, 0x65, 0x00,
            0x41, 0x48, 0x50, 0x4C,
            0x56, 0x4F, 0x2D, 0x31
        ])
        let order = NFCManager.rawWriteOrder(snapshot.pageWrites)

        #expect(order.map(\.page) == [6, 5, 4])
        #expect(order.first?.data == Data([0x56, 0x4F, 0x2D, 0x31]))
    }

    // MARK: - Lock bits and read-only

    /// Pages 0-3 of a real, writable NTAG213 (the ELEGOO tester dump).
    private let writableHeader: [UInt8] = [
        0x53, 0xCC, 0x7A, 0x6D, 0x05, 0x30, 0x00, 0x04,
        0x31, 0x48, 0x00, 0x00, 0xE1, 0x10, 0x12, 0x00
    ]

    @Test func aWritableTagAllowsARawClone() {
        #expect(NFCManager.rawWriteHeaderAllowsWrite(Data(writableHeader)) == true)
    }

    @Test func staticLockBitsOverUserPagesRefuseARawClone() {
        var pages4To7 = writableHeader
        pages4To7[10] = 0x10
        var pages8To15 = writableHeader
        pages8To15[11] = 0x01

        #expect(NFCManager.rawWriteHeaderAllowsWrite(Data(pages4To7)) == false)
        #expect(NFCManager.rawWriteHeaderAllowsWrite(Data(pages8To15)) == false)
    }

    /// Block-lock bits and the capability container's own lock bit protect
    /// nothing a copy writes.
    @Test func lockBitsOutsidePages4To15DoNotRefuse() {
        var header = writableHeader
        header[10] = 0x0F
        #expect(NFCManager.rawWriteHeaderAllowsWrite(Data(header)) == true)
    }

    @Test func theLastLockBitOfEachByteRefusesToo() {
        var page7 = writableHeader
        page7[10] = 0x80
        var page15 = writableHeader
        page15[11] = 0x80

        #expect(NFCManager.rawWriteHeaderAllowsWrite(Data(page7)) == false)
        #expect(NFCManager.rawWriteHeaderAllowsWrite(Data(page15)) == false)
    }

    /// Locking the capability container locks page 3, which a copy never writes.
    @Test func theCapabilityContainerLockBitAloneDoesNotRefuse() {
        var header = writableHeader
        header[10] = 0x08
        #expect(NFCManager.rawWriteHeaderAllowsWrite(Data(header)) == true)
    }

    // MARK: - What a failed raw write says

    @Test func aCopyCutShortSaysItIsPartlyWritten() {
        #expect(NFCManager.rawCloneFailureMessage(
            pagesWritten: 12, totalPages: 32, refused: true,
            cause: "The tag refused page 19, so it was not fully written."
        ) == "The copy was cut short after 12 of 32 pages, so the tag is only partly written. Clone it again.")
    }

    @Test func aRefusedFirstPageSaysNothingWasWritten() {
        #expect(NFCManager.rawCloneFailureMessage(
            pagesWritten: 0, totalPages: 32, refused: true,
            cause: "The tag refused page 35, so it was not fully written."
        ) == "The tag refused the copy before anything was written. It may be too small or protected — use a blank NTAG213 or larger.")
    }

    /// A lost connection on the first WRITE cannot say whether that page landed.
    @Test func aLostTagOnTheFirstPageKeepsItsCause() {
        #expect(NFCManager.rawCloneFailureMessage(
            pagesWritten: 0, totalPages: 32, refused: false,
            cause: "Write failed at page 35: Tag connection lost"
        ) == "The tag was lost before the copy could be confirmed (Write failed at page 35: Tag connection lost). Hold it still and clone again.")
    }

    /// The NDEF path refuses a read-only capability container; a raw copy must too.
    @Test func aReadOnlyCapabilityContainerRefusesARawClone() {
        var header = writableHeader
        header[15] = 0x0F
        #expect(NFCManager.rawWriteHeaderAllowsWrite(Data(header)) == false)
    }

    @Test func anIncompleteHeaderReadLeavesItToTheWrite() {
        #expect(NFCManager.rawWriteHeaderAllowsWrite(Data([0x00])) == nil)
    }

    @Test func anNDEFSnapshotHasNoPageWrites() {
        let record = NDEFRecordSnapshot(typeNameFormat: 0x02, type: Data("application/json".utf8), identifier: Data(), payload: Data("{}".utf8))
        #expect(TagSnapshot.ndef([record]).pageWrites.isEmpty)
    }

    @Test func onlyASnapshotWithContentIsCopyable() {
        let record = NDEFRecordSnapshot(typeNameFormat: 0x02, type: Data("application/json".utf8), identifier: Data(), payload: Data("{}".utf8))
        #expect(TagSnapshot.ndef([record]).isCopyable)
        #expect(!TagSnapshot.ndef([]).isCopyable)
        #expect(TagSnapshot.rawPages(firstPage: 4, bytes: [1, 2, 3, 4]).isCopyable)
        #expect(!TagSnapshot.rawPages(firstPage: 4, bytes: []).isCopyable)
        #expect(!TagSnapshot.rawPages(firstPage: 4, bytes: [1, 2, 3]).isCopyable)
    }
}
