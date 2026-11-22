//
//  LocationTagPayload.swift
//  SpoolKid
//
//  Purpose: What a SpoolKid location tag carries — a stable uuid plus the
//  location's name at the time of writing.
//
//  Deliberately NOT a `TagFormat` case and never a `FilamentTagData`: the four
//  filament formats and their round-trip tests are a hard invariant, and the
//  cheapest way to protect them is to stay outside their blast radius. A tag
//  holds either a location record or filament data, never both — an NDEF write
//  replaces the whole message.
//
//  The uuid, not the name, is the identity: a location renamed after its tag
//  was written still resolves, and the on-tag name is a cached label.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated struct LocationTagPayload: Equatable, Sendable {
    static let mimeType = "application/vnd.spoolkid.location"
    static let protocolName = "spoolkid-location"
    static let version = 1

    let uuid: UUID
    let name: String

    /// Written as a well-known Text record BEFORE the MIME record, so a
    /// generic NFC reader shows something a person can act on.
    var textRecordString: String { "SpoolKid location: \(name)" }

    func encoded() -> Data? {
        let object: [String: Any] = [
            "protocol": Self.protocolName,
            "version": Self.version,
            "id": uuid.uuidString,
            "name": name
        ]
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// Strict on purpose. A foreign MIME type, an unknown `version`, a
    /// protocol that is not ours, a malformed id or a blank name are all
    /// refused outright rather than best-effort parsed — a refused payload
    /// falls through to the existing scan paths, so an unrecognised tag is
    /// never silently treated as a location.
    static func decode(payload: Data, mimeType: String?) -> LocationTagPayload? {
        guard mimeType == Self.mimeType else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return nil }
        guard object["protocol"] as? String == Self.protocolName else { return nil }
        guard let version = object["version"] as? Int, version == Self.version else { return nil }
        guard let idString = object["id"] as? String, let uuid = UUID(uuidString: idString) else { return nil }

        let name = LocationName.trimmed(object["name"] as? String ?? "")
        guard !name.isEmpty else { return nil }

        return LocationTagPayload(uuid: uuid, name: name)
    }
}
