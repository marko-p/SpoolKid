//
//  SpoolDataStore.swift
//  SpoolKid
//
//  Purpose: Observable facade over `any SpoolDataRepository`. The protocol is
//  intentionally NOT ObservableObject (keeps the existential usable), so this
//  concrete type republishes the repository's read state as @Published properties
//  for SwiftUI. It also hosts the pure backend-selection seam.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Combine
import SwiftData

@MainActor
final class SpoolDataStore: ObservableObject, SpoolDataRepository {
    @Published private(set) var spools: [Spool] = []
    @Published private(set) var filaments: [Filament] = []
    @Published private(set) var vendors: [Vendor] = []
    @Published private(set) var locations: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastQuotaError: QuotaError?

    /// The Status picker's options, empty on every backend whose
    /// `fieldSupport` omits `status`. Empty means the picker does not render
    /// and a spool's status is left alone rather than guessed — a form that
    /// cannot show the current value must not overwrite it.
    @Published private(set) var spoolStatusOptions: [FilaManSpoolStatus.Option] = []

    /// The caveat from the most recent write that LANDED but could not do
    /// everything it was asked (plan defect I1) — "the filament was saved
    /// without its colour", "the spool was saved without its location".
    ///
    /// It lives here rather than on the form because the form dismisses: the
    /// record was written, so trapping the user in it would be worse than
    /// letting them out, but the note still has to reach them. `ContentView`
    /// renders this at the root, above the tab bar, where it survives the
    /// sheet going away.
    @Published private(set) var saveNotice: SaveNotice?

    /// Successful row writes this session, monotonic. Published so the root can
    /// observe activity without this type knowing what the root does with it —
    /// the support prompts read it through `ContentView`, and `SpoolDataStore`
    /// stays ignorant of them.
    @Published private(set) var writeCount = 0

    /// The active backend's tag stores, republished because Spoolman's answer
    /// changes with the server version it reports.
    @Published private(set) var availableTagStores: Set<TagStore> = []

    /// The ONE answer to "how does SpoolKid identify a spool from a tag" on
    /// this backend now (`TagIdentityPolicy`). Recomputed on every refresh and
    /// whenever a setting it reads changes.
    @Published private(set) var tagIdentity = TagIdentityPolicy(mode: .neither, linkTargets: [])

    /// The tag stores a write can reach: none while a server backend's
    /// connection is not validated.
    private var connectedTagStores: Set<TagStore> { connected(availableTagStores) }

    private func connected(_ stores: Set<TagStore>) -> Set<TagStore> {
        guard let key = capabilities.connectionValidKey else { return stores }
        return defaults.bool(forKey: key) ? stores : []
    }

    /// Whether the upgrade decision may run: at once on the Library, on a
    /// server only once it is connected and has answered.
    private var tagStoresAreKnown: Bool {
        capabilities.connectionValidKey == nil || (repository.tagStoresKnown && !connectedTagStores.isEmpty)
    }

    /// The Library's store is new in this release (spec 2), and the upgrade
    /// rule must know it; read by capability, never by backend.
    private func recomputeTagIdentity() {
        TagIdentityMigration.persistUpgradeIfNeeded(
            available: connectedTagStores, storesAreNew: capabilities.isOnDeviceStorage,
            storesKnown: tagStoresAreKnown, defaults: defaults
        )
        let next = TagIdentityPolicy.current(
            available: connectedTagStores, storesAreNew: capabilities.isOnDeviceStorage, defaults: defaults
        )
        if next != tagIdentity { tagIdentity = next }
    }

    let capabilities: BackendCapabilities

    /// True when new links go to `card_uids` on a backend that needs that
    /// custom field provisioned first — Spoolman does, FilaMan does not. Kept
    /// distinct from "can this backend store a mapping" so that widening
    /// SpoolLink to a new backend never implies running Spoolman's field
    /// bootstrap against it: conflating the two is what made one flag mean two
    /// things.
    ///
    /// Only once the stores are known: before Spoolman's version is read a
    /// 0.27 server looks single-store, so Tag Links would register
    /// `card_uids` there with SpoolLink off — on every cold launch, undoing
    /// "Delete card_uids" (final review I1). And from the stores the
    /// repository has now, not `tagIdentity`: the spool fetch reads the
    /// version, then awaits the spools before the facade refreshes, and a
    /// render in that window saw "known" beside the cached single-store
    /// policy (final re-review).
    var needsCardUIDsFieldProvisioning: Bool {
        guard capabilities.requiresCardUIDsFieldRegistration, repository.tagStoresKnown else { return false }
        return TagIdentityPolicy.current(
            available: connected(repository.availableTagStores),
            storesAreNew: capabilities.isOnDeviceStorage,
            defaults: defaults
        ).linkTargets.contains(.cardUIDs)
    }

