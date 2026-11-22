//
//  Type5FormatTests.swift
//  SpoolKidTests
//
//  What SpoolKid writes to a factory-blank ISO 15693 tag before iOS will
//  write NDEF to it. The bytes follow the OpenPrintTag reference initializer
//  (utils/nfc_initialize.py): CC `E1 40 <memory / 8> <MBREAD>`, then an empty
//  NDEF TLV. The fixture is the owner's ICODE SLIX dump of 2026-10-02 —
//  28 blocks of 4 bytes, every one of them zero.
//

import CoreNFC
import Foundation
import Testing
@testable import SpoolKid

struct Type5FormatTests {

    // MARK: - Which tags are blank

    @Test func aZeroFirstBlockIsUnformatted() {
        #expect(Type5Format.isUnformatted(firstBlock: Data([0x00, 0x00, 0x00, 0x00])))
    }

    @Test func aCapabilityContainerIsNotUnformatted() {
        #expect(!Type5Format.isUnformatted(firstBlock: Data([0xE1, 0x40, 0x0E, 0x01])))
    }

    /// Any byte that is not zero is data SpoolKid did not put there.
    @Test func foreignBytesAreNotUnformatted() {
        #expect(!Type5Format.isUnformatted(firstBlock: Data([0x00, 0x00, 0x7F, 0x00])))
    }

    /// An empty read is no reading at all, not evidence of a blank tag.
    @Test func anEmptyReadIsNotUnformatted() {
        #expect(!Type5Format.isUnformatted(firstBlock: Data()))
    }

    // MARK: - What gets written

