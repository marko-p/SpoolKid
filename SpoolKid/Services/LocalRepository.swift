//
//  LocalRepository.swift
//  SpoolKid
//
//  Purpose: Data access backed by the on-device SwiftData store (offline-first,
//  local-only users). Maps the Local* @Models to the shared Spoolman* DTOs the
//  app already consumes, loads them into @Published arrays (so the view layer is
//  uniform with the live-API backend), and enforces the free-tier quota on
//  create.
//
//  Covers the full `SpoolDataRepository` surface: store, persistent monotonic
//  local ids, Local→DTO mapping for all entities, reads, the quota guard, and
//  CRUD for vendors / filaments / spools plus UID mapping and location rename.
//  Nothing is wired to it until the backend-selection spec.
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
final class LocalRepository: ObservableObject, SpoolDataRepository {
    @Published private(set) var spools: [Spool] = []
    @Published private(set) var filaments: [Filament] = []
    @Published private(set) var vendors: [Vendor] = []
    @Published private(set) var locations: [String] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Set when a create is refused by the free-tier quota; the at-limit UI reads it.
    @Published var lastQuotaError: QuotaError?
    nonisolated let capabilities = BackendCapabilities.local

    private let context: ModelContext
    /// Test seam: replaces the entitlement's cap, so a quota test need not
    /// create thousands of rows to reach it. `nil` everywhere in the app.
    private let quotaLimit: Int?

    init(context: ModelContext, quotaLimit: Int? = nil) {
        self.context = context
        self.quotaLimit = quotaLimit
        reload()
    }

    // MARK: - Id allocation

    /// Allocates the next persistent local id for the given entity type from the
    /// sequence row. Monotonic and never reused — the counter only increments.
    private func allocateLocalId(for kind: String) -> Int {
        let descriptor = FetchDescriptor<LocalIdSequence>(
            predicate: #Predicate { $0.kind == kind }
        )
        let sequence: LocalIdSequence
        if let existing = try? context.fetch(descriptor).first {
            sequence = existing
        } else {
            sequence = LocalIdSequence(kind: kind, next: 1)
            context.insert(sequence)
        }
        let allocated = sequence.next
        sequence.next = allocated + 1
        return allocated
    }

    // MARK: - Entity lookups by localId

    private func vendorEntity(for id: Int) -> LocalVendor? {
        let descriptor = FetchDescriptor<LocalVendor>(
            predicate: #Predicate { $0.localId == id }
        )
        return (try? context.fetch(descriptor).first)
    }

    // MARK: - Load

