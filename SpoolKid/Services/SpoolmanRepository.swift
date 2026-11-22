//
//  SpoolmanRepository.swift
//  SpoolKid
//
//  Purpose: `SpoolDataRepository` backed by the live Spoolman REST API.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// Thin wrapper over the shared `SpoolmanService`. Forwards every call,
/// sourcing `baseUrl` from the configured Spoolman URL (the same UserDefaults
/// key views read via `@AppStorage`) so callers no longer pass it. Behavior is
/// identical to calling the service directly.
@MainActor
final class SpoolmanRepository: SpoolDataRepository {
    private let service: SpoolmanService
    nonisolated let capabilities = BackendCapabilities.spoolman

    init(service: SpoolmanService) {
        self.service = service
    }

    private var baseUrl: String {
        UserDefaults.standard.string(forKey: AppConfig.spoolmanUrlKey) ?? ""
    }

    // MARK: - Reads

    var spools: [Spool] { service.spools }
    var filaments: [Filament] { service.filaments }
    var vendors: [Vendor] { service.vendors }
    var locations: [String] { service.locations }
    var isLoading: Bool { service.isLoading }
    var errorMessage: String? { service.errorMessage }
    nonisolated var lastQuotaError: QuotaError? { nil }

    // MARK: - Fetch

    func fetchSpools() async { await service.fetchSpools(baseUrl: baseUrl) }
    func fetchFilaments() async { await service.fetchFilaments(baseUrl: baseUrl) }
    func fetchVendors() async { await service.fetchVendors(baseUrl: baseUrl) }
    func fetchLocations() async { await service.fetchLocations(baseUrl: baseUrl) }
    func testConnection() async -> Bool { await service.testConnection(baseUrl: baseUrl) }

    var connectionTarget: String { "spoolman|\(ServerAddress.identity(of: baseUrl))" }

    /// Spoolman serves the catalogue its `EXTERNAL_DB_URL` points at, so a
    /// self-hosted fork's entries reach the import picker.
    func fetchFilamentCatalog() async throws -> [SpoolmanDBFilament]? {
        try await service.fetchExternalFilaments(baseUrl: baseUrl)
    }

    /// `healthCheck` rather than `testConnection`: short timeout, and it leaves
    /// `errorMessage` and `spoolman_connection_valid` untouched.
    func checkReachability() async -> BackendReachability {
        await BackendReachability.probing(address: baseUrl) {
            await service.healthCheck(baseUrl: baseUrl)
        }
    }

    // MARK: - Vendors

    @discardableResult
    func addVendor(draft: VendorDraft) async -> Vendor? {
        await service.addVendor(draft: draft, baseUrl: baseUrl)
    }

    @discardableResult
    func addVendor(name: String) async -> Vendor? {
        await service.addVendor(name: name, baseUrl: baseUrl)
    }

    @discardableResult
    func updateVendor(id: Int, draft: VendorDraft) async -> Bool {
        await service.updateVendor(id: id, draft: draft, baseUrl: baseUrl)
    }

    /// Spoolman itself would answer 200 and leave the vendor's filaments with no
    /// vendor, so the refusal is the app's, from a fresh filament list.
    @discardableResult
    func deleteVendor(id: Int) async -> Bool {
        await service.fetchFilaments(baseUrl: baseUrl)
        guard service.errorMessage == nil else { return false }
        let impact = DeletionImpact.forVendors([id], filaments: service.filaments, spools: [])
        guard impact.isEmpty else {
            service.errorMessage = impact.refusalMessage(for: "manufacturer")
            return false
        }
        return await service.deleteVendor(id: id, baseUrl: baseUrl)
    }

    func deleteVendorCascading(id: Int) async -> Bool {
        await service.fetchFilaments(baseUrl: baseUrl)
        guard service.errorMessage == nil else { return false }
        await service.fetchSpools(baseUrl: baseUrl)
        guard service.errorMessage == nil else { return false }
        let impact = DeletionImpact.forVendors([id], filaments: service.filaments, spools: service.spools)
        return await deleteInOrder(target: "manufacturer", impact: impact) {
            await service.deleteVendor(id: id, baseUrl: baseUrl)
        }
    }

    // MARK: - Filaments

    func missingFilamentRequirements(for draft: FilamentDraft) -> [FilamentCreateRequirement] {
        Self.missingRequirements(of: draft)
    }