    @Test func theOwnersICODESLIXGetsTheReferenceContainer() throws {
        let writes = try #require(Type5Format.formatWrites(blockSize: 4, blockCount: 28, multipleBlockRead: true, uid: []))
        #expect(blocks(writes) == [
            0: Data([0xE1, 0x40, 0x0E, 0x01]),
            1: Data([0x03, 0x00, 0xFE, 0x00])
        ])
    }

    /// A tag not named SLIX2 by its UID declares all of its memory.
    @Test func anUnnamedEightyBlockTagDeclaresItsWholeMemory() throws {
        let writes = try #require(Type5Format.formatWrites(blockSize: 4, blockCount: 80, multipleBlockRead: true, uid: []))
        #expect(blocks(writes)[0] == Data([0xE1, 0x40, 0x28, 0x01]))
    }

    /// Block 79 is the SLIX2's counter and holds no user data: 79 blocks of
    /// 4 B are 316 B, which the 8-byte units round down to 312 (0x27).
    @Test func anICODESLIX2LeavesItsCounterBlockOut() throws {
        let writes = try #require(Type5Format.formatWrites(
            blockSize: 4, blockCount: 80, multipleBlockRead: true,
            uid: [0xE0, 0x04, 0x01, 0x09, 0x18, 0xED, 0xD6, 0xBD]
        ))
        #expect(blocks(writes)[0] == Data([0xE1, 0x40, 0x27, 0x01]))
    }

    /// The owner's SLIX has no counter block, so its 28 blocks are all declared.
    @Test func anICODESLIXIsUnchangedByItsUID() throws {
        let writes = try #require(Type5Format.formatWrites(
            blockSize: 4, blockCount: 28, multipleBlockRead: true,
            uid: [0xE0, 0x04, 0x01, 0x53, 0x09, 0xB8, 0x60, 0x31]
        ))
        #expect(blocks(writes)[0] == Data([0xE1, 0x40, 0x0E, 0x01]))
    }

    /// MBREAD tells readers they may use Read Multiple Blocks. It is claimed
    /// only for a tag that just answered one.
    @Test func multipleBlockReadIsClaimedOnlyWhenSeen() throws {
        let writes = try #require(Type5Format.formatWrites(blockSize: 4, blockCount: 28, multipleBlockRead: false, uid: []))
        #expect(blocks(writes)[0] == Data([0xE1, 0x40, 0x0E, 0x00]))
    }

    @Test func eightByteBlocksHoldContainerAndTLVInOneBlock() throws {
        let writes = try #require(Type5Format.formatWrites(blockSize: 8, blockCount: 14, multipleBlockRead: true, uid: []))
        #expect(blocks(writes) == [0: Data([0xE1, 0x40, 0x0E, 0x01, 0x03, 0x00, 0xFE, 0x00])])
    }

    /// The CC counts memory in 8-byte units; a remainder is not declared.
    @Test func memoryRoundsDownToEightByteUnits() throws {
        let writes = try #require(Type5Format.formatWrites(blockSize: 4, blockCount: 27, multipleBlockRead: true, uid: []))
        #expect(blocks(writes)[0]?[2] == 0x0D)
    }

    /// Past 2040 bytes the one-byte size cannot say more; the tag is declared
    /// at the most it can, which is still a valid tag.
    @Test func largeMemoryIsCappedAtTheOneByteMaximum() throws {
        let writes = try #require(Type5Format.formatWrites(blockSize: 8, blockCount: 256, multipleBlockRead: true, uid: []))
        #expect(blocks(writes)[0]?[2] == 0xFF)
    }

    /// A partial format must leave the tag as blank as it found it, so a retry
    /// starts over. Block 0 is what makes a tag look formatted; it goes last.
    @Test func theCapabilityContainerIsWrittenLast() throws {
        let writes = try #require(Type5Format.formatWrites(blockSize: 4, blockCount: 28, multipleBlockRead: true, uid: []))
        #expect(writes.map(\.block) == [1, 0])
    }

    @Test func aMissingSizeFormatsNothing() {
        // CoreNFC reports -1 when the tag's reply leaves the field out.
        #expect(Type5Format.formatWrites(blockSize: -1, blockCount: 28, multipleBlockRead: true, uid: []) == nil)
        #expect(Type5Format.formatWrites(blockSize: 4, blockCount: -1, multipleBlockRead: true, uid: []) == nil)
    }

    /// Seven bytes — CC plus an empty TLV — is the least a tag must hold.
    @Test func aTagTooSmallForAnEmptyMessageFormatsNothing() {
        #expect(Type5Format.formatWrites(blockSize: 4, blockCount: 1, multipleBlockRead: true, uid: []) == nil)
    }

    // MARK: - Which scanned tags are empty

    /// The owner's ICODE SLIX as it shipped: 28 blocks, every byte zero.
    @Test func aFactoryBlankTagIsEmpty() {
        #expect(Type5Format.isBlank(memory: [UInt8](repeating: 0, count: 112)))
    }

    /// What `formatWrites` leaves when the write after it never lands.
    @Test func aFormattedTagWithNoMessageIsEmpty() {
        let memory: [UInt8] = [0xE1, 0x40, 0x0E, 0x01, 0x03, 0x00, 0xFE, 0x00] + zeros(104)
        #expect(Type5Format.isBlank(memory: memory))
    }

    /// What "Empty This Tag…" writes: one TNF-empty record.
    @Test func anEmptiedTagIsEmpty() {
        let memory: [UInt8] = [0xE1, 0x40, 0x0E, 0x01, 0x03, 0x03, 0xD0, 0x00, 0x00, 0xFE] + zeros(102)
        #expect(Type5Format.isBlank(memory: memory))
    }

    /// An 8-byte CC (byte 2 zero, size in bytes 6–7) puts the TLV chain at byte 8.
    @Test func anEightByteContainerIsReadPast() {
        let memory: [UInt8] = [0xE2, 0x40, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x03, 0x00, 0xFE] + zeros(101)
        #expect(Type5Format.isBlank(memory: memory))
    }

    @Test func aTagWithAMessageIsNotEmpty() {
        let memory: [UInt8] = [0xE1, 0x40, 0x0E, 0x01, 0x03, 0x05, 0xD1, 0x01, 0x01, 0x55, 0x00, 0xFE] + zeros(100)
        #expect(!Type5Format.isBlank(memory: memory))
    }

    /// No CC, so not NDEF — and bytes after it are data in a format SpoolKid
    /// does not know, not padding.
    @Test func dataWithoutAContainerIsNotEmpty() {
        let memory: [UInt8] = zeros(16) + [0x5B, 0xF5, 0x92, 0x64] + zeros(92)
        #expect(!Type5Format.isBlank(memory: memory))
    }

    @Test func aForeignFirstBlockIsNotEmpty() {
        let memory: [UInt8] = [0x12, 0x34, 0x56, 0x78] + zeros(108)
        #expect(!Type5Format.isBlank(memory: memory))
    }

    /// A read that returned nothing proves nothing.
    @Test func anUnreadTagIsNotEmpty() {
        #expect(!Type5Format.isBlank(memory: []))
    }

    // MARK: - What a refused write says

    @Test func aReadOnlyTagSaysSo() {
        #expect(NFCManager.ndefStatusRefusal(.readOnly, preparedBlankTag: false)
                == "Tag is read-only (write-protected).")
    }

    @Test func anUnsupportedTagIsNotWritable() {
        #expect(NFCManager.ndefStatusRefusal(.notSupported, preparedBlankTag: false)
                == "Tag is not writable.")
    }

    /// The tag was changed, so "not writable" would be false: it is now set up,
    /// and a second tap writes it.
    @Test func aTagPreparedThisTapAsksForAnotherTap() {
        #expect(NFCManager.ndefStatusRefusal(.notSupported, preparedBlankTag: true)
                == "This blank tag is now set up. Hold it near again to write.")
    }

    // MARK: - Helpers

    private func zeros(_ count: Int) -> [UInt8] {
        [UInt8](repeating: 0, count: count)
    }

    private func blocks(_ writes: [(block: Int, data: Data)]) -> [Int: Data] {
        Dictionary(uniqueKeysWithValues: writes.map { ($0.block, $0.data) })
    }
}
