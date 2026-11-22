//
//  BackendCapabilities.swift
//  SpoolKid
//
//  Purpose: What a backend can do, declared as data. Views and services ask the
//  capability, never the backend's identity — a fourth backend then needs no
//  view changes.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// Which backend the app is talking to. Persisted under
/// `AppConfig.backendKindKey`; the raw values are stored data and never change.
///
/// `nonisolated`: the target defaults actor isolation to MainActor, which would
/// make the synthesized conformances unusable from Swift Testing.
nonisolated enum BackendKind: String, CaseIterable, Equatable, Sendable {
    case local
    case spoolman
    case filaman
}

/// A public catalogue: the manufacturer picker lists its names, and Select
/// Filament, Scan Result and the spool form read its filaments.
nonisolated enum ManufacturerCatalogSource: Equatable, Sendable {
    case spoolmanDB
    case filamanDB

    /// The catalogue's name, as the picker's section header says it.
    var displayName: String {
        switch self {
        case .spoolmanDB: "SpoolmanDB"
        case .filamanDB: "FilaManDB"
        }
    }
}

/// Facts about the active backend. Contains ONLY what a caller actually reads —
/// a capability is added when the code that reads it is written, never before.
///
/// Mechanism differences (how remaining weight is written, how archiving is
/// expressed, whether a location is a derived string or a first-class row)
/// deliberately do NOT appear here: they are absorbed inside each
/// `SpoolDataRepository` behind uniform methods.
///
/// A `locationModel` field lived here until 2026-08-23 and never acquired a
/// consumer — Task 17's shared resolve-or-create helper absorbed the whole
/// difference inside the repository. Removed under the rule above rather than
/// left declared-but-unread. Following the "an orphaned capability is a bug
/// report about its would-be consumer" heuristic first is what surfaced the
/// real gap it pointed at: the app has no "Add Location" affordance anywhere,
/// so on FilaMan — where a location is a real row with a create API — one can
/// only come into existence as a side effect of a spool form. If that control
/// is ever built and needs to know the difference, this is three lines.
nonisolated struct BackendCapabilities: Equatable, Sendable {
    var kind: BackendKind
    /// The backend's name in copy and on a server backend's connection row
    /// in the Library tab.
    var displayName: String
    /// SF Symbol for the library tab.
    var tabSymbol: String
    /// True when rows live on the device. Drives the on-device storage copy and
    /// the "usable without a connection" gate.
    var isOnDeviceStorage: Bool
    /// nil = unlimited. Non-nil only for on-device storage (free tier).
    var spoolCapacity: Int?
    /// Whether the backend exposes a server currency setting for the dashboard's
    /// total-value card.
    var supportsCurrencySetting: Bool
    /// Whether the backend can store a tag→spool mapping at all. This is what
    /// SpoolLink actually requires — the gate was `kind == .spoolman` until
    /// 2026-08-21 (plan defect, Task 19b), which made FilaMan's mapping code
    /// correct and unreachable. Naming the requirement rather than the vendor
    /// is what stops the next backend re-breaking it.
    var supportsTagMapping: Bool
    /// Whether the backend keeps a readable history of weighings. Only FilaMan
    /// does (`GET /spools/{id}/events`); Spoolman's API has no measurement log
    /// at all and the on-device Library stores only the current weight. Named
    /// for the capability rather than the vendor so the weigh loop can ask one
    /// question and get the right answer everywhere — the app's own
    /// `WeighHistoryStore` covers the backends that answer no.
    var providesMeasurementHistory: Bool
    /// Whether `card_uids` must be registered as a custom field before it can
    /// be written. Spoolman requires provisioning; FilaMan's `custom_fields`
    /// are free-form and need none. Deliberately separate from
    /// `supportsTagMapping`: one flag serving both is what conflated
    /// "can map tags" with "is Spoolman" in the first place.
    var requiresCardUIDsFieldRegistration: Bool
    /// Whether a spool's ID here is the ID a SpoolLink client addresses it by,
    /// so writing it onto a tag (`SM<id>` in an ACE SKU) names that spool to
    /// hardware outside the app. Spoolman's are; FilaMan's are too, because its
    /// Spoolman-compat layer serves the native IDs unchanged (measured
    /// 2026-08-25). On-device IDs mean nothing outside the app, and an `SM<id>`
    /// minted from one would resolve confidently to whichever Spoolman spool
    /// shares the number.
    ///
    /// Separate from `supportsTagMapping` although the two agree today:
    /// storing a UID mapping and being addressable by ID are different
    /// requirements, and one flag answering both is how "can map tags" once
    /// came to mean "is Spoolman".
    var spoolIDsResolveViaSpoolLink: Bool
    /// Whether the backend's own location rows have a field for the NFC tag
    /// that labels them, so a location tag SpoolKid writes can be mirrored
    /// there for the backend's other clients to see.
    ///
    /// True only for FilaMan (`locations.identifier`). Spoolman has no location
    /// entity at all and the on-device Library derives locations from spools,
    /// so on both of those a location tag is a device-local fact and the
    /// registry is the only record of it.
    var storesLocationTagUID: Bool
    /// `UserDefaults` key holding this backend's validated-connection flag, or
    /// nil for on-device storage, which is always available. Each server
    /// backend owns its own flag; reading Spoolman's for every backend was the
    /// second half of the same defect.
    var connectionValidKey: String?
    /// `UserDefaults` key holding this backend's trust-all-certificates flag,
    /// or nil where there is no transport to secure (on-device).
    ///
    /// The last hiding place of the identity-coupling this epic retired 28
    /// times, and the subtlest: not a view branching on a backend, but a
    /// vendor *service* reading another vendor's default. `FilaManService`
    /// read `spoolman_trust_all_certs`, whose only writer renders solely when
    /// the backend is Spoolman — so a FilaMan user over HTTPS with a
    /// self-signed certificate could not set the flag their own transport
    /// read, could not connect, and was told nothing about why (I2).
    var trustAllCertsKey: String?

    /// Which catalogue fields this backend actually has. Forms and the
    /// visibility editor intersect this with the user's preference; nothing
    /// branches on `kind`.
    var fieldSupport: BackendFieldSupport

    /// The public catalogue this backend reads: whose manufacturer names the
    /// manufacturer picker offers after the backend's own (owner, 2026-10-12),
    /// and whose filaments Select Filament, Scan Result and the spool form
    /// search and take an empty-spool weight from (owner, 2026-10-18):
    /// FilaManDB on FilaMan, SpoolmanDB elsewhere — on the Library the public
    /// SpoolmanDB.
    var manufacturerCatalog: ManufacturerCatalogSource

    /// Whose printed labels name records here: a scanned label from any other
    /// origin is refused rather than looked up by its ID. Nil on the
    /// on-device Library, which prints none.
    var labelOrigin: BackendLabel.Origin?

    /// Whether this backend's transport should accept any certificate.
    ///
    /// Reads `UserDefaults` live, deliberately: the value is consulted per
    /// request while building a `URLSession`, so a user toggling it in the
    /// connection form takes effect on the next call rather than the next
    /// launch. `nil` key — on-device storage — is always `false`; there is no
    /// transport, so there is nothing to trust.
    var trustsAllCerts: Bool {
        guard let trustAllCertsKey else { return false }
        return UserDefaults.standard.bool(forKey: trustAllCertsKey)
    }

    /// The noun for prose that names WHERE a row lives — "will be permanently
    /// deleted from …". `displayName` is the backend's name and reads as a proper
    /// noun; the on-device library is not a place with a name, so it takes the
    /// possessive form instead.
    ///
    /// Derived rather than stored: it is a rendering of two fields already
    /// here, and a fourth backend gets it without a new declaration. It exists
    /// because four delete-confirmation dialogs each hardcoded "Spoolman" and
    /// so lied on two backends out of three (I4).
    var storageNoun: String { isOnDeviceStorage ? "your library" : displayName }

    /// The label of the Library tab's first row, which opens the Backend
    /// screen — and so the second half of every "Library → …" path in copy.
    /// A server backend's row carries its name; the on-device row says
    /// "Library Mode", because "Library → Library" reads as a stutter.
    ///
    /// Derived for the same reason as `storageNoun`. It exists because copy
    /// pointing at the row used `displayName`, which on the on-device backend
    /// is "Library" — a row the user could not find (final review FR-1).
    var connectionRowLabel: String { isOnDeviceStorage ? "Library Mode" : displayName }

    static let local = BackendCapabilities(
        kind: .local,
        displayName: "Library",
        tabSymbol: "books.vertical",
        isOnDeviceStorage: true,
        spoolCapacity: Entitlement.localCapacity,
        supportsCurrencySetting: false,
        // Links live in each spool's `extra["card_uids"]` (spec 2), shown as
        // Tags; there is no field to register (below).
        supportsTagMapping: true,
        providesMeasurementHistory: false,
        requiresCardUIDsFieldRegistration: false,
        spoolIDsResolveViaSpoolLink: false,
        storesLocationTagUID: false,
        connectionValidKey: nil,
        trustAllCertsKey: nil,
        fieldSupport: .spoolmanShaped,
        manufacturerCatalog: .spoolmanDB,
        labelOrigin: nil
    )

    static let spoolman = BackendCapabilities(
        kind: .spoolman,
        displayName: "Spoolman",
        tabSymbol: "server.rack",
        isOnDeviceStorage: false,
        spoolCapacity: nil,
        supportsCurrencySetting: true,
        supportsTagMapping: true,
        providesMeasurementHistory: false,
        requiresCardUIDsFieldRegistration: true,
        spoolIDsResolveViaSpoolLink: true,
        // No location entity to carry it — Spoolman's locations are strings on
        // spools.
        storesLocationTagUID: false,
        connectionValidKey: AppConfig.spoolmanConnectionValidKey,
        trustAllCertsKey: AppConfig.trustAllCertsKey,
        fieldSupport: .spoolmanShaped,
        manufacturerCatalog: .spoolmanDB,
        labelOrigin: .spoolman
    )

    /// FilaMan exposes no Spoolman-style `/setting/currency` on its native API,
    /// so the dashboard falls back to the device locale.
    static let filaman = BackendCapabilities(
        kind: .filaman,
        displayName: "FilaMan",
        tabSymbol: "server.rack",
        isOnDeviceStorage: false,
        spoolCapacity: nil,
        supportsCurrencySetting: false,
        supportsTagMapping: true,
        providesMeasurementHistory: true,
        // `custom_fields` is free-form, so a mapping WRITES without any
        // registration — which is why this was false until 2026-08-24. But
        // FilaMan does have a registry (`/api/v1/system-extra-fields`), and
        // without a row in it `card_uids` exists only on the spools SpoolKid
        // happens to have mapped: absent from the Admin Panel, and absent from
        // `GET /spoolman/api/v1/field/spool`, which is what a SpoolLink client
        // reads. Owner decision, 2026-08-24: with SpoolLink on, every backend
        // that can hold the field should declare it.
        requiresCardUIDsFieldRegistration: true,
        spoolIDsResolveViaSpoolLink: true,
        // `locations.identifier` — the "Identifier" column in FilaMan's own
        // Locations list, written by its "Write RFID Tag" action.
        storesLocationTagUID: true,
        connectionValidKey: AppConfig.filamanConnectionValidKey,
        trustAllCertsKey: AppConfig.filamanTrustAllCertsKey,
        fieldSupport: .filaman,
        manufacturerCatalog: .filamanDB,
        labelOrigin: .filaman
    )

    /// The kind⇄capabilities table, for the one caller that needs facts about a
    /// backend the app is **not** currently running: the Backend picker, whose
    /// footer describes the kind the user just selected, a launch before
    /// `SpoolDataStore` starts answering for it.
    ///
    /// This is not the identity coupling the architecture rule forbids — that
    /// rule is about branching on *which* backend is active instead of asking
    /// what it can do. Here the kind is the input, and the same switch
    /// `SpoolDataStore.selectRepository` already performs.
    static func `for`(_ kind: BackendKind) -> BackendCapabilities {
        switch kind {
        case .local: .local
        case .spoolman: .spoolman
        case .filaman: .filaman
        }
    }
}
