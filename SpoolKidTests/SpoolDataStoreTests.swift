//
//  SpoolDataStoreTests.swift
//  SpoolKidTests
//
//  Purpose: Covers the SpoolDataStore facade — backend selection seam, published-
//  array refresh after mutations, and quota-error surfacing through a local-backed
//  store.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import SwiftData
import Testing
@testable import SpoolKid

@MainActor
struct SpoolDataStoreTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: config
        )
        return ModelContext(container)
    }

    // MARK: - Spool status options

    /// A spool form can open before any spool fetch (from the scan hub, say),
    /// and an empty list hides FilaMan's Status picker. The form asks the
    /// store to load it; the store asks the backend only while it is empty.
    @Test func statusOptionsLoadOnDemandOnlyWhileEmpty() async throws {
        let writer = MockMigrationWriter(capabilities: .filaman)
        writer.spoolStatusOptionsStub = [
            FilaManSpoolStatus.Option(id: 1, key: "active", label: "Active", sortOrder: 0)
        ]
        let store = SpoolDataStore(repository: writer)
        #expect(store.spoolStatusOptions.isEmpty)

        await store.loadSpoolStatusOptionsIfNeeded()
        #expect(store.spoolStatusOptions.map(\.key) == ["active"])

        await store.loadSpoolStatusOptionsIfNeeded()
        #expect(writer.fetchSpoolStatusOptionsCalls == 1)
    }

    /// The protocol's default answers "no catalogue", so a facade that took it
    /// would hide Spoolman's configured catalogue behind the public one.
    @Test func filamentCatalogIsForwardedNotDefaulted() async throws {
        let writer = MockMigrationWriter()
        let entry = SpoolmanDBFilament(
            id: "fork_pla_red", manufacturer: "Fork", name: "Red", material: "PLA",
            spoolType: nil, density: 1.24, weight: nil, spoolWeight: nil, diameter: 1.75,
            colorHex: nil, extruderTemp: nil, bedTemp: nil
        )
        writer.filamentCatalogResult = .success([entry])
        let store = SpoolDataStore(repository: writer)

        #expect(try await store.fetchFilamentCatalog() == [entry])
    }

    // MARK: - capabilities.isOnDeviceStorage

    @Test func localRepositorySetsCapabilitiesIsOnDeviceStorageTrue() throws {
        let context = try makeContext()
        let local = LocalRepository(context: context)
        let store = SpoolDataStore(repository: local)
        #expect(store.capabilities.isOnDeviceStorage == true)
    }

    @Test func spoolmanRepositorySetsCapabilitiesIsOnDeviceStorageFalse() throws {
        let service = SpoolmanService()
        let repo = SpoolmanRepository(service: service)
        let store = SpoolDataStore(repository: repo)
        #expect(store.capabilities.isOnDeviceStorage == false)
    }

    // MARK: - Selection seam

    @Test func spoolmanKindSelectsSpoolmanRepository() throws {
        let service = SpoolmanService()
        let context = try makeContext()
        let repo = SpoolDataStore.selectRepository(
            kind: .spoolman,
            spoolmanService: service,
            filaManService: FilaManService(),
            context: context
        )
        #expect(repo is SpoolmanRepository)
    }

    @Test func localKindSelectsLocalRepository() throws {
        let service = SpoolmanService()
        let context = try makeContext()
        let repo = SpoolDataStore.selectRepository(
            kind: .local,
            spoolmanService: service,
            filaManService: FilaManService(),
            context: context
        )
        #expect(repo is LocalRepository)
    }

    /// Task 16b: closes the coverage gap Task 10 deferred — `.filaman` used
    /// to route to `LocalRepository` as a placeholder (a user who picked
    /// FilaMan silently got their local Library instead); this pins that it
    /// now resolves to the real `FilaManRepository`.
    @Test func filamanKindSelectsFilaManRepository() throws {
        let service = SpoolmanService()
        let context = try makeContext()
        let repo = SpoolDataStore.selectRepository(
            kind: .filaman,
            spoolmanService: service,
            filaManService: FilaManService(),
            context: context
        )
        #expect(repo is FilaManRepository)
    }

    // MARK: - Mutation refreshes published arrays

    @Test func mutationUpdatesPublishedArrays() async throws {
        let context = try makeContext()
        let local = LocalRepository(context: context)
        let store = SpoolDataStore(repository: local)
        #expect(store.vendors.isEmpty)

        let created = await store.addVendor(name: "TestVendor")
        #expect(created != nil)
        #expect(store.vendors.count == 1)
        #expect(store.vendors.first?.name == "TestVendor")
    }

    // MARK: - Quota error surfacing

    @Test func quotaRefusalSurfacesLastQuotaError() async throws {
        let context = try makeContext()
        let local = LocalRepository(context: context, quotaLimit: 15)
        let store = SpoolDataStore(repository: local)

        for i in 1...15 {
            let created = await store.addVendor(name: "v\(i)")
            #expect(created != nil)
        }
        #expect(store.vendors.count == 15)
        #expect(store.lastQuotaError == nil)

        let overflow = await store.addVendor(name: "v16")
        #expect(overflow == nil)
        #expect(store.vendors.count == 15)
        #expect(store.lastQuotaError == QuotaError(entity: .vendors, limit: 15))
    }

    @Test func filamentQuotaRefusalSurfacesLastQuotaError() async throws {
        let context = try makeContext()
        let local = LocalRepository(context: context, quotaLimit: 15)
        let store = SpoolDataStore(repository: local)

        for i in 1...15 {
            let draft = FilamentDraft(name: "f\(i)")
            let created = await store.addFilament(draft: draft)
            #expect(created != nil)
        }
        #expect(store.filaments.count == 15)
        #expect(store.lastQuotaError == nil)

        let overflow = await store.addFilament(draft: FilamentDraft(name: "f16"))
        #expect(overflow == nil)
        #expect(store.filaments.count == 15)
        #expect(store.lastQuotaError == QuotaError(entity: .filaments, limit: 15))
    }

    @Test func spoolQuotaRefusalSurfacesLastQuotaError() async throws {
        let context = try makeContext()
        let local = LocalRepository(context: context, quotaLimit: 15)
        let store = SpoolDataStore(repository: local)

        let filament = await store.addFilament(draft: FilamentDraft(name: "testFilament"))
        #expect(filament != nil)
        guard let filamentId = filament?.id else {
            Issue.record("Failed to create test filament")
            return
        }

        for _ in 1...15 {
            let draft = SpoolDraft(filamentId: filamentId)
            let created = await store.addSpool(draft: draft)
            #expect(created != nil)
        }
        #expect(store.spools.count == 15)
        #expect(store.lastQuotaError == nil)

        let overflow = await store.addSpool(draft: SpoolDraft(filamentId: filamentId))
        #expect(overflow == nil)
        #expect(store.spools.count == 15)
        #expect(store.lastQuotaError == QuotaError(entity: .spools, limit: 15))
    }

    // MARK: - Bulk actions

    @Test func deletionImpactForVendorsReadsTheBackendsCurrentRecords() async throws {
        let context = try makeContext()
        let store = SpoolDataStore(repository: LocalRepository(context: context))
        let vendor = try #require(await store.addVendor(name: "V"))
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "F", vendorId: .set(vendor.id))))
        let spool = try #require(await store.addSpool(draft: SpoolDraft(filamentId: filament.id)))
        _ = await store.setSpoolArchived(id: spool.id, archived: true)

        let impact = try #require(await store.deletionImpact(vendorIDs: [vendor.id]))
        #expect(impact.filamentIDs == [filament.id])
        #expect(impact.spoolIDs == [spool.id])
        #expect(impact.archivedSpoolCount == 1)
    }

    @Test func deletionImpactForFilamentsCountsItsSpools() async throws {
        let context = try makeContext()
        let store = SpoolDataStore(repository: LocalRepository(context: context))
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "F")))
        let spool = try #require(await store.addSpool(draft: SpoolDraft(filamentId: filament.id)))

        let impact = try #require(await store.deletionImpact(filamentIDs: [filament.id]))
        #expect(impact.spoolIDs == [spool.id])
    }

    /// A count that could not be made must not be reported as "nothing depends
    /// on this" — that would delete a filament's spools' worth of dependents
    /// without ever showing them.
    @Test func deletionImpactIsNilWhenTheFetchFails() async throws {
        let repo = MockMigrationWriter(fetchSpoolsError: "Could not connect to the server")
        let store = SpoolDataStore(repository: repo)

        #expect(await store.deletionImpact(filamentIDs: [1]) == nil)
        #expect(store.errorMessage == "Could not connect to the server")
    }

    @Test func aCascadingDeleteRefreshesTheStoreAndCountsOneWrite() async throws {
        let context = try makeContext()
        let store = SpoolDataStore(repository: LocalRepository(context: context))
        let vendor = try #require(await store.addVendor(name: "V"))
        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "F", vendorId: .set(vendor.id))))
        _ = await store.addSpool(draft: SpoolDraft(filamentId: filament.id))

        let before = store.writeCount
        #expect(await store.deleteVendorCascading(id: vendor.id))
        #expect(store.vendors.isEmpty)
        #expect(store.filaments.isEmpty)
        #expect(store.spools.isEmpty)
        #expect(store.writeCount == before + 1)
    }

    @Test func archiveSpoolsArchivesAllSelectedAndReportsSuccess() async throws {
        let context = try makeContext()
        let store = SpoolDataStore(repository: LocalRepository(context: context))
        let v = await store.addVendor(name: "V")
        let f = await store.addFilament(draft: FilamentDraft(name: "F", vendorId: v.map { .set($0.id) } ?? .ignore))
        let s1 = try #require(await store.addSpool(draft: SpoolDraft(filamentId: f?.id))?.id)
        let s2 = try #require(await store.addSpool(draft: SpoolDraft(filamentId: f?.id))?.id)

        let result = await store.archiveSpools(ids: [s1, s2])

        #expect(result.succeeded == 2)
        #expect(result.failed == 0)
        #expect(result.isCompleteSuccess)
        #expect(store.spools.filter { $0.archived == true }.count == 2)
    }

    // MARK: - unlinkTag writes only what SpoolKid may write

    private static func mappedSpool(cardUIDs: [String], lotNr: String? = nil, rfidUID: String? = nil) -> Spool {
        Spool(
            id: 7, filament: Filament(id: 1, name: "White PLA", material: "PLA", vendor: nil), lotNr: lotNr,
            extra: ["card_uids": CardUIDsCodec.encode(cardUIDs)],
            rfidUID: rfidUID, statusId: nil, externalId: nil, purchaseDate: nil
        )
    }

    /// What the spool keeps was built from `mappedCardUIDs`, so unlinking one
    /// tag copied FilaMan's `rfid_uid` into `card_uids` (final review FR-2).
    @Test func unlinkingATagNeverCopiesTheRFIDUIDIntoCardUIDs() async {
        let writer = MockMigrationWriter(
            serverSpools: [Self.mappedSpool(cardUIDs: ["04AA", "04BB"], rfidUID: "04CC")], capabilities: .filaman
        )
        let store = SpoolDataStore(repository: writer)

        #expect(await store.unlinkTag(uid: "04aa"))
        #expect(writer.setCardUIDsCalls.map(\.spoolId) == [7])
        #expect(writer.setCardUIDsCalls.map(\.uids) == [["04BB"]])
    }

    // MARK: - Outside Tag Links nothing creates a link (R13)

    /// A connected server that keeps links, in Spool ID mode.
    private static func spoolIDStore(_ writer: MockMigrationWriter) -> SpoolDataStore {
        SpoolDataStore(
            repository: writer,
            defaults: isolatedDefaults([
                AppConfig.tagIdentityModeKey: "spoolID", AppConfig.filamanConnectionValidKey: true,
            ])
        )
    }

    /// The facade every caller uses refuses a write that ADDS a tag while the
    /// mode writes no links, and says why.
    @Test func outsideTagLinksAWriteThatAddsATagIsRefused() async {
        let writer = Self.filaManDouble(spools: [Self.mappedSpool(cardUIDs: ["04AA"])])
        let store = Self.spoolIDStore(writer)
        #expect(!store.tagIdentity.writesLinks)

        #expect(await store.setCardUIDs(spoolId: 7, uids: ["04AA", "04bb"]) == false)
        #expect(writer.setCardUIDsCalls.isEmpty)
        #expect(store.errorMessage == TagStoreText.linksOffNote(connectionRowLabel: "FilaMan"))
    }

    /// Links are read in every mode, so a wrong one must stay removable.
    @Test func outsideTagLinksARemovalStillRuns() async {
        let writer = Self.filaManDouble(spools: [Self.mappedSpool(cardUIDs: ["04AA", "04BB"])])
        let store = Self.spoolIDStore(writer)

        #expect(await store.setCardUIDs(spoolId: 7, uids: ["04aa"]))
        #expect(writer.setCardUIDsCalls.map(\.uids) == [["04aa"]])
    }

    // MARK: - Tag identity through the defaults seam

    private static func isolatedDefaults(_ values: [String: Any] = [:]) -> UserDefaults {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        for (key, value) in values { defaults.set(value, forKey: key) }
        return defaults
    }

    /// A FilaMan-like double: one tag store, fixed and known.
    private static func filaManDouble(spools: [Spool] = []) -> MockMigrationWriter {
        let writer = MockMigrationWriter(serverSpools: spools, capabilities: .filaman)
        writer.availableTagStores = [.cardUIDs]
        return writer
    }

    /// A server's stores count only while its connection is validated.
    @Test func aServerLinksOnlyWhileItsConnectionIsValid() {
        let offline = SpoolDataStore(
            repository: Self.filaManDouble(),
            defaults: Self.isolatedDefaults([AppConfig.tagIdentityModeKey: "tagLinks"])
        )
        #expect(offline.tagIdentity.linkTargets.isEmpty)

        let online = SpoolDataStore(
            repository: Self.filaManDouble(),
            defaults: Self.isolatedDefaults([
                AppConfig.tagIdentityModeKey: "tagLinks", AppConfig.filamanConnectionValidKey: true,
            ])
        )
        #expect(online.tagIdentity.linkTargets == [.cardUIDs])
    }

    @Test func inTagLinksAWriteThatAddsATagRuns() async {
        let writer = Self.filaManDouble(spools: [Self.mappedSpool(cardUIDs: ["04AA"])])
        let store = SpoolDataStore(
            repository: writer,
            defaults: Self.isolatedDefaults([
                AppConfig.tagIdentityModeKey: "tagLinks", AppConfig.filamanConnectionValidKey: true,
            ])
        )

        #expect(await store.setCardUIDs(spoolId: 7, uids: ["04AA", "04BB"]))
        #expect(writer.setCardUIDsCalls.map(\.uids) == [["04AA", "04BB"]])
    }

    /// Spoolman's stores are not an answer until its version is read; the
    /// upgrade decision waits for that, then runs once.
    @Test func theUpgradeWaitsForAServersStoresThenDecides() async {
        let writer = MockMigrationWriter()
        writer.availableTagStores = [.cardUIDs]
        writer.tagStoresKnown = false
        let defaults = Self.isolatedDefaults([
            AppConfig.hasCompletedWelcomeKey: true, AppConfig.spoolmanConnectionValidKey: true,
        ])
        let store = SpoolDataStore(repository: writer, defaults: defaults)
        #expect(defaults.string(forKey: AppConfig.tagIdentityModeKey) == nil)
        #expect(store.tagIdentity.mode == .spoolID)

        // The server answers: 0.27, Spoolman Tags on by default.
        writer.availableTagStores = [.cardUIDs, .spoolmanTags]
        writer.tagStoresKnown = true
        _ = await store.testConnection()

        #expect(defaults.string(forKey: AppConfig.tagIdentityModeKey) == "tagLinks")
        #expect(defaults.bool(forKey: AppConfig.tagIdentityExplanationPendingKey))
        #expect(store.tagIdentity.linkTargets == [.spoolmanTags])
    }

    /// A Library upgrader whose SpoolLink switch is still on from an earlier
    /// server only ever wrote spool IDs, and keeps them (final review I3).
    @Test func aLibraryUpgraderWithALeftoverSpoolLinkSwitchKeepsSpoolID() {
        let defaults = Self.isolatedDefaults([
            AppConfig.hasCompletedWelcomeKey: true, AppConfig.spoolmanPersistCardUIDKey: true,
        ])
        let store = SpoolDataStore(repository: MockMigrationWriter(capabilities: .local), defaults: defaults)

        #expect(defaults.string(forKey: AppConfig.tagIdentityModeKey) == "spoolID")
        #expect(defaults.bool(forKey: AppConfig.tagIdentityExplanationPendingKey) == false)
        #expect(store.tagIdentity.mode == .spoolID)
    }

    /// Spec 2: through the store, a Library upgrader who wrote no spool IDs
    /// is decided onto Tag Links, with no explanation owed.
    @Test func aLibraryUpgraderWhoWroteNoSpoolIDsLandsOnTagLinks() {
        let writer = MockMigrationWriter(capabilities: .local)
        writer.availableTagStores = [.cardUIDs]
        let defaults = Self.isolatedDefaults([
            AppConfig.hasCompletedWelcomeKey: true, AppConfig.legacyWriteSpoolIdKey: false,
        ])
        let store = SpoolDataStore(repository: writer, defaults: defaults)

        #expect(defaults.string(forKey: AppConfig.tagIdentityModeKey) == "tagLinks")
        #expect(defaults.bool(forKey: AppConfig.tagIdentityExplanationPendingKey) == false)
        #expect(store.tagIdentity.linkTargets == [.cardUIDs])
    }

    // MARK: - Tag scan reporting (spec 3)

    /// Forwarded, never defaulted: the default answers "unsupported", which
    /// on Spoolman 0.27 would silently report nothing.
    @Test func scanReportsAreForwarded() async {
        let writer = MockMigrationWriter()
        writer.supportsTagScanReporting = true
        let store = SpoolDataStore(repository: writer, defaults: Self.isolatedDefaults())
        let report = TagScanReport(uid: "04AABBCC", readerId: "spoolkid-0a1b2c3d", name: "Bench")

        #expect(store.supportsTagScanReporting)
        #expect(await store.reportTagScan(report) == .reported)
        #expect(writer.tagScanReports == [report])
    }

    /// The Library has no tag reader API.
    @Test func theLibraryDoesNotReportScans() async throws {
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SpoolDataStore(
            repository: LocalRepository(context: ModelContext(container)), defaults: Self.isolatedDefaults()
        )
        #expect(!store.supportsTagScanReporting)
        #expect(await store.reportTagScan(TagScanReport(uid: "04AA", readerId: "spoolkid-0a1b2c3d", name: "x")) == .unsupported)
    }

    // MARK: - card_uids provisioning (I1)

    /// Before Spoolman's version is read a 0.27 server looks single-store, and
    /// Tag Links there would register `card_uids` even with SpoolLink off —
    /// on every cold launch, undoing "Delete card_uids".
    @Test func provisioningWaitsUntilTheServersStoresAreKnown() async {
        let writer = MockMigrationWriter()
        writer.availableTagStores = [.cardUIDs]
        writer.tagStoresKnown = false
        let store = SpoolDataStore(
            repository: writer,
            defaults: Self.isolatedDefaults([
                AppConfig.tagIdentityModeKey: "tagLinks", AppConfig.spoolmanConnectionValidKey: true,
            ])
        )
        #expect(store.tagIdentity.linkTargets == [.cardUIDs])
        #expect(!store.needsCardUIDsFieldProvisioning)

        // 0.27 answers; Spoolman Tags only, so still nothing to register.
        writer.availableTagStores = [.cardUIDs, .spoolmanTags]
        writer.tagStoresKnown = true
        _ = await store.testConnection()
        #expect(store.tagIdentity.linkTargets == [.spoolmanTags])
        #expect(!store.needsCardUIDsFieldProvisioning)
    }

    /// The spool fetch reads the version, then awaits the spools before the
    /// facade refreshes. In that window the stores are known but the cached
    /// policy is not: the gate must read the stores the repository has now,
    /// or a 0.27 server with SpoolLink off gets `card_uids` registered on
    /// every cold launch (final re-review, I1).
    @Test func provisioningReadsTheStoresTheServerHasNowNotTheCachedPolicy() {
        let writer = MockMigrationWriter()
        writer.availableTagStores = [.cardUIDs]
        writer.tagStoresKnown = false
        let store = SpoolDataStore(
            repository: writer,
            defaults: Self.isolatedDefaults([
                AppConfig.tagIdentityModeKey: "tagLinks", AppConfig.spoolmanConnectionValidKey: true,
            ])
        )

        // 0.27 answers mid-fetch; the facade has not refreshed yet.
        writer.availableTagStores = [.cardUIDs, .spoolmanTags]
        writer.tagStoresKnown = true
        #expect(!store.needsCardUIDsFieldProvisioning)
    }

    /// Below 0.27 the same read leaves the policy unchanged, and the gate
    /// opens at once: Tag Links needs the field there.
    @Test func provisioningOpensAsSoonAsASingleStoreServerAnswers() {
        let writer = MockMigrationWriter()
        writer.availableTagStores = [.cardUIDs]
        writer.tagStoresKnown = false
        let store = SpoolDataStore(
            repository: writer,
            defaults: Self.isolatedDefaults([
                AppConfig.tagIdentityModeKey: "tagLinks", AppConfig.spoolmanConnectionValidKey: true,
            ])
        )
        #expect(!store.needsCardUIDsFieldProvisioning)

        writer.tagStoresKnown = true
        #expect(store.needsCardUIDsFieldProvisioning)
    }

    @Test func provisioningRunsOnceLinksAreKnownToGoToCardUIDs() {
        let writer = MockMigrationWriter()
        writer.availableTagStores = [.cardUIDs]
        let store = SpoolDataStore(
            repository: writer,
            defaults: Self.isolatedDefaults([
                AppConfig.tagIdentityModeKey: "tagLinks", AppConfig.spoolmanConnectionValidKey: true,
            ])
        )
        #expect(store.needsCardUIDsFieldProvisioning)
    }

    /// A `lot_nr` token is lot text: unlinking never carries it into `card_uids`.
    @Test func unlinkingATagNeverCarriesALotNrToken() async {
        let writer = MockMigrationWriter(
            serverSpools: [Self.mappedSpool(cardUIDs: ["04AA"], lotNr: "card_uid:04bb")]
        )
        let store = SpoolDataStore(repository: writer)

        #expect(await store.unlinkTag(uid: "04AA"))
        #expect(writer.setCardUIDsCalls.map(\.uids) == [[]])
    }

    // MARK: - Save notices (I4): a caveat must not be replaced before it is seen

    /// The defect: nested forms let a second write post its caveat while the
    /// first is still on screen and unread, and replacing it destroys the only
    /// report that a write half-failed.
    @Test func aSecondCaveatIsAddedRatherThanReplacingAnUnreadFirst() throws {
        let context = try makeContext()
        let store = SpoolDataStore(repository: LocalRepository(context: context))

        store.postSaveNotice("Colour — not saved.", record: "Filament · PLA Silk GOLD")
        store.postSaveNotice("Location — not created.", record: "Spool #4")

        let notice = try #require(store.saveNotice)
        #expect(notice.entries.map(\.message) == ["Colour — not saved.", "Location — not created."])
        // Each note keeps the record it is about, which one accumulated string
        // had nowhere to store (device finding 4.2.1).
        #expect(notice.entries.map(\.record) == ["Filament · PLA Silk GOLD", "Spool #4"])
    }

    @Test func dismissingANoticeClearsEverythingItAccumulated() throws {
        let context = try makeContext()
        let store = SpoolDataStore(repository: LocalRepository(context: context))

        store.postSaveNotice("first", record: "Spool #1")
        store.postSaveNotice("second", record: "Spool #2")
        store.clearSaveNotice()

        #expect(store.saveNotice == nil)
    }


    // MARK: - Connection flags

    @Test func eachServerBackendReadsItsOwnConnectionFlag() {
        // FilaMan's validity lives in its own key; a gate that only ever read
        // Spoolman's left every FilaMan path dead (Task 19b).
        #expect(BackendCapabilities.spoolman.connectionValidKey == AppConfig.spoolmanConnectionValidKey)
        #expect(BackendCapabilities.filaman.connectionValidKey == AppConfig.filamanConnectionValidKey)
        #expect(BackendCapabilities.local.connectionValidKey == nil)
    }

    // MARK: - Reachability forwarding

    @Test func theStoreForwardsReachabilityToItsRepository() async throws {
        let context = try makeContext()
        let store = SpoolDataStore(repository: LocalRepository(context: context))

        // The Library tab asks the store, never a concrete backend — so this
        // has to be a real forward, not a hardcoded answer.
        #expect(await store.checkReachability() == .alwaysAvailable)
        #expect(store.connectionTarget == LocalRepository(context: context).connectionTarget)
    }

    @Test func eachBackendProbesItsOwnTarget() throws {
        let context = try makeContext()
        let spoolman = SpoolmanRepository(service: SpoolmanService())
        let filaman = FilaManRepository(service: FilaManService())
        let local = LocalRepository(context: context)

        // A shared or copy-pasted target would make the tab's stale-answer guard
        // accept a verdict about a different server.
        let targets = Set([spoolman.connectionTarget, filaman.connectionTarget, local.connectionTarget])
        #expect(targets.count == 3)
    }

    /// Was `onlySpoolmanNeedsItsCardUIDsFieldProvisioned` until 2026-08-24, on
    /// the reading that FilaMan's free-form `custom_fields` left nothing to
    /// register. It has a registry (`/api/v1/system-extra-fields`); a mapping
    /// simply does not need it. Owner decision: with SpoolLink on, every
    /// backend that can hold `card_uids` declares it system-wide.
    ///
    /// The original point of the test still stands and is what the on-device
    /// case guards: provisioning is gated on its OWN capability, so the
    /// bootstrap is never implied by "this backend can map tags".
    @Test func everyBackendWithARegistryProvisionsItsCardUIDsField() {
        #expect(BackendCapabilities.spoolman.requiresCardUIDsFieldRegistration)
        #expect(BackendCapabilities.filaman.requiresCardUIDsFieldRegistration)
        #expect(BackendCapabilities.local.requiresCardUIDsFieldRegistration == false)
    }

    // MARK: - writeCount

    @Test func aSuccessfulWriteBumpsTheWriteCount() async throws {
        let context = try makeContext()
        let store = SpoolDataStore(repository: LocalRepository(context: context))
        #expect(store.writeCount == 0)

        _ = await store.addVendor(name: "Prusament")
        #expect(store.writeCount == 1)
    }

    @Test func fetchingDoesNotBumpTheWriteCount() async throws {
        let context = try makeContext()
        let store = SpoolDataStore(repository: LocalRepository(context: context))

        await store.fetchVendors()
        await store.fetchSpools()
        #expect(store.writeCount == 0)
    }

    @Test func aBulkActionCountsEveryRowItWrote() async throws {
        let context = try makeContext()
        let store = SpoolDataStore(repository: LocalRepository(context: context))

        let filament = try #require(await store.addFilament(draft: FilamentDraft(name: "F")))
        var spools: [Spool?] = []
        for _ in 0..<3 { spools.append(await store.addSpool(draft: SpoolDraft(filamentId: filament.id))) }
        let ids = Set(spools.compactMap { $0?.id })
        #expect(ids.count == 3)

        let before = store.writeCount
        _ = await store.archiveSpools(ids: ids)
        #expect(store.writeCount == before + 3)
    }
}