    private let repository: any SpoolDataRepository

    /// Where the tag-identity settings and the connection flag are read and
    /// the upgrade decision is written. `.standard` in the app; a test hands
    /// in its own suite so it never reads or writes the host app's settings.
    private let defaults: UserDefaults

    /// Device-local names and tag bindings the backend cannot hold. Optional
    /// so tests that only exercise repository forwarding need not build one.
    let locationRegistry: LocationRegistry?

    /// The user's hand-arranged shelf order. Optional for the same reason the
    /// registry is: tests that only exercise repository forwarding need not
    /// build one.
    let locationOrder: LocationOrderStore?

    /// Registry snapshot, republished for views. Empty when no registry was
    /// supplied — never `nil`, so callers need no second code path.
    var registeredLocations: [LocationRecord] { locationRegistry?.records ?? [] }

    private var cancellables = Set<AnyCancellable>()

    init(
        repository: any SpoolDataRepository,
        registry: LocationRegistry? = nil,
        order: LocationOrderStore? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.capabilities = repository.capabilities
        self.locationRegistry = registry
        self.locationOrder = order
        self.defaults = defaults
        refresh()

        registry?.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        order?.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // The mode and both store switches live in UserDefaults; a change
        // from Settings must reach every screen reading `tagIdentity`.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.recomputeTagIdentity() } }
            .store(in: &cancellables)
    }

    // MARK: - Selection seam

    /// Pure backend selection. The kind is resolved by `resolveBackendKind`
    /// before this is called, so the mapping here is total and explicit.
    static func selectRepository(
        kind: BackendKind,
        spoolmanService: SpoolmanService,
        filaManService: FilaManService,
        context: ModelContext
    ) -> any SpoolDataRepository {
        switch kind {
        case .spoolman:
            return SpoolmanRepository(service: spoolmanService)
        case .filaman:
            return FilaManRepository(service: filaManService)
        case .local:
            return LocalRepository(context: context)
        }
    }

    /// Pure, testable backend resolution. An explicitly stored kind always wins.
    /// Absent (or unrecognised) storage reproduces the historical behaviour,
    /// modulo whitespace trimming, so an existing install upgrades with no
    /// configuration change: Spoolman URL non-empty AND connection validated →
    /// .spoolman, else → .local. The trim is intentional and more correct than
    /// the historical formula it replaces — a whitespace-only stored URL now
    /// resolves to .local instead of .spoolman.
    nonisolated static func resolveBackendKind(
        stored: String?,
        spoolmanUrl: String,
        spoolmanConnectionValid: Bool
    ) -> BackendKind {
        if let stored, let kind = BackendKind(rawValue: stored) {
            return kind
        }
        let configured = !spoolmanUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && spoolmanConnectionValid
        return configured ? .spoolman : .local
    }

    /// Seeds a backend-picker selection from storage, with an idempotency
    /// guard: a non-empty `current` (a value already picked by the user, or
    /// already seeded this session) is returned unchanged — this function
    /// never overwrites a live selection. An empty `current` derives via
    /// `resolveBackendKind`. Split out from `resolveBackendKind` itself so
    /// the guard (new in Task 11 — the concept the F15 blank-picker defect
    /// lived in) has its own testable seam instead of being inlined into a
    /// view's `onAppear`, and so `ContentView.init` and the Backend picker
    /// share one implementation rather than each reassembling
    /// `resolveBackendKind`'s three arguments from storage independently.
    /// `ContentView.init` has no prior selection to preserve, so it always
    /// calls this with `current: ""`, which always takes the derive branch —
    /// identical in effect to calling `resolveBackendKind` directly.
    nonisolated static func seedBackendKindSelection(
        current: String,
        stored: String?,
        spoolmanUrl: String,
        spoolmanConnectionValid: Bool
    ) -> String {
        guard current.isEmpty else { return current }
        return resolveBackendKind(
            stored: stored,
            spoolmanUrl: spoolmanUrl,
            spoolmanConnectionValid: spoolmanConnectionValid
        ).rawValue
    }

