//
//  FilaManRepository.swift
//  SpoolKid
//
//  Purpose: `SpoolDataRepository` backed by FilaMan's native /api/v1 REST API.
//
//  Unlike `SpoolmanRepository` (a thin forwarding wrapper over
//  `SpoolmanService`'s own @Published arrays), this type owns FilaMan's
//  app-level state itself: `FilaManService` (Task 16a) is a stateless
//  transport layer returning wire DTOs, not app models, so the DTO→app-model
//  mapping — and its dependency ordering, since FilaMan's list endpoints
//  return bare foreign-key ids rather than Spoolman's embedded objects —
//  lives here.
//
//  Not `nonisolated`: `Spool`/`Filament`/`Vendor` (Models/Spool.swift) are not
//  marked `nonisolated` either, so their initializers are MainActor-isolated
//  by the project's default actor isolation. A `nonisolated` mapper here
//  cannot call them synchronously; this type stays MainActor to match.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import os.log

// MARK: - Resolve-or-create outcomes
//
// FilaMan models locations and colours as first-class entities, so writing
// either from a free-text draft is a resolve-or-create step rather than a
// field assignment. The types below exist so that step can say "I could not
// do this" in its RETURN TYPE.
//
// Plan defects F24, F25 and F29 were the same mistake three times: a code path
// that communicated more than it established, letting an unresolvable value
// collapse into "the user didn't ask for anything" so the caller reported
// success for work it never did. A failure that has nowhere to live in the
// type is a failure the caller cannot report.

/// Whether a `FilamentDraft` carries everything `FilamentCreate` requires
/// (review finding F30). Two cases, because the satisfied one has to hand the
/// manufacturer id onward: a `String?` "what's missing" answer would leave
/// `addFilament` unwrapping `vendorId` a second time, in a branch that can no
/// longer be reached.
nonisolated enum FilaManFilamentCreateRequirements: Equatable, Sendable {
    case satisfied(manufacturerId: Int)
    case missing(String)
}

/// What a `SpoolDraft`'s free-text location patch means against the locations
/// FilaMan already knows about. `.create` is the case that must never be
/// folded into `.ignore` (F25): "the user named a shelf I don't have yet" and
/// "the user didn't touch the location" call for opposite behaviour.
nonisolated enum FilaManLocationPlan: Equatable, Sendable {
    /// The draft doesn't touch the location — omit `location_id` entirely.
    case ignore
    /// The draft clears the location — send an explicit `null`.
    case clear
    /// The name matches a location FilaMan already has.
    case existing(Int)
    /// The name is new (trimmed, non-empty) and the entity must be created.
    case create(String)
}

/// The result of actually performing a `FilaManLocationPlan`. Deliberately two
/// cases: either there is a wire patch to send, or there is a reason there
/// isn't. `SpoolmanPatchValue` carries the `.ignore` / `.set` / `.setNil`
/// distinction the payload builder already understands, so no caller has to
/// re-derive that encoding — and no caller can reach for `.ignore` as a
/// stand-in for failure, because failure is a case of its own.
nonisolated enum FilaManLocationResolution {
    case patch(SpoolmanPatchValue<Int>)
    case failed(String)
}

/// What one colour hex means against the rows `GET /api/v1/colors` returned.
nonisolated enum FilaManColorSlotPlan: Equatable, Sendable {
    case existing(Int)
    /// Normalized hex (`FilaManPayloadBuilder.normalizedHex`) to create.
    case create(String)
}

/// The result of resolving every colour hex a filament draft asks for.
/// `.skip` means the draft carries no colour at all, which is NOT the same as
/// resolving to an empty list: `PUT /filaments/{id}/colors` is a full replace
/// and `colors: []` wipes every colour, so `.skip` means send no request.
nonisolated enum FilaManColorResolution: Equatable, Sendable {
    case skip
    case resolved([Int])
    case failed(String)
}

/// How to move a spool's remaining weight to a target, given what FilaMan
/// currently reports. `.currentUnknown` is its own case because a *relative*
/// adjustment is meaningless without a current value — treating a missing
/// `remaining_weight_g` as zero would set the spool to `target` above whatever
/// it actually holds and report success (R17).
nonisolated enum FilaManWeightAdjustment: Equatable, Sendable {
    case alreadyThere
    case delta(Double)
    case currentUnknown
}

/// Which endpoint a save's weight goes to. FilaMan files the two differently
/// in its event history — `measurement` versus `manual_adjust` — so this is a
/// user-visible distinction, not an implementation detail.
nonisolated enum FilaManWeightWrite: Equatable {
    /// A GROSS scale reading, written whole to `POST /spools/{id}/measurements`.
    case measurement(Double)
    /// A net target, reached by a delta through `POST /spools/{id}/adjustments`.
    case adjustment
}

/// What a spool's remaining weight must BECOME, before any delta arithmetic.
///
/// `.unsupported` is the case that must never be folded into `.unchanged`
/// (I2): "the user set a used weight I cannot convert" and "the user named no
/// weight at all" call for opposite behaviour, and only one of them is
/// something to tell them about. It carries every reason the weight cannot be
/// settled — unconvertible, out of range, or (R20) a pre-PATCH value that
/// could not be read — because all of them mean the same two things to the
/// caller: write nothing, and say this.
///
/// `.unchanged` means "nothing has to happen for the weight to be right",
/// which after R20 is a stronger claim than "the user asked for nothing".
nonisolated enum FilaManRemainingWeightTarget: Equatable, Sendable {
    case unchanged
    case grams(Double)
    case unsupported(String)
}

/// A spool's remaining weight as FilaMan reported it immediately BEFORE a
/// scalar PATCH — the reference point R20 restores to.
///
/// Four cases rather than a `Double?`, because "the PATCH cannot move it",
/// "FilaMan reports no weight for this spool" and "the read failed" are three
/// different situations that a single optional would flatten into one, and
/// exactly one of them is a thing to tell the user about. Collapsing them is
/// the defect this whole round exists to stop repeating.
nonisolated enum FilaManPrePatchRemainingWeight: Equatable, Sendable {
    /// The payload carries no `empty_spool_weight_g`, so under F32 nothing it
    /// does can shift the reported remaining weight. Nothing to guard.
    case cannotMove
    /// What FilaMan reported before the PATCH.
    case reported(Double)
    /// FilaMan reports no remaining weight for this spool at all, so there is
    /// no value to hold it to — and the re-base only ever moves a remaining
    /// weight that already exists, so no basis change can conjure one.
    case unreported
    /// The pre-PATCH read failed. Whether the PATCH moved the weight is now
    /// unknowable, which is a caveat and not a silent pass.
    case unreadable(String)
}

/// What actually happened when a remaining weight was written. `.unchanged`
/// means no adjustment event was posted (the spool is already there), which
/// is why it is distinct from `.adjusted`: only `.adjusted` invalidates the
/// caller's copy of the spool and earns the re-read.
nonisolated enum FilaManWeightWriteOutcome: Equatable, Sendable {
    case unchanged
    case adjusted
    case failed(String)
}

