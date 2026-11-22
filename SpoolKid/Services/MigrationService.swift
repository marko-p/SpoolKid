//
//  MigrationService.swift
//  SpoolKid
//
//  Purpose: Applies a resolved M3 migration plan to whichever server backend is
//  active, in dependency order (vendors → filaments → spools), keeps child
//  foreign keys pointed at the resolved server ids, carries tag links, lot_nr
//  and location on spools, marks synced rows with `serverId`, and wipes the
//  local Library only on full success.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Combine
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.spoolkid", category: "MigrationService")

/// One row the migration could not upload, and why.
///
/// The reason exists because the counts alone are useless to the person
/// holding the phone: "1 failed" cannot be acted on, while "A filament needs a
/// manufacturer on FilaMan" can (device finding, 2026-08-29). `nil` only where
/// the backend gave nothing to pass on.
nonisolated struct MigrationFailure: Equatable, Sendable, Identifiable {
    let label: String
    let reason: String?
    var id: String { "\(label)\u{1F}\(reason ?? "")" }
}

/// Outcome of executing a migration plan.
struct MigrationResult {
    let created: Int
    let reused: Int
    let failed: [MigrationFailure]
    let skipped: [MigrationFailure]
    /// Rows that uploaded, but with a note: a value the local row holds that
    /// the backend did not store (FilaMan has no field for a filament comment,
    /// for instance). Those values now exist only on this iPhone.
    var notStored: [MigrationFailure] = []

    /// Nothing failed, nothing was skipped, and nothing was left behind — the
    /// only outcome that empties the on-device Library without asking.
    var isComplete: Bool { failed.isEmpty && skipped.isEmpty && notStored.isEmpty }
}

/// How many on-device rows are still waiting to be uploaded — or the fact that
/// the store would not answer.
///
/// `.unavailable` is deliberately NOT folded into `.counted(0)`. Both lead to
/// the same screen (no migration offer), but only one of them is a bug, and a
/// fetch failure quietly counted as zero is exactly how a feature stops
/// appearing without anyone noticing.
///
/// `nonisolated`: the target defaults actor isolation to MainActor, which would
/// make the synthesized `Equatable` unusable from Swift Testing.
nonisolated enum UnsyncedLocalRowCount: Equatable, Sendable {
    case counted(Int)
    case unavailable
}

/// Executor for the one-shot local → server migration described in M3.
/// Reads local SwiftData rows directly (independent of the active backend) and
/// writes through an `any SpoolDataRepository` pointed at whichever server
/// backend is active.
@MainActor
final class MigrationService: ObservableObject {
    @Published var progress: (done: Int, total: Int) = (0, 0)
    @Published var lastResult: MigrationResult?
    @Published var buildError: String?

    /// The note for a row that uploaded but whose server id this iPhone could
    /// not save. The id stays pending, so a later save that succeeds keeps it;
    /// lost instead, the row reads as not uploaded and is offered again.
    static let stampNotSavedNote = "It was uploaded, but this iPhone could not save that yet. If it never does, a later upload offers it again."

    private let context: ModelContext
    private let writer: any SpoolDataRepository

    init(context: ModelContext, writer: any SpoolDataRepository) {
        self.context = context
        self.writer = writer
    }

    /// The backend this plan uploads to. The review sheet's copy reads this
    /// rather than naming Spoolman, so a third backend needs no view change.
    var capabilities: BackendCapabilities { writer.capabilities }

    // MARK: - Trigger helper