    // MARK: - Save notices

    /// Hands a partial-success caveat to the root banner, ADDING to whatever
    /// is still on screen rather than replacing it (plan defect I4).
    ///
    /// A notice is only cleared when the user dismisses it, so anything still
    /// showing is by definition something they have not read yet. Overwriting
    /// it destroys the only report of a write that half-failed — which is the
    /// same silent success the notice exists to end, one layer up. Nested
    /// forms make this ordinary rather than exotic: a filament saved from
    /// inside the spool sheet can post its colour caveat while that sheet is
    /// still up, and the spool's own save follows moments later.
    ///
    /// `FilaManRepository.combinedNote` does this WITHIN one repository write;
    /// this is the same rule ACROSS writes, where no single caller can see
    /// both messages.
    /// `record` names what the note is about — "Spool #4 · PLA Matte HS ROSY".
    /// Optional because a create that failed before the record existed has no
    /// name to give; everything else should pass one, since a caveat the user
    /// cannot trace to a row is barely a caveat (device finding 4.2.1).
    func postSaveNotice(_ message: String, record: String?) {
        saveNotice = SaveNotice.appending(record: record, message: message, to: saveNotice)
    }

    func clearSaveNotice() {
        saveNotice = nil
    }

    // MARK: - Refresh

    /// `writes` is the number of rows this call successfully wrote. The fetch
    /// paths call `refresh()` with no argument and never move the counter.
    private func refresh(writes: Int = 0) {
        spools = repository.spools
        filaments = repository.filaments
        vendors = repository.vendors
        locations = repository.locations
        isLoading = repository.isLoading
        errorMessage = repository.errorMessage
        lastQuotaError = repository.lastQuotaError
        availableTagStores = repository.availableTagStores
        recomputeTagIdentity()
        writeCount += writes
    }

    // MARK: - SpoolDataRepository forwarding

    func fetchSpools() async {
        await repository.fetchSpools()
        refresh()
        await refreshSpoolStatusOptions()
    }

    /// For a spool form that opens before any spool fetch has run — from the
    /// scan hub, say — so FilaMan's Status picker is not simply missing. Asks
    /// the backend only while the list is empty.
    func loadSpoolStatusOptionsIfNeeded() async {
        guard spoolStatusOptions.isEmpty else { return }
        await refreshSpoolStatusOptions()
    }

    /// Populates `spoolStatusOptions` alongside every spool refresh, gated by
    /// CAPABILITY and never by backend identity — the Status picker's guard
    /// (`SpoolFormView`) already treats an empty list as "no picker", so a
    /// backend that lacks `status` simply keeps this empty rather than being
    /// special-cased here.
    private func refreshSpoolStatusOptions() async {
        guard capabilities.fieldSupport.supports("status", in: .spool) else {
            spoolStatusOptions = []
            return
        }
        spoolStatusOptions = await repository.fetchSpoolStatusOptions()
    }

    func fetchFilaments() async {
        await repository.fetchFilaments()
        refresh()
    }

    func fetchVendors() async {
        await repository.fetchVendors()
        refresh()
    }

    func fetchLocations() async {
        await repository.fetchLocations()
        refresh()
    }

    func testConnection() async -> Bool {
        let connected = await repository.testConnection()
        // A connection test is also where a server first says its version.
        availableTagStores = repository.availableTagStores
        recomputeTagIdentity()
        return connected
    }

    var connectionTarget: String { repository.connectionTarget }

    var tagStoresKnown: Bool { repository.tagStoresKnown }

    /// Forwarded, never defaulted (spec 4).
    var filamentTagStore: TagStore? { repository.filamentTagStore }

    /// Spec 4: the one place a filament link is written. Refuses outside
    /// Tag Links (R13's shape) and never takes a tag another spool, filament
    /// or location holds: a conflict names the holder and nothing is written.
    func linkFilamentTag(filamentId: Int, uid: String) async -> SpoolmanService.TagLinkOutcome {
        let normalized = SpoolMappingService.normalizeUID(uid)
        guard !normalized.isEmpty else { return .failed("That tag has no readable ID, so it could not be linked.") }
        guard filamentTagStore != nil else {
            return .failed(TagStoreText.noFilamentStoreNote(displayName: capabilities.displayName))
        }
        guard tagIdentity.writesFilamentLinks(store: filamentTagStore) else {
            return .failed(TagStoreText.linksOffNote(connectionRowLabel: capabilities.connectionRowLabel))
        }
        switch owner(ofTagUID: normalized) {
        case .none:
            break
        case .filament(let id, _) where id == filamentId:
            return .linked
        case .filament(let id, _):
            return .heldByFilament(id)
        case .spool(let id, _):
            return .heldBySpool(id)
        case .location(let name):
            return .failed("That tag labels \(name). A tag belongs to one spool, one filament or one location.")
        }
        let outcome = await repository.linkFilamentTag(filamentId: filamentId, uid: normalized)
        refresh(writes: outcome == .linked ? 1 : 0)
        return outcome
    }