    /// What `POST /filament` would refuse with a 422, probed 2026-08-27:
    /// `density` and `diameter` are required; name, material and vendor are
    /// not. Asked by migration's pre-flight so such a row is fixable on the
    /// review screen; the form pre-fills both, so it rarely gets this far.
    /// Zero is missing — Spoolman takes neither as a real measurement.
    nonisolated static func missingRequirements(of draft: FilamentDraft) -> [FilamentCreateRequirement] {
        var missing: [FilamentCreateRequirement] = []
        if FilamentTagData.statedMeasurement(draft.density) == nil { missing.append(.density) }
        if FilamentTagData.statedMeasurement(draft.diameter) == nil { missing.append(.diameter) }
        return missing
    }

    @discardableResult
    func addFilament(draft: FilamentDraft) async -> Filament? {
        await service.addFilament(draft: draft, baseUrl: baseUrl)
    }

    @discardableResult
    func updateFilament(id: Int, draft: FilamentDraft) async -> Bool {
        await service.updateFilament(id: id, draft: draft, baseUrl: baseUrl)
    }

    /// Spoolman refuses this itself (403) while spools reference the filament.
    @discardableResult
    func deleteFilament(id: Int) async -> Bool { await service.deleteFilament(id: id, baseUrl: baseUrl) }

    func deleteFilamentCascading(id: Int) async -> Bool {
        await service.fetchSpools(baseUrl: baseUrl)
        guard service.errorMessage == nil else { return false }
        let impact = DeletionImpact.forFilaments([id], spools: service.spools)
        return await deleteInOrder(target: "filament", impact: impact) {
            await service.deleteFilament(id: id, baseUrl: baseUrl)
        }
    }

    /// Spoolman has no transaction and no cascade, so dependents go first —
    /// spools, then filaments, then the record — one request at a time,
    /// stopping at the first failure. A stop leaves `errorMessage` saying what
    /// is already gone, because that cannot be undone.
    private func deleteInOrder(target: String, impact: DeletionImpact, deleteTarget: () async -> Bool) async -> Bool {
        var deletedSpools = 0, deletedFilaments = 0
        func stopped() -> Bool {
            service.errorMessage = Self.cascadeStoppedMessage(
                target: target,
                deletedSpools: deletedSpools, totalSpools: impact.spoolIDs.count,
                deletedFilaments: deletedFilaments, totalFilaments: impact.filamentIDs.count,
                reason: service.errorMessage ?? "\(capabilities.displayName) refused the delete."
            )
            return false
        }
        for spoolID in impact.spoolIDs.sorted() {
            guard await service.deleteSpool(id: spoolID, baseUrl: baseUrl) else { return stopped() }
            deletedSpools += 1
        }
        for filamentID in impact.filamentIDs.sorted() {
            guard await service.deleteFilament(id: filamentID, baseUrl: baseUrl) else { return stopped() }
            deletedFilaments += 1
        }
        guard await deleteTarget() else { return stopped() }
        service.errorMessage = nil
        return true
    }

    nonisolated static func cascadeStoppedMessage(
        target: String,
        deletedSpools: Int, totalSpools: Int,
        deletedFilaments: Int, totalFilaments: Int,
        reason: String
    ) -> String {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = trimmed.hasSuffix(".") ? trimmed : trimmed + "."
        func progress(_ done: Int, _ total: Int, _ noun: String) -> String? {
            done > 0 ? "\(done) of \(total) \(noun)\(total == 1 ? "" : "s")" : nil
        }
        let gone = [progress(deletedSpools, totalSpools, "spool"), progress(deletedFilaments, totalFilaments, "filament")]
            .compactMap { $0 }
        guard !gone.isEmpty else { return "\(sentence) Nothing was deleted." }
        return "\(sentence) Already deleted: \(gone.joined(separator: " and ")); the \(target) was not deleted."
    }

    // MARK: - Spools

    @discardableResult
    func addSpool(draft: SpoolDraft) async -> Spool? {
        await service.addSpool(draft: draft, baseUrl: baseUrl)
    }

    @discardableResult
    func updateSpool(id: Int, draft: SpoolDraft) async -> Bool {
        await service.updateSpool(id: id, draft: draft, baseUrl: baseUrl)
    }

    @discardableResult
    func deleteSpool(id: Int) async -> Bool { await service.deleteSpool(id: id, baseUrl: baseUrl) }

    @discardableResult
    func setSpoolArchived(id: Int, archived: Bool) async -> Bool {
        await service.setSpoolArchived(id: id, archived: archived, baseUrl: baseUrl)
    }

    // MARK: - UID mapping