    /// Cheap count of un-synced local rows. Used by the launch-time auto-prompt
    /// and the manual "Migrate now" entry to decide whether migration is
    /// relevant. A failed fetch returns `.unavailable`, not zero — see
    /// `UnsyncedLocalRowCount`.
    static func unsyncedLocalRowCount(in context: ModelContext) -> UnsyncedLocalRowCount {
        do {
            let vendors = try context.fetchCount(FetchDescriptor<LocalVendor>(
                predicate: #Predicate { $0.serverId == nil }
            ))
            let filaments = try context.fetchCount(FetchDescriptor<LocalFilament>(
                predicate: #Predicate { $0.serverId == nil }
            ))
            let spools = try context.fetchCount(FetchDescriptor<LocalSpool>(
                predicate: #Predicate { $0.serverId == nil }
            ))
            return .counted(vendors + filaments + spools)
        } catch {
            logger.error("Could not count un-synced local rows: \(error.localizedDescription)")
            return .unavailable
        }
    }

    /// Migration uploads the on-device Library to whichever server is active.
    /// Server→server is deliberately out of scope: FilaMan ships its own
    /// `spoolman_import` plugin, which does that job better than the app could.
    ///
    /// This replaced a Spoolman-URL-plus-Spoolman-connection-flag test at both
    /// entry points, which made the offer dead on FilaMan.
    nonisolated static func shouldOfferMigration(
        capabilities: BackendCapabilities,
        unsyncedLocalRows: Int
    ) -> Bool {
        !capabilities.isOnDeviceStorage && unsyncedLocalRows > 0
    }

    /// The form both entry points call. Decides once, here, that a store which
    /// would not answer offers nothing — rather than letting each view invent
    /// its own reading of `.unavailable`.
    nonisolated static func shouldOfferMigration(
        capabilities: BackendCapabilities,
        localRows: UnsyncedLocalRowCount
    ) -> Bool {
        switch localRows {
        case .counted(let rows):
            return shouldOfferMigration(capabilities: capabilities, unsyncedLocalRows: rows)
        case .unavailable:
            // Logged where the count failed. `buildPlan` reads the same store,
            // so offering here would only lead to an empty review sheet.
            return false
        }
    }

    // MARK: - Plan

    /// Builds a migration plan from the current local store (rows that have not
    /// yet been synced) and the current Spoolman server state.
    /// Returns `nil` when a pre-flight fetch fails (e.g., server unreachable).
    func buildPlan() async -> MigrationPlan? {
        buildError = nil

        await writer.fetchVendors()
        if let error = writer.errorMessage {
            buildError = error
            return nil
        }

        await writer.fetchFilaments()
        if let error = writer.errorMessage {
            buildError = error
            return nil
        }

        await writer.fetchSpools()
        if let error = writer.errorMessage {
            buildError = error
            return nil
        }

        // A failed local fetch must NOT become an empty plan (review finding
        // M2). `execute` wipes the local store whenever nothing failed and
        // nothing was skipped — and rows that were never planned cannot do
        // either, so three swallowed `(try? fetch) ?? []`s ended in a wipe of
        // the very rows they could not read. Same reasoning as
        // `UnsyncedLocalRowCount`, applied one layer down; a plan built from a
        // store that would not answer is not a plan.
        let localVendors: [MigrationLocalVendor]
        let localFilaments: [MigrationLocalFilament]
        let localSpools: [MigrationLocalSpool]
        do {
            localVendors = try unsyncedLocalVendors()
            localFilaments = try unsyncedLocalFilaments()
            localSpools = try unsyncedLocalSpools(using: localVendors)
        } catch {
            logger.error("Could not read local rows to migrate: \(error.localizedDescription)")
            buildError = "The on-device Library could not be read, so there is nothing "
                + "to migrate from yet. Try again — nothing has been changed or deleted."
            return nil
        }

        return MigrationPlanner.plan(
            localVendors: localVendors,
            localFilaments: localFilaments,
            localSpools: localSpools,
            serverVendors: writer.vendors,
            serverFilaments: writer.filaments,
            serverSpools: writer.spools
        )
    }

    // MARK: - Execute