    /// Every mode: links are read in every mode, so a wrong one must stay
    /// removable.
    @discardableResult
    func unlinkFilamentTag(filamentId: Int, uid: String) async -> Bool {
        let result = await repository.unlinkFilamentTag(
            filamentId: filamentId, uid: SpoolMappingService.normalizeUID(uid)
        )
        refresh(writes: result ? 1 : 0)
        return result
    }

    /// Forwarded, never defaulted (spec 3).
    var supportsTagScanReporting: Bool { repository.supportsTagScanReporting }

    func reportTagScan(_ report: TagScanReport) async -> TagScanReportOutcome {
        await repository.reportTagScan(report)
    }

    func checkReachability() async -> BackendReachability {
        await repository.checkReachability()
    }

    @discardableResult
    func addVendor(draft: VendorDraft) async -> Vendor? {
        let result = await repository.addVendor(draft: draft)
        refresh(writes: result == nil ? 0 : 1)
        return result
    }

    @discardableResult
    func addVendor(name: String) async -> Vendor? {
        let result = await repository.addVendor(name: name)
        refresh(writes: result == nil ? 0 : 1)
        return result
    }

    @discardableResult
    func updateVendor(id: Int, draft: VendorDraft) async -> Bool {
        let result = await repository.updateVendor(id: id, draft: draft)
        refresh(writes: result ? 1 : 0)
        return result
    }

    @discardableResult
    func deleteVendor(id: Int) async -> Bool { let r = await repository.deleteVendor(id: id); refresh(writes: r ? 1 : 0); return r }

    /// One write: a cascade is one user action on one record, whatever it takes with it.
    func deleteVendorCascading(id: Int) async -> Bool {
        let r = await repository.deleteVendorCascading(id: id); refresh(writes: r ? 1 : 0); return r
    }

    /// What deleting these vendors would take with it, counted from a FRESH
    /// fetch — never from arrays another screen loaded earlier. `nil` when a
    /// fetch failed; `errorMessage` says why, and nothing may be deleted on a
    /// count that could not be made.
    func deletionImpact(vendorIDs: Set<Int>) async -> DeletionImpact? {
        await repository.fetchFilaments()
        guard repository.errorMessage == nil else { refresh(); return nil }
        await repository.fetchSpools()
        refresh()
        guard errorMessage == nil else { return nil }
        return DeletionImpact.forVendors(vendorIDs, filaments: filaments, spools: spools)
    }

    /// See `deletionImpact(vendorIDs:)`.
    func deletionImpact(filamentIDs: Set<Int>) async -> DeletionImpact? {
        await repository.fetchSpools()
        refresh()
        guard errorMessage == nil else { return nil }
        return DeletionImpact.forFilaments(filamentIDs, spools: spools)
    }

    /// Forwarded, never defaulted — see the protocol extension's note. The
    /// migration screen reads it through this facade, so a `[]` here would
    /// hide FilaMan's refusals from the one caller that exists to surface them.
    func missingFilamentRequirements(for draft: FilamentDraft) -> [FilamentCreateRequirement] {
        repository.missingFilamentRequirements(for: draft)
    }

    @discardableResult
    func addFilament(draft: FilamentDraft) async -> Filament? {
        let result = await repository.addFilament(draft: draft)
        refresh(writes: result == nil ? 0 : 1)
        return result
    }

    @discardableResult
    func updateFilament(id: Int, draft: FilamentDraft) async -> Bool {
        let result = await repository.updateFilament(id: id, draft: draft)
        refresh(writes: result ? 1 : 0)
        return result
    }

    @discardableResult
    func deleteFilament(id: Int) async -> Bool { let r = await repository.deleteFilament(id: id); refresh(writes: r ? 1 : 0); return r }

