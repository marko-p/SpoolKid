//
//  CardUIDsCodec.swift
//  SpoolKid
//
//  Purpose: Encode/decode the SpoolLink `card_uids` extra field.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// Pure codec for the SpoolLink `card_uids` Spoolman custom field.
///
/// Spoolman stores every `extra` value JSON-encoded, so the value carried in
/// `spool.extra["card_uids"]` is a quoted string such as
/// `"\"AABBCCDD,11223344\""`. The codec JSON-unwraps on read, splits on `,`,
/// normalizes each UID through `SpoolMappingService.normalizeUID`, deduplicates
/// order-preserving, and JSON-wraps on write. Cardinality is unlimited.
nonisolated enum CardUIDsCodec {
    /// Comma-separated is what SpoolKid writes; Bespok3D's bridge writes a
    /// JSON array, which it stores inside the same string wrapping.
    private static func parts(of inner: String) -> [String] {
        if inner.hasPrefix("["), let data = inner.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return array
        }
        return inner.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    }

    static func parse(_ extraValue: String?) -> [String] {
        guard let extraValue else { return [] }

        let inner: String
        if let unwrapped = jsonUnwrap(extraValue) {
            inner = unwrapped
        } else {
            inner = extraValue
        }

        guard !inner.isEmpty else { return [] }

        var seen = Set<String>()
        var result: [String] = []

        for part in parts(of: inner) {
            var normalized = SpoolMappingService.normalizeUID(part)
            if normalized.hasPrefix("0X") { normalized.removeFirst(2) }
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }

        return result
    }

    static func encode(_ uids: [String]) -> String {
        let normalized = uniqueNormalizedUIDs(from: uids)
        let inner = normalized.joined(separator: ",")
        return jsonWrap(inner)
    }

    /// Bare comma-separated form, for backends that store `extra`/`custom_fields`
    /// as free-form JSON rather than Spoolman's quoted-string convention.
    ///
    /// FilaMan's Spoolman-compat layer JSON-encodes each custom field on read,
    /// so a value written bare through the native API comes back through
    /// `/spoolman/api/v1/` byte-identical to what Spoolman itself would serve —
    /// which is what keeps SpoolLink and Snapmaker U1 clients working against
    /// either backend. Verified live 2026-08-21: `custom_fields`
    /// `{"card_uids": "AABBCCDD,11223344"}` written natively reads back from the
    /// compat layer as `{"card_uids": "\"AABBCCDD,11223344\""}`.
    ///
    /// Writing `encode`'s wrapped form here instead would double-wrap through
    /// that layer. `parse` tolerates both, so SpoolKid itself would not notice —
    /// only other clients would.
    static func encodeBare(_ uids: [String]) -> String {
        uniqueNormalizedUIDs(from: uids).joined(separator: ",")
    }

    // MARK: - Applying a draft's UID list to a field dictionary

    /// The `extra` / `custom_fields` key the UID list lives under, on every
    /// mapping-capable backend. Named once so the four writers cannot drift.
    static let fieldKey = "card_uids"

    /// Merges `uids` into an `extra`-style dictionary in the **wrapped** form —
    /// Spoolman's `extra` convention, which the local store mirrors so a spool
    /// migrated between them round-trips byte-identically.
    static func applyingWrapped(_ uids: [String]?, to fields: [String: String]?) -> [String: String]? {
        applying(uids, to: fields, encoded: encode)
    }

    /// The same merge against an `extra` PATCH rather than a plain dictionary.
    ///
    /// A stated UID list always produces a `.set`, whatever the patch said:
    /// the mapping is the one thing this draft definitely means to write, and
    /// `.ignore`/`.setNil` describe the bucket it happens to live in, not the
    /// mapping. `nil` uids leave the patch exactly as it came — including
    /// `.ignore`, which is what stops an untouched form re-asserting the whole
    /// object (R21 stage 3c).
    ///
    /// In practice only `MigrationService` sets both, and only on a create.
    static func applyingWrapped(
        _ uids: [String]?, to patch: SpoolmanPatchValue<[String: String]>
    ) -> SpoolmanPatchValue<[String: String]> {
        guard uids != nil else { return patch }
        let base: [String: String]? = if case .set(let fields) = patch { fields } else { nil }
        return .set(applyingWrapped(uids, to: base) ?? [:])
    }

    /// Merges `uids` into a `custom_fields`-style dictionary in the **bare**
    /// form — FilaMan's, whose compat layer adds the wrapper itself on read.
    /// See `encodeBare` for why writing the wrapped form here is a defect.
    static func applyingBare(_ uids: [String]?, to fields: [String: String]?) -> [String: String]? {
        applying(uids, to: fields, encoded: encodeBare)
    }

    /// `nil` uids means the caller said nothing about the mapping, so the
    /// dictionary — including any `card_uids` already in it — is returned
    /// untouched. A non-nil list always wins over an entry already present:
    /// that entry is pre-encoded in *some* backend's form, and only the typed
    /// list knows which one this destination wants.
    private static func applying(
        _ uids: [String]?, to fields: [String: String]?, encoded: ([String]) -> String
    ) -> [String: String]? {
        guard let uids else { return fields }
        var merged = fields ?? [:]
        merged[fieldKey] = encoded(uids)
        return merged
    }

    // MARK: - Private helpers

    private static func jsonUnwrap(_ value: String) -> String? {
        guard let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(String.self, from: data)
    }

    private static func jsonWrap(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let wrapped = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return wrapped
    }

    private static func uniqueNormalizedUIDs(from uids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for uid in uids {
            let normalized = SpoolMappingService.normalizeUID(uid)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }

        return result
    }
}
