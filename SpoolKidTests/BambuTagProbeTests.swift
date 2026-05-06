//
//  BambuTagProbeTests.swift
//  SpoolKidTests
//
//  Tests for BambuTagProbe: UID normalization, strict detection heuristics,
//  and encryption status reporting.
//

import Testing
@testable import SpoolKid

struct BambuTagProbeTests {

    // MARK: UID normalization

    @Test func normalizesRawBytesToLowercaseHexString() {
        let bytes: [UInt8] = [0x04, 0x5D, 0x77, 0x74, 0xCE, 0x2A, 0x81]
        let uid = BambuTagProbe.normalizeUID(bytes: bytes)
        #expect(uid == "045d7774ce2a81")
    }

    @Test func normalizesEmptyBytesToEmptyString() {
        let uid = BambuTagProbe.normalizeUID(bytes: [])
        #expect(uid == "")
    }

    @Test func normalizeSingleBytePadsToTwoHexChars() {
        let uid = BambuTagProbe.normalizeUID(bytes: [0x0A])
        #expect(uid == "0a")
    }

    // MARK: Detection heuristic

    @Test func sevenByteIdentifierStartingWith04IsMaybeBambu() {
        // Real Bambu Lab NFC tags use 7-byte NXP MIFARE identifiers starting with 0x04
        let bytes: [UInt8] = [0x04, 0x5D, 0x77, 0x74, 0xCE, 0x2A, 0x81]
        let result = BambuTagProbe.probe(identifierBytes: bytes, ndefPayload: nil)
        #expect(result.couldBeBambu == true)
    }

    @Test func fourByteIdentifierIsNotBambu() {
        // ISO 14443-3A 4-byte UID — not a Bambu format
        let bytes: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
        let result = BambuTagProbe.probe(identifierBytes: bytes, ndefPayload: nil)
        #expect(result.couldBeBambu == false)
    }

    @Test func sevenByteIdentifierNotStartingWith04IsNotBambu() {
        let bytes: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07]
        let result = BambuTagProbe.probe(identifierBytes: bytes, ndefPayload: nil)
        #expect(result.couldBeBambu == false)
    }

    @Test func emptyIdentifierIsNotBambu() {
        let result = BambuTagProbe.probe(identifierBytes: [], ndefPayload: nil)
        #expect(result.couldBeBambu == false)
    }

    // MARK: Encryption status

    @Test func probeAlwaysReportsDataEncrypted() {
        // iOS CoreNFC cannot read MIFARE Classic sectors, so data is always inaccessible
        let bytes: [UInt8] = [0x04, 0x5D, 0x77, 0x74, 0xCE, 0x2A, 0x81]
        let result = BambuTagProbe.probe(identifierBytes: bytes, ndefPayload: nil)
        #expect(result.dataEncrypted == true)
    }

    // MARK: Display label

    @Test func displayLabelIsBambuWhenCouldBeBambu() {
        let bytes: [UInt8] = [0x04, 0x5D, 0x77, 0x74, 0xCE, 0x2A, 0x81]
        let result = BambuTagProbe.probe(identifierBytes: bytes, ndefPayload: nil)
        #expect(result.displayLabel == "Bambu Lab (encrypted)")
    }

    @Test func displayLabelIsGenericWhenNotBambu() {
        let bytes: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
        let result = BambuTagProbe.probe(identifierBytes: bytes, ndefPayload: nil)
        #expect(result.displayLabel == "Encrypted MIFARE Classic")
    }

    // MARK: UID in result

    @Test func probeResultExposesNormalizedUID() {
        let bytes: [UInt8] = [0x04, 0x5D, 0x77, 0x74, 0xCE, 0x2A, 0x81]
        let result = BambuTagProbe.probe(identifierBytes: bytes, ndefPayload: nil)
        #expect(result.normalizedUID == "045d7774ce2a81")
    }
}