    /// `card_uids` everywhere; Spoolman Tags too once the server has said it
    /// is 0.27.0 or newer.
    var availableTagStores: Set<TagStore> {
        service.supportsNativeTags(at: baseUrl) ? [.cardUIDs, .spoolmanTags] : [.cardUIDs]
    }

    var tagStoresKnown: Bool { service.knowsServer(at: baseUrl) }

    func findSpool(byCardUID uid: String) -> Spool? {
        service.findSpool(byCardUID: uid)
    }

    /// Below Spoolman 0.27 this is one `card_uids` PATCH, as it always was.
    /// With native tags it runs a `TagWritePlan`: links into the stores
    /// `TagIdentityPolicy` names (none outside Tag Links — removals only),
    /// removals out of every store.
    @discardableResult
    func setCardUIDs(spoolId: Int, uids: [String]) async -> Bool {
        guard availableTagStores.contains(.spoolmanTags) else {
            return await service.setCardUIDs(spoolId: spoolId, uids: uids, baseUrl: baseUrl)
        }
        guard let spool = await cachedSpool(spoolId) else { return false }
        let plan = TagWritePlan.make(
            spool: spool,
            desired: uids,
            targets: TagIdentityPolicy.current(available: availableTagStores).linkTargets,
            nativeHolder: { nativeHolder(of: $0, excluding: spoolId) }
        )
        return await execute(plan, on: spool)
    }

    // MARK: - Native tags

    /// The spool as last read; fetched once when the cache does not have it.
    private func cachedSpool(_ id: Int) async -> Spool? {
        if let spool = service.spools.first(where: { $0.id == id }) { return spool }
        await service.refetchSpool(id: id, baseUrl: baseUrl)
        guard let spool = service.spools.first(where: { $0.id == id }) else {
            service.errorMessage = "Spool #\(id) could not be found in Spoolman."
            return nil
        }
        return spool
    }

    private func nativeHolder(of uid: String, excluding spoolId: Int) -> TagWritePlan.NativeTagHolder? {
        if let other = service.spools.first(where: { $0.id != spoolId && $0.nativeTagUIDs.contains(uid) }) {
            return .spool(id: other.id)
        }
        if let filament = service.filaments.first(where: { $0.nativeTagUIDs.contains(uid) }) {
            return .filament(id: filament.id, label: filament.listTitle)
        }
        return nil
    }

    private func filamentLabel(_ id: Int) -> String {
        service.filaments.first { $0.id == id }?.listTitle ?? "#\(id)"
    }

    /// Runs a plan. Every call is idempotent, so `false` plus a retry
    /// converges; the message says what landed.
    private func execute(_ plan: TagWritePlan.Result, on spool: Spool) async -> Bool {
        var landed = 0
        var failures: [String] = []
        var touched: Set<Int> = [spool.id]

        for skip in plan.skips {
            if case .heldByFilament(let uid, let label, true) = skip {
                failures.append("Tag \(uid) identifies the filament \(label) in Spoolman.")
            }
        }

        for op in plan.ops {
            switch op {
            case .link(let uid, let moveFrom):
                switch await service.linkTag(spoolId: spool.id, uid: uid, baseUrl: baseUrl) {
                case .linked:
                    landed += 1
                case .heldBySpool(let holder) where moveFrom != nil:
                    // The caller is moving this tag here; whoever holds it
                    // now lets go first (paxx12's 409 rule).
                    touched.insert(holder)
                    if case .failed(let why) = await service.unlinkTag(spoolId: holder, uid: uid, baseUrl: baseUrl) {
                        failures.append(why)
                    } else if case .linked = await service.linkTag(spoolId: spool.id, uid: uid, baseUrl: baseUrl) {
                        landed += 1
                    } else {
                        failures.append("Tag \(uid) could not be linked to this spool in Spoolman Tags.")
                    }
                case .heldBySpool(let holder):
                    failures.append("Tag \(uid) is now linked to spool #\(holder) in Spoolman.")
                case .heldByFilament(let id):
                    failures.append("Tag \(uid) identifies the filament \(filamentLabel(id)) in Spoolman.")
                case .failed(let why):
                    failures.append(why)
                }
            case .unlink(let uid):
                if case .failed(let why) = await service.unlinkTag(spoolId: spool.id, uid: uid, baseUrl: baseUrl) {
                    failures.append(why)
                } else {
                    landed += 1
                }
            case .setCardUIDs(let list):
                if await service.setCardUIDs(spoolId: spool.id, uids: list, baseUrl: baseUrl) {
                    landed += 1
                } else {
                    failures.append("card_uids could not be updated: \(service.errorMessage ?? "unknown error")")
                }
            }
        }

        for id in touched.sorted() {
            await service.refetchSpool(id: id, baseUrl: baseUrl)
        }
        guard failures.isEmpty else {
            service.errorMessage = Self.nativeWriteFailureMessage(landed: landed, failures: failures)
            return false
        }
        return true
    }

