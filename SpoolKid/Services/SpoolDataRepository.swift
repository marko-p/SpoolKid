//
//  SpoolDataRepository.swift
//  SpoolKid
//
//  Purpose: Backend-agnostic data access for spools/filaments/vendors/locations.
//  Views and services depend on this protocol, never on a concrete backend, so a
//  Spoolman-backed and a local (SwiftData) implementation are interchangeable.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// What a display-only reachability probe determined about the active backend.
///
/// Deliberately not a `Bool`: "this backend needs no probe" and "no address is
/// configured, so nothing was probed" are different answers from "a probe ran
/// and the server did not respond", and collapsing them is how a status row
/// ends up reporting a verdict on work it never did. There is no `checking`
/// case because a repository never has that answer to give — callers spell an
/// unanswered probe as `nil`.
nonisolated enum BackendReachability: Equatable, Sendable {
    /// The rows live on the device; no server exists to reach.
    case alwaysAvailable
    /// No server address is configured. Nothing was contacted.
    case notConfigured
    case reachable
    /// A probe ran against a configured address and did not get a usable answer.
    case unreachable

    /// Shared "probe only what has been configured" rule, so each server
    /// backend expresses it once rather than each re-deriving when to skip the
    /// network. `probe` is not called at all for a blank address — the caller
    /// can therefore never mistake "unconfigured" for "unreachable".
    @MainActor
    static func probing(address: String, using probe: () async -> Bool) async -> BackendReachability {
        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .notConfigured
        }
        return await probe() ? .reachable : .unreachable
    }
}

/// Where a backend can keep tag↔spool links. Which ones exist is a fact about
/// the SERVER (Spoolman gained native tags in 0.27.0), not about the backend
/// kind, which is why it is not a `BackendCapabilities` field.
nonisolated enum TagStore: String, Hashable, Sendable, CaseIterable {
    /// SpoolLink's `card_uids` custom field.
    case cardUIDs
    /// Spoolman 0.27+'s own tags (`/spool/{id}/tag`).
    case spoolmanTags
    /// FilaMan's `rfid_uid`, a writable tag store (spec 2026-11-03). Its
    /// switch is `FilaManTagSwitches.tagsEnabled`.
    case filamanTags

    /// The name of the switch that controls it, so copy and toggles agree.
    var displayName: String {
        switch self {
        case .cardUIDs: "SpoolLink"
        case .spoolmanTags: "Spoolman Tags"
        case .filamanTags: "FilaMan Tags"
        }
    }
}

/// What a bulk native-tag removal did. Failures are listed, never folded
/// into a count that would read as done.
nonisolated struct TagBulkDeleteResult: Equatable, Sendable {
    var deleted = 0
    var failures: [String] = []
}

/// The single data-access surface the app talks to. `baseUrl` is intentionally
/// absent from every method — each implementation owns its own connection
/// details (the local backend has none). Reads are snapshots of the current
/// state.
///
/// The protocol deliberately does NOT inherit `ObservableObject`: conformers
/// are expected to be observable, but keeping the constraint off the protocol
/// keeps `any SpoolDataRepository` usable as an existential. The spec that wires
/// views to the active backend resolves SwiftUI observation via a concrete
/// facade that republishes these arrays.
@MainActor
protocol SpoolDataRepository {
    /// What this backend can do. Callers read this instead of testing the
    /// concrete repository type.
    var capabilities: BackendCapabilities { get }
    var spools: [Spool] { get }
    var filaments: [Filament] { get }
    var vendors: [Vendor] { get }
    var locations: [String] { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }
    /// Set when a create is refused by an on-device quota. Always nil for
    /// backends whose capacities are unlimited.
    var lastQuotaError: QuotaError? { get }

    func fetchSpools() async
    func fetchFilaments() async
    func fetchVendors() async
    func fetchLocations() async
    func testConnection() async -> Bool