    /// See `deleteVendorCascading`.
    func deleteFilamentCascading(id: Int) async -> Bool {
        let r = await repository.deleteFilamentCascading(id: id); refresh(writes: r ? 1 : 0); return r
    }

    /// Outside Tag Links a new spool's tags stay behind (R13): the spool is
    /// created, and the note says which tags were not linked, so a caller
    /// that reads a create's caveat — the migration does — keeps them.
    @discardableResult
    func addSpool(draft: SpoolDraft) async -> Spool? {
        var draft = draft
        let unlinked = tagIdentity.writesLinks ? [] : (draft.cardUIDs ?? [])
        if !unlinked.isEmpty { draft.cardUIDs = nil }
        let result = await repository.addSpool(draft: draft)
        refresh(writes: result == nil ? 0 : 1)
        if result != nil, !unlinked.isEmpty {
            let note = "Tags \(unlinked.joined(separator: ", ")) were not linked to it.\n"
                + TagStoreText.linksOffNote(connectionRowLabel: capabilities.connectionRowLabel)
            errorMessage = [errorMessage, note].compactMap { $0 }.joined(separator: "\n")
        }
        return result
    }

    /// Creates `drafts` in order through `addSpool(draft:)`, stopping at the first
    /// that does not confirm. Never rolls back: what landed stays, and the result
    /// says where it stopped. The caveat and the failure are read straight after
    /// each create, because the next one overwrites `errorMessage`.
    func addSpools(drafts: [SpoolDraft]) async -> SpoolBatchResult {
        var created: [Spool] = []
        var caveats: [String] = []
        for (index, draft) in drafts.enumerated() {
            guard let spool = await addSpool(draft: draft) else {
                let failure = SpoolBatchFailure(
                    position: index + 1,
                    total: drafts.count,
                    reason: errorMessage ?? "The spool could not be saved."
                )
                return SpoolBatchResult(created: created, failure: failure, caveats: caveats)
            }
            created.append(spool)
            if let caveat = errorMessage, !caveats.contains(caveat) { caveats.append(caveat) }
        }
        return SpoolBatchResult(created: created, failure: nil, caveats: caveats)
    }

    @discardableResult
    func updateSpool(id: Int, draft: SpoolDraft) async -> Bool {
        let result = await repository.updateSpool(id: id, draft: draft)
        refresh(writes: result ? 1 : 0)
        return result
    }

    @discardableResult
    func deleteSpool(id: Int) async -> Bool { let r = await repository.deleteSpool(id: id); refresh(writes: r ? 1 : 0); return r }

    @discardableResult
    func setSpoolArchived(id: Int, archived: Bool) async -> Bool {
        let r = await repository.setSpoolArchived(id: id, archived: archived); refresh(writes: r ? 1 : 0); return r
    }

    func findSpool(byCardUID uid: String) -> Spool? {
        repository.findSpool(byCardUID: uid)
    }

    /// Forwarded rather than inherited: the protocol's default answers `[]`,
    /// and a facade that took the default would hide FilaMan's history behind
    /// its own silence.
    func fetchMeasurementHistory(spoolID: Int) async -> [MeasurementRecord] {
        await repository.fetchMeasurementHistory(spoolID: spoolID)
    }

    /// Forwarded for the same reason: the default answers "no catalogue",
    /// which would hide the one Spoolman's operator configured.
    func fetchFilamentCatalog() async throws -> [SpoolmanDBFilament]? {
        try await repository.fetchFilamentCatalog()
    }

    /// Outside Tag Links SpoolKid creates no links, migration included (R13):
    /// a write that ADDS a tag the spool does not already answer for is
    /// refused here, once, for every caller and every backend — the plan a
    /// repository would run then adds nothing and still reports success.
    /// Removals run in every mode: links are read in every mode, so a wrong
    /// one must stay removable.
    @discardableResult
    func setCardUIDs(spoolId: Int, uids: [String]) async -> Bool {
        guard tagIdentity.writesLinks
            || !Self.addsTag(uids, to: repository.spools.first { $0.id == spoolId })
        else {
            errorMessage = TagStoreText.linksOffNote(connectionRowLabel: capabilities.connectionRowLabel)
            return false
        }
        let result = await repository.setCardUIDs(spoolId: spoolId, uids: uids)
        refresh(writes: result ? 1 : 0)
        return result
    }

