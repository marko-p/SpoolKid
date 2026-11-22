//
//  TagReader.swift
//  SpoolKid
//
//  Purpose: SpoolKid as a Spoolman 0.27 tag reader — the id and name it
//  reports under, the `POST /tag/scan` body, which scans are reported, and
//  the copy.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// Who SpoolKid says it is. A browser pairs to the reader id, so it is
/// generated once per install and never changes.
nonisolated enum TagReaderIdentity {
    /// Spoolman accepts it and links it to nothing (probed on 0.27.0); a
    /// non-hex placeholder is refused.
    static let pairingUID = "00000000"
    /// Spoolman's limit on `name`.
    static let nameLimit = 64

    /// `spoolkid-` + 8 lowercase hex, generated on first use and kept.
    static func readerID(defaults: UserDefaults = .standard) -> String {
        if let stored = defaults.string(forKey: AppConfig.tagReaderIdKey), !stored.isEmpty { return stored }
        let hex = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
        let id = "spoolkid-\(hex)"
        defaults.set(id, forKey: AppConfig.tagReaderIdKey)
        return id
    }

    static func defaultName(model: String) -> String { "SpoolKid on \(model)" }

    /// The user's name, trimmed, else the default; at most `nameLimit`.
    static func name(stored: String?, model: String) -> String {
        let trimmed = (stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return limited(trimmed.isEmpty ? defaultName(model: model) : trimmed)
    }

    /// `text` cut to `nameLimit` Unicode scalars, which is how Spoolman
    /// counts; Swift's `count` counts grapheme clusters.
    static func limited(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.prefix(nameLimit)))
    }

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: AppConfig.tagReaderEnabledKey) as? Bool ?? true
    }
}

/// One `POST /api/v1/tag/scan`.
nonisolated struct TagScanReport: Equatable, Sendable {
    let uid: String
    let readerId: String
    let name: String
    var format: String? = nil
    var payloadBase64: String? = nil

    /// The request body, in Spoolman's keys; a missing field is left out.
    var body: [String: String] {
        var body = ["uid": uid, "reader_id": readerId, "name": name]
        if let format { body["format"] = format }
        if let payloadBase64 { body["payload_b64"] = payloadBase64 }
        return body
    }
}

/// What a report did. `.reported` only when Spoolman answered 2xx.
nonisolated enum TagScanReportOutcome: Equatable, Sendable {
    case reported
    /// This backend has no tag reader API (not Spoolman 0.27+).
    case unsupported
    case failed(String)
}

nonisolated enum TagReaderText {
    static func footer(readerID: String) -> String {
        "Each tag you scan is reported to Spoolman, so a browser paired with SpoolKid opens its spool. "
            + "Spoolman finds only tags linked in Spoolman Tags."
            + (readerID.isEmpty ? "" : " Reader id: \(readerID).")
    }

    static func pairingResult(_ outcome: TagScanReportOutcome, name: String) -> String {
        switch outcome {
        case .reported: "In Spoolman, open Settings → Tag Scanning and choose Use this next to \(name)."
        case .unsupported: "This server can't pair with a tag reader. Spoolman 0.27 or later can."
        case .failed(let message): "SpoolKid could not report to Spoolman: \(message)"
        }
    }
}

/// Which scans are reported, and with what.
enum TagScanReporter {
    /// Spoolman's limit on `payload_b64`.
    static let payloadLimit = 8192

    /// Nil when the switch is off, the scan has no UID (a camera scan: QR/web
    /// or OCR), or it is one of SpoolKid's location tags. An NFC tag that
    /// carries a URL record has a UID and is reported.
    static func report(for scan: ScanResult, defaults: UserDefaults = .standard, model: String) -> TagScanReport? {
        guard TagReaderIdentity.isEnabled(defaults: defaults),
              let uid = scan.cardUID.map(SpoolMappingService.normalizeUID), !uid.isEmpty,
              scan.locationTag == nil
        else { return nil }
        return TagScanReport(
            uid: uid,
            readerId: TagReaderIdentity.readerID(defaults: defaults),
            name: TagReaderIdentity.name(stored: defaults.string(forKey: AppConfig.tagReaderNameKey), model: model),
            format: formatSlug(scan.format),
            payloadBase64: payloadBase64(scan.tagSnapshot)
        )
    }

    /// Makes SpoolKid appear in Spoolman's Recent Readers without a tag.
    static func pairingReport(defaults: UserDefaults = .standard, model: String) -> TagScanReport {
        TagScanReport(
            uid: TagReaderIdentity.pairingUID,
            readerId: TagReaderIdentity.readerID(defaults: defaults),
            name: TagReaderIdentity.name(stored: defaults.string(forKey: AppConfig.tagReaderNameKey), model: model)
        )
    }

    static func formatSlug(_ format: ScanResult.DetectedFormat?) -> String? {
        switch format {
        case .openSpool: "openspool"
        case .openPrintTag: "openprinttag"
        case .openTag3D: "opentag3d"
        case .anycubicACE: "anycubic"
        case .elegoo: "elegoo"
        case .tigerTag: "tigertag"
        default: nil
        }
    }

    /// The NDEF message, or the raw user pages; nil when nothing was read or
    /// it would exceed Spoolman's limit.
    static func payloadBase64(_ snapshot: TagSnapshot?) -> String? {
        let bytes: [UInt8]
        switch snapshot {
        case .ndef(let records)?: bytes = NDEFMessageEncoder.encode(records)
        case .rawPages(_, let pages)?: bytes = pages
        case nil: return nil
        }
        guard !bytes.isEmpty else { return nil }
        let encoded = Data(bytes).base64EncodedString()
        return encoded.count <= payloadLimit ? encoded : nil
    }
}
