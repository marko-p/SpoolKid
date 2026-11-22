//
//  Type5Format.swift
//  SpoolKid
//
//  Purpose: The bytes that turn a factory-blank ISO 15693 tag into an empty
//  NFC Forum Type 5 tag.
//
//  iOS writes NDEF only to a tag that already carries a capability container
//  (CC) in block 0. NTAGs ship with one; ICODE SLIX tags typically ship with
//  every block zero, and `queryNDEFStatus` answers notSupported until
//  something writes the CC. The layout follows the OpenPrintTag reference
//  initializer (`utils/nfc_initialize.py`): `E1 40 <memory / 8> <MBREAD>`,
//  then an NDEF TLV holding no message, then the terminator.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum Type5Format {

    /// CC magic for one-byte memory sizes, then version 1.0 with unrestricted
    /// read and write access.
    private static let magic: UInt8 = 0xE1
    private static let versionAndAccess: UInt8 = 0x40

    /// CC byte 3, bit 0: readers may use Read Multiple Blocks.
    private static let multipleBlockReadFlag: UInt8 = 0x01

    /// An NDEF TLV with a zero-length message, then the terminator TLV.
    private static let emptyNDEF: [UInt8] = [0x03, 0x00, 0xFE]

    /// Whether a scanned tag's memory, read from block 0, holds nothing.
    ///
    /// Without a capability container the tag is not NDEF, so only all-zero
    /// memory is empty — a factory-blank tag; any other byte is data in a
    /// format SpoolKid does not know. With one, the NTAG rule applies to the
    /// TLV chain after it (`TagDumpDecode.isBlank`): no message, or only
    /// TNF-empty records. A CC whose size byte is zero is the 8-byte form,
    /// so the chain starts at byte 8 rather than 4.
    static func isBlank(memory: [UInt8]) -> Bool {
        guard memory.count >= 4 else { return false }
        guard memory[0] == magic || memory[0] == 0xE2 else {
            return memory.allSatisfy { $0 == 0 }
        }
        return TagDumpDecode.isBlank(in: memory, from: memory[2] == 0 ? 8 : 4)
    }

    /// Whether block 0 holds no capability container at all.
    ///
    /// Only an all-zero block counts: anything else is data SpoolKid did not
    /// write — a CC iOS refused, or a format that is not NDEF — and is never
    /// overwritten.
    static func isUnformatted(firstBlock: Data) -> Bool {
        !firstBlock.isEmpty && firstBlock.allSatisfy { $0 == 0 }
    }

    /// The block writes that format a blank tag, in the order to send them.
    ///
    /// `blockSize` and `blockCount` are Get System Info's, which CoreNFC
    /// reports as actual values and as -1 when the tag leaves them out; nil
    /// means the tag cannot be formatted from what it said. Block 0 comes
    /// last, so a format cut short leaves the tag looking as blank as before.
    ///
    /// A SLIX2 (named by `uid`) declares one block fewer: block 79 is its
    /// counter (SL2S2602 §9.2). Its 80 blocks declare 312 bytes, CC `0x27`,
    /// the size Prusament's SLIX2 tags are inferred to declare.
    static func formatWrites(
        blockSize: Int,
        blockCount: Int,
        multipleBlockRead: Bool,
        uid: [UInt8]
    ) -> [(block: Int, data: Data)]? {
        guard blockSize > 0, blockCount > 0 else { return nil }
        let declaredBlocks = TagDumpWalk.isSLIX2(uid: uid) ? blockCount - 1 : blockCount
        let memoryUnits = min(declaredBlocks * blockSize / 8, 0xFF)
        let bytes = [magic, versionAndAccess, UInt8(memoryUnits),
                     multipleBlockRead ? multipleBlockReadFlag : 0x00] + emptyNDEF
        guard memoryUnits > 0, blockSize * blockCount >= bytes.count else { return nil }

        let padded = bytes + [UInt8](repeating: 0, count: (blockSize - bytes.count % blockSize) % blockSize)
        let blocks = stride(from: 0, to: padded.count, by: blockSize).map {
            (block: $0 / blockSize, data: Data(padded[$0..<($0 + blockSize)]))
        }
        return blocks.reversed()
    }
}