    /// Whether `uids` names a tag `spool` does not already answer for. A spool
    /// the store does not hold answers for none.
    nonisolated static func addsTag(_ uids: [String], to spool: Spool?) -> Bool {
        let held = Set((spool?.mappedCardUIDs ?? []).map(SpoolMappingService.normalizeUID))
        return uids.map(SpoolMappingService.normalizeUID).contains { !$0.isEmpty && !held.contains($0) }
    }

    /// Every tag UID currently claimed by a spool: the backend's own mapping
    /// plus the device-local ledger, which can hold a UID the backend has not
    /// caught up with. Normalized, so it can be compared directly.
    var tagMappedUIDs: Set<String> {
        var uids = Set(spools.flatMap { $0.mappedCardUIDs }.map(SpoolMappingService.normalizeUID))
        uids.formUnion(TagAssociationStore.shared.snapshot().keys.map(SpoolMappingService.normalizeUID))
        uids.remove("")
        return uids
    }

    /// Every tag UID linked to a filament type (spec 4). Not claimable by a
    /// spool or a shelf.
    var filamentTagUIDs: Set<String> {
        Set(filaments.flatMap(\.mappedTagUIDs))
    }

    /// What this tag belongs to, across BOTH kinds of owner.
    ///
    /// The one place the global single-owner rule is evaluated. Spools are
    /// checked first only because their claim is the one stored on a server and
    /// visible to other clients; the two are mutually exclusive by construction
    /// — every claim site consults this before writing — so the order is not a
    /// precedence rule and must not be read as one.
    func owner(ofTagUID uid: String) -> TagOwner {
        let normalized = SpoolMappingService.normalizeUID(uid)
        guard !normalized.isEmpty else { return .none }

        if let spool = findSpool(byCardUID: normalized) {
            return .spool(id: spool.id, label: spool.listTitle)
        }
        // After spools: a `card_uids` claim is what the printer resolves, so a
        // spool that still carries the UID there answers for it.
        if let filament = filaments.first(where: { $0.mappedTagUIDs.contains(normalized) }) {
            return .filament(id: filament.id, label: filament.listTitle)
        }
        if let record = locationRegistry?.record(forTagUID: normalized) {
            return .location(name: record.name)
        }
        return .none
    }

    /// Releases a tag from whichever spool claims it, on the backend and in the
    /// local ledger. Used when the user confirms that a tag a spool still owns
    /// should become a location tag.
    @discardableResult
    func unlinkTag(uid: String) async -> Bool {
        let normalized = SpoolMappingService.normalizeUID(uid)
        guard !normalized.isEmpty else { return false }

        TagAssociationStore.shared.remove(uid: normalized)

        guard let spool = findSpool(byCardUID: normalized) else {
            // Nothing on the backend claimed it; the ledger row was the whole
            // claim and it is gone.
            return true
        }
        // What the spool keeps, from the UIDs a `card_uids` write may carry —
        // never `mappedCardUIDs`, which would copy FilaMan's `rfid_uid` into
        // `card_uids` whenever a different tag is unlinked (final review
        // FR-2). A UID that also lives in `rfid_uid` still resolves to the
        // spool afterwards, so callers re-ask rather than trust the Bool
        // (`TagLinkService.unlinkCaveat`, `TagCloneService.releaseNote`, the
        // location write's block list).
        let remaining = spool.writableCardUIDs.filter { $0 != normalized }
        return await setCardUIDs(spoolId: spool.id, uids: remaining)
    }

    /// Forwards the SpoolLink field bootstrap to whichever backend is active.
    /// No `refresh()`: this declares a field, it does not change any record.
    @discardableResult
    func ensureCardUIDsField() async -> Bool {
        await repository.ensureCardUIDsField()
    }

    @discardableResult
    func deleteCardUIDsField() async -> Bool {
        let result = await repository.deleteCardUIDsField()
        refresh()
        return result
    }

    /// Forwarded, never defaulted: the default answers "nothing to delete",
    /// which on Spoolman would report a deletion that never ran.
    func deleteSpoolmanTagLinks() async -> TagBulkDeleteResult {
        let result = await repository.deleteSpoolmanTagLinks()
        refresh()
        return result
    }

    /// The `SpoolDataRepository` witness. Ordinary creates mint a fresh uuid.
    @discardableResult
    func addLocation(name: String) async -> LocationCreateOutcome {
        await addLocation(name: name, adoptingUUID: nil, tagUID: nil)
    }

