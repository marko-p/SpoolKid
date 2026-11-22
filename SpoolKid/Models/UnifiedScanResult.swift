//
//  UnifiedScanResult.swift
//  SpoolKid
//
//  Purpose: Unified model representing the outcome of any scan (NFC, QR, URL, OCR).
//  Used to drive the new unified card views and contextual actions in ScanResultHubView.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

enum UnifiedScanResult {
    case spool(Spool, FilamentTagData?, scannedUID: String?)
    /// A scan that resolved to filament data rather than to one spool —
    /// ranked candidates, or none. `scannedUID` is the tag's UID when the
    /// scan came from NFC and nil when it came from QR, a URL, or OCR. It
    /// was absent from this case until 2026-08-24, which silently discarded
    /// the UID of every unmapped tag whose filament the backend knows, and
    /// left the hub with no way to map it (see
    /// `HubActionPlan.shouldShowMapToExistingSpoolButton`).
    case filament(FilamentTagData, Filament?, scannedUID: String?)
    case uidOnly(String)
}

extension UnifiedScanResult {
    var uid: String? {
        switch self {
        case .spool(_, _, let scannedUID):
            return scannedUID
        case .filament(_, _, let scannedUID):
            return scannedUID
        case .uidOnly(let uid):
            return uid
        }
    }
}

/// Whether the scanned tag is linked to a spool — ONE answer for every hub
/// control that asks, so Link Tag and Unlink are never offered together.
///
/// Audit H8 (2026-09-27): the Unlink offer counted on-device ledger rows while
/// the Link branch counted only mapped UIDs, and the embedded-spool-ID lookup
/// (`ScanResolutionService.mappedSpool`) writes a ledger row for the tag it
/// resolves. The first scan of such a tag offered "Link This Tag to a Spool"
/// and "Unlink from …" side by side, and Unlink would only have deleted the
/// row that lookup had just written.
nonisolated enum HubLinkState: Equatable, Sendable {
    case notLinked
    /// `spoolID` holds the UID in its mapped UIDs (Spoolman Tags, `card_uids`,
    /// or FilaMan's `rfid_uid`). `releasable` is true unless FilaMan's
    /// `rfid_uid`, which SpoolKid cannot write, also holds it (I1): that copy
    /// would still resolve the tag to the spool after the writable ones are
    /// removed (final review FR-3).
    case mapped(spoolID: Int, releasable: Bool)
    /// Only SpoolKid's on-device ledger knows the tag, and this scan resolved
    /// through that row. It identifies the spool but is NOT a link: nothing on
    /// the backend holds the tag, so Link Tag is offered and Unlink is not
    /// (issue #24 — the hub used to show this as linked).
    case ledger(spoolID: Int)

    /// True only when the backend holds the tag.
    var isLinked: Bool {
        if case .mapped = self { return true }
        return false
    }

    /// Link Tag is offered exactly when nothing on the backend links the tag.
    var offersLinkTag: Bool { !isLinked }

    /// The spool Unlink releases; nil hides Unlink.
    var unlinkSpoolID: Int? {
        switch self {
        case .mapped(let spoolID, true):
            return spoolID
        case .mapped(_, false), .ledger, .notLinked:
            return nil
        }
    }

    /// `resolvedViaLedger` is true only when the hub's answer came from the
    /// ledger tier (`HubResolutionSource.onDeviceLedger`). `card_uids` wins over
    /// other mapped fields and over the ledger, matching the resolution cascade
    /// (a native tag first);
    /// the ledger is followed only to an active spool, like the resolution
    /// fallback it parallels. A `card_uids` holder that ALSO holds the UID
    /// undetachably stays the owner but is not releasable — offering Unlink or
    /// Transfer there would report a release that did not happen.
    static func resolve(
        uid: String?, resolvedViaLedger: Bool, spools: [Spool], ledger: [String: Int]
    ) -> HubLinkState {
        guard let uid else { return .notLinked }
        let normalized = SpoolMappingService.normalizeUID(uid)
        guard !normalized.isEmpty else { return .notLinked }

        // A native Spoolman tag wins, as in scan resolution
        // (`SpoolMappingService.resolvingSpoolIDs`) — else a stale `card_uids`
        // copy on another spool names a spool the scan did not resolve to.
        if let spool = spools.first(where: { $0.nativeTagUIDs.contains(normalized) })
            ?? spools.first(where: { $0.cardUIDs.map(SpoolMappingService.normalizeUID).contains(normalized) }) {
            let undetachable = spool.undetachableCardUIDs.map(SpoolMappingService.normalizeUID)
            return .mapped(spoolID: spool.id, releasable: !undetachable.contains(normalized))
        }
        if let spool = spools.first(where: {
            $0.mappedCardUIDs.map(SpoolMappingService.normalizeUID).contains(normalized)
        }) {
            return .mapped(spoolID: spool.id, releasable: false)
        }
        guard resolvedViaLedger,
              let spoolID = ledger[normalized],
              spools.contains(where: { $0.id == spoolID && $0.archived != true })
        else { return .notLinked }
        return .ledger(spoolID: spoolID)
    }
}