    /// Opaque identity of whatever `checkReachability` would probe — the backend
    /// plus its configured address. The Library tab captures this before the
    /// await and compares it after, discarding an answer that arrived once the
    /// user had already retyped the server address; without it a slow probe can
    /// paint the old server's verdict onto the new one.
    var connectionTarget: String { get }

    /// Display-only reachability probe for the status indicator.
    ///
    /// Distinct from `testConnection()` and NOT interchangeable with it:
    /// `testConnection` is the user's explicit "check this server" action and
    /// reports its failure through `errorMessage`, whereas this runs
    /// unprompted on every appearance and foreground, so it must leave
    /// `errorMessage` and every sticky connection flag exactly as it found
    /// them. Conformers should keep the timeout short — an unreachable server
    /// is a routine state here, not an error worth hanging on.
    func checkReachability() async -> BackendReachability

    @discardableResult func addVendor(draft: VendorDraft) async -> Vendor?
    @discardableResult func addVendor(name: String) async -> Vendor?
    @discardableResult func updateVendor(id: Int, draft: VendorDraft) async -> Bool
    /// Refuses — `false`, reason on `errorMessage` — while any filament still
    /// references the vendor, on every backend (owner decision, 2026-09-15).
    /// Only `deleteVendorCascading` removes dependents.
    @discardableResult func deleteVendor(id: Int) async -> Bool
    /// Deletes the vendor, its filaments and their spools. `false` means the
    /// vendor was not deleted; where the backend has no transaction (Spoolman)
    /// `errorMessage` says which dependents were already gone.
    func deleteVendorCascading(id: Int) async -> Bool

    /// Which of this backend's create requirements the draft does not satisfy.
    ///
    /// Empty means "this backend would accept it" — which is the honest answer
    /// for Spoolman and the on-device Library, neither of which refuses a
    /// filament for a missing manufacturer, material or diameter. FilaMan does
    /// (`FilamentCreate`), and a caller that can only learn this by attempting
    /// the write can only report the refusal after the fact.
    ///
    /// Pre-flight only: `addFilament` still performs its own check, because a
    /// draft can change between the two calls.
    func missingFilamentRequirements(for draft: FilamentDraft) -> [FilamentCreateRequirement]

    @discardableResult func addFilament(draft: FilamentDraft) async -> Filament?
    @discardableResult func updateFilament(id: Int, draft: FilamentDraft) async -> Bool
    /// Refuses while any spool still references the filament, on every backend.
    @discardableResult func deleteFilament(id: Int) async -> Bool
    /// Deletes the filament and its spools; `false` means the filament was not
    /// deleted — see `deleteVendorCascading`.
    func deleteFilamentCascading(id: Int) async -> Bool

    @discardableResult func addSpool(draft: SpoolDraft) async -> Spool?
    @discardableResult func updateSpool(id: Int, draft: SpoolDraft) async -> Bool
    @discardableResult func deleteSpool(id: Int) async -> Bool
    @discardableResult func setSpoolArchived(id: Int, archived: Bool) async -> Bool

    /// The Status picker's options. `[]` on every backend whose `fieldSupport`
    /// omits `status` — the default below is what keeps `LocalRepository` and
    /// `SpoolmanRepository` untouched; only `FilaManRepository` overrides it.
    func fetchSpoolStatusOptions() async -> [FilaManSpoolStatus.Option]

    /// A spool's weighing history as the BACKEND knows it. `[]` on every
    /// backend whose `capabilities.providesMeasurementHistory` is false — the
    /// default below keeps `LocalRepository` and `SpoolmanRepository`
    /// untouched; only `FilaManRepository` overrides it. The app's own
    /// `WeighHistoryStore` is what covers the rest, and the two are merged by
    /// `MeasurementRecord.merge`.
    func fetchMeasurementHistory(spoolID: Int) async -> [MeasurementRecord]

