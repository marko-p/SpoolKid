//
//  TigerTagSignatureTests.swift
//  SpoolKidTests
//
//  Nobody outside TigerTag Corp holds the signing key, so the .valid path is
//  proven with a CryptoKit-generated test keypair over the documented message;
//  the embedded protocol key gets its own negative test (a rogue signature
//  must NOT verify under it) plus a parse test in TigerTagRegistryTests.
//

import Testing
import Foundation
import CryptoKit
@testable import SpoolKid

struct TigerTagSignatureTests {

    private static var sampleData: [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 144)
        bytes[0] = 0x5B; bytes[1] = 0xF5; bytes[2] = 0x92; bytes[3] = 0x64 // ID TigerTag
        bytes[4] = 0xFF; bytes[5] = 0xFF; bytes[6] = 0xFF; bytes[7] = 0xFF // ID Product
        return bytes
    }

    /// The signed input is the raw 15 bytes UID ‖ block4 ‖ block5 — the hash
    /// is applied once, inside the signature API (the SDK reference hashes
    /// `message` exactly once: `pub.verify(der, message, ECDSA(SHA256()))`).
    @Test func verifiesASignatureOverTheDocumentedMessage() throws {
        let privateKey = P256.Signing.PrivateKey()
        let uid = Data([0x04, 0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6])
        var data = Self.sampleData

        let message = uid + Data(data[0..<8])
        let signature = try privateKey.signature(for: message) // hashes once, internally
        data.replaceSubrange(80..<144, with: signature.rawRepresentation) // r‖s, 64 bytes

        #expect(TigerTagSignature.verify(uid: uid, dataBytes: data, publicKey: privateKey.publicKey))
    }

    /// The signature covers ONLY the identity bytes (uid ‖ block4 ‖ block5).
    /// Settings fields are deliberately outside it — that is how TigerTag+
    /// remote updates keep a genuine tag valid (spec §3) — so a tamper test
    /// must flip an identity byte, not a settings byte.
    @Test func tamperedIdentityIsInvalid() throws {
        let privateKey = P256.Signing.PrivateKey()
        let uid = Data([0x04, 0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6])
        var data = Self.sampleData
        let signature = try privateKey.signature(for: uid + Data(data[0..<8]))
        data.replaceSubrange(80..<144, with: signature.rawRepresentation)

        data[6] = 0x01 // inside block5 — the chip's identity
        #expect(!TigerTagSignature.verify(uid: uid, dataBytes: data, publicKey: privateKey.publicKey))
    }

    /// The flip side of the identity-only coverage: a settings change does
    /// NOT break the signature. If this ever fails, the message construction
    /// has drifted beyond block5 and genuine remote-updated tags would read
    /// invalid.
    @Test func settingsChangeKeepsTheSignatureValid() throws {
        let privateKey = P256.Signing.PrivateKey()
        let uid = Data([0x04, 0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6])
        var data = Self.sampleData
        let signature = try privateKey.signature(for: uid + Data(data[0..<8]))
        data.replaceSubrange(80..<144, with: signature.rawRepresentation)

        data[24] = 0xC3 // a nozzle temperature — outside the signed message
        #expect(TigerTagSignature.verify(uid: uid, dataBytes: data, publicKey: privateKey.publicKey))
    }

    @Test func tamperedSignatureIsInvalid() throws {
        let privateKey = P256.Signing.PrivateKey()
        let uid = Data([0x04] + Array(repeating: 0xB2, count: 6))
        var data = Self.sampleData
        let signature = try privateKey.signature(for: uid + Data(data[0..<8]))
        data.replaceSubrange(80..<144, with: signature.rawRepresentation)

        data[100] ^= 0xFF
        #expect(!TigerTagSignature.verify(uid: uid, dataBytes: data, publicKey: privateKey.publicKey))
    }

    @Test func wrongUIDIsInvalid() throws {
        let privateKey = P256.Signing.PrivateKey()
        let uid = Data(Array(repeating: 0x04, count: 7))
        var data = Self.sampleData
        let signature = try privateKey.signature(for: uid + Data(data[0..<8]))
        data.replaceSubrange(80..<144, with: signature.rawRepresentation)

        #expect(!TigerTagSignature.verify(
            uid: Data(Array(repeating: 0x05, count: 7)),
            dataBytes: data,
            publicKey: privateKey.publicKey
        ))
    }

    @Test func zeroSignatureIsUnsigned() {
        let status = TigerTagSignature.verify(
            uid: Data(Array(repeating: 0x04, count: 7)),
            dataBytes: Array(hex: "6c41a2e100000000000000000000000000000000000000150000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000") + [UInt8](repeating: 0, count: 64)
        )
        #expect(status == .unsigned)
    }

    /// The embedded protocol key must parse — a malformed PEM would turn
    /// every genuine tag "unsigned" at runtime.
    @Test func embeddedPublicKeyParsesAndRejectsRogueSignatures() throws {
        let key = try #require(TigerTagRegistry.publicKey())
        let privateKey = P256.Signing.PrivateKey()
        let uid = Data(Array(repeating: 0x04, count: 7))
        let data = Self.sampleData
        let rogue = try privateKey.signature(for: uid + Data(data[0..<8]))
        var signed = data
        signed.replaceSubrange(80..<144, with: rogue.rawRepresentation)
        #expect(TigerTagSignature.verify(uid: uid, dataBytes: signed) == .invalid)
    }
}
