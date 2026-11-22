//
//  TigerTagSignature.swift
//  SpoolKid
//
//  Purpose: Offline ECDSA-P256 verification of the optional TigerTag
//  signature (spec §3). The signed input is the raw 15 bytes
//  UID ‖ block4 ‖ block5; the hash is applied exactly once, inside the
//  signature API — the SDK reference verifies
//  `pub.verify(der, message, ECDSA(SHA256()))` over the same raw message.
//  Pre-hashing here would double-hash and read every genuine factory tag
//  invalid. The signature on the tag is raw r‖s (64 bytes) at data
//  offsets 80–143. The public key ships with the protocol, so no network
//  is involved.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import CryptoKit

enum TigerTagSignatureStatus: Equatable, Sendable {
    case valid, unsigned, invalid
}

struct TigerTagInfo: Equatable, Sendable {
    let variant: TigerTagVariant
    let signature: TigerTagSignatureStatus
}

enum TigerTagSignature {

    /// Verifies against the protocol's embedded public key (id_version.json).
    /// `uid` is the tag's raw identifier Data from CoreNFC.
    static func verify(uid: Data, dataBytes: [UInt8]) -> TigerTagSignatureStatus {
        guard let key = TigerTagRegistry.publicKey() else { return .invalid }
        guard dataBytes.count >= TigerTagPayload.totalByteCount else { return .invalid }
        let signatureBytes = dataBytes[TigerTagPayload.signatureRangeInData]
        // All-zero pages are an unsigned chip — a normal state, not an error.
        if signatureBytes.allSatisfy({ $0 == 0 }) { return .unsigned }
        return verify(uid: uid, dataBytes: dataBytes, publicKey: key) ? .valid : .invalid
    }

    /// The pure math, open for tests: any P-256 key.
    static func verify(uid: Data, dataBytes: [UInt8], publicKey: P256.Signing.PublicKey) -> Bool {
        guard dataBytes.count >= TigerTagPayload.totalByteCount, !uid.isEmpty else { return false }
        let message = uid + Data(dataBytes[0..<8])
        guard let signature = try? P256.Signing.ECDSASignature(
            rawRepresentation: Data(dataBytes[TigerTagPayload.signatureRangeInData])
        ) else { return false }
        return publicKey.isValidSignature(signature, for: message)
    }
}