    /// The SpoolmanDB-format catalogue this backend serves, so imports offer
    /// what the user's own server offers. `nil` means it serves none and the
    /// public catalogue applies; a throw means it has one and could not
    /// deliver it. Only `SpoolmanRepository` overrides the default below.
    func fetchFilamentCatalog() async throws -> [SpoolmanDBFilament]?

    func findSpool(byCardUID uid: String) -> Spool?
    @discardableResult func setCardUIDs(spoolId: Int, uids: [String]) async -> Bool
    /// Declares `card_uids` as a system-wide spool field on the backend, so it
    /// exists on every spool rather than only on the ones SpoolKid has mapped.
    /// Idempotent — safe to call on every foreground event.
    ///
    /// Gated by `BackendCapabilities.requiresCardUIDsFieldRegistration`, and
    /// deliberately NOT by `supportsTagMapping`: writing a mapping and
    /// declaring the field are different requirements, and conflating them is
    /// what made this Spoolman-only in the first place. A failure is never a
    /// failure to map a tag — on FilaMan `custom_fields` is free-form and the
    /// mapping writes regardless; the registration is visibility and interop.
    @discardableResult func ensureCardUIDsField() async -> Bool
    /// Removes the `card_uids` field declaration and every stored value, for
    /// the SpoolLink disable-teardown. Gated by the same capability as
    /// `ensureCardUIDsField`. Must report false on a PARTIAL teardown: the
    /// caller keeps the prompt pending on false, which is the only thing that
    /// makes a half-finished removal recoverable.
    @discardableResult func deleteCardUIDsField() async -> Bool

    /// The tag stores this backend has right now. Reads use all of them;
    /// `TagIdentityPolicy` decides which ones receive new links.
    var availableTagStores: Set<TagStore> { get }

    /// Whether `availableTagStores` is an answer yet — Spoolman's is not until
    /// its version has been read. Gates the one-time upgrade decision.
    var tagStoresKnown: Bool { get }

    /// Unlinks every spool's Spoolman Tag, for deleting that store. Filament
    /// tags are never touched: SpoolKid did not make them.
    func deleteSpoolmanTagLinks() async -> TagBulkDeleteResult

    /// Whether this backend hears about scans (`POST /tag/scan`, spec 3): a
    /// Spoolman that has said it is 0.27.0 or newer.
    var supportsTagScanReporting: Bool { get }

    /// Reports one scan, so a browser paired with SpoolKid opens its spool.
    func reportTagScan(_ report: TagScanReport) async -> TagScanReportOutcome

    /// Where this backend keeps filament links (spec 4): Spoolman 0.27's
    /// native tags, the Library's `card_uids`; nil where there is none.
    var filamentTagStore: TagStore? { get }

    /// Links `uid` to a filament. No policy or owner check here: the facade
    /// (`SpoolDataStore`) does both, once, for every backend.
    func linkFilamentTag(filamentId: Int, uid: String) async -> SpoolmanService.TagLinkOutcome

    /// Unlinks `uid` from a filament; `true` once it is no longer linked there.
    func unlinkFilamentTag(filamentId: Int, uid: String) async -> Bool

    /// Creates a location, and says which of the two possible things happened.
    ///
    /// FilaMan has a `locations` table and creates a row. Spoolman and the
    /// on-device Library derive locations from spools and have no create
    /// endpoint at all, so they report `.registeredOnDeviceOnly` and the
    /// device-local registry holds the name until an assignment writes it
    /// through. Returning `Bool` here would report success for work two of
    /// three backends cannot do.
    @discardableResult func addLocation(name: String) async -> LocationCreateOutcome

    /// Mirrors the UID of the tag that labels `locationName` onto the
    /// backend's own location row, where the backend has a field for it.
    ///
    /// Gated by `BackendCapabilities.storesLocationTagUID`, and the return type
    /// says which of the three things happened rather than claiming a write on
    /// backends that have nowhere to put one. A location tag works regardless:
    /// resolution is by the uuid on the tag against the device-local registry,
    /// and this mirror exists so the backend's OTHER clients can see the same
    /// binding.
    ///
    /// One UID, because the field holds one. SpoolKid allows a location
    /// unlimited tags, so this is the most recent one and the registry stays
    /// the authority on the rest.
    @discardableResult func setLocationTagUID(locationName: String, uid: String?) async -> LocationTagUIDOutcome