    /// Applies a resolved plan. Creates rows in dependency order, repoints child
    /// FKs to the server ids that were created or reused, stamps `serverId` on
    /// every synced local row, and wipes the local store only when the run is
    /// complete (`MigrationResult.isComplete`).
    func execute(_ plan: MigrationPlan) async -> MigrationResult {
        var vendorIdMap: [Int: Int] = [:]
        var filamentIdMap: [Int: Int] = [:]
        var created = 0
        var reused = 0
        var failed: [MigrationFailure] = []
        var skipped: [MigrationFailure] = []
        var notStored: [MigrationFailure] = []
        // Read right after the write that returned nil, while it is still that
        // write's message: `SpoolDataStore.refresh()` copies the repository's
        // `errorMessage` on every call, so it is current, not accumulated.
        func writeFailure(_ label: String) -> MigrationFailure {
            MigrationFailure(label: label, reason: writer.errorMessage)
        }
        // After a create that SUCCEEDED, `errorMessage` is that create's own
        // "saved, but…" note or nil: every server backend resets it on a
        // successful create. Dropping it was how a migrated comment or
        // external ID FilaMan could not store vanished without a word — and
        // was then wiped with the local Library.
        func noteNotStored(_ label: String) {
            if let note = writer.errorMessage {
                notStored.append(MigrationFailure(label: label, reason: note))
            }
        }
        let unreadableRow = "This item could not be read from the on-device Library."
        // A row whose server id could not be saved still reads as not
        // uploaded, so it holds the wipe like any other note.
        func stamp<T: PersistentModel, C>(_ type: T.Type, _ item: MigrationItem<C>, serverId: Int) {
            if !stampServerId(type, localId: item.localId, serverId: serverId) {
                notStored.append(MigrationFailure(label: item.label, reason: Self.stampNotSavedNote))
            }
        }


        let total = plan.vendors.count + plan.filaments.count + plan.spools.count
        progress = (0, total)

        // Vendors first: they have no local parent.
        for item in plan.vendors {
            switch item.resolution {
            case .reuse(let serverId):
                vendorIdMap[item.localId] = serverId
                stamp(LocalVendor.self, item, serverId: serverId)
                reused += 1
            case .create:
                if let vendor = localVendor(localId: item.localId) {
                    let draft = vendorDraft(from: vendor)
                    if let createdVendor = await writer.addVendor(draft: draft) {
                        vendorIdMap[item.localId] = createdVendor.id
                        stamp(LocalVendor.self, item, serverId: createdVendor.id)
                        created += 1
                        noteNotStored(item.label)
                    } else {
                        failed.append(writeFailure(item.label))
                    }
                } else {
                    failed.append(MigrationFailure(label: item.label, reason: unreadableRow))
                }
            }
            progress.done += 1
        }

        // Filaments second: their parent vendor must have resolved.
        for item in plan.filaments {
            guard let filament = localFilament(localId: item.localId) else {
                failed.append(MigrationFailure(label: item.label, reason: unreadableRow))
                progress.done += 1
                continue
            }
            let vendorLocalId = filament.vendor?.localId
            if let requiredVendorLocalId = vendorLocalId, vendorIdMap[requiredVendorLocalId] == nil {
                skipped.append(MigrationFailure(
                    label: item.label, reason: "Its manufacturer was not uploaded."
                ))
                progress.done += 1
                continue
            }

            switch item.resolution {
            case .reuse(let serverId):
                filamentIdMap[item.localId] = serverId
                stamp(LocalFilament.self, item, serverId: serverId)
                reused += 1
                if let failure = await linkFilamentTags(of: filament, to: serverId, label: item.label) {
                    notStored.append(failure)
                }
            case .create:
                let draft = filamentDraft(from: filament, vendorIdMap: vendorIdMap)
                if let createdFilament = await writer.addFilament(draft: draft) {
                    filamentIdMap[item.localId] = createdFilament.id
                    stamp(LocalFilament.self, item, serverId: createdFilament.id)
                    created += 1
                    noteNotStored(item.label)
                    if let failure = await linkFilamentTags(of: filament, to: createdFilament.id, label: item.label) {
                        notStored.append(failure)
                    }
                } else {
                    failed.append(writeFailure(item.label))
                }
            }
            progress.done += 1
        }

        // Spools last: their parent filament must have resolved.
        for item in plan.spools {
            guard let spool = localSpool(localId: item.localId) else {
                failed.append(MigrationFailure(label: item.label, reason: unreadableRow))
                progress.done += 1
                continue
            }
            guard let filamentLocalId = spool.filament?.localId,
                  filamentIdMap[filamentLocalId] != nil else {
                skipped.append(MigrationFailure(
                    label: item.label, reason: "Its filament was not uploaded."
                ))
                progress.done += 1
                continue
            }

            switch item.resolution {
            case .reuse(let serverId):
                let localUIDs = Self.localTagUIDs(of: spool)
                if !localUIDs.isEmpty,
                   let serverSpool = writer.spools.first(where: { $0.id == serverId }) {
                    // Every link the write could take away: a 0.27 server's
                    // native tags as well as `card_uids` (the write unlinks
                    // any native tag it is not given), and FilaMan's
                    // `rfid_uid` while FilaMan Tags makes it writable.
                    let serverUIDs = serverSpool.writableCardUIDs
                    var merged = serverUIDs
                    for uid in localUIDs where !merged.contains(uid) {
                        merged.append(uid)
                    }
                    // The spool is linked either way; its tags are not if this
                    // write is refused, and those IDs live only in the local
                    // row — so a refusal holds the wipe like any other note.
                    // Outside Tag Links the facade refuses it (R13).
                    if merged != serverUIDs, !(await writer.setCardUIDs(spoolId: serverId, uids: merged)) {
                        let unlinked = merged.filter { !serverUIDs.contains($0) }
                        let reason = "Tags \(unlinked.joined(separator: ", ")) were not linked to it."
                        notStored.append(MigrationFailure(
                            label: item.label,
                            reason: [reason, writer.errorMessage].compactMap { $0 }.joined(separator: "\n")
                        ))
                    }
                } else if !localUIDs.isEmpty {
                    // The server spool left the list after planning: its tags
                    // were not linked, so the row is kept.
                    notStored.append(MigrationFailure(
                        label: item.label,
                        reason: "Tags \(localUIDs.joined(separator: ", ")) were not linked to it."
                    ))
                }
                stamp(LocalSpool.self, item, serverId: serverId)
                reused += 1
            case .create:
                var draft = spoolDraft(from: spool, filamentIdMap: filamentIdMap)
                // Created without its tags, then linked through the one linking
                // path: a 0.27 server gets Spoolman Tags, never a `card_uids`
                // field it may not have registered (spec 2 §3). A refusal
                // (outside Tag Links, R13) or a failure keeps the row, like any
                // other note.
                let tags = draft.cardUIDs ?? []
                draft.cardUIDs = nil
                if let createdSpool = await writer.addSpool(draft: draft) {
                    stamp(LocalSpool.self, item, serverId: createdSpool.id)
                    created += 1
                    noteNotStored(item.label)
                    if !tags.isEmpty, !(await writer.setCardUIDs(spoolId: createdSpool.id, uids: tags)) {
                        let reason = "Tags \(tags.joined(separator: ", ")) were not linked to it."
                        notStored.append(MigrationFailure(
                            label: item.label,
                            reason: [reason, writer.errorMessage].compactMap { $0 }.joined(separator: "\n")
                        ))
                    }
                } else {
                    failed.append(writeFailure(item.label))
                }
            }
            progress.done += 1
        }

        let result = MigrationResult(
            created: created, reused: reused, failed: failed, skipped: skipped, notStored: notStored
        )
        lastResult = result

        if result.isComplete {
            SpoolKidApp.wipeLocalStore(context)
        }
        return result
    }