    /// The tag reader API arrived with native tags, in 0.27.0.
    var supportsTagScanReporting: Bool { service.supportsNativeTags(at: baseUrl) }

    /// Spoolman 0.27's own filament tags (spec 4).
    var filamentTagStore: TagStore? { availableTagStores.contains(.spoolmanTags) ? .spoolmanTags : nil }

    func linkFilamentTag(filamentId: Int, uid: String) async -> SpoolmanService.TagLinkOutcome {
        guard filamentTagStore != nil else {
            return .failed("This Spoolman can't link a tag to a filament. Spoolman 0.27 or later can.")
        }
        let outcome = await service.linkFilamentTag(filamentId: filamentId, uid: uid, baseUrl: baseUrl)
        // Owner checks read the cached filaments; the link must show there.
        if outcome == .linked { await service.fetchFilaments(baseUrl: baseUrl) }
        return outcome
    }

    func unlinkFilamentTag(filamentId: Int, uid: String) async -> Bool {
        guard filamentTagStore != nil else { return false }
        if case .failed(let message) = await service.unlinkFilamentTag(filamentId: filamentId, uid: uid, baseUrl: baseUrl) {
            // Kept, so the caller shows Spoolman's reason rather than an
            // older message.
            service.errorMessage = message
            return false
        }
        await service.fetchFilaments(baseUrl: baseUrl)
        return true
    }

    func reportTagScan(_ report: TagScanReport) async -> TagScanReportOutcome {
        guard supportsTagScanReporting else { return .unsupported }
        return await service.reportTagScan(report, baseUrl: baseUrl)
    }

    /// One DELETE per linked tag — Spoolman has no bulk endpoint — then a
    /// fresh fetch, so the cache shows what the server now holds.
    func deleteSpoolmanTagLinks() async -> TagBulkDeleteResult {
        guard availableTagStores.contains(.spoolmanTags) else { return TagBulkDeleteResult() }
        var result = TagBulkDeleteResult()
        for spool in service.spools {
            for uid in spool.nativeTagUIDs {
                switch await service.unlinkTag(spoolId: spool.id, uid: uid, baseUrl: baseUrl) {
                case .unlinked:
                    result.deleted += 1
                case .failed(let why):
                    result.failures.append("\(spool.listTitle): \(why)")
                }
            }
        }
        await service.fetchSpools(baseUrl: baseUrl)
        return result
    }

    nonisolated static func nativeWriteFailureMessage(landed: Int, failures: [String]) -> String {
        let reasons = failures.joined(separator: " ")
        return landed > 0 ? "Partly saved: \(reasons) Saving again finishes it." : reasons
    }

    /// `POST /api/v1/field/spool/card_uids`, guarded by a read of the existing
    /// field list. Was called straight from `ContentView` until 2026-08-24,
    /// which is why it stayed Spoolman-only: a view reaching past the
    /// repository into one vendor's service cannot be given a second backend.
    @discardableResult
    func ensureCardUIDsField() async -> Bool {
        do {
            try await service.ensureCardUIDsField(baseUrl: baseUrl)
            return true
        } catch {
            // `errorMessage` here is a read-through of the service's, so the
            // message has to be set where it is read from.
            service.errorMessage = error.localizedDescription
            return false
        }
    }

    /// `DELETE /api/v1/field/spool/card_uids` — one call that removes the field
    /// definition and every spool's stored value.
    @discardableResult
    func deleteCardUIDsField() async -> Bool {
        await service.deleteCardUIDsField(baseUrl: baseUrl)
    }

    // MARK: - Locations

    /// Spoolman's `/api/v1/location` returns bare strings derived from spools;
    /// there is no entity and no create endpoint. The registry holds the name
    /// until a spool assignment puts it on the server.
    @discardableResult
    func addLocation(name: String) async -> LocationCreateOutcome {
        LocationCreateOutcome.precheck(name: name, existing: locations) ?? .registeredOnDeviceOnly
    }

    @discardableResult
    func renameLocation(currentName: String, newName: String) async -> Bool {
        await service.renameLocation(currentName: currentName, newName: newName, baseUrl: baseUrl)
    }

    @discardableResult
    func deleteLocation(_ name: String) async -> Bool {
        await service.deleteLocation(name, baseUrl: baseUrl)
    }
}