    /// `adoptingUUID` is the uuid a scanned location tag already carries — a tag
    /// written on another device. Registering under it, rather than under a
    /// fresh one, is what makes that tag recognised from the next scan on;
    /// `tagUID` is the tag's hardware UID, recorded so a later rename can offer
    /// to rewrite it.
    @discardableResult
    func addLocation(
        name: String, adoptingUUID uuid: UUID?, tagUID: String?
    ) async -> LocationCreateOutcome {
        let result = await repository.addLocation(name: name)
        // A tag a spool already claims is not this location's to take. The
        // location is still created — the user asked for it — but it is created
        // untagged rather than as the second owner of one UID. The spool's
        // claim wins because it is the one stored on a server and readable by
        // other clients; releasing it is a decision only the user can make, and
        // the location screen's own write path asks.
        let claimableTagUID: String? = switch tagUID.map(owner(ofTagUID:)) {
        case .spool?, .filament?: nil
        default: tagUID
        }

        // A location the backend cannot hold has to live somewhere, and one it
        // CAN hold still needs a uuid for its tags — so every success
        // registers, and only a failure does not.
        if result.isSuccess, let registry = locationRegistry {
            let registered = if let uuid {
                registry.adopt(uuid: uuid, name: name, tagUID: claimableTagUID)
            } else {
                registry.add(name: name)
            }
            if registered == nil {
                let reason = registry.errorMessage.map { " \($0)" } ?? ""
                // The registry was to be its only home, so nothing exists.
                if result == .registeredOnDeviceOnly {
                    refresh()
                    return .failed("\(LocationName.trimmed(name)) could not be saved on this device.\(reason)")
                }
                // The backend holds it; what is missing is the scanned tag's
                // link. With no tag, nothing the user asked for is: the entry
                // is made when a tag is first written, and that path reports
                // its own failure (`LocationDetailView.startTagWrite`).
                if uuid != nil {
                    postSaveNotice(
                        "This tag could not be linked to it on this iPhone, so it is not recognised yet.\(reason)",
                        record: LocationName.trimmed(name)
                    )
                }
            }
        }
        refresh(writes: result == .created ? 1 : 0)
        return result
    }

    /// Forwarded, never defaulted — a facade answering `.unsupported` on behalf
    /// of a backend that does have the field is the same lie one layer up.
    ///
    /// Short-circuits on the capability so no backend without a location entity
    /// is asked, and on a location the backend has never heard of: one that
    /// lives only in the registry has no row to carry the identifier yet, and
    /// the assignment that creates it will not carry the tag either. Both cases
    /// are `.unsupported` — nothing was attempted, and nothing is missing.
    @discardableResult
    func setLocationTagUID(locationName: String, uid: String?) async -> LocationTagUIDOutcome {
        guard capabilities.storesLocationTagUID, backendKnowsLocation(named: locationName) else {
            return .unsupported
        }
        let result = await repository.setLocationTagUID(locationName: locationName, uid: uid)
        if case .written = result { refresh(writes: 1) }
        return result
    }

    @discardableResult
    func renameLocation(currentName: String, newName: String) async -> Bool {
        // A location that exists ONLY in the registry has no server half to
        // rename: Spoolman's `PATCH /location/<name>` fails for a name no spool
        // references, which is precisely the pending-on-device case. Renaming
        // the entry IS the whole operation there, so it succeeds without a
        // backend call instead of reporting a server error over work the
        // server was never asked to do — and the tag-rewrite offer that
        // follows a successful rename fires as it should.
        guard backendKnowsLocation(named: currentName) else {
            guard let registry = locationRegistry, registry.record(named: currentName) != nil else { return false }
            guard registry.rename(from: currentName, to: newName) else {
                errorMessage = registry.errorMessage
                return false
            }
            locationOrder?.rename(from: currentName, to: newName)
            return true
        }

        let result = await repository.renameLocation(currentName: currentName, newName: newName)
        refresh(writes: result ? 1 : 0)
        guard result else { return false }
        locationOrder?.rename(from: currentName, to: newName)
        // The backend has the new name either way; a registry entry that
        // could not follow it keeps the old one, which its tags then read.
        if let registry = locationRegistry, registry.record(named: currentName) != nil,
           !registry.rename(from: currentName, to: newName) {
            postSaveNotice(
                "This iPhone could not save the new name, so its tags still read \(currentName)."
                    + (registry.errorMessage.map { " \($0)" } ?? ""),
                record: LocationName.trimmed(newName)
            )
        }
        return true
    }