@MainActor
final class FilaManRepository: SpoolDataRepository {
    private let service: FilaManService
    nonisolated let capabilities = BackendCapabilities.filaman

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SpoolKid",
        category: "FilaManRepository"
    )

    private(set) var spools: [Spool] = []
    private(set) var filaments: [Filament] = []
    private(set) var vendors: [Vendor] = []
    private(set) var locations: [String] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    nonisolated var lastQuotaError: QuotaError? { nil }

    /// FilaMan location id ⇄ name, populated by `loadLocations`. Used both to
    /// resolve `FilaManSpool.locationId` for display (`mapSpool`) and to
    /// resolve a `SpoolDraft`'s free-text location name back to an id for
    /// writes (`plannedLocationResolution` / `resolveLocation`).
    private var locationsById: [Int: String] = [:]
    private var locationIdByName: [String: Int] = [:]

    init(service: FilaManService) {
        self.service = service
    }

    private var baseUrl: String {
        UserDefaults.standard.string(forKey: AppConfig.filamanUrlKey) ?? ""
    }

    /// `errorMessage` is a stored property here (unlike `SpoolmanRepository`'s,
    /// which forwards live via a computed getter onto `SpoolmanService`'s own
    /// `@Published errorMessage`) — so a call that sets `service.errorMessage`
    /// as a side effect (as `probeIsFilaMan`, which this delegates to via
    /// `testConnection`, does on its unreachable paths) does not automatically
    /// show up on `self.errorMessage` unless copied over explicitly.
    func testConnection() async -> Bool {
        let result = await service.testConnection(baseUrl: baseUrl)
        errorMessage = service.errorMessage
        return result
    }

    var connectionTarget: String { "filaman|\(ServerAddress.identity(of: baseUrl))" }

    /// Note the contrast with `testConnection` directly above: no
    /// `errorMessage` copy-back. `healthCheck` deliberately leaves the service's
    /// banner alone, and this must not reintroduce the mutation by the back
    /// door.
    ///
    /// A rejected API key means the server answered — but the status dot has
    /// only two colours to say it with, so it collapses to `.unreachable` here
    /// exactly as Spoolman's does. `FilaManConnectionForm`'s explicit Test
    /// Connection is where that distinction is reported to the user.
    func checkReachability() async -> BackendReachability {
        await BackendReachability.probing(address: baseUrl) {
            await service.healthCheck(baseUrl: baseUrl) == .confirmed
        }
    }

    // MARK: - Fetch orchestration
    //
    // FilaMan's list endpoints return bare foreign-key ids (locationId,
    // manufacturerId, filamentId) rather than Spoolman's embedded related
    // objects, so each mapper needs its dependency already resolved: vendors
    // before filaments (`mapFilament`'s `vendor` parameter), and filaments +
    // locations before spools (`mapSpool`'s `filament` and `locationsById`
    // parameters). Each public `fetch*` below pulls its own dependencies
    // itself rather than trusting caller order — existing call sites (e.g.
    // `SpoolmanTabView`'s spools→filaments→vendors refresh sequence) were
    // written for Spoolman's no-dependency shape and do not fetch in the
    // order FilaMan needs.

    private func run(_ operation: () async throws -> Void) async {
        isLoading = true
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadVendors() async throws {
        let manufacturers = try await service.fetchManufacturers(baseUrl: baseUrl)
        vendors = manufacturers.map(Self.mapVendor)
    }

    private func loadLocations() async throws {
        let items = try await service.fetchLocations(baseUrl: baseUrl)
        locationsById = Dictionary(items.map { ($0.id, $0.name) }, uniquingKeysWith: { _, last in last })
        locationIdByName = Dictionary(
            items.map { (Self.normalizedLocationKey($0.name), $0.id) },
            uniquingKeysWith: { _, last in last }
        )
        locations = items.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func loadFilaments() async throws {
        try await loadVendors()
        let dtos = try await service.fetchFilaments(baseUrl: baseUrl)
        filaments = Self.mapFilaments(dtos, vendors: vendors)
    }

    private func loadSpools() async throws {
        try await loadFilaments()
        try await loadLocations()
        let dtos = try await service.fetchSpools(baseUrl: baseUrl)
        spools = Self.mapSpools(
            dtos, filaments: filaments, locationsById: locationsById,
            rfidWritable: FilaManTagSwitches.tagsEnabled()
        )
    }

    func fetchVendors() async { await run { try await self.loadVendors() } }
    func fetchLocations() async { await run { try await self.loadLocations() } }
    func fetchFilaments() async { await run { try await self.loadFilaments() } }
    func fetchSpools() async { await run { try await self.loadSpools() } }

    // MARK: - Write helpers

    /// Registers FilaMan's `td` field after a save that set a TD. The value is
    /// already stored either way; a refusal (it needs `admin:system`) only
    /// means FilaMan's own UI won't list the field — a caveat, not a failure.
    private func registerTransmissionDistanceField(for draft: FilamentDraft) async -> String? {
        guard case .set = draft.transmissionDistance else { return nil }
        do {
            try await service.ensureTransmissionDistanceField(baseUrl: baseUrl)
            return nil
        } catch {
            return Self.transmissionDistanceRegistryNote(error: error.localizedDescription)
        }
    }

    nonisolated static func transmissionDistanceRegistryNote(error: String) -> String {
        "TD saved, but FilaMan's field list could not be updated, so its own pages won't show TD: \(error)"
    }

    /// Shared GET → merge step behind `updateVendor`/`updateFilament`/
    /// `updateSpool`'s merge-protected `custom_fields` writes. A no-op
    /// (returns `payload` unchanged) when `payload` carries no `custom_fields`
    /// key at all — nothing to protect. Otherwise fetches the record's
    /// current `custom_fields` fresh via `fetchCurrentFields` and merges the
    /// draft-derived keys on top (`FilaManService.mergedCustomFields`) before
    /// returning the payload with the merged object in place, so the
    /// eventual PATCH is one combined GET → merge → PATCH rather than a
    /// partial write that could destroy an existing `spoolman_id` linkage —
    /// see `updateVendor`'s doc comment for the live evidence that risk is
    /// real for manufacturers and filaments too, not just spools.
    private func mergeCustomFieldsIfNeeded(
        into payload: [String: Any],
        fetchCurrentFields: () async throws -> [String: FilaManJSONValue]?
    ) async throws -> [String: Any] {
        let newCustomFields = payload["custom_fields"] as? [String: String]
        guard let newCustomFields else { return payload }
        var merged = payload
        let existing = try await fetchCurrentFields()
        merged["custom_fields"] = FilaManService.mergedCustomFields(
            existing: existing, new: newCustomFields
        ).jsonObject
        return merged
    }

    // MARK: - Vendors

    @discardableResult
    func addVendor(draft: VendorDraft) async -> Vendor? {
        let payload = FilaManPayloadBuilder.vendorPayload(from: draft)
        do {
            let created = try await service.createManufacturer(payload: payload, baseUrl: baseUrl)
            let vendor = Self.mapVendor(created)
            vendors.append(vendor)
            errorMessage = Self.unwritableVendorFieldsNoteOnCreate(comment: draft.comment, externalId: draft.externalId)
            return vendor
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func addVendor(name: String) async -> Vendor? {
        await addVendor(draft: VendorDraft(name: name))
    }

    /// Merge-protected: manufacturers on a migrated FilaMan instance carry a
    /// `custom_fields: {"spoolman_id": N, ...}` linkage — the same shape
    /// `FilaManService.mergedCustomFields`'s doc comment documents for
    /// spools, verified live 2026-08-20 to also hold for manufacturers and
    /// filaments. A plain PATCH of `custom_fields` (draft-derived keys only)
    /// would destroy that linkage the first time a vendor is edited, so the
    /// current object is re-read and merged locally before the PATCH — same
    /// GET → merge → PATCH shape as `patchSpoolCustomFields`.
    @discardableResult
    func updateVendor(id: Int, draft: VendorDraft) async -> Bool {
        var payload = FilaManPayloadBuilder.vendorPayload(from: draft)
        do {
            payload = try await mergeCustomFieldsIfNeeded(into: payload) {
                try await self.service.fetchManufacturer(id: id, baseUrl: self.baseUrl).customFields
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        do {
            let updated = try await service.updateManufacturer(id: id, payload: payload, baseUrl: baseUrl)
            if let index = vendors.firstIndex(where: { $0.id == id }) {
                vendors[index] = Self.mapVendor(updated)
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteVendor(id: Int) async -> Bool {
        do {
            try await service.deleteManufacturer(id: id, force: false, baseUrl: baseUrl)
            vendors.removeAll { $0.id == id }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// `force=true`: the server removes the dependents in the same commit, so
    /// the cached arrays drop what this cache knew depended on the vendor.
    func deleteVendorCascading(id: Int) async -> Bool {
        do {
            try await service.deleteManufacturer(id: id, force: true, baseUrl: baseUrl)
            let impact = DeletionImpact.forVendors([id], filaments: filaments, spools: spools)
            spools.removeAll { impact.spoolIDs.contains($0.id) }
            filaments.removeAll { impact.filamentIDs.contains($0.id) }
            vendors.removeAll { $0.id == id }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Filaments

    /// Everything `FilamentCreate` requires, checked in one place before the
    /// request is built (review finding F30).
    ///
    /// The manufacturer guard was here from the start;
    /// `designation`/`material_type`/`diameter_mm` are required by the same
    /// schema and were not, so a draft missing one of them reached the server
    /// and came back as a raw 422 — the outcome the manufacturer guard exists
    /// to prevent. `FilamentFormView` gates Save on a non-empty name alone,
    /// and `MigrationService` assembles drafts with no gate at all, so both
    /// paths could reach it.
    ///
    /// Reports the FIRST missing requirement rather than all of them: this
    /// lands in `errorMessage`, which the forms render as one sentence.
    /// Whitespace does not satisfy a string requirement.
    ///
    /// The satisfied case carries the manufacturer id so the caller unwraps
    /// nothing a second time — a re-check after this returns would be an
    /// unreachable branch, and this way the type says the id is there.
    nonisolated static func createRequirements(
        of draft: FilamentDraft
    ) -> FilaManFilamentCreateRequirements {
        if let first = missingRequirements(of: draft).first {
            return .missing(sentence(for: first))
        }
        // Unreachable unless `.manufacturer` is absent from the list above,
        // which is what makes the force-free unwrap safe here.
        guard let manufacturerId = draft.vendorId.valueOnCreate else {
            return .missing(sentence(for: .manufacturer))
        }
        return .satisfied(manufacturerId: manufacturerId)
    }

    /// Every requirement the draft fails, in form order — the list `migration`
    /// renders a control per, where `createRequirements` returns only the first
    /// as a sentence. One source of truth for both: the sentence is derived
    /// from this list, so the two can never disagree about what FilaMan wants.
    nonisolated static func missingRequirements(of draft: FilamentDraft) -> [FilamentCreateRequirement] {
        func isBlank(_ value: String?) -> Bool {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }

        var missing: [FilamentCreateRequirement] = []
        if isBlank(draft.name) { missing.append(.name) }
        if isBlank(draft.material) { missing.append(.material) }
        if draft.diameter == nil { missing.append(.diameter) }
        // `.setNil` counts as MISSING, not as a clear to attempt: FilaMan
        // answers a null `manufacturer_id` with a 500, and a 500 carries no
        // useful message to pass on.
        if draft.vendorId.valueOnCreate == nil { missing.append(.manufacturer) }
        return missing
    }

    nonisolated static func sentence(for requirement: FilamentCreateRequirement) -> String {
        switch requirement {
        case .name: "A filament needs a name on FilaMan."
        case .material: "A filament needs a material on FilaMan."
        case .density: "A filament needs a density on FilaMan."
        case .diameter: "A filament needs a diameter on FilaMan."
        case .manufacturer: "A filament needs a manufacturer on FilaMan."
        }
    }

    func missingFilamentRequirements(for draft: FilamentDraft) -> [FilamentCreateRequirement] {
        Self.missingRequirements(of: draft)
    }

    /// Colours ride along INLINE: `FilamentCreate` accepts the same
    /// `color_mode`/`multi_color_style`/`colors` keys `colorsPayload` builds,
    /// so a create needs no second call and has no post-create partial-failure
    /// window. If a colour cannot be resolved or created the filament is still
    /// created — without colours, and saying so — because losing the filament
    /// is worse than losing its swatch.
    @discardableResult
    func addFilament(draft: FilamentDraft) async -> Filament? {
        let manufacturerId: Int
        switch Self.createRequirements(of: draft) {
        case .missing(let message):
            errorMessage = message
            return nil
        case .satisfied(let id):
            manufacturerId = id
        }
        var payload = FilaManPayloadBuilder.filamentPayload(from: draft, manufacturerId: manufacturerId)
        var colourWarning: String?
        switch await resolveColorIds(hexes: Self.colorHexes(from: draft)) {
        case .skip:
            break
        case .resolved(let colorIds):
            payload.merge(
                FilaManPayloadBuilder.colorsPayload(
                    colorIds: colorIds, multiColorStyle: draft.multiColorDirection.valueOnCreate
                )
            ) { _, new in new }
            colourWarning = Self.droppedStyleNote(
                requested: draft.multiColorDirection.valueOnCreate, colorCount: colorIds.count
            )
        case .failed(let message):
            colourWarning = "The filament was saved without its colour: \(message)"
        }
        if draft.transmissionDistance != .ignore {
            let stated = (payload["custom_fields"] as? [String: String] ?? [:]).mapValues { FilaManJSONValue.string($0) }
            let fields = FilaManPayloadBuilder.customFieldsApplyingTransmissionDistance(draft.transmissionDistance, to: stated)
            payload["custom_fields"] = fields.isEmpty ? nil : fields.jsonObject
        }
        do {
            let created = try await service.createFilament(payload: payload, baseUrl: baseUrl)
            let vendor = vendors.first { $0.id == created.manufacturerId }
            let filament = Self.mapFilament(created, vendor: vendor)
            filaments.append(filament)
            errorMessage = SaveOutcome.combinedNote([
                colourWarning,
                Self.unwritableFilamentFieldsNoteOnCreate(draft),
                await registerTransmissionDistanceField(for: draft)
            ])
            return filament
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// `FilaManPayloadBuilder.filamentPayload` always writes `manufacturer_id`
    /// (its parameter is non-optional) even though FilaMan's `FilamentUpdate`
    /// itself does not require it — a draft that doesn't change the
    /// manufacturer falls back to the filament's current one so the PATCH
    /// still carries a valid id. Merge-protected the same way as `updateVendor`.
    ///
    /// Two calls, because `FilamentUpdate` has no `colors` property: the scalar
    /// PATCH, then `PUT /filaments/{id}/colors` (R18). If the colour call
    /// fails the scalar edit still stands, so this returns `true` with an
    /// `errorMessage` naming the colour failure — reporting a flat `false`
    /// would suggest the whole edit was lost, which is its own kind of lie.
    @discardableResult
    func updateFilament(id: Int, draft: FilamentDraft) async -> Bool {
        // A draft that does not change the manufacturer falls back to the
        // filament's current one, so the PATCH still carries a valid id. A
        // `.setNil` lands here too and takes the same fallback — the clear is
        // refused (500) and reported, never sent.
        guard let manufacturerId = draft.vendorId.valueOnCreate
                ?? filaments.first(where: { $0.id == id })?.vendor?.id else {
            errorMessage = "A filament needs a manufacturer on FilaMan."
            return false
        }
        var payload = FilaManPayloadBuilder.filamentPayload(from: draft, manufacturerId: manufacturerId)

        // Merge-protected the same way as `updateVendor`: a filament on a
        // migrated FilaMan instance carries a `custom_fields: {"spoolman_id":
        // N}` linkage that a plain PATCH would destroy.
        let writesTD = draft.transmissionDistance != .ignore
        var current: Result<FilaManFilament, any Error>?
        if payload["custom_fields"] != nil || writesTD {
            do {
                current = .success(try await service.fetchFilament(id: id, baseUrl: baseUrl))
            } catch {
                current = .failure(error)
            }
        }
        do {
            if writesTD {
                // TD needs the fresh object even when the draft states no
                // other custom field: the PATCH replaces it whole.
                let existing = try current?.get().customFields ?? nil
                let stated = payload["custom_fields"] as? [String: String]
                let merged = stated.map { FilaManService.mergedCustomFields(existing: existing, new: $0) } ?? existing ?? [:]
                payload["custom_fields"] = FilaManPayloadBuilder
                    .customFieldsApplyingTransmissionDistance(draft.transmissionDistance, to: merged).jsonObject
            } else {
                payload = try await mergeCustomFieldsIfNeeded(into: payload) {
                    try current?.get().customFields ?? nil
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        do {
            let updated = try await service.updateFilament(id: id, payload: payload, baseUrl: baseUrl)
            let hexes = Self.colorHexes(from: draft)
            let colourOutcome = await applyFilamentColors(
                id: id, hexes: hexes, multiColorStyle: draft.multiColorDirection.valueOnCreate
            )
            // The PATCH response predates the colour write, so it still carries
            // the OLD swatch. Re-read whenever the colours actually landed — a
            // dropped direction (R19) still means they landed, so it must not
            // suppress this. A failed re-read costs only a stale swatch until
            // the next refresh, so it must not turn a successful write into a
            // reported failure either.
            var latest = updated
            if case .written = colourOutcome {
                latest = (try? await service.fetchFilament(id: id, baseUrl: baseUrl)) ?? updated
            }
            let vendor = vendors.first { $0.id == latest.manufacturerId }
            if let index = filaments.firstIndex(where: { $0.id == id }) {
                filaments[index] = Self.mapFilament(latest, vendor: vendor)
            }
            errorMessage = SaveOutcome.combinedNote([
                colourOutcome.message,
                Self.unclearableFilamentNote(draft),
                await registerTransmissionDistanceField(for: draft)
            ])
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteFilament(id: Int) async -> Bool {
        do {
            try await service.deleteFilament(id: id, force: false, baseUrl: baseUrl)
            filaments.removeAll { $0.id == id }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteFilamentCascading(id: Int) async -> Bool {
        do {
            try await service.deleteFilament(id: id, force: true, baseUrl: baseUrl)
            spools.removeAll { $0.filament.id == id }
            filaments.removeAll { $0.id == id }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Spools

    /// A location the user typed is resolved — or created — before the spool is
    /// written (R15). If that fails the spool is still created, without a
    /// location and saying so: losing an unsaved spool is worse than losing its
    /// shelf. `updateSpool` deliberately does the opposite.
    ///
    /// The remaining weight rides along in the create body: `SpoolCreate`
    /// carries `remaining_weight_g` (verified live 2026-08-21), so unlike
    /// `updateSpool` this needs no adjustment event and has no post-create
    /// window in which the weight could be lost (I2). The basis for converting
    /// a "used" weight comes from the draft, falling back to the chosen
    /// filament's own net weight — the same fallback
    /// `DashboardStatsService.fillFraction` uses.
    @discardableResult
    func addSpool(draft: SpoolDraft) async -> Spool? {
        guard draft.filamentId != nil else {
            errorMessage = "A spool needs a filament."
            return nil
        }
        let locationPatch: SpoolmanPatchValue<Int>
        var locationWarning: String?
        switch await resolveLocation(for: draft.location) {
        case .patch(let patch):
            locationPatch = patch
        case .failed(let message):
            locationPatch = .ignore
            locationWarning = "The spool was saved without its location: \(message)"
        }
        var remainingForCreate: Double?
        var weightWarning: String?
        switch Self.remainingWeightTarget(
            for: draft,
            netInitial: draft.initialWeight.valueOnCreate
                ?? filaments.first { $0.id == draft.filamentId }?.weight
        ) {
        case .unchanged:
            break
        case .grams(let grams):
            remainingForCreate = grams
        case .unsupported(let message):
            weightWarning = message
        }
        // With FilaMan Tags as the only target the create carries no card_uids;
        // the follow-up below writes the first tag into rfid_uid.
        let targets = TagIdentityPolicy.current(available: availableTagStores).linkTargets
        let rfidOnly = targets == [.filamanTags]
        var createDraft = draft
        if rfidOnly { createDraft.cardUIDs = nil }
        let payload = FilaManPayloadBuilder.spoolCreatePayload(
            from: createDraft, location: locationPatch, remainingWeight: remainingForCreate
        )
        do {
            let created = try await service.createSpool(payload: payload, baseUrl: baseUrl)
            // Archiving cannot ride in the create body: it is a status
            // transition, and only `POST /spools/{id}/status` is proven live.
            // Posted after the spool exists, and only when the draft actually
            // asks for it — a create carrying `archived: false` leaves FilaMan's
            // own default (`new`) alone rather than forcing `active` (F39).
            let (latest, statusNote) = await applyArchivedStatus(
                archived: draft.archived, statusKey: draft.statusKey, to: created
            )
            // Resolved from the server's own response, not the draft's
            // filamentId — the server's returned value is the authority on
            // what was actually written (matches updateSpool/setSpoolArchived).
            guard let filament = filaments.first(where: { $0.id == latest.filamentId }) else {
                errorMessage = "Spool was created, but its filament could not be found locally. Refresh to see it."
                return nil
            }
            let spool = Self.mapSpool(
                latest, filament: filament, locationsById: locationsById,
                rfidWritable: FilaManTagSwitches.tagsEnabled()
            )
            spools.append(spool)
            // The planner fills rfid_uid while FilaMan Tags is on. R-only keeps
            // the first tag only (known limitation, see the decision entry).
            var tagNote: String?
            var result = spool
            if FilaManTagSwitches.tagsEnabled(), let uids = draft.cardUIDs, !uids.isEmpty {
                let wanted = rfidOnly ? Array(uids.prefix(1)) : uids
                if await setCardUIDs(spoolId: spool.id, uids: wanted) {
                    result = spools.first { $0.id == spool.id } ?? spool
                } else {
                    tagNote = "The spool was saved without its tag link: \(errorMessage ?? "FilaMan refused it.")"
                }
            }
            errorMessage = SaveOutcome.combinedNote([
                locationWarning,
                weightWarning,
                statusNote,
                tagNote,
                Self.unwritableDateNoteOnCreate(firstUsed: draft.firstUsed, lastUsed: draft.lastUsed),
                Self.unwritableCommentNoteOnCreate(draft.comment.valueOnCreate)
            ])
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// The caveat for a measurement FilaMan recorded but could not apply.
    ///
    /// Names the fix rather than the failure: a tara is what is missing, and
    /// the spool form's own Measured mode already offers to derive one from a
    /// reading above the initial weight (`SpoolFormView.measuredWeightSuggestion`).
    nonisolated static func taraMissingNote(_ event: FilaManMeasurementEvent) -> String? {
        guard event.taraMissing else { return nil }
        return "The reading was recorded, but this spool has no empty-spool weight, "
            + "so FilaMan could not work out how much filament is left. "
            + "Set the empty-spool weight and weigh it again."
    }

    /// What a spool save could not write, because FilaMan does not accept it.
    ///
    /// Probed live 2026-08-25: `PATCH /spools/{id}` takes `stocked_in_at` and
    /// `last_used_at` with a **200** and stores neither. A create keeps
    /// `stocked_in_at` and still ignores `last_used_at`, which FilaMan derives
    /// from its own usage history.
    ///
    /// Reported rather than silently dropped — the eleventh member of this
    /// integration's "reported success for work it did not do" family, and the
    /// first found on the ordinary write path rather than a clear path. It hid
    /// so long because `updateSpool` re-reads the spool afterwards: the form
    /// redisplayed FilaMan's unchanged values and nothing looked wrong.
    ///
    /// Silent when the draft says nothing about either date, which is the
    /// common case by far — the form loads what the server has (null on every
    /// real spool) and the user edits something else. Nagging there would
    /// train people to ignore the notice, and `.ignore` is what keeps it
    /// quiet: before R21 stage 3b the same job was done by the value being
    /// empty, which could not tell an untouched box from a cleared one.
    ///
    /// **A refused CLEAR is reported exactly like a refused set.** Both are
    /// changes FilaMan will not make, and a user who deleted a date and was
    /// told nothing would believe the deletion took.
    ///
    /// `updateSpool`'s counterpart, `unwritableDateNoteOnUpdate`, was deleted
    /// 2026-08-28: Task 5 stopped rendering First Used / Last Used on FilaMan's
    /// spool form, so `updateSpool` can no longer receive anything but
    /// `.ignore` for either. This create-side half stays: `MigrationService`
    /// builds `SpoolDraft.lastUsed` straight from a local spool's history,
    /// bypassing the form (and its field gating) entirely, so a migrated
    /// spool with a Last Used date still reaches `addSpool` asking to write
    /// it — and FilaMan still silently drops it on create.
    nonisolated static func unwritableDateNoteOnCreate(
        firstUsed: SpoolmanPatchValue<String>,
        lastUsed: SpoolmanPatchValue<String>
    ) -> String? {
        guard states(lastUsed) else { return nil }
        return "Last Used — FilaMan works this out from its own usage history, so your change was not saved."
    }

    /// What a vendor or spool create could not write, because FilaMan has no
    /// `comment` field outside `custom_fields`, and this integration no
    /// longer emulates one there (2026-08-28, this task). Shared by
    /// `addVendor` and `addSpool` — `FilamentDraft`'s equivalent is folded
    /// into `unwritableFilamentFieldsNoteOnCreate` instead, since a filament
    /// create can drop up to three OTHER fields in the same save.
    ///
    /// The form path is closed on both entities (Task 5 removed `comment`
    /// from FilaMan's vendor and spool support tables), so the only live path
    /// that can still state one is `MigrationService`, which builds `comment`
    /// straight from local history, bypassing the form's field gating
    /// entirely — the same story `unwritableDateNoteOnCreate` tells for
    /// `firstUsed`/`lastUsed`.
    nonisolated static func unwritableCommentNoteOnCreate(_ comment: String?) -> String? {
        guard let comment, !comment.isEmpty else { return nil }
        return "Comment — FilaMan has no field for this, so it was not saved."
    }

    /// What a manufacturer create could not write: `comment` (see
    /// `unwritableCommentNoteOnCreate`) and `external_id`, which FilaMan has
    /// on spools only. Only `MigrationService` can state either — FilaMan's
    /// vendor form offers neither field.
    nonisolated static func unwritableVendorFieldsNoteOnCreate(comment: String?, externalId: String?) -> String? {
        SaveOutcome.combinedNote([
            unwritableCommentNoteOnCreate(comment),
            unwritableExternalIDNoteOnCreate(externalId)
        ])
    }

    /// FilaMan has an `external_id` column on spools only, so a filament's or
    /// manufacturer's is dropped by the payload builders. Said once, here, for
    /// both creates.
    nonisolated static func unwritableExternalIDNoteOnCreate(_ externalId: String?) -> String? {
        guard let externalId, !externalId.isEmpty else { return nil }
        return "External ID — FilaMan has no field for this, so it was not saved."
    }

    /// What a filament create could not write, because Task 5 stopped
    /// rendering Article Number / Comment / Extruder Temp / Bed Temp on
    /// FilaMan's filament form, and this task stopped emulating all four in
    /// `custom_fields`. The only live path that can still state one is
    /// `MigrationService.filamentDraft`, which builds them straight from a
    /// local filament's stored values, bypassing the form's field gating
    /// entirely — the same story `unwritableDateNoteOnCreate` tells for
    /// `firstUsed`/`lastUsed`.
    ///
    /// One sentence per field actually stated, so the user knows exactly what
    /// did not travel rather than guessing from a bare "some fields could not
    /// be saved."
    nonisolated static func unwritableFilamentFieldsNoteOnCreate(_ draft: FilamentDraft) -> String? {
        var lines: [String] = []
        if let articleNumber = draft.articleNumber.valueOnCreate, !articleNumber.isEmpty {
            lines.append("Article Number — FilaMan has no field for this, so it was not saved.")
        }
        if let comment = draft.comment.valueOnCreate, !comment.isEmpty {
            lines.append("Comment — FilaMan has no field for this, so it was not saved.")
        }
        if draft.extruderTemp.valueOnCreate != nil {
            lines.append("Extruder Temp — FilaMan has no field for this, so it was not saved.")
        }
        if draft.bedTemp.valueOnCreate != nil {
            lines.append("Bed Temp — FilaMan has no field for this, so it was not saved.")
        }
        if let externalIdLine = unwritableExternalIDNoteOnCreate(draft.externalId.valueOnCreate) {
            lines.append(externalIdLine)
        }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    /// The filament fields FilaMan will not let go of, named in one sentence.
    ///
    /// Three refusals, each measured live 2026-08-25 and each for a different
    /// reason:
    ///
    /// - **Manufacturer** — `manufacturer_id` is required and a null answers
    ///   with a **500**, not a 422, so there is no server message to pass on.
    /// - **Colours** — clearing them means `colors: []` on
    ///   `PUT /filaments/{id}/colors`, which is a full REPLACE and would take
    ///   the primary colour with it. Refusing costs the user a multi-colour
    ///   list; honouring it would cost them the swatch as well.
    ///
    /// `external_id` is deliberately absent: FilaMan has **no filament-side
    /// field at all** for it, so a clear there is a no-op about something the
    /// backend does not have. Reporting it would be noise the user can do
    /// nothing with (owner's call, 2026-08-25).
    nonisolated static func unclearableFilamentNote(_ draft: FilamentDraft) -> String? {
        var refusals: [String] = []
        if case .setNil = draft.vendorId {
            refusals.append("a filament on FilaMan must have a manufacturer")
        }
        let clearsPair: Bool = {
            if case .setNil = draft.multiColorHexes { return true }
            if case .setNil = draft.multiColorDirection { return true }
            return false
        }()
        // With a primary colour in the draft this is a switch to single colour,
        // which replaces the colours on purpose. Only a bare clear is refused.
        let clearsColours = clearsPair && draft.colorHex == nil
        if clearsColours {
            refusals.append("removing the extra colours would remove the main one too")
        }
        guard !refusals.isEmpty else { return nil }
        return "Some fields could not be cleared: " + refusals.joined(separator: ", ") + "."
    }

    /// Whether the draft says anything at all about a field. It deliberately
    /// does not distinguish `.set` from `.setNil`, because FilaMan refuses
    /// both and the user needs telling either way.
    private nonisolated static func states(_ patch: SpoolmanPatchValue<String>) -> Bool {
        if case .ignore = patch { return false }
        return true
    }

    /// Merge-protected the same way as `updateVendor`/`updateFilament` — a
    /// spool's `custom_fields` carries `card_uids` (SpoolLink) and, on a
    /// migrated instance, `spoolman_id`; neither is represented in
    /// `SpoolDraft`, so a naive PATCH would destroy them on the first edit
    /// made through the ordinary spool form. This is the exact risk
    /// `patchSpoolCustomFields` (16a) protects against for its own callers;
    /// `updateSpool` needs the same protection because it PATCHes the same
    /// endpoint with a `custom_fields` key of its own.
    ///
    /// Shares `addSpool`'s resolve-or-create location step but fails CLOSED on
    /// `.failed` (R15): the spool already exists and the edit was the user's
    /// only intent, so reporting success for a location that was never written
    /// would be the F24/F25 defect all over again. It is never downgraded to
    /// "leave the location alone".
    ///
    /// Two calls, because `SpoolUpdate` has no remaining-weight field: the
    /// scalar PATCH, then `applyRemainingWeight`'s adjustment event (I2).
    @discardableResult
    func updateSpool(id: Int, draft: SpoolDraft) async -> Bool {
        let locationPatch: SpoolmanPatchValue<Int>
        switch await resolveLocation(for: draft.location) {
        case .patch(let patch):
            locationPatch = patch
        case .failed(let message):
            errorMessage = "The spool was not updated. \(message)"
            return false
        }
        var payload = FilaManPayloadBuilder.spoolPayload(from: draft, location: locationPatch)

        // ONE pre-PATCH read, shared by the only two things that need it: the
        // `custom_fields` merge below, and R20's "what was the remaining
        // weight before this PATCH?". Reading the same record twice in a row
        // would be waste, and `applyRemainingWeight` already reads it a third
        // time when it posts an event.
        let movesBasis = FilaManPayloadBuilder.movesWeightBasis(payload)
        var prePatch: Result<FilaManSpool, any Error>?
        if payload["custom_fields"] != nil || movesBasis {
            do {
                prePatch = .success(try await service.fetchSpool(id: id, baseUrl: baseUrl))
            } catch {
                prePatch = .failure(error)
            }
        }
        do {
            payload = try await mergeCustomFieldsIfNeeded(into: payload) {
                try prePatch?.get().customFields ?? nil
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        // A basis change that could not be measured beforehand is a caveat,
        // not a refusal: the merge above already failed closed on the same
        // read, so reaching here with a `.failure` means the PATCH itself is
        // still worth making.
        var before: FilaManPrePatchRemainingWeight = .cannotMove
        if movesBasis {
            switch prePatch {
            case .success(let spool):
                before = spool.remainingWeightG.map { .reported($0) } ?? .unreported
            case .failure(let error):
                before = .unreadable(
                    "The spool's remaining weight could not be checked before saving "
                    + "(\(error.localizedDescription)), so a change to the empty-spool weight "
                    + "may have shifted it."
                )
            case nil:
                break  // unreachable: `movesBasis` is one of the two reasons the read happens
            }
        }

        do {
            let updated = try await service.updateSpool(id: id, payload: payload, baseUrl: baseUrl)
            let (weighed, weightNote) = await applyRemainingWeight(
                id: id, draft: draft, before: before, afterPatch: updated
            )
            // AFTER the weight, not before: posting an adjustment event flips
            // `status_id` 1 "new" → 2 "opened", so archiving first would be
            // silently undone by the weight write in the same save (F39).
            let (latest, statusNote) = await applyArchivedStatus(
                archived: draft.archived, statusKey: draft.statusKey, to: weighed
            )
            guard let filament = filaments.first(where: { $0.id == latest.filamentId }) else {
                errorMessage = "Spool was updated, but its filament could not be found locally. Refresh to see it."
                return false
            }
            if let index = spools.firstIndex(where: { $0.id == id }) {
                spools[index] = Self.mapSpool(
                    latest, filament: filament, locationsById: locationsById,
                    rfidWritable: FilaManTagSwitches.tagsEnabled()
                )
            }
            // The PATCH landed, so a weight or a status that did not is a caveat
            // rather than a failure — reporting a flat `false` would suggest the
            // whole edit was lost, which is its own kind of lie (same call as
            // `updateFilament` makes for a failed colour write).
            errorMessage = SaveOutcome.combinedNote([
                weightNote,
                statusNote
            ])
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Writes the draft's remaining weight onto a spool that has just been
    /// PATCHed, returning the spool as it now stands plus anything that could
    /// not be done (plan defect I2).
    ///
    /// `SpoolUpdate` has no remaining-weight field, so this is an
    /// event-sourced `POST /spools/{id}/adjustments` — the only mechanism that
    /// can write it (R17). This save path is the ONLY production caller of that
    /// mechanism; there is no separate weight-only entry point.
    ///
    /// ## Ordering rule — not a precaution, a requirement
    ///
    /// The adjustment is a DELTA, so it needs the spool's remaining weight as
    /// it stands at the moment the event is posted. That value is
    /// `afterPatch.remainingWeightG` — the scalar PATCH's **own response**.
    /// Never the cached `spools` copy, and never a GET taken before the PATCH.
    ///
    /// This is load-bearing because of F32: a PATCH that CHANGES
    /// `empty_spool_weight_g` makes FilaMan re-base the remaining weight by
    /// exactly the basis delta, opposite in sign, to hold the gross figure
    /// constant. A delta computed against any pre-PATCH figure therefore lands
    /// the spool short or long by that same amount — silently, with a 200 on
    /// every call.
    ///
    /// Nothing can pin this in a test: there is no network seam here, so the
    /// ordering has no guard but this comment. In particular, folding the
    /// delta onto the cached spool to "save a round trip" — an obvious-looking
    /// optimisation, since the cached copy also has a remaining weight — would
    /// break every weight edit that also touches the empty-spool weight, and
    /// break it invisibly.
    ///
    /// The spool is re-read ONCE, at the end, and only when an event was
    /// actually posted.
    private func applyRemainingWeight(
        id: Int, draft: SpoolDraft, before: FilaManPrePatchRemainingWeight, afterPatch: FilaManSpool
    ) async -> (FilaManSpool, String?) {
        // A scale reading is written as a measurement, not a correction, and
        // that path is simpler in one load-bearing way: FilaMan SETS the
        // remaining weight from the reading itself (`measured − tara`) rather
        // than nudging it, so it needs no current value, no delta, and no R20
        // compensation — whatever a basis change in the same PATCH did to the
        // remaining weight, this overwrites (F32). `before` is deliberately
        // unused here.
        if case .measurement(let grams) = Self.weightWriteKind(for: draft) {
            guard let event = await service.recordMeasurement(
                spoolId: id, measuredWeight: grams, baseUrl: baseUrl
            ) else {
                return (afterPatch, "Measured Weight — not recorded: "
                    + (service.errorMessage ?? "the measurement was refused."))
            }
            // A measurement flips `status_id` the same way an adjustment does,
            // so the spool is re-read rather than patched locally.
            let latest = (try? await service.fetchSpool(id: id, baseUrl: baseUrl)) ?? afterPatch
            // A 200 here is NOT proof the reading was used. With no tara on
            // either the spool or its filament there is nothing to subtract,
            // so FilaMan records the event and leaves the remaining weight
            // exactly where it was. Nothing false is displayed — the re-read
            // above sees the unchanged value — but without this the user is
            // never told their reading did nothing.
            return (latest, Self.taraMissingNote(event))
        }

        let netInitial = Self.netInitialWeight(
            gross: afterPatch.initialTotalWeightG, emptySpool: afterPatch.emptySpoolWeightG
        )
        switch Self.remainingWeightGoal(draft: draft, netInitial: netInitial, before: before) {
        case .unchanged:
            return (afterPatch, nil)
        case .unsupported(let message):
            return (afterPatch, message)
        case .grams(let target):
            switch await postWeightAdjustment(
                spoolId: id, target: target, current: afterPatch.remainingWeightG
            ) {
            case .unchanged:
                return (afterPatch, nil)
            case .failed(let message):
                return (afterPatch, message)
            case .adjusted:
                // The adjustment also flips status_id (1 "new" → 2 "opened"),
                // so the fresh spool is remapped rather than the local copy
                // patched. A failed re-read costs only a stale weight until
                // the next refresh, so it must not turn a write that landed
                // into a reported failure.
                return ((try? await service.fetchSpool(id: id, baseUrl: baseUrl)) ?? afterPatch, nil)
            }
        }
    }

    /// Hits `DELETE /api/v1/spools/{id}/permanent`, not the plain
    /// `/spools/{id}` route — the plain route soft-deletes (sets
    /// `status_id = 6`, identical to archiving) and still returns 204 while
    /// the spool persists; a later GET would still return 200. `/permanent`
    /// actually removes the row. Verified live 2026-08-19/20.
    @discardableResult
    func deleteSpool(id: Int) async -> Bool {
        do {
            try await service.deleteSpoolPermanent(id: id, baseUrl: baseUrl)
            spools.removeAll { $0.id == id }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Archiving is a status transition (`POST /spools/{id}/status`), not a
    /// field PATCH. Its response is an event-log entry, not the updated
    /// spool (`FilaManService.setSpoolStatus`'s doc comment), so the fresh
    /// spool is re-read with a follow-up GET before updating local state.
    @discardableResult
    func setSpoolArchived(id: Int, archived: Bool) async -> Bool {
        let payload = FilaManPayloadBuilder.statusPayload(archived: archived)
        do {
            try await service.setSpoolStatus(id: id, payload: payload, baseUrl: baseUrl)
            let updated = try await service.fetchSpool(id: id, baseUrl: baseUrl)
            guard let filament = filaments.first(where: { $0.id == updated.filamentId }) else {
                errorMessage = "Status changed, but its filament could not be found locally. Refresh to see it."
                return false
            }
            if let index = spools.firstIndex(where: { $0.id == id }) {
                spools[index] = Self.mapSpool(
                    updated, filament: filament, locationsById: locationsById,
                    rfidWritable: FilaManTagSwitches.tagsEnabled()
                )
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// The Status picker's labels. A failure here is not reported to the
    /// user — an empty list just leaves the picker hidden (`SpoolFormView`),
    /// which is a correct-if-unlabeled state, not a save gone wrong.
    func fetchSpoolStatusOptions() async -> [FilaManSpoolStatus.Option] {
        do {
            return try await service.fetchSpoolStatuses(baseUrl: baseUrl)
        } catch {
            logger.error("fetchSpoolStatuses failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// FilaMan is the one backend that keeps a readable weighing history.
    ///
    /// Events whose timestamp will not parse are DROPPED rather than dated
    /// `now`: a measurement filed under today because its stamp was unreadable
    /// would sort to the top of the list and read as the most recent weighing
    /// of that spool, which is the one thing this list must never get wrong.
    func fetchMeasurementHistory(spoolID: Int) async -> [MeasurementRecord] {
        let events = await service.fetchMeasurementEvents(spoolId: spoolID, baseUrl: baseUrl)
        return events.compactMap { event in
            guard let gross = event.measuredWeightG,
                  let date = Self.parseDate(event.eventAt) else { return nil }
            return MeasurementRecord(
                id: "filaman-\(event.id)",
                spoolID: event.spoolId,
                grossWeight: gross,
                // The event states the reading, not what FilaMan made of it.
                // The net weight it implies depends on the tara AT THE TIME,
                // which the event does not carry — and the current tara is not
                // it. Better no number than a wrong one.
                netWeight: nil,
                recordedAt: date,
                origin: .backend,
                note: event.note
            )
        }
    }

    /// Whether a save must post a status transition, and which one — `nil`
    /// meaning "leave the status alone".
    ///
    /// FilaMan's status is ONE field holding six values (`new`, `opened`,
    /// `drying`, `active`, `empty`, `archived`), and "not archived" is not one
    /// of them. So `archived: false` cannot simply be written: the spool form's
    /// Archived toggle is a plain `Bool`, so EVERY ordinary save carries it, and
    /// posting `active` each time would flatten whatever the spool's real status
    /// was — including the `opened` a weight adjustment had just set moments
    /// earlier. The decision is therefore a COMPARISON against the status the
    /// spool actually has, and it fires only when the two disagree.
    ///
    /// That rule also gives creates the right behaviour for free: FilaMan
    /// defaults a new spool to `new` (1), and a create carrying `archived: false`
    /// leaves it there instead of overriding FilaMan's own default.
    ///
    /// Pure, because this is the whole of the decision — `applyArchivedStatus`
    /// only performs it, and there is no network seam that could test it there.
    nonisolated static func archivedStatusTransition(wanted: Bool?, currentStatusId: Int) -> Bool? {
        guard let wanted, (currentStatusId == FilaManSpoolStatus.archived) != wanted else { return nil }
        return wanted
    }

    /// Whether a save must post a status transition, and which KEY — `nil`
    /// meaning "leave the status alone".
    ///
    /// `statusKey` wins when the draft sets it (`.set`): the picker is a full
    /// six-value choice, and `SpoolFormView` only ever states it when the user
    /// actually changed the selection from what was loaded (R21, `textPatch`)
    /// — so, unlike `archived`, a stated key needs no comparison against the
    /// spool's current status to know it is a real change.
    ///
    /// Falls back to `archivedStatusTransition` only when the draft leaves the
    /// picker untouched — every backend without a picker's form, and a picker
    /// left alone on FilaMan's.
    nonisolated static func statusKeyTransition(
        statusKey: SpoolmanPatchValue<String>, archived: Bool?, currentStatusId: Int
    ) -> String? {
        if case .set(let key) = statusKey {
            return key
        }
        guard let wantsArchived = archivedStatusTransition(
            wanted: archived, currentStatusId: currentStatusId
        ) else { return nil }
        return FilaManSpoolStatus.key(archived: wantsArchived)
    }

    /// Performs `statusKeyTransition`'s verdict for one spool, returning the
    /// spool as it now stands plus anything that could not be done.
    ///
    /// `FilaManPayloadBuilder` deliberately does not read `draft.archived` or
    /// `draft.statusKey`: `SpoolUpdate` and `SpoolCreate` both carry a
    /// `status_id`, but only `POST /spools/{id}/status` is verified live, and
    /// a PATCH key FilaMan silently ignores is exactly how every
    /// remaining-weight edit was lost while the form reported success (I2).
    /// Reading it in the builder would have looked correct and written
    /// nothing. Until 2026-08-23 the builder simply dropped the field instead,
    /// which is the same lie one step earlier — instance ten of this epic's
    /// defect family, and reachable from `MigrationService`, which silently
    /// un-archived every archived local spool it migrated.
    ///
    /// A failure here is a CAVEAT, worded field-first: on update the PATCH has
    /// already landed, and on create the spool exists — reporting a flat
    /// failure would suggest the whole save was lost.
    private func applyArchivedStatus(
        archived: Bool?, statusKey: SpoolmanPatchValue<String>, to spool: FilaManSpool
    ) async -> (FilaManSpool, String?) {
        guard let key = Self.statusKeyTransition(
            statusKey: statusKey, archived: archived, currentStatusId: spool.statusId
        ) else { return (spool, nil) }
        do {
            try await service.setSpoolStatus(
                id: spool.id,
                payload: FilaManPayloadBuilder.statusPayload(key: key),
                baseUrl: baseUrl
            )
            // The status response is an event-log entry, not the updated spool
            // (see `setSpoolArchived`), so the fresh record is re-read. A failed
            // re-read costs only a stale flag until the next refresh, so it must
            // not turn a write that landed into a reported failure.
            return ((try? await service.fetchSpool(id: spool.id, baseUrl: baseUrl)) ?? spool, nil)
        } catch {
            return (spool, Self.statusNotChangedNote(error))
        }
    }

    /// The wire caveat for a status transition that could not be posted —
    /// worded field-first ("Status — not changed", not "Archived — the spool
    /// could not be…"): a value chosen from the picker can be any of six
    /// states, not just archived/unarchived, so this names the FIELD rather
    /// than guessing a verb for the direction. Pure so the exact wording is
    /// testable without a live FilaMan to fail against.
    nonisolated static func statusNotChangedNote(_ error: any Error) -> String {
        "Status — not changed: \(error.localizedDescription)"
    }

    // MARK: - UID mapping

    /// `card_uids` lives in free-form `custom_fields`; FilaMan has no native
    /// tag API.
    var availableTagStores: Set<TagStore> { [.cardUIDs, .filamanTags] }

    /// Pure in-memory search over the already-fetched `spools`, delegating to
    /// `findSpool(in:byCardUID:)` so the matching itself is unit-testable
    /// without an instance. Mirrors `SpoolmanService.findSpool(byCardUID:)` —
    /// needs no transport of its own, since `Spool.mappedCardUIDs` already
    /// unions `extra["card_uids"]` and (FilaMan-only) `rfidUID`.
    func findSpool(byCardUID uid: String) -> Spool? {
        Self.findSpool(in: spools, byCardUID: uid)
    }

    nonisolated static func findSpool(in spools: [Spool], byCardUID uid: String) -> Spool? {
        SpoolMappingService.spool(in: spools, claiming: uid)
    }

    /// The `custom_fields` entry a `card_uids` write puts on the wire, in ONE
    /// place so the two writers below cannot drift apart on the key or the
    /// encoding.
    ///
    /// The value is `CardUIDsCodec.encodeBare` — comma-separated — and NOT the
    /// JSON-wrapped form Spoolman's `extra` carries. FilaMan's Spoolman-compat
    /// layer JSON-encodes each custom field on read, so a bare value written
    /// natively reads back through `/spoolman/api/v1/` byte-identical to what
    /// Spoolman itself serves (Task 18). Writing `CardUIDsCodec.encode` here
    /// would double-wrap it: invisible to SpoolKid, whose `parse` tolerates
    /// both, and broken for every other SpoolLink client.
    nonisolated static func cardUIDsField(_ uids: [String]) -> [String: String] {
        ["card_uids": CardUIDsCodec.encodeBare(uids)]
    }

    /// Writes the spool's complete `card_uids` set. `uids` is the whole list;
    /// callers compute the append/remove themselves, exactly as on Spoolman.
    ///
    /// Goes through `FilaManService.patchSpoolCustomFields`, which is a
    /// GET → merge → PATCH. That indirection is the entire safety of this
    /// method: `PATCH /api/v1/spools/{id}` REPLACES the whole `custom_fields`
    /// object server-side (verified live 2026-08-19) and every spool on a
    /// migrated instance carries `custom_fields: {"spoolman_id": N}`, so
    /// handing that PATCH a bare `["card_uids": …]` would destroy the linkage
    /// on the first tag mapped. Passing only the key that changes is correct
    /// ONLY because the service merges.
    ///
    /// The service reports failures on its OWN `errorMessage`; this type's is a
    /// stored property (see `testConnection`), so it is copied across
    /// explicitly. Without that the reason never reaches
    /// `SaveOutcome.classify`, and the user is told a mapping "could not be
    /// saved" with no reason — or, worse, a stale message left by an earlier
    /// call is read as a caveat on a mapping that actually landed.
    @discardableResult
    func setCardUIDs(spoolId: Int, uids: [String]) async -> Bool {
        guard let cached = await cachedSpool(spoolId) else { return false }
        let (spool, uids) = Self.tagWriteInputs(
            spool: cached, uids: uids, writable: FilaManTagSwitches.tagsEnabled()
        )
        let targets = TagIdentityPolicy.current(available: availableTagStores).linkTargets
        let plan = FilaManTagPlan.make(spool: spool, desired: uids, targets: targets) { uid in
            spools.first {
                $0.id != spoolId
                    && SpoolMappingService.normalizeUID($0.rfidUID ?? "") == uid
            }?.id
        }
        // A new tag the plan stores nowhere (the one slot is taken, or another
        // spool holds the tag) would come back "saved" and be lost. Refuse the
        // whole write instead.
        let unplaced = FilaManTagPlan.unplaced(spool: spool, desired: uids, result: plan)
        if let lost = unplaced.first {
            if plan.heldElsewhere.contains(lost),
               let holder = spools.first(where: {
                   $0.id != spoolId && SpoolMappingService.normalizeUID($0.rfidUID ?? "") == lost
               }) {
                errorMessage = TagStoreText.heldElsewhereNote(holder: holder.listTitle)
            } else {
                errorMessage = TagStoreText.filamanOneTagNote(
                    existing: spool.mappedCardUIDs.first.map(SpoolMappingService.normalizeUID) ?? lost
                )
            }
            return false
        }
        if plan.isEmpty {
            errorMessage = nil
            return true
        }
        guard await service.patchSpoolTags(
            spoolId: spoolId, cardUIDs: plan.cardUIDs, rfid: plan.rfid, baseUrl: baseUrl
        ) else {
            errorMessage = service.errorMessage
            return false
        }
        await refreshCachedSpool(id: spoolId)
        errorMessage = nil
        return true
    }

    /// The spool and tag list a write plans from. Writability comes from the
    /// switch now, not from the cached copy: a refetch that failed after the
    /// switch was flipped must not leave the old answer. While `rfid_uid` is
    /// read-only its tag is dropped from `uids` unless `card_uids` already
    /// carries it, so it is never copied into `card_uids`.
    nonisolated static func tagWriteInputs(spool: Spool, uids: [String], writable: Bool) -> (Spool, [String]) {
        var spool = spool
        spool.rfidUIDWritable = writable
        guard !writable else { return (spool, uids) }
        let rfid = SpoolMappingService.normalizeUID(spool.rfidUID ?? "")
        guard !rfid.isEmpty, !spool.cardUIDs.contains(rfid) else { return (spool, uids) }
        return (spool, uids.filter { SpoolMappingService.normalizeUID($0) != rfid })
    }

    /// The cached spool, re-read once when it is missing (as Spoolman's does).
    private func cachedSpool(_ id: Int) async -> Spool? {
        if let spool = spools.first(where: { $0.id == id }) { return spool }
        if let fetched = try? await service.fetchSpool(id: id, baseUrl: baseUrl),
           let filament = filaments.first(where: { $0.id == fetched.filamentId }) {
            return Self.mapSpool(
                fetched, filament: filament, locationsById: locationsById,
                rfidWritable: FilaManTagSwitches.tagsEnabled()
            )
        }
        errorMessage = "Spool #\(id) could not be found in FilaMan."
        return nil
    }

    /// `POST /api/v1/system-extra-fields` with `target_type: "spool"`, guarded
    /// by a read of the registry. FilaMan needs no registration for a mapping
    /// to be *written* — `custom_fields` is free-form — so this is purely
    /// about the field existing system-wide: visible on every spool in
    /// FilaMan's own UI, and declared to any Spoolman-compatible client that
    /// reads `GET /spoolman/api/v1/field/spool`.
    @discardableResult
    func ensureCardUIDsField() async -> Bool {
        do {
            try await service.ensureCardUIDsField(baseUrl: baseUrl)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Two halves, because FilaMan has no single call for it: the registry row
    /// goes, and then `card_uids` is stripped from every spool that carries
    /// one. The spool list is taken from the cache rather than re-fetched — a
    /// spool the app has never seen cannot have been mapped by it — and only
    /// spools that actually hold a mapping are touched.
    @discardableResult
    func deleteCardUIDsField() async -> Bool {
        let mapped = spools.filter { !$0.mappedCardUIDs.isEmpty }.map(\.id)
        guard await service.deleteCardUIDsField(baseUrl: baseUrl, spoolIds: mapped) else {
            errorMessage = service.errorMessage
            return false
        }
        await fetchSpools()
        errorMessage = nil
        return true
    }

    /// Re-reads one spool and replaces the cached copy, after a write whose
    /// response this type does not hold onto.
    ///
    /// Not housekeeping: `findSpool(byCardUID:)` searches this very array, so
    /// without it a tag mapped and then immediately rescanned comes back
    /// UNKNOWN until the next full fetch. `SpoolmanService.setCardUIDs` and
    /// `LocalRepository.setCardUIDs` both update their caches for the same
    /// reason; skipping it here would make the same mapping behave differently
    /// on FilaMan.
    ///
    /// A failure costs a stale local copy until the next refresh and nothing at
    /// all on the server, so it must not turn a write that landed into a
    /// reported failure — the same call `updateFilament` makes about its own
    /// post-write re-read. The spool is looked up again AFTER the await: the
    /// array can have been re-fetched while the GET was in flight.
    private func refreshCachedSpool(id: Int) async {
        guard spools.contains(where: { $0.id == id }),
              let updated = try? await service.fetchSpool(id: id, baseUrl: baseUrl),
              let filament = filaments.first(where: { $0.id == updated.filamentId }),
              let index = spools.firstIndex(where: { $0.id == id })
        else { return }
        spools[index] = Self.mapSpool(
            updated, filament: filament, locationsById: locationsById,
            rfidWritable: FilaManTagSwitches.tagsEnabled()
        )
    }

    // MARK: - Locations
    //
    // Unlike Spoolman/Local, where a location is a free string derived from
    // spools, FilaMan locations are first-class entities with their own id and
    // a full CRUD surface, verified live 2026-08-20 via its
    // OpenAPI schema. That is why the spool write paths have to CREATE a
    // location the user typed (`resolveLocation`) instead of relying on it
    // coming into existence as a side effect of the spool referencing it.
    // Rename/delete below call that entity API directly
    // rather than rewriting every referencing spool the way `LocalRepository`
    // and `SpoolmanService` do. FilaMan's own server-side behavior when spools
    // still reference a deleted location (cascade-clear vs. an FK refusal) was
    // not verified live — the delete route was not exercised, per this task's
    // read-only constraint — so `deleteLocation` reports exactly what the
    // server reports rather than assuming either outcome.

    /// Creates a real `locations` row. Re-reads first for the same reason
    /// `resolveLocation` does: FilaMan does not dedupe location names, so a
    /// blind POST forks one shelf into two entities.
    @discardableResult
    func addLocation(name: String) async -> LocationCreateOutcome {
        let trimmed = LocationName.trimmed(name)
        guard !trimmed.isEmpty else { return .failed("A location needs a name.") }

        do {
            try await loadLocations()
        } catch {
            errorMessage = error.localizedDescription
            return .failed("Locations could not be read: \(error.localizedDescription)")
        }

        if let settled = LocationCreateOutcome.precheck(name: trimmed, existing: locations) {
            if settled.isSuccess { errorMessage = nil }
            return settled
        }

        do {
            let created = try await service.createLocation(
                payload: FilaManPayloadBuilder.locationPayload(name: trimmed), baseUrl: baseUrl
            )
            register(created)
            errorMessage = nil
            return .created
        } catch {
            errorMessage = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func renameLocation(currentName: String, newName: String) async -> Bool {
        do {
            try await loadLocations()
            guard let id = locationIdByName[Self.normalizedLocationKey(currentName)] else {
                errorMessage = "No FilaMan location named \"\(currentName)\" was found."
                return false
            }
            _ = try await service.updateLocation(
                id: id, payload: FilaManPayloadBuilder.locationPayload(name: newName), baseUrl: baseUrl
            )
            try await loadLocations()
            try await loadSpools()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Writes the tag UID into `locations.identifier` — the "Identifier" column
    /// in FilaMan's own Locations list, and what its "Write RFID Tag" action
    /// fills in. Mirrors SpoolKid's location tag so FilaMan and its other
    /// clients see the same binding.
    ///
    /// A malformed UID is refused rather than stored: FilaMan puts no
    /// constraint on the column, so a value that is not hex would be accepted
    /// and would then read back as a binding matching nothing.
    @discardableResult
    func setLocationTagUID(locationName: String, uid: String?) async -> LocationTagUIDOutcome {
        var identifier: String?
        if let uid {
            guard let formatted = FilaManPayloadBuilder.locationIdentifier(fromUID: uid) else {
                return .failed("That tag's ID is not readable hex, so FilaMan was not updated.")
            }
            identifier = formatted
        }

        do {
            let existing = try await service.fetchLocations(baseUrl: baseUrl)
            try await loadLocations()
            guard let id = locationIdByName[Self.normalizedLocationKey(locationName)] else {
                return .failed("No FilaMan location named \"\(locationName)\" was found, so the tag was not recorded there.")
            }

            // FilaMan treats a tag UID as globally unique across spools AND
            // locations: its own write path clears the UID from whatever held
            // it before assigning it. `locations.identifier` carries no unique
            // constraint to enforce that, and its scan-to-file endpoint reads
            // the match with `scalar_one_or_none()` — so a duplicate SpoolKid
            // left behind would not fail here, it would fail later, inside
            // FilaMan, on the scale. Release it first.
            for other in existing where other.id != id
                && other.identifier != nil
                && other.identifier == identifier {
                _ = try await service.updateLocation(
                    id: other.id,
                    payload: FilaManPayloadBuilder.locationIdentifierPayload(nil),
                    baseUrl: baseUrl
                )
            }

            _ = try await service.updateLocation(
                id: id,
                payload: FilaManPayloadBuilder.locationIdentifierPayload(identifier),
                baseUrl: baseUrl
            )
            try await loadLocations()
            errorMessage = nil
            return .written
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func deleteLocation(_ name: String) async -> Bool {
        do {
            try await loadLocations()
            guard let id = locationIdByName[Self.normalizedLocationKey(name)] else {
                errorMessage = "No FilaMan location named \"\(name)\" was found."
                return false
            }
            try await service.deleteLocation(id: id, baseUrl: baseUrl)
            try await loadLocations()
            try await loadSpools()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private nonisolated static func normalizedLocationKey(_ name: String) -> String {
        LocationName.normalizedKey(name)
    }

    /// Pure classification of a `SpoolDraft`'s free-text location patch against
    /// the locations FilaMan already knows about. `.ignore` stays `.ignore`
    /// (omit `location_id` — leave it untouched) and `.setNil` becomes
    /// `.clear` (send an explicit `null` — FilaMan's `location_id` DOES accept
    /// one, verified live 2026-08-20 against the owner's instance:
    /// `PATCH {"location_id": null}` returns 200 and a re-GET confirms the
    /// clear actually took).
    ///
    /// An unrecognized name yields `.create`, NOT `.ignore` (F25). The shared,
    /// backend-agnostic `SpoolFormView.locationSection` is a free-text field
    /// whose comment reads "Typing a new name here is how locations are
    /// created (they are spool-derived)" — true for the local and Spoolman
    /// backends, and made true here by creating the entity rather than by
    /// quietly dropping the name. The previous version of this function
    /// downgraded an unknown name to `.ignore`, which discarded the difference
    /// between "the user asked for a shelf I don't have" and "the user didn't
    /// touch the location" before any caller could see it — so `updateSpool`
    /// could not have failed closed even if it wanted to.
    ///
    /// A whitespace-only name is a genuine `.ignore`: nothing was named, so
    /// there is nothing that could have failed. (`SpoolFormView.locationPatch`
    /// already trims and never produces one; this is belt-and-braces.)
    nonisolated static func plannedLocationResolution(
        for patch: SpoolmanPatchValue<String>,
        locationIdByName: [String: Int]
    ) -> FilaManLocationPlan {
        switch patch {
        case .ignore:
            return .ignore
        case .setNil:
            return .clear
        case .set(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .ignore }
            if let id = locationIdByName[normalizedLocationKey(trimmed)] { return .existing(id) }
            return .create(trimmed)
        }
    }

    /// Performs `plannedLocationResolution` — the ONE resolve-or-create path
    /// both `addSpool` and `updateSpool` go through (R15). The two differ only
    /// in what they do with `.failed`: `addSpool` saves the spool without a
    /// shelf (losing an unsaved spool is worse than losing its shelf) while
    /// `updateSpool` fails closed (the spool already exists and the edit was
    /// the user's only intent). Neither can silently no-op, because `.failed`
    /// is not `.patch(.ignore)`.
    private func resolveLocation(for patch: SpoolmanPatchValue<String>) async -> FilaManLocationResolution {
        switch Self.plannedLocationResolution(for: patch, locationIdByName: locationIdByName) {
        case .ignore:
            return .patch(.ignore)
        case .clear:
            return .patch(.setNil)
        case .existing(let id):
            return .patch(.set(id))
        case .create(let name):
            // Re-read before creating: the in-memory map is only as fresh as
            // the last fetch, and FilaMan does not dedupe location names — a
            // blind POST would fork one shelf into two entities.
            do {
                try await loadLocations()
            } catch {
                return .failed("Location \"\(name)\" could not be looked up: \(error.localizedDescription)")
            }
            if let id = locationIdByName[Self.normalizedLocationKey(name)] { return .patch(.set(id)) }
            do {
                let created = try await service.createLocation(
                    payload: FilaManPayloadBuilder.locationPayload(name: name), baseUrl: baseUrl
                )
                register(created)
                return .patch(.set(created.id))
            } catch {
                return .failed("Location \"\(name)\" could not be created: \(error.localizedDescription)")
            }
        }
    }

    /// Folds a newly created location into the caches `mapSpool` resolves
    /// display names from, so the spool about to be written renders with its
    /// shelf instead of a blank until the next full refresh.
    private func register(_ location: FilaManLocation) {
        locationsById[location.id] = location.name
        locationIdByName[Self.normalizedLocationKey(location.name)] = location.id
        if !locations.contains(location.name) {
            locations.append(location.name)
            locations.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }

    // MARK: - Colours
    //
    // FilaMan colours are entities under `/api/v1/colors` referenced by integer
    // FK, so writing a filament's colour is the same resolve-or-create shape as
    // a location (F27). Both `addFilament` and `updateFilament` go through the
    // one helper below (R18) — scoping colour writes to creates only would have
    // left `updateFilament` PATCHing, getting a 200, and reporting success
    // while the colour the user just picked was never written.

    /// The hexes a colour write should actually cover: normalized, with the
    /// blanks gone.
    ///
    /// `PUT /api/v1/filaments/{id}/colors` is a full REPLACE, and an empty
    /// `colors: []` wipes every colour the filament has (verified live
    /// 2026-08-21). So an EMPTY result here means SKIP THE REQUEST ENTIRELY —
    /// it must never be turned into "send an empty list", which would silently
    /// destroy colours for any draft that simply doesn't carry one. That
    /// distinction is the entire reason this helper exists rather than an
    /// inline `isEmpty`.
    ///
    /// It returns the list rather than a `Bool` (review finding M3) so the
    /// same value decides *whether* to write and *what* to write. The previous
    /// `needsColourWrite` answered with `contains` while the caller went on to
    /// iterate every element, so a list with one good hex and one blank passed
    /// the check and then tried to create a `{"name":"#","hex_code":"#"}` row.
    /// Both call sites happen to pre-filter today; this makes the junk colour
    /// impossible rather than merely unreached.
    ///
    /// A blank or `#`-only string is not a colour.
    nonisolated static func writableHexes(_ hexes: [String]) -> [String] {
        hexes
            .map { FilaManPayloadBuilder.normalizedHex($0) }
            .filter { !$0.isEmpty }
    }

    /// The ordered colour hexes a filament draft asks for, normalized and with
    /// blanks dropped. `multiColorHexes` is the COMPLETE list when present —
    /// `mapFilament` builds it that way, position 1 included — so it wins over
    /// the single `colorHex` rather than being appended to it.
    nonisolated static func colorHexes(from draft: FilamentDraft) -> [String] {
        // `.setNil` is NOT an empty list here: an empty `colors` array is a
        // full REPLACE that wipes the primary colour too, so a colour clear is
        // refused and reported (`unclearableFilamentNote`). `valueOnCreate`
        // collapses `.ignore` and `.setNil` into "say nothing", which is what
        // `writableHexes` already means by an empty result.
        if let multi = draft.multiColorHexes.valueOnCreate {
            let parts = multi
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { FilaManPayloadBuilder.normalizedHex(String($0)) }
                .filter { !$0.isEmpty }
            if !parts.isEmpty { return parts }
        }
        let single = FilaManPayloadBuilder.normalizedHex(draft.colorHex ?? "")
        return single.isEmpty ? [] : [single]
    }

    /// Hex → `color_id` lookup over every row `GET /colors` returned. Keyed by
    /// `FilaManPayloadBuilder.normalizedHex`, so matching is case- and
    /// `#`-insensitive: FilaMan stores `hex_code` verbatim and rows differ in
    /// case, while `mapFilament` strips the `#` on read. Rows with no usable
    /// hex are skipped. When two rows mean the same colour the LOWEST id wins,
    /// so repeated writes keep landing on the same row instead of alternating.
    nonisolated static func colorIdByHex(_ colors: [FilaManColor]) -> [String: Int] {
        var map: [String: Int] = [:]
        for color in colors {
            guard let hexCode = color.hexCode else { continue }
            let key = FilaManPayloadBuilder.normalizedHex(hexCode)
            guard !key.isEmpty else { continue }
            if let existing = map[key], existing <= color.id { continue }
            map[key] = color.id
        }
        return map
    }

    /// Pure per-hex decision. A miss is `.create`, never "nothing to do":
    /// `GET /colors` has no hex filter so the match happens locally, and an
    /// exact-pair duplicate `POST /colors` returns 500 — which makes
    /// resolve-before-create mandatory rather than an optimisation.
    nonisolated static func plannedColorSlot(hex: String, colorIdByHex: [String: Int]) -> FilaManColorSlotPlan {
        let key = FilaManPayloadBuilder.normalizedHex(hex)
        if let id = colorIdByHex[key] { return .existing(id) }
        return .create(key)
    }

    /// Resolves each hex to a `color_id`, creating rows FilaMan doesn't have.
    /// Fetches the colour list fresh — a row created by another client (or by
    /// the previous filament saved in this same session) must be reused, not
    /// duplicated.
    private func resolveColorIds(hexes: [String]) async -> FilaManColorResolution {
        // One list decides both "is there anything to write" and "what gets
        // written", so a blank entry cannot survive the first question to be
        // turned into a colour by the second (M3).
        let usable = Self.writableHexes(hexes)
        guard !usable.isEmpty else { return .skip }
        var idByHex: [String: Int]
        do {
            idByHex = Self.colorIdByHex(try await service.fetchColors(baseUrl: baseUrl))
        } catch {
            return .failed(error.localizedDescription)
        }
        var ids: [Int] = []
        for hex in usable {
            // Consulted per hex rather than planned up front so a draft naming
            // the same colour in two slots reuses the row it just created
            // instead of tripping the (name, hex_code) uniqueness 500.
            switch Self.plannedColorSlot(hex: hex, colorIdByHex: idByHex) {
            case .existing(let id):
                ids.append(id)
            case .create(let key):
                do {
                    let created = try await service.createColor(
                        payload: FilaManPayloadBuilder.colorPayload(hex: key), baseUrl: baseUrl
                    )
                    idByHex[key] = created.id
                    ids.append(created.id)
                } catch {
                    return .failed("Colour #\(key.uppercased()) could not be created: \(error.localizedDescription)")
                }
            }
        }
        return .resolved(ids)
    }

    /// Names a multi-colour direction FilaMan cannot store, or `nil` when
    /// there is nothing to report (plan defect C1/R19).
    ///
    /// `FilaManPayloadBuilder.supportedMultiColorStyle` omits an unrecognised
    /// direction so the write still succeeds — but omitting it silently is the
    /// exact "reported success for work never done" pattern this task exists to
    /// eliminate, so the caller folds this into its partial-failure message.
    /// Only multi-colour writes carry the key at all, so a single colour can
    /// never drop anything.
    nonisolated static func droppedStyleNote(requested: String?, colorCount: Int) -> String? {
        guard colorCount > 1,
              let requested = requested?.trimmingCharacters(in: .whitespacesAndNewlines),
              !requested.isEmpty,
              FilaManPayloadBuilder.supportedMultiColorStyle(requested) == nil
        else { return nil }
        let supported = FilaManPayloadBuilder.multiColorStyles.joined(separator: " or ")
        return "The colour direction \"\(requested)\" was not saved — FilaMan only supports \(supported)."
    }

    /// What a colour write on an EXISTING filament actually did.
    ///
    /// `written` deliberately carries its own optional note rather than the
    /// method returning a bare `String?`: a dropped colour direction (R19) and
    /// a failed colour write are both "there is something to tell the user",
    /// but only the second means the swatch on the server is unchanged. Collapsing
    /// them into one optional would make a successful write look failed to the
    /// re-read guard below — the same "one value meaning two things" defect
    /// F24/F25/F29 were each an instance of.
    nonisolated enum FilaManColorWriteOutcome {
        case skipped
        case written(note: String?)
        case failed(String)

        /// The user-facing message, if there is one, regardless of which.
        var message: String? {
            switch self {
            case .skipped: nil
            case .written(let note): note
            case .failed(let message): message
            }
        }
    }

    /// Writes a draft's colours onto an EXISTING filament. `FilamentUpdate` has
    /// no `colors` property, so this call is the only way — and its failure must
    /// not be swallowed, since the scalar PATCH that preceded it did land.
    private func applyFilamentColors(
        id: Int, hexes: [String], multiColorStyle: String?
    ) async -> FilaManColorWriteOutcome {
        switch await resolveColorIds(hexes: hexes) {
        case .skip:
            return .skipped
        case .failed(let message):
            return .failed("Colour — not saved: \(message)")
        case .resolved(let colorIds):
            do {
                try await service.replaceFilamentColors(
                    id: id,
                    payload: FilaManPayloadBuilder.colorsPayload(colorIds: colorIds, multiColorStyle: multiColorStyle),
                    baseUrl: baseUrl
                )
                return .written(
                    note: Self.droppedStyleNote(requested: multiColorStyle, colorCount: colorIds.count)
                )
            } catch {
                return .failed("Colour — not saved: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Remaining weight

    /// Pure relative-adjustment computation (R17). FilaMan's
    /// `AdjustmentRequest` accepts `absolute` too, but `absolute` pairs with
    /// `measured_weight_g` — a GROSS weight — while SpoolKid's
    /// `remainingWeight` is net filament; see
    /// `FilaManPayloadBuilder.adjustmentPayload` for what that mismatch would
    /// silently cost. A relative delta reads and writes the same net quantity.
    nonisolated static func weightAdjustment(target: Double, current: Double?) -> FilaManWeightAdjustment {
        guard let current else { return .currentUnknown }
        let delta = target - current
        return delta == 0 ? .alreadyThere : .delta(delta)
    }

    /// Which of FilaMan's two weight-writing mechanisms a draft calls for.
    ///
    /// They are not interchangeable, and the difference is visible to the user
    /// in the event history: `/measurements` files a **`measurement`**,
    /// `/adjustments` files a **`manual_adjust`**. A spool actually put on a
    /// scale should read as the former.
    ///
    /// `SpoolFormView` fills `remainingWeight` in every mode — Spoolman and the
    /// on-device Library have no measurement concept — so the gross reading has
    /// to win where both are present. It is also the more faithful of the two:
    /// `measured_weight_g` is stored directly as the gross figure, where the
    /// adjustment path converts to net, diffs against the server's current
    /// value and posts a delta.
    nonisolated static func weightWriteKind(for draft: SpoolDraft) -> FilaManWeightWrite {
        guard let measured = draft.measuredWeight else { return .adjustment }
        return .measurement(measured)
    }

    /// What a draft asks the spool's remaining weight to become (plan defect
    /// I2). `SpoolFormView` puts the user's number into `remainingWeight` or
    /// `usedWeight` depending on the mode they picked, and FilaMan's spool
    /// payload carried neither — so a weight edit PATCHed, got a 200, cleared
    /// the error and returned `true` while nothing was written.
    ///
    /// FilaMan stores what is LEFT, so a used weight is converted against the
    /// NET initial (`netInitialWeight`) — the same direction Spoolman derives
    /// it in. When there is no basis to convert against, that is
    /// `.unsupported`, never `.unchanged`: the user asked for something and it
    /// cannot be honoured, which is a thing to say rather than a thing to drop.
    ///
    /// An explicit remaining weight wins over a used one; `SpoolFormView`
    /// never sets both, but a draft assembled elsewhere (`MigrationService`)
    /// could, and the direct value needs no basis.
    ///
    /// Semantic choice worth naming: `SpoolFormView` PREFILLS the weight field
    /// from the spool's current remaining weight, so an edit that only changes
    /// a comment still arrives here carrying one. SpoolKid treats that
    /// prefilled number as the user's intent and writes it, which means it
    /// overrides FilaMan's own re-base of the same spool (a print that
    /// consumed filament since the form opened, say). The form is the user's
    /// statement of what the spool holds; the alternative — diffing against
    /// the value the form opened with — would silently discard a deliberate
    /// correction that happens to be typed twice.
    nonisolated static func remainingWeightTarget(
        for draft: SpoolDraft,
        netInitial: Double?
    ) -> FilaManRemainingWeightTarget {
        // `.setNil` is `.unsupported`, not `.unchanged`: FilaMan's remaining
        // weight is EVENT-SOURCED — `SpoolUpdate` has no such field and an
        // adjustment can only move it by a delta — so there is no way to make
        // it null. Folding that into "unchanged" would be this integration's
        // own defect (R21).
        switch draft.remainingWeight {
        case .set(let remaining):
            return .grams(remaining)
        case .setNil:
            return .unsupported(
                "The remaining weight was not cleared — FilaMan works it out from the spool's "
                + "own history, so it cannot be left empty."
            )
        case .ignore:
            break
        }
        switch draft.usedWeight {
        case .setNil:
            return .unsupported(
                "The used weight was not cleared — FilaMan stores what is left on the spool "
                + "rather than what is gone, so there is nothing to clear."
            )
        case .ignore:
            return .unchanged
        case .set:
            break
        }
        guard let used = draft.usedWeight.valueOnCreate else { return .unchanged }
        guard let netInitial else {
            return .unsupported(
                "The used weight was not applied — FilaMan stores what is left on the spool, "
                + "and there is no initial weight to work that out from."
            )
        }
        // A used weight above the initial weight would compute a negative
        // remaining. Update clamps that at 0 server-side; create is unprobed
        // and may 422 (M3). Either way it is a number the user cannot have
        // meant, so it is refused out loud rather than sent.
        guard used <= netInitial else {
            return .unsupported(
                "The used weight was not applied — it is more than the spool's initial weight, "
                + "so there would be nothing left on the spool."
            )
        }
        return .grams(netInitial - used)
    }

    /// What the spool's remaining weight must BECOME once the scalar PATCH has
    /// landed: the draft's own target when it named one, and otherwise the
    /// value the spool reported before the PATCH (plan defect I2, rule R20).
    ///
    /// `.unchanged` used to mean "the user asked for no weight change, so do
    /// nothing". Under F32 that is not the same thing: a PATCH that changes
    /// `empty_spool_weight_g` re-bases the remaining weight whether the user
    /// asked for it or not, so "do nothing" quietly loses filament. The
    /// user not asking for a change is a statement about the OUTCOME — the
    /// weight must end up where it started — and honouring it takes the same
    /// compensating adjustment the `.grams` path already posts.
    ///
    /// So `.unchanged` survives only where it is still true: the PATCH cannot
    /// move the weight, or there is no weight to move.
    nonisolated static func remainingWeightGoal(
        draft: SpoolDraft,
        netInitial: Double?,
        before: FilaManPrePatchRemainingWeight
    ) -> FilaManRemainingWeightTarget {
        switch remainingWeightTarget(for: draft, netInitial: netInitial) {
        case .grams(let target):
            return .grams(target)
        case .unsupported(let message):
            return .unsupported(message)
        case .unchanged:
            switch before {
            case .cannotMove, .unreported:
                return .unchanged
            case .reported(let grams):
                return .grams(grams)
            case .unreadable(let message):
                return .unsupported(message)
            }
        }
    }

    /// Moves a spool's remaining weight onto `target` from a `current` the
    /// caller has ALREADY established — the read is the caller's, because both
    /// call sites already hold a fresh spool and a second GET here would make
    /// `updateSpool` read the same record three times.
    ///
    /// The delta is relative, so `current` must be the value as it stands
    /// AFTER any write that could have moved it (R17).
    private func postWeightAdjustment(
        spoolId: Int, target: Double, current: Double?
    ) async -> FilaManWeightWriteOutcome {
        switch Self.weightAdjustment(target: target, current: current) {
        case .currentUnknown:
            return .failed(
                "The remaining weight was not changed: FilaMan reports no current weight for this spool, "
                + "so a relative adjustment cannot be worked out."
            )
        case .alreadyThere:
            // Posting a zero delta would still create an event and move the
            // spool off "new" — a real change for a write that changes nothing.
            return .unchanged
        case .delta(let delta):
            do {
                try await service.createSpoolAdjustment(
                    spoolId: spoolId,
                    payload: FilaManPayloadBuilder.adjustmentPayload(deltaGrams: delta),
                    baseUrl: baseUrl
                )
                return .adjusted
            } catch {
                return .failed("The remaining weight was not saved: \(error.localizedDescription)")
            }
        }
    }

    /// NET filament weight, from FilaMan's GROSS `initial_total_weight_g`.
    ///
    /// The DTO name means what it says: filament PLUS the empty spool. The
    /// spec asserted the opposite and this mapper carried a comment repeating
    /// it until the owner corrected both and proved it live (plan defect F31,
    /// 2026-08-21). `Spool.initialWeight` is NET everywhere else in SpoolKid —
    /// Spoolman's `initial_weight` is net filament, and
    /// `DashboardStatsService.fillFraction` divides the net `remaining_weight_g`
    /// by it — so the basis has to come off here. Without it an untouched 1 kg
    /// spool on a 250 g core reported 250 g already used and read a whole fill
    /// bucket emptier than it was.
    ///
    /// Only `initial` needs converting: `remaining_weight_g` is net on both
    /// sides, which is what leaves R17's relative-delta design untouched.
    ///
    /// A nil basis counts as 0 — `empty_spool_weight_g` is nullable, and a null
    /// there means FilaMan tracks no core weight, not that the net initial is
    /// unknowable. `nil` in, `nil` out: with no gross figure there is no net one.
    nonisolated static func netInitialWeight(gross: Double?, emptySpool: Double?) -> Double? {
        guard let gross else { return nil }
        return gross - (emptySpool ?? 0)
    }

    // MARK: - Batch mapping (dependency resolution)
    //
    // Thin, pure wrappers around the per-item mappers below that also do the
    // id→object dependency resolution `loadFilaments`/`loadSpools` need.
    // Extracted so that resolution — including the "drop a spool whose
    // filament can't be found" decision — is unit-testable without a network
    // seam.

    static func mapFilaments(_ dtos: [FilaManFilament], vendors: [Vendor]) -> [Filament] {
        let vendorsById = Dictionary(vendors.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return dtos.map { mapFilament($0, vendor: vendorsById[$0.manufacturerId]) }
    }

    /// A spool whose `filamentId` has no match among `filaments` is dropped
    /// rather than crashing or being mapped with a placeholder — this should
    /// only happen from a genuine server-side data-integrity gap, since
    /// `loadSpools` always resolves filaments before spools.
    static func mapSpools(
        _ dtos: [FilaManSpool], filaments: [Filament], locationsById: [Int: String], rfidWritable: Bool = false
    ) -> [Spool] {
        let filamentsById = Dictionary(filaments.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return dtos.compactMap { dto in
            guard let filament = filamentsById[dto.filamentId] else { return nil }
            return mapSpool(dto, filament: filament, locationsById: locationsById, rfidWritable: rfidWritable)
        }
    }

    // MARK: - Spools (Task 15 mapping — unchanged)

    /// `filament` is already resolved by the caller (via `filamentId`);
    /// `locationsById` likewise resolves `locationId` → a display name.
    /// `rfidWritable` is FilaMan Tags' switch, read by the caller, so the
    /// mapping stays pure.
    static func mapSpool(
        _ spool: FilaManSpool, filament: Filament, locationsById: [Int: String], rfidWritable: Bool = false
    ) -> Spool {
        let netInitial = netInitialWeight(gross: spool.initialTotalWeightG, emptySpool: spool.emptySpoolWeightG)
        let remaining = spool.remainingWeightG
        let usedWeight: Double?
        if let netInitial, let remaining {
            // Both sides of this subtraction are now NET, which is what makes
            // an untouched spool report zero used rather than its core weight.
            usedWeight = netInitial - remaining
        } else {
            usedWeight = nil
        }

        let location = spool.locationId.flatMap { locationsById[$0] }

        return Spool(
            id: spool.id,
            filament: filament,
            registered: parseDate(spool.createdAt),
            firstUsed: parseDate(spool.stockedInAt),
            lastUsed: parseDate(spool.lastUsedAt),
            remainingWeight: remaining,
            // NET filament weight, converted from the DTO's GROSS figure by
            // `netInitialWeight` — see there for why (F31).
            initialWeight: netInitial,
            spoolWeight: spool.emptySpoolWeightG,
            usedWeight: usedWeight,
            price: spool.purchasePrice,
            location: location,
            lotNr: spool.lotNumber,
            comment: spool.customFields?["comment"]?.stringValue,
            archived: spool.statusId == FilaManSpoolStatus.archived,
            extra: spool.customFields?.displayStrings,
            rfidUID: spool.rfidUid,
            statusId: spool.statusId,
            externalId: spool.externalId,
            // A CALENDAR date, not an instant — `parseDate` (below) is for
            // genuine timestamps and would read the UTC instant, then display
            // a day early at a negative offset (fix round 1). `CalendarDateCodec`
            // reads only the date portion, in the same zone the form writes it in.
            purchaseDate: CalendarDateCodec.date(from: spool.purchaseDate),
            rfidUIDWritable: rfidWritable
        )
    }

    // MARK: - Filaments (Task 15 mapping — unchanged)

    /// `vendor` is already resolved by the caller (via `manufacturerId`).
    static func mapFilament(_ filament: FilaManFilament, vendor: Vendor?) -> Filament {
        let sortedColors = (filament.colors ?? []).sorted { $0.position < $1.position }
        let colorHex = filament.colors?
            .first { $0.position == 1 }?
            .color.hexCode.map { stripLeadingHash($0) }
        let multiColorHexList = sortedColors.compactMap { $0.color.hexCode.map { stripLeadingHash($0) } }
        let multiColorHexes = multiColorHexList.isEmpty ? nil : multiColorHexList.joined(separator: ",")
        // FilaMan's `striped`/`gradient` read back as Spoolman's directions, the
        // same layouts (owner decision 2026-10-28). A single colour has none.
        // With two or more colours and no recognised style, SpoolKid shows
        // Coextruded, per the spec's reading rule. Nothing is written unless the
        // user changes the pattern.
        let multiColorDirection = sortedColors.count >= 2
            ? FilamentColors.Pattern(filaManStyle: filament.multiColorStyle)?.rawValue ?? "coaxial"
            : nil

        // `Filament.variant` is a computed property that reads `extra["variant"]`
        // (no stored `variant` field exists) — this is the only way to carry
        // `materialSubgroup` through to it.
        var extra: [String: String] = [:]
        if let subgroup = filament.materialSubgroup, !subgroup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            extra["variant"] = subgroup
        }
        // `Filament.transmissionDistance` reads `extra["td"]`, in Spoolman's
        // float form; FilaMan keeps it as a number in `custom_fields`.
        if let td = TransmissionDistance.decode(filament.customFields?[TransmissionDistance.fieldKey]?.displayString) {
            extra[TransmissionDistance.fieldKey] = TransmissionDistance.spoolmanWireValue(td, fieldType: "float")
        }

        return Filament(
            id: filament.id,
            name: filament.designation,
            material: filament.materialType,
            vendor: vendor,
            price: filament.price,
            colorHex: colorHex,
            density: filament.densityG_cm3,
            diameter: filament.diameterMm,
            weight: filament.rawMaterialWeightG,
            spoolWeight: filament.defaultSpoolWeightG,
            articleNumber: filament.customFields?["article_number"]?.stringValue,
            settingsExtruderTemp: filament.customFields?["settings_extruder_temp"]?.stringValue.flatMap(Int.init),
            settingsBedTemp: filament.customFields?["settings_bed_temp"]?.stringValue.flatMap(Int.init),
            multiColorHexes: multiColorHexes,
            multiColorDirection: multiColorDirection,
            extra: extra.isEmpty ? nil : extra
        )
    }

    // MARK: - Vendors (Task 15 mapping — unchanged)

    static func mapVendor(_ manufacturer: FilaManManufacturer) -> Vendor {
        Vendor(
            id: manufacturer.id,
            name: manufacturer.name,
            comment: manufacturer.customFields?["comment"]?.stringValue,
            emptySpoolWeight: manufacturer.emptySpoolWeightG,
            extra: manufacturer.customFields?.displayStrings
        )
    }

    // MARK: - Read-side helpers

    private static func stripLeadingHash(_ hex: String) -> String {
        hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    }

    private static func parseDate(_ string: String?) -> Date? {
        FlexibleDateParser.date(from: string)
    }
}
