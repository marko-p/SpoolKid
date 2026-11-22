//
//  Entitlement.swift
//  SpoolKid
//
//  Purpose: Quota policy for the local (on-device) store. The local app is
//  always free-tier; premium capacity comes from connecting your own Spoolman
//  server or the future SaaS, where limits are enforced server-side.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// The entities the local store caps. Locations are derived strings on spools
/// (never a first-class row) and are NOT capped — they don't appear here.
///
/// `nonisolated`: the target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
/// which would make the synthesized `Equatable` main-actor-isolated and thus
/// unusable from nonisolated contexts (e.g. Swift Testing tests). These are pure
/// policy value types with no main-actor state, so opt out at the type level.
nonisolated enum QuotaEntity: String, Equatable, Sendable {
    case spools
    case filaments
    case vendors

    /// User-facing noun. Vendors are presented as "manufacturers" in the app.
    var displayName: String {
        switch self {
        case .spools: return "spools"
        case .filaments: return "filaments"
        case .vendors: return "manufacturers"
        }
    }
}

/// Thrown by the local store when a create would exceed the entitlement's cap.
/// Carries structured data; the at-limit UI renders `errorDescription`.
/// `nonisolated` for the same reason as `QuotaEntity` above.
nonisolated struct QuotaError: LocalizedError, Equatable, Sendable {
    let entity: QuotaEntity
    let limit: Int

    var errorDescription: String? {
        "You've reached the limit of \(limit.formatted()) \(entity.displayName) in your on-device library. "
            + "To add another, delete one you no longer need — or connect your own Spoolman server for more capacity."
    }
}

/// Capacity tier for the local store.
/// `nonisolated` for the same reason as `QuotaEntity` above.
nonisolated enum Entitlement: Equatable, Sendable {
    case free
    case premium

    /// The single build-time knob for the on-device library's capacity. The
    /// capped entities — spools, filaments, and manufacturers — share this cap
    /// on the free tier. Change this one value to re-balance the local store.
    /// (Locations are uncapped and not a `QuotaEntity`.)
    static let localCapacity = 5000

    /// The local app is always free for now (no in-app upgrade). Premium is
    /// reserved and never reached locally; the authoritative premium limits
    /// live server-side on the future SaaS.
    static var current: Entitlement { .free }

    /// Max allowed rows for an entity. The free tier caps every entity uniformly
    /// at `localCapacity`; premium values are reserved and never reached locally.
    func limit(for entity: QuotaEntity) -> Int {
        switch self {
        case .free:
            return Self.localCapacity
        case .premium:
            switch entity {
            case .spools: return 1000
            case .filaments: return 30000
            case .vendors: return 1000
            }
        }
    }
}