    // MARK: - Pre-flight

    /// Which planned filaments the active backend would refuse, and what each
    /// one is missing.
    ///
    /// Runs BEFORE the upload so the review screen can offer to supply the
    /// values, rather than reporting the refusal afterwards to a user with no
    /// way to act on it (device finding, 2026-08-29). Only `.create` rows can
    /// be refused — a `.reuse` writes nothing.
    func blockedFilaments(in plan: MigrationPlan) -> [Int: [FilamentCreateRequirement]] {
        let vendorIdMap = Self.preflightVendorIdMap(plan)
        var blocked: [Int: [FilamentCreateRequirement]] = [:]
        for item in plan.filaments {
            guard item.resolution == .create, let filament = localFilament(localId: item.localId) else {
                continue
            }
            let draft = filamentDraft(from: filament, vendorIdMap: vendorIdMap)
            let missing = writer.missingFilamentRequirements(for: draft)
            if !missing.isEmpty { blocked[item.localId] = missing }
        }
        return blocked
    }

    /// Stand-in id for a vendor the plan will CREATE, so a pre-flight draft can
    /// answer "does this filament have a manufacturer?" before any vendor has
    /// a server id. Never written anywhere: `execute` builds its own map from
    /// the ids the server actually returns, and vendors upload first, so a
    /// filament whose local row names a vendor always has a real id by the time
    /// it is written.
    nonisolated static let plannedVendorPlaceholderId = 0