    /// Rebuilds the published arrays from the store. Each row's persistent
    /// `localId` is the DTO id, so SwiftUI list identity is stable across reloads
    /// and app launches.
    func reload() {
        do {
            let vendorRows = try context.fetch(FetchDescriptor<LocalVendor>())
            let filamentRows = try context.fetch(FetchDescriptor<LocalFilament>())
            let spoolRows = try context.fetch(FetchDescriptor<LocalSpool>())

            vendors = vendorRows.map { dto(from: $0) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            filaments = filamentRows.map { dto(from: $0) }
            spools = spoolRows.compactMap { dto(from: $0) }

            let names = spoolRows.compactMap(\.location).filter { !$0.isEmpty }
            locations = Array(Set(names))
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchVendors() async { reload() }
    func fetchFilaments() async { reload() }
    func fetchSpools() async { reload() }
    func fetchLocations() async { reload() }

    /// The local store is always reachable.
    func testConnection() async -> Bool { true }

    /// Nothing is configurable, so this never changes and the Library tab's
    /// stale-answer guard always accepts.
    var connectionTarget: String { "local" }

    /// Reported as "no probe was needed", not as a probe that succeeded: there
    /// is no server here to have reached.
    func checkReachability() async -> BackendReachability { .alwaysAvailable }

    // MARK: - Local -> DTO mapping

    private func dto(from v: LocalVendor) -> Vendor {
        Vendor(
            id: v.localId,
            name: v.name,
            comment: v.comment,
            emptySpoolWeight: v.emptySpoolWeight,
            externalId: v.externalId,
            extra: v.extra
        )
    }

    private func dto(from f: LocalFilament) -> Filament {
        Filament(
            id: f.localId,
            name: f.name,
            material: f.material,
            vendor: f.vendor.map { dto(from: $0) },
            price: f.price,
            colorHex: f.colorHex,
            density: f.density,
            diameter: f.diameter,
            weight: f.weight,
            spoolWeight: f.spoolWeight,
            articleNumber: f.articleNumber,
            comment: f.comment,
            settingsExtruderTemp: f.settingsExtruderTemp,
            settingsBedTemp: f.settingsBedTemp,
            multiColorHexes: f.multiColorHexes,
            multiColorDirection: f.multiColorDirection,
            externalId: f.externalId,
            extra: f.extra
        )
    }

    /// Nil when the spool has no filament (a spool cannot be represented without
    /// one; the repository never creates such a row).
    private func dto(from s: LocalSpool) -> Spool? {
        guard let filament = s.filament else { return nil }
        return Spool(
            id: s.localId,
            filament: dto(from: filament),
            registered: s.registered,
            firstUsed: s.firstUsed,
            lastUsed: s.lastUsed,
            remainingWeight: s.remainingWeight,
            initialWeight: s.initialWeight,
            spoolWeight: s.spoolWeight,
            usedWeight: s.usedWeight,
            price: s.price,
            location: s.location,
            lotNr: s.lotNr,
            comment: s.comment,
            archived: s.archived,
            extra: s.extra,
            // The on-device Library has no status/external id/purchase date
            // columns — FilaMan-only fields, nil here as on Spoolman.
            statusId: nil,
            externalId: nil,
            purchaseDate: nil
        )
    }

    // MARK: - Quota

    /// Returns true if a new row of `entity` is within the current entitlement.
    /// On refusal, records `lastQuotaError` + `errorMessage` for the UI.
    private func withinQuota(_ entity: QuotaEntity, currentCount: Int) -> Bool {
        let limit = quotaLimit ?? Entitlement.current.limit(for: entity)
        guard currentCount >= limit else { return true }
        let error = QuotaError(entity: entity, limit: limit)
        lastQuotaError = error
        errorMessage = error.errorDescription
        return false
    }

    /// Every write's commit: a failed save rolls the pending changes back and
    /// reports `false`, rather than reloading over the error and returning
    /// `true` for a change that was never stored. The rollback matters beyond
    /// this repository: the context is the app's main one, shared with
    /// `EmptySpoolLibrary`, `LocationRegistry` and `MigrationService`, so a
    /// change left pending here would be committed by whichever saves next.
    private func commit() -> Bool {
        do {
            try context.save()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
            return false
        }
        reload()
        return true
    }

    // MARK: - Vendors

    @discardableResult
    func addVendor(draft: VendorDraft) async -> Vendor? {
        guard withinQuota(.vendors, currentCount: vendors.count) else { return nil }
        // Past the quota, so a failed save below is not a quota refusal; a
        // stale value would have the forms say "Limit Reached" over it.
        lastQuotaError = nil
        let localId = allocateLocalId(for: "vendor")
        let vendor = LocalVendor(localId: localId, name: draft.name ?? "")
        vendor.comment = draft.comment
        vendor.emptySpoolWeight = draft.emptySpoolWeight
        vendor.externalId = draft.externalId
        vendor.extra = draft.extra
        context.insert(vendor)
        guard commit() else { return nil }
        return dto(from: vendor)
    }

    @discardableResult
    func addVendor(name: String) async -> Vendor? {
        await addVendor(draft: VendorDraft(name: name))
    }

    @discardableResult
    func updateVendor(id: Int, draft: VendorDraft) async -> Bool {
        guard let vendor = vendorEntity(for: id) else { return false }
        // nil draft fields are omitted (unchanged), mirroring Spoolman's PATCH;
        // VendorDraft has no explicit-clear channel.
        if let name = draft.name { vendor.name = name }
        if draft.comment != nil { vendor.comment = draft.comment }
        if draft.emptySpoolWeight != nil { vendor.emptySpoolWeight = draft.emptySpoolWeight }
        if draft.externalId != nil { vendor.externalId = draft.externalId }
        if draft.extra != nil { vendor.extra = draft.extra }
        vendor.updatedAt = .now
        vendor.isDirty = true
        return commit()
    }

    /// Refuses a vendor its filaments still reference. The `.nullify` rule
    /// would otherwise orphan them silently (owner decision, 2026-09-15).
    @discardableResult
    func deleteVendor(id: Int) async -> Bool {
        guard let vendor = vendorEntity(for: id) else { return false }
        let impact = DeletionImpact.forVendors([id], filaments: filaments, spools: spools)
        guard impact.isEmpty else {
            errorMessage = impact.refusalMessage(for: "manufacturer")
            return false
        }
        context.delete(vendor)
        return commit()
    }

    /// One save, so the vendor and its dependents go together or not at all.
    func deleteVendorCascading(id: Int) async -> Bool {
        guard let vendor = vendorEntity(for: id) else { return false }
        for filament in Array(vendor.filaments) {
            Array(filament.spools).forEach { context.delete($0) }
            context.delete(filament)
        }
        context.delete(vendor)
        return commit()
    }

    // MARK: - Filaments

    @discardableResult
    func addFilament(draft: FilamentDraft) async -> Filament? {
        guard withinQuota(.filaments, currentCount: filaments.count) else { return nil }
        lastQuotaError = nil  // See `addVendor(draft:)`.
        let localId = allocateLocalId(for: "filament")
        let filament = LocalFilament(
            localId: localId,
            name: draft.name,
            material: draft.material,
            price: draft.price.valueOnCreate,
            colorHex: draft.colorHex,
            density: draft.density,
            diameter: draft.diameter,
            weight: draft.weight.valueOnCreate,
            spoolWeight: draft.spoolWeight.valueOnCreate,
            articleNumber: draft.articleNumber.valueOnCreate,
            comment: draft.comment.valueOnCreate,
            settingsExtruderTemp: draft.extruderTemp.valueOnCreate,
            settingsBedTemp: draft.bedTemp.valueOnCreate,
            multiColorHexes: draft.multiColorHexes.valueOnCreate,
            multiColorDirection: draft.multiColorDirection.valueOnCreate,
            externalId: draft.externalId.valueOnCreate,
            extra: draft.extra.valueOnCreate,
            vendor: draft.vendorId.valueOnCreate.flatMap { vendorEntity(for: $0) }
        )
        apply(transmissionDistance: draft.transmissionDistance, to: &filament.extra)
        context.insert(filament)
        guard commit() else { return nil }
        return dto(from: filament)
    }

    /// TD lives in `extra["td"]` in Spoolman's float form, so a migration to
    /// Spoolman carries it unchanged. Applied after `draft.extra`, so the
    /// typed value wins over a stale `td` key.
    private func apply(transmissionDistance patch: SpoolmanPatchValue<Double>, to extra: inout [String: String]?) {
        switch patch {
        case .ignore:
            return
        case .set(let value):
            var fields = extra ?? [:]
            fields[TransmissionDistance.fieldKey] = TransmissionDistance.spoolmanWireValue(value, fieldType: "float")
            extra = fields
        case .setNil:
            extra?[TransmissionDistance.fieldKey] = nil
            if extra?.isEmpty == true { extra = nil }
        }
    }

    /// Writes one patch value onto a stored property: leave / set / clear.
    /// Generic so the eleven clearable filament fields — four value types
    /// between them — cannot drift apart.
    private func apply<T>(_ patch: SpoolmanPatchValue<T>, to property: inout T?) {
        switch patch {
        case .ignore: break
        case .set(let value): property = value
        case .setNil: property = nil
        }
    }

    @discardableResult
    func updateFilament(id: Int, draft: FilamentDraft) async -> Bool {
        guard let filament = filamentEntity(for: id) else { return false }
        // No explicit-clear channel for these: set only when provided.
        if let v = draft.name { filament.name = v }
        if let v = draft.material { filament.material = v }
        if let v = draft.colorHex { filament.colorHex = v }
        // A multi-colour list replaces the single colour, as Spoolman's
        // `color_hex: null` does. Without this a stale colour outlives it.
        if case .set = draft.multiColorHexes, case .set = draft.multiColorDirection {
            filament.colorHex = nil
        }
        if let v = draft.density { filament.density = v }
        if let v = draft.diameter { filament.diameter = v }
        // Clearable, tri-state. This block used to look each field's SPOOLMAN
        // key name up in `clearFieldKeys` — the local store translating a
        // vendor's vocabulary to reach its own properties, which is the
        // coupling R21 removed.
        switch draft.vendorId {
        case .ignore: break
        case .set(let v): filament.vendor = vendorEntity(for: v)
        case .setNil: filament.vendor = nil
        }
        apply(draft.price, to: &filament.price)
        apply(draft.weight, to: &filament.weight)
        apply(draft.spoolWeight, to: &filament.spoolWeight)
        apply(draft.articleNumber, to: &filament.articleNumber)
        apply(draft.comment, to: &filament.comment)
        apply(draft.extruderTemp, to: &filament.settingsExtruderTemp)
        apply(draft.bedTemp, to: &filament.settingsBedTemp)
        apply(draft.multiColorHexes, to: &filament.multiColorHexes)
        apply(draft.multiColorDirection, to: &filament.multiColorDirection)
        apply(draft.externalId, to: &filament.externalId)
        apply(draft.extra, to: &filament.extra)
        apply(transmissionDistance: draft.transmissionDistance, to: &filament.extra)
        filament.updatedAt = .now
        filament.isDirty = true
        return commit()
    }

    /// Refuses a filament its spools still reference. The `.cascade` rule
    /// would otherwise delete them silently (owner decision, 2026-09-15).
    @discardableResult
    func deleteFilament(id: Int) async -> Bool {
        guard let filament = filamentEntity(for: id) else { return false }
        let impact = DeletionImpact.forFilaments([id], spools: spools)
        guard impact.isEmpty else {
            errorMessage = impact.refusalMessage(for: "filament")
            return false
        }
        context.delete(filament)
        return commit()
    }

    func deleteFilamentCascading(id: Int) async -> Bool {
        guard let filament = filamentEntity(for: id) else { return false }
        Array(filament.spools).forEach { context.delete($0) }
        context.delete(filament)
        return commit()
    }

    // MARK: - Spools

    @discardableResult
    func addSpool(draft: SpoolDraft) async -> Spool? {
        guard let filamentId = draft.filamentId, let filament = filamentEntity(for: filamentId) else {
            errorMessage = "A spool requires a filament."
            return nil
        }
        guard withinQuota(.spools, currentCount: spools.count) else { return nil }
        lastQuotaError = nil  // See `addVendor(draft:)`.
        let newLocation = locationOnCreate(draft.location)
        let localId = allocateLocalId(for: "spool")
        let spool = LocalSpool(
            localId: localId,
            registered: .now,
            firstUsed: parseDate(draft.firstUsed.valueOnCreate),
            lastUsed: parseDate(draft.lastUsed.valueOnCreate),
            remainingWeight: draft.remainingWeight.valueOnCreate,
            initialWeight: draft.initialWeight.valueOnCreate,
            spoolWeight: draft.spoolWeight.valueOnCreate,
            usedWeight: draft.usedWeight.valueOnCreate,
            price: draft.price,
            location: newLocation,
            lotNr: draft.lotNr.valueOnCreate,
            comment: draft.comment.valueOnCreate,
            archived: draft.archived,
            // The local store mirrors Spoolman's wrapped `extra` convention —
            // same form `setCardUIDs` writes below, so a spool created with a
            // mapping is indistinguishable from one mapped afterwards (F38).
            extra: CardUIDsCodec.applyingWrapped(draft.cardUIDs, to: draft.extra).valueOnCreate,
            filament: filament
        )
        context.insert(spool)
        guard commit() else { return nil }
        return dto(from: spool)
    }

    @discardableResult
    func updateSpool(id: Int, draft: SpoolDraft) async -> Bool {
        guard let spool = spoolEntity(for: id) else { return false }
        if let v = draft.filamentId, let filament = filamentEntity(for: v) { spool.filament = filament }
        // No explicit-clear channel for these: set only when provided.
        if let v = draft.price { spool.price = v }
        // Tri-state since R21: `.ignore` leaves the stored value alone, which
        // is what a bare optional could not say.
        switch draft.initialWeight {
        case .ignore: break
        case .set(let v): spool.initialWeight = v
        case .setNil: spool.initialWeight = nil
        }
        switch draft.spoolWeight {
        case .ignore: break
        case .set(let v): spool.spoolWeight = v
        case .setNil: spool.spoolWeight = nil
        }
        switch draft.remainingWeight {
        case .ignore: break
        case .set(let v): spool.remainingWeight = v
        case .setNil: spool.remainingWeight = nil
        }
        switch draft.usedWeight {
        case .ignore: break
        case .set(let v): spool.usedWeight = v
        case .setNil: spool.usedWeight = nil
        }
        if let v = draft.archived { spool.archived = v }
        // Location is a tri-state patch.
        switch draft.location {
        case .ignore: break
        case .set(let value): spool.location = value
        case .setNil: spool.location = nil
        }
        // Tri-state, no key-name lookup: these two moved off `clearFieldKeys`
        // in the same change that made FilaMan honour them (R21).
        switch draft.comment {
        case .ignore: break
        case .set(let v): spool.comment = v
        case .setNil: spool.comment = nil
        }
        switch draft.lotNr {
        case .ignore: break
        case .set(let v): spool.lotNr = v
        case .setNil: spool.lotNr = nil
        }
        // Clearable: set if provided, else nil if its API key is marked.
        switch draft.firstUsed {
        case .ignore: break
        case .set(let v): spool.firstUsed = parseDate(v)
        case .setNil: spool.firstUsed = nil
        }
        switch draft.lastUsed {
        case .ignore: break
        case .set(let v): spool.lastUsed = parseDate(v)
        case .setNil: spool.lastUsed = nil
        }
        switch draft.extra {
        case .ignore: break
        case .set(let v): spool.extra = v
        case .setNil: spool.extra = nil
        }
        // After the wholesale `extra` assignment, so a draft that carries both
        // lands the typed list rather than whatever the raw JSON held (F38).
        // The other two conformers honour `cardUIDs` on update through the same
        // payload builder their create uses; dropping it here would make the
        // local backend the one that reports a mapping it never wrote.
        spool.extra = CardUIDsCodec.applyingWrapped(draft.cardUIDs, to: spool.extra)
        spool.updatedAt = .now
        spool.isDirty = true
        return commit()
    }

    @discardableResult
    func deleteSpool(id: Int) async -> Bool {
        guard let spool = spoolEntity(for: id) else { return false }
        context.delete(spool)
        return commit()
    }

    @discardableResult
    func setSpoolArchived(id: Int, archived: Bool) async -> Bool {
        guard let spool = spoolEntity(for: id) else { return false }
        spool.archived = archived
        spool.updatedAt = .now
        spool.isDirty = true
        return commit()
    }

    // MARK: - UID mapping

    /// Links live in each spool's `extra["card_uids"]`, the field this
    /// repository already reads and writes (spec 2); the UI calls them Tags.
    var availableTagStores: Set<TagStore> { [.cardUIDs] }

    /// Filament links live in each filament's `extra["card_uids"]` (spec 4).
    var filamentTagStore: TagStore? { .cardUIDs }

    func linkFilamentTag(filamentId: Int, uid: String) async -> SpoolmanService.TagLinkOutcome {
        guard let filament = filamentEntity(for: filamentId) else {
            return .failed("That filament is no longer in your library.")
        }
        let normalized = SpoolMappingService.normalizeUID(uid)
        var uids = CardUIDsCodec.parse(filament.extra?[CardUIDsCodec.fieldKey])
        guard !uids.contains(normalized) else { return .linked }
        uids.append(normalized)
        var updatedExtra = filament.extra ?? [:]
        updatedExtra[CardUIDsCodec.fieldKey] = CardUIDsCodec.encode(uids)
        filament.extra = updatedExtra
        filament.updatedAt = .now
        filament.isDirty = true
        guard commit() else { return .failed("The link could not be saved.") }
        return .linked
    }

    func unlinkFilamentTag(filamentId: Int, uid: String) async -> Bool {
        guard let filament = filamentEntity(for: filamentId) else { return false }
        let normalized = SpoolMappingService.normalizeUID(uid)
        var updatedExtra = filament.extra ?? [:]
        let remaining = CardUIDsCodec.parse(updatedExtra[CardUIDsCodec.fieldKey]).filter { $0 != normalized }
        updatedExtra[CardUIDsCodec.fieldKey] = remaining.isEmpty ? nil : CardUIDsCodec.encode(remaining)
        filament.extra = updatedExtra.isEmpty ? nil : updatedExtra
        filament.updatedAt = .now
        filament.isDirty = true
        return commit()
    }

    func findSpool(byCardUID uid: String) -> Spool? {
        SpoolMappingService.spool(in: spools, claiming: uid)
    }

    @discardableResult
    func setCardUIDs(spoolId: Int, uids: [String]) async -> Bool {
        guard let spool = spoolEntity(for: spoolId) else { return false }
        var updatedExtra = spool.extra ?? [:]
        updatedExtra["card_uids"] = CardUIDsCodec.encode(uids)
        spool.extra = updatedExtra
        spool.updatedAt = .now
        spool.isDirty = true
        return commit()
    }

    /// Unreachable: the on-device Library declares
    /// `requiresCardUIDsFieldRegistration = false` — it maps tags, but has no
    /// field registry — so nothing gates on this. It answers `false` rather than
    /// `true` because there is no registry here to have succeeded against, and
    /// a bare `true` would be a success reported for work never done — the
    /// exact shape this epic kept finding.
    @discardableResult
    func ensureCardUIDsField() async -> Bool { false }

    /// Unreachable for the same reason as `ensureCardUIDsField`.
    @discardableResult
    func deleteCardUIDsField() async -> Bool { false }

    // MARK: - Locations

    /// The local store has no Location entity — `location` is a string on
    /// `LocalSpool`. Nothing to create; the registry holds the name.
    @discardableResult
    func addLocation(name: String) async -> LocationCreateOutcome {
        LocationCreateOutcome.precheck(name: name, existing: locations) ?? .registeredOnDeviceOnly
    }

    @discardableResult
    func renameLocation(currentName: String, newName: String) async -> Bool {
        let rows = (try? context.fetch(FetchDescriptor<LocalSpool>())) ?? []
        var changed = false
        for spool in rows where spool.location == currentName {
            spool.location = newName
            spool.updatedAt = .now
            spool.isDirty = true
            changed = true
        }
        guard changed else { return true }
        return commit()
    }

    @discardableResult
    func deleteLocation(_ name: String) async -> Bool {
        let rows = (try? context.fetch(FetchDescriptor<LocalSpool>())) ?? []
        var changed = false
        for spool in rows where spool.location == name {
            spool.location = nil
            spool.updatedAt = .now
            spool.isDirty = true
            changed = true
        }
        guard changed else { return true }
        return commit()
    }

    // MARK: - Entity lookups & parsing

    private func filamentEntity(for id: Int) -> LocalFilament? {
        let descriptor = FetchDescriptor<LocalFilament>(
            predicate: #Predicate { $0.localId == id }
        )
        return (try? context.fetch(descriptor).first)
    }

    private func spoolEntity(for id: Int) -> LocalSpool? {
        let descriptor = FetchDescriptor<LocalSpool>(
            predicate: #Predicate { $0.localId == id }
        )
        return (try? context.fetch(descriptor).first)
    }

    /// Create only sets a location when the patch explicitly carries one
    /// (.ignore / .setNil → no location). The spool form already downgrades
    /// .setNil to .ignore on add.
    private func locationOnCreate(_ patch: SpoolmanPatchValue<String>) -> String? {
        if case .set(let value) = patch { return value }
        return nil
    }

    private func parseDate(_ string: String?) -> Date? {
        FlexibleDateParser.date(from: string)
    }
}