    /// `LocationReconciliation.backendKnows` over state every fetch already
    /// refreshes. Archived spools count: they still name the location on the
    /// server.
    private func backendKnowsLocation(named name: String) -> Bool {
        LocationReconciliation.backendKnows(
            name: name,
            backendLocations: locations,
            spoolLocations: spools.compactMap(\.location)
        )
    }

    @discardableResult
    func deleteLocation(_ name: String) async -> Bool {
        // Asked first: the delete takes the name off the backend.
        let backendHeldIt = backendKnowsLocation(named: name)
        guard await repository.deleteLocation(name) else {
            refresh()
            return false
        }
        guard let registry = locationRegistry, !registry.remove(named: name) else {
            refresh(writes: 1)
            return true
        }
        guard backendHeldIt else {
            // The entry was the location's only home, so nothing was deleted.
            refresh()
            errorMessage = registry.errorMessage
            return false
        }
        refresh(writes: 1)
        postSaveNotice(
            "This iPhone could not save the change, so it still lists \(name)."
                + (registry.errorMessage.map { " \($0)" } ?? ""),
            record: name
        )
        return true
    }

    /// Lists a tag just written for a location among its tags, so a rename
    /// offers to rewrite it. The tag is written either way, so a failed save
    /// is posted as what that write went without.
    func recordWrittenLocationTag(uid: String, to uuid: UUID, locationName: String) {
        guard let registry = locationRegistry, !registry.attachTag(uid: uid, to: uuid) else { return }
        postSaveNotice(
            "The tag was written, but this iPhone could not list it under \(locationName), so a rename will not offer to update it."
                + (registry.errorMessage.map { " \($0)" } ?? ""),
            record: locationName
        )
    }

    // MARK: - Registry-only reconciliation
    //
    // These touch the device-local registry and NOTHING else. The backend
    // already holds the name in the "Match to…" case — that is the premise —
    // so routing either through `renameLocation`/`deleteLocation` would act on
    // the server a second time, over a location the user never named.

    /// Re-points a registry entry at a name the backend actually lists,
    /// keeping its uuid so tags already written for it go on resolving.
    /// `false` when it could not be saved; `errorMessage` says why.
    @discardableResult
    func matchRegisteredLocation(currentName: String, to backendName: String) -> Bool {
        guard locationRegistry?.rename(from: currentName, to: backendName) == true else {
            errorMessage = locationRegistry?.errorMessage
            return false
        }
        locationOrder?.rename(from: currentName, to: backendName)
        objectWillChange.send()
        return true
    }

    /// Forgets a device-local entry. The backend is not touched. `false` when
    /// it could not be saved; `errorMessage` says why.
    @discardableResult
    func forgetRegisteredLocation(named name: String) -> Bool {
        guard locationRegistry?.remove(named: name) ?? true else {
            errorMessage = locationRegistry?.errorMessage
            return false
        }
        objectWillChange.send()
        return true
    }

    /// How a location's registry entry stands against what the backend lists.
    /// A location with no registry entry at all is `.inSync` — it exists
    /// because the backend says so, which is the definition.
    func syncState(forLocationNamed name: String) -> LocationSyncState {
        guard let record = locationRegistry?.record(named: name) else { return .inSync }
        return LocationReconciliation.state(for: record, backendLocations: locations)
    }

    // MARK: - Bulk list actions

    func archiveSpools(ids: Set<Int>) async -> BulkActionResult {
        var ok = 0, fail = 0
        for id in ids {
            if await repository.setSpoolArchived(id: id, archived: true) { ok += 1 } else { fail += 1 }
        }
        refresh(writes: ok)
        return BulkActionResult(succeeded: ok, failed: fail)
    }

    /// Moves a selection of spools to one location — or clears it, with
    /// `.setNil`. Sequential rather than concurrent, like every other bulk
    /// action here: the backends are single-user servers on a LAN, and a
    /// stampede buys nothing but a harder failure story.
    ///
    /// The return type carries the truth. A partial run is a partial run, and
    /// the caller says so.
    func assignLocation(spoolIDs: [Int], to location: SpoolmanPatchValue<String>) async -> BulkActionResult {
        var ok = 0, fail = 0
        for id in spoolIDs {
            if await repository.updateSpool(id: id, draft: .locationAssignment(location)) { ok += 1 } else { fail += 1 }
        }
        refresh(writes: ok)
        return BulkActionResult(succeeded: ok, failed: fail)
    }
}