    /// `@MainActor`, not `nonisolated`: it reads `MigrationItem<Vendor>`, and
    /// `Vendor`'s `Identifiable` conformance is main-actor isolated — the same
    /// reason `MigrationPlan.conflictCount` carries the attribute.
    @MainActor
    static func preflightVendorIdMap(_ plan: MigrationPlan) -> [Int: Int] {
        var map: [Int: Int] = [:]
        for item in plan.vendors {
            switch item.resolution {
            case .reuse(let serverId): map[item.localId] = serverId
            case .create: map[item.localId] = plannedVendorPlaceholderId
            }
        }
        return map
    }

    /// Empties the on-device Library after a partial run — the rows that could
    /// not be uploaded, together with the ones that were and now live on the
    /// server.
    ///
    /// Irreversible, and the caller confirms before calling. This is the same
    /// wipe `execute` performs on a clean run, taken deliberately instead of
    /// automatically: "I don't want the ones that failed" is a decision only
    /// the user can make, and without it a partial run leaves the migration
    /// offer coming back on every launch with no way to answer it.
    func discardLocalLibrary() {
        SpoolKidApp.wipeLocalStore(context)
        lastResult = nil
    }

    // MARK: - Fixing a blocked row

    /// The manufacturers the fix sheet offers, as NAMES: every one on this
    /// iPhone and every one already on the server, deduped by the planner's own
    /// match rule and shown once each.
    ///
    /// Names rather than ids because a manufacturer is one manufacturer whether
    /// it exists locally, on the server, or both — and because name is exactly
    /// what `MigrationPlanner` matches on. Choosing one that exists only on the
    /// server therefore does the right thing without an override channel: the
    /// fix creates the local row, and the next plan resolves it to `.reuse` of
    /// the server's, so nothing is duplicated there.
    ///
    /// The local spelling wins a tie, since that is the row the fix will reuse.
    func manufacturerOptions() -> [String] {
        ManufacturerName.distinct(LocalRepository(context: context).vendors.map(\.name) + writer.vendors.map(\.name))
    }