    @discardableResult func renameLocation(currentName: String, newName: String) async -> Bool
    /// Deletes a location, by name — the app has no location ids because two of
    /// the three backends have none.
    ///
    /// The MECHANISM differs and callers must not care: where locations are
    /// derived strings on spools (local store, Spoolman) the location ceases to
    /// exist once no spool references it, so deleting means clearing the name
    /// off every spool that uses it; on FilaMan a location is a first-class row
    /// with its own id, so deleting means `DELETE /api/v1/locations/{id}` after
    /// resolving the name. The doc here claimed the spool-derived model held
    /// "in both backends" until 2026-08, which stopped being true the moment
    /// FilaMan landed.
    @discardableResult func deleteLocation(_ name: String) async -> Bool
}

extension SpoolDataRepository {
    /// No location row to carry a tag UID on this backend. Overridden only by
    /// `FilaManRepository`, and forwarded — never defaulted — by
    /// `SpoolDataStore`.
    func setLocationTagUID(locationName: String, uid: String?) async -> LocationTagUIDOutcome { .unsupported }

    /// Spools excluding archived ones. This is the default source for browse,
    /// pick, and match UIs — archived spools are intentionally surfaced ONLY in
    /// ManageSpoolsView via its "Show Archived" toggle. Functional lookups
    /// (exact spool id / card_uid, migration) deliberately use the full `spools`
    /// set so a scanned tag on an archived spool still resolves.
    var activeSpools: [Spool] { spools.filter { $0.archived != true } }

    /// No status field to label on this backend.
    func fetchSpoolStatusOptions() async -> [FilaManSpoolStatus.Option] { [] }

    /// No server-side history on this backend.
    func fetchMeasurementHistory(spoolID: Int) async -> [MeasurementRecord] { [] }

    /// No catalogue of its own on this backend.
    func fetchFilamentCatalog() async throws -> [SpoolmanDBFilament]? { nil }

    /// No tag store at all. Every app repository overrides it (the Library
    /// since spec 2), and `SpoolDataStore` forwards it — never defaults it.
    var availableTagStores: Set<TagStore> { [] }

    /// Nothing to wait for: the Library's answer and FilaMan's are fixed.
    var tagStoresKnown: Bool { true }

    /// No native tags on this backend, so nothing to delete.
    func deleteSpoolmanTagLinks() async -> TagBulkDeleteResult { TagBulkDeleteResult() }

    /// No tag reader API on this backend. Overridden by `SpoolmanRepository`,
    /// forwarded — never defaulted — by `SpoolDataStore`.
    var supportsTagScanReporting: Bool { false }

    func reportTagScan(_ report: TagScanReport) async -> TagScanReportOutcome { .unsupported }

    /// No filament store on this backend. Overridden by the Library and by
    /// `SpoolmanRepository`; forwarded, never defaulted, by `SpoolDataStore`.
    var filamentTagStore: TagStore? { nil }

    func linkFilamentTag(filamentId: Int, uid: String) async -> SpoolmanService.TagLinkOutcome {
        .failed("This backend can't link a tag to a filament.")
    }

    func unlinkFilamentTag(filamentId: Int, uid: String) async -> Bool { false }
}

// MARK: - Create requirements (default: none)

extension SpoolDataRepository {
    /// Backends that refuse nothing need not say so. Overridden by
    /// `FilaManRepository`, and forwarded — never defaulted — by
    /// `SpoolDataStore`: a facade answering "nothing missing" on behalf of a
    /// backend that would refuse the write is the same lie one layer up.
    func missingFilamentRequirements(for draft: FilamentDraft) -> [FilamentCreateRequirement] { [] }
}
