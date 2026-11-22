//
//  SpoolPage.swift
//  SpoolKid
//
//  Purpose: The pure rules the Spool page renders: its action tiles, the tags
//  it lists and which of them it can unlink, its read-only detail rows, the
//  header subtitle, and when the page closes itself. Views render these
//  values; the rules live here (conventions A2/A3).
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// One tag in the Spool page's Tags section.
nonisolated struct SpoolPageTag: Equatable, Sendable {
    let uid: String
    /// False for a tag no write path can release (FilaMan's `rfid_uid`).
    let canUnlink: Bool
}

/// What the Spool page's one NFC session in flight is for.
nonisolated enum SpoolPageNFC: Equatable, Sendable { case write, link, location }

/// `nonisolated`: the target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`;
/// these pure rules must stay usable from nonisolated contexts (tests included).
nonisolated enum SpoolPage {
    /// Same locale as the Filament page: a decimal point on every region.
    private static let decimalPointLocale = Locale(identifier: "en_US_POSIX")

    /// A 2×2 grid read row by row: Link Tag, Write Tag / Location, Weigh
    /// (owner, 2026-11-03). Link Tag only where linking is active, as the
    /// spool form's `tagSectionActions(writesLinks:)`.
    static func tiles(writesLinks: Bool, isLinkScanning: Bool) -> [HubAction] {
        var tiles: [HubAction] = []
        if writesLinks {
            tiles.append(HubAction(id: .linkTag, title: isLinkScanning ? "Scanning…" : "Link Tag", systemImage: "link"))
        }
        tiles += [
            HubAction(id: .writeTag, title: "Write Tag", systemImage: "wave.3.right"),
            HubAction(id: .setLocation, title: "Location", systemImage: "mappin.and.ellipse"),
            HubAction(id: .weigh, title: "Weigh", systemImage: "scalemass"),
        ]
        return tiles
    }

    /// Every tag that resolves to the spool, in `mappedCardUIDs` order. Unlink
    /// follows the hub's rule: offered in every mode, except for a tag no
    /// write path can remove.
    static func tagRows(for spool: Spool) -> [SpoolPageTag] {
        let stuck = Set(spool.undetachableCardUIDs)
        return spool.mappedCardUIDs.map { SpoolPageTag(uid: $0, canUnlink: !stuck.contains($0)) }
    }

    /// The filament and its manufacturer, for example "Original WHITE · AzureFilm".
    static func headerSubtitle(_ spool: Spool) -> String {
        [spool.filament.name.nonBlank ?? spool.filament.material.nonBlank, (spool.filament.vendor?.name).nonBlank]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// The read-only rows, in a fixed order. A gated row shows only when its
    /// field is visible for the backend; nil and blank values are left out.
    static func detailRows(for spool: Spool, visibleFieldIDs: Set<String>, statusName: String?) -> [FilamentSpecRow] {
        func date(_ value: Date?) -> String? { value?.formatted(date: .abbreviated, time: .omitted) }
        let rows: [(label: String, gate: String?, value: String?)] = [
            ("Location", "location", spool.location.nonBlank),
            ("Status", "status", statusName.nonBlank),
            ("Price", nil,
             spool.price.map { $0.formatted(.number.precision(.fractionLength(2)).locale(decimalPointLocale)) }),
            ("Lot/Batch", nil, spool.lotNr.nonBlank),
            ("Purchase Date", "purchase_date", date(spool.purchaseDate)),
            ("First Used", "first_used", date(spool.firstUsed)),
            ("Last Used", "last_used", date(spool.lastUsed)),
            ("Registered", nil, date(spool.registered)),
            ("External ID", "external_id", spool.externalId.nonBlank),
            ("Comment", "comment", spool.comment.nonBlank),
        ]
        return rows.compactMap { row in
            if let gate = row.gate, !visibleFieldIDs.contains(gate) { return nil }
            return row.value.map { FilamentSpecRow(label: row.label, value: $0) }
        }
    }

    /// The location a scan names: a location tag's resolved name, nil for any
    /// other tag (which writes nothing).
    @MainActor
    static func locationFromScan(_ result: ScanResult, registry: LocationRegistry?) -> String? {
        guard let payload = result.locationTag else { return nil }
        return ScanResultHubView.resolvedLocationName(for: payload, scannedUID: result.cardUID, registry: registry)
    }

    nonisolated struct WriteResult: Equatable, Sendable {
        let handles: Bool
        let pendingAfter: SpoolPageNFC?
    }

    /// Routes a change of `NFCManager.lastWriteSucceeded`. Every write first
    /// resets it to `false`, which after an earlier success is a real change:
    /// that edge must not use up the pending write, or the second write on
    /// the page is never recorded or linked (final review C1).
    static func writeResult(pending: SpoolPageNFC?, succeeded: Bool) -> WriteResult {
        guard pending == .write, succeeded else { return WriteResult(handles: false, pendingAfter: pending) }
        return WriteResult(handles: true, pendingAfter: nil)
    }

    /// A start request (open in Edit at Weight) applies once, not again each
    /// time the page reappears from a push (final review I1).
    static func appliesOnce(requested: Bool, applied: Bool) -> Bool {
        requested && !applied
    }

    /// `NFCManager.alertMessage` as a failure to show, nil when empty. Every
    /// message it sets is a refusal or a failed session (final review I2).
    static func nfcFailure(_ alertMessage: String) -> String? {
        alertMessage.isEmpty ? nil : alertMessage
    }

    /// The page closes once a spool it showed is gone (deleted from Edit, or
    /// elsewhere); before it was ever found, "Not Found" stands.
    static func shouldDismiss(wasFound: Bool, spool: Spool?) -> Bool {
        wasFound && spool == nil
    }
}