    /// Supplies what a backend requires, on the LOCAL row, so the correction
    /// survives a retry and stays true of the user's data — and so the plan
    /// picks it up on the next build with no override channel of its own.
    /// Creating the manufacturer here is what makes the fix reachable at all
    /// for the case that prompted it: a Library with no manufacturers, and no
    /// way to add one while a server backend is active.
    ///
    /// Returns an error message, or `nil` on success.
    func applyFilamentFix(_ fix: MigrationFilamentFix) async -> String? {
        let local = LocalRepository(context: context)
        var vendorLocalId: Int?
        let name = fix.manufacturerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty {
            // An existing local row with that name is REUSED, never duplicated —
            // by the planner's rule, so what is reused here is what the planner
            // will match there.
            guard let vendor = await ManufacturerName.resolve(name, in: local.vendors, create: { await local.addVendor(name: $0) }) else {
                return local.errorMessage ?? "The manufacturer could not be created."
            }
            vendorLocalId = vendor.id
        }
        let draft = FilamentDraft(
            name: fix.name,
            vendorId: vendorLocalId.map { .set($0) } ?? .ignore,
            material: fix.material,
            density: fix.density,
            diameter: fix.diameter
        )
        guard await local.updateFilament(id: fix.localId, draft: draft) else {
            return local.errorMessage ?? "The filament could not be updated."
        }
        return nil
    }
}

/// What the fix sheet collected. Only the fields the backend actually asked
/// for are ever non-nil — the sheet renders a control per missing requirement
/// and nothing else, so a fix cannot quietly rewrite a field the row already
/// had.
nonisolated struct MigrationFilamentFix: Equatable, Sendable {
    let localId: Int
    var name: String?
    /// The manufacturer to point the filament at, by name — chosen from
    /// `manufacturerOptions()` (local or already on the server) or typed. An
    /// existing local row with that name is reused; otherwise one is created.
    var manufacturerName: String?
    var material: String?
    var diameter: Double?
    var density: Double?
}

// MARK: - Local row reads

private extension MigrationService {
    // These three `throw` rather than answering `[]` on a failed fetch: an
    // unreadable store and an empty one lead to opposite behaviour, and only
    // one of them is a bug. `buildPlan` is the one caller and turns a throw
    // into "no plan" (M2).

    func unsyncedLocalVendors() throws -> [MigrationLocalVendor] {
        let descriptor = FetchDescriptor<LocalVendor>(
            predicate: #Predicate { $0.serverId == nil }
        )
        return try context.fetch(descriptor).map {
            MigrationLocalVendor(localId: $0.localId, name: $0.name)
        }
    }

    func unsyncedLocalFilaments() throws -> [MigrationLocalFilament] {
        let descriptor = FetchDescriptor<LocalFilament>(
            predicate: #Predicate { $0.serverId == nil }
        )
        return try context.fetch(descriptor).map {
            MigrationLocalFilament(
                localId: $0.localId,
                vendorLocalId: $0.vendor?.localId,
                name: $0.name,
                material: $0.material,
                diameter: $0.diameter,
                weight: $0.weight
            )
        }
    }

    func unsyncedLocalSpools(using localVendors: [MigrationLocalVendor]) throws -> [MigrationLocalSpool] {
        let descriptor = FetchDescriptor<LocalSpool>(
            predicate: #Predicate { $0.serverId == nil }
        )
        return try context.fetch(descriptor).compactMap { spool in
            guard let filament = spool.filament else { return nil }
            let key = FilamentMatchKey(
                manufacturer: filament.vendor?.name,
                name: filament.name,
                material: filament.material,
                diameter: filament.diameter,
                weight: filament.weight
            )
            return MigrationLocalSpool(
                localId: spool.localId,
                filamentLocalId: filament.localId,
                filamentKey: key
            )
        }
    }

    func localVendor(localId: Int) -> LocalVendor? {
        let descriptor = FetchDescriptor<LocalVendor>(
            predicate: #Predicate { $0.localId == localId }
        )
        return try? context.fetch(descriptor).first
    }

    func localFilament(localId: Int) -> LocalFilament? {
        let descriptor = FetchDescriptor<LocalFilament>(
            predicate: #Predicate { $0.localId == localId }
        )
        return try? context.fetch(descriptor).first
    }

    func localSpool(localId: Int) -> LocalSpool? {
        let descriptor = FetchDescriptor<LocalSpool>(
            predicate: #Predicate { $0.localId == localId }
        )
        return try? context.fetch(descriptor).first
    }

    /// `false` only when the save failed.
    func stampServerId<T: PersistentModel>(
        _ type: T.Type,
        localId: Int,
        serverId: Int
    ) -> Bool {
        switch type {
        case is LocalVendor.Type:
            if let row = localVendor(localId: localId) {
                row.serverId = serverId
                return save()
            }
        case is LocalFilament.Type:
            if let row = localFilament(localId: localId) {
                row.serverId = serverId
                return save()
            }
        case is LocalSpool.Type:
            if let row = localSpool(localId: localId) {
                row.serverId = serverId
                return save()
            }
        default:
            break
        }
        return true
    }

    /// Not rolled back on failure, unlike the other writers on this shared
    /// context: what is pending is a true server id, which a later save that
    /// succeeds keeps.
    func save() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            logger.error("Failed to save migration progress: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - Draft builders

private extension MigrationService {
    func vendorDraft(from vendor: LocalVendor) -> VendorDraft {
        VendorDraft(
            name: vendor.name,
            comment: vendor.comment,
            emptySpoolWeight: vendor.emptySpoolWeight,
            externalId: vendor.externalId,
            extra: vendor.extra
        )
    }

    /// Spec 4: a Library filament's links go to the server's filament store
    /// through the writer (the facade refuses outside Tag Links or where there
    /// is no filament store). Any tag not linked is named, so the row is kept.
    private func linkFilamentTags(of filament: LocalFilament, to serverId: Int, label: String) async -> MigrationFailure? {
        let uids = CardUIDsCodec.parse(filament.extra?[CardUIDsCodec.fieldKey])
        guard !uids.isEmpty else { return nil }
        var unlinked: [String] = []
        var reasons: [String] = []
        for uid in uids {
            let reason: String
            switch await writer.linkFilamentTag(filamentId: serverId, uid: uid) {
            case .linked: continue
            case .failed(let message): reason = message
            case .heldBySpool(let id): reason = "Tag \(uid) is linked to spool #\(id)."
            case .heldByFilament(let id): reason = "Tag \(uid) is linked to filament #\(id)."
            }
            unlinked.append(uid)
            if !reasons.contains(reason) { reasons.append(reason) }
        }
        guard !unlinked.isEmpty else { return nil }
        return MigrationFailure(
            label: label,
            reason: (["Tags \(unlinked.joined(separator: ", ")) were not linked to it."] + reasons).joined(separator: "\n")
        )
    }

    func filamentDraft(from filament: LocalFilament, vendorIdMap: [Int: Int]) -> FilamentDraft {
        let vendorServerId: Int? = {
            guard let localId = filament.vendor?.localId else { return nil }
            return vendorIdMap[localId]
        }()
        // Migration only ever CREATES, so a local row that carries no value
        // has nothing to say about the field — `.ignore`, exactly as the old
        // bare nil meant here. Never `.setNil`: clearing a field on a record
        // being created is not a thing. Same rule as `spoolDraft` below.
        return FilamentDraft(
            name: filament.name,
            vendorId: vendorServerId.map { .set($0) } ?? .ignore,
            material: filament.material,
            price: filament.price.map { .set($0) } ?? .ignore,
            density: filament.density,
            diameter: filament.diameter,
            weight: filament.weight.map { .set($0) } ?? .ignore,
            spoolWeight: filament.spoolWeight.map { .set($0) } ?? .ignore,
            articleNumber: filament.articleNumber.map { .set($0) } ?? .ignore,
            comment: filament.comment.map { .set($0) } ?? .ignore,
            extruderTemp: filament.settingsExtruderTemp.map { .set($0) } ?? .ignore,
            bedTemp: filament.settingsBedTemp.map { .set($0) } ?? .ignore,
            colorHex: filament.colorHex,
            multiColorHexes: filament.multiColorHexes.map { .set($0) } ?? .ignore,
            multiColorDirection: filament.multiColorDirection.map { .set($0) } ?? .ignore,
            externalId: filament.externalId.map { .set($0) } ?? .ignore,
            // The Library's filament links (spec 4) travel through
            // `linkFilamentTag`, and TD through its typed draft field (which
            // registers Spoolman's `td` first) — never as an `extra` key a
            // server may refuse.
            extra: filament.extra
                .map { extra in extra.filter { entry in
                    entry.key != CardUIDsCodec.fieldKey && entry.key != TransmissionDistance.fieldKey
                } }
                .flatMap { rest in rest.isEmpty ? nil : rest }
                .map { .set($0) } ?? .ignore,
            transmissionDistance: TransmissionDistance.decode(filament.extra?[TransmissionDistance.fieldKey])
                .map { .set($0) } ?? .ignore
        )
    }

    /// Every tag a Library spool links: its `card_uids` (where the Library
    /// keeps links since spec 2), normalized and de-duplicated. A `card_uid:`
    /// token in `lotNr` is lot text, not a link (2026-10-11).
    static func localTagUIDs(of spool: LocalSpool) -> [String] {
        var seen = Set<String>()
        return CardUIDsCodec.parse(spool.extra?[CardUIDsCodec.fieldKey])
            .map(SpoolMappingService.normalizeUID)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func spoolDraft(from spool: LocalSpool, filamentIdMap: [Int: Int]) -> SpoolDraft {
        let filamentServerId: Int? = {
            guard let localId = spool.filament?.localId else { return nil }
            return filamentIdMap[localId]
        }()
        // The local store keeps `card_uids` in Spoolman's WRAPPED form. Handing
        // that string to the destination inside `extra` wrote it verbatim into
        // FilaMan's `custom_fields`, whose compat layer wraps it a second time
        // on read — so a migrated spool's tag mapping was unreadable to a
        // SpoolLink/Snapmaker U1 client. Lifting it into the typed field lets
        // the destination's payload builder apply its own encoding (F38).
        var extra = spool.extra
        var cardUIDs: [String]?
        if let stored = extra?.removeValue(forKey: CardUIDsCodec.fieldKey) {
            cardUIDs = CardUIDsCodec.parse(stored)
        }
        return SpoolDraft(
            filamentId: filamentServerId,
            firstUsed: spool.firstUsed.flatMap { .set(Self.iso8601.string(from: $0)) } ?? .ignore,
            lastUsed: spool.lastUsed.flatMap { .set(Self.iso8601.string(from: $0)) } ?? .ignore,
            price: spool.price,
            // Migration only ever CREATES, so a local row that carries no
            // weight has nothing to say about the field — `.ignore`, exactly
            // as the old bare nil meant here. Never `.setNil`: clearing a
            // field on a record being created is not a thing.
            //
            // `initialWeight` and `spoolWeight` travel together or not at all
            // (F31): a gross figure with an unstated basis makes FilaMan
            // inherit the filament's default and rewrite the number, so a
            // local row with an initial weight and no spool weight states the
            // basis it actually has — zero.
            initialWeight: spool.initialWeight.map { .set($0) } ?? .ignore,
            spoolWeight: spool.spoolWeight.map { .set($0) }
                ?? (spool.initialWeight != nil ? .set(0) : .ignore),
            remainingWeight: spool.remainingWeight.map { .set($0) } ?? .ignore,
            usedWeight: spool.usedWeight.map { .set($0) } ?? .ignore,
            location: spool.location.map { .set($0) } ?? .ignore,
            lotNr: spool.lotNr.map { .set($0) } ?? .ignore,
            comment: spool.comment.map { .set($0) } ?? .ignore,
            archived: spool.archived,
            extra: extra.map { .set($0) } ?? .ignore,
            cardUIDs: cardUIDs
        )
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

// MARK: - MigrationResolution helper

private extension MigrationResolution {
    var serverId: Int? {
        if case .reuse(let id) = self { return id }
        return nil
    }
}
