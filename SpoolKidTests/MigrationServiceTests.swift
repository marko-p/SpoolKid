//
//  MigrationServiceTests.swift
//  SpoolKidTests
//
//  Purpose: Locks the M3 migration executor behavior: dependency-order upload,
//  correct server foreign keys, lot_nr preservation, full-success wipe,
//  resumability after partial failure, and idempotency.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import Combine
import SwiftData
import Testing
@testable import SpoolKid

@MainActor
struct MigrationServiceTests {

    /// TD travels as the draft's typed field, never as a raw `extra` key a
    /// server may refuse before its `td` field is registered.
    @Test func migrationCarriesTDTyped() async throws {
        let (container, local) = try makeLocalStore()
        local.filaments[0].extra = ["td": "3.5", "variant": "\"Silk\""]
        try container.mainContext.save()
        let writer = MockMigrationWriter()
        let service = MigrationService(context: container.mainContext, writer: writer)

        let plan = try #require(await service.buildPlan())
        _ = await service.execute(plan)

        let draft = try #require(writer.createdFilamentDrafts.first)
        #expect(draft.transmissionDistance == SpoolmanPatchValue<Double>.set(3.5))
        #expect(draft.extra.valueOnCreate == ["variant": "\"Silk\""])
    }

    // MARK: - Full success

    @Test func fullRunCreatesInDependencyOrderAndWipesLocalStore() async throws {
        let (container, _) = try makeLocalStore()
        let writer = MockMigrationWriter()
        let service = MigrationService(context: container.mainContext, writer: writer)

        let plan = try #require(await service.buildPlan())
        #expect(plan.vendors.count == 1)
        #expect(plan.filaments.count == 1)
        #expect(plan.spools.count == 1)

        let result = await service.execute(plan)

        #expect(result.created == 3)
        #expect(result.reused == 0)
        #expect(result.failed.isEmpty)
        #expect(result.skipped.isEmpty)

        // Vendors created first, filaments reference server vendor id, spools
        // reference server filament id and preserve the lot_nr.
        #expect(writer.createdVendors.count == 1)
        #expect(writer.createdFilaments.count == 1)
        let serverVendorId = writer.createdVendors[0].id
        #expect(writer.createdFilaments[0].vendor?.id == serverVendorId)

        #expect(writer.createdSpools.count == 1)
        let serverFilamentId = writer.createdFilaments[0].id
        #expect(writer.createdSpools[0].filament.id == serverFilamentId)
        #expect(writer.createdSpools[0].lotNr == "card_uid:DEADBEEF")

        // Local store is wiped after full success.
        let remainingVendors = try container.mainContext.fetch(FetchDescriptor<LocalVendor>())
        let remainingFilaments = try container.mainContext.fetch(FetchDescriptor<LocalFilament>())
        let remainingSpools = try container.mainContext.fetch(FetchDescriptor<LocalSpool>())
        #expect(remainingVendors.isEmpty)
        #expect(remainingFilaments.isEmpty)
        #expect(remainingSpools.isEmpty)
    }

    // MARK: - Uploaded, but some fields stayed behind

    /// A create that lands WITH a note (FilaMan has no field for a value the
    /// local row holds) is not a clean run: the value exists only on this
    /// iPhone, so the Library must not be wiped out from under it.
    @Test func aCreateThatLeavesFieldsBehindIsListedAndHoldsTheWipe() async throws {
        let (container, local) = try makeLocalStore()
        let note = "Comment — FilaMan has no field for this, so it was not saved."
        let writer = MockMigrationWriter()
        writer.filamentCreateNote = note
        let service = MigrationService(context: container.mainContext, writer: writer)

        let plan = try #require(await service.buildPlan())
        let result = await service.execute(plan)

        #expect(result.created == 3)
        #expect(result.failed.isEmpty)
        #expect(result.skipped.isEmpty)
        #expect(result.notStored == [MigrationFailure(label: plan.filaments[0].label, reason: note)])
        #expect(!result.isComplete)

        let remainingFilaments = try container.mainContext.fetch(FetchDescriptor<LocalFilament>())
        #expect(remainingFilaments.map(\.name) == local.filaments.map(\.name))
    }

    @Test func aCleanRunIsComplete() async throws {
        let (container, _) = try makeLocalStore()
        let service = MigrationService(context: container.mainContext, writer: MockMigrationWriter())

        let plan = try #require(await service.buildPlan())
        let result = await service.execute(plan)

        #expect(result.notStored.isEmpty)
        #expect(result.isComplete)
    }

    /// A row that uploaded but whose `serverId` this iPhone could not save is
    /// listed, and holds the wipe: the run did not finish recording itself.
    /// Not rolled back — the stamp is true, so a later save that succeeds
    /// keeps it.
    @Test func aStampThatCannotBeSavedIsListedAndHoldsTheWipe() async throws {
        let context = try SaveFailureInjection.makeContext(
            for: [LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self]
        )
        _ = try seedLocalStore(in: context)
        let writer = MockMigrationWriter()
        let service = MigrationService(context: context, writer: writer)
        let plan = try #require(await service.buildPlan())
        try SaveFailureInjection.arm(context)

        let result = await service.execute(plan)

        #expect(result.created == 3)
        #expect(result.notStored.map(\.label) == [plan.vendors[0].label, plan.filaments[0].label, plan.spools[0].label])
        #expect(result.notStored.allSatisfy { $0.reason?.hasPrefix(MigrationService.stampNotSavedNote) == true })
        #expect(!result.isComplete)
        #expect(try context.fetchCount(FetchDescriptor<LocalSpool>()) == 1)

        try SaveFailureInjection.disarm(context)
        try context.save()
        let vendor = try #require(try context.fetch(FetchDescriptor<LocalVendor>()).first)
        #expect(vendor.serverId == writer.createdVendors.first?.id)
    }

    // MARK: - Reuse

    @Test func reuseVendorUsesServerIdForChildFilament() async throws {
        let (container, local) = try makeLocalStore()
        let serverVendor = Vendor(id: 42, name: local.vendor.name)
        let writer = MockMigrationWriter(serverVendors: [serverVendor])
        let service = MigrationService(context: container.mainContext, writer: writer)

        let plan = try #require(await service.buildPlan())
        #expect(plan.vendors[0].resolution == .reuse(serverId: 42))

        let result = await service.execute(plan)

        #expect(result.created == 2)
        #expect(result.reused == 1)
        #expect(writer.createdVendors.isEmpty)
        #expect(writer.createdFilaments[0].vendor?.id == 42)
    }

    /// A reused spool whose tag IDs could not be merged into the server spool
    /// is linked, but its tags are not: those IDs live only in the local row,
    /// so the run must list it and must not wipe the Library.
    @Test func aReusedSpoolWhoseTagsCouldNotBeLinkedIsListedAndHoldsTheWipe() async throws {
        let (container, local, writer) = try makeLocalStoreWithReusableServerSpool()
        local.spools[0].extra = ["card_uids": CardUIDsCodec.encode(["LOCAL01"])]
        try container.mainContext.save()
        writer.setCardUIDsError = "Server refused the change."
        let service = MigrationService(context: container.mainContext, writer: writer)

        let plan = try #require(await service.buildPlan())
        let result = await service.execute(plan)

        #expect(result.reused == 3)
        #expect(result.notStored.count == 1)
        #expect(result.notStored.first?.label == plan.spools[0].label)
        #expect(result.notStored.first?.reason?.contains("LOCAL01") == true)
        #expect(result.notStored.first?.reason?.contains("Server refused the change.") == true)
        #expect(!result.isComplete)

        let remainingSpools = try container.mainContext.fetch(FetchDescriptor<LocalSpool>())
        #expect(remainingSpools.map { CardUIDsCodec.parse($0.extra?[CardUIDsCodec.fieldKey]) } == [["LOCAL01"]])
    }

    // MARK: - Outside Tag Links (R13)
    //
    // Outside Tag Links SpoolKid creates no links, migration included. The
    // facade the migration writes through refuses them; the run lists the
    // spool, and the Library keeps the row that still holds the tags.

    /// The facade over a connected server that keeps links, in Spool ID mode.
    private func spoolIDStore(over writer: MockMigrationWriter) -> SpoolDataStore {
        writer.availableTagStores = [.cardUIDs]
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("spoolID", forKey: AppConfig.tagIdentityModeKey)
        defaults.set(true, forKey: AppConfig.spoolmanConnectionValidKey)
        return SpoolDataStore(repository: writer, defaults: defaults)
    }

    @Test func aReusedSpoolsTagsAreNotLinkedOutsideTagLinksAndTheRowIsKept() async throws {
        let (container, local, writer) = try makeLocalStoreWithReusableServerSpool()
        local.spools[0].extra = ["card_uids": CardUIDsCodec.encode(["LOCAL01"])]
        try container.mainContext.save()
        let store = spoolIDStore(over: writer)
        #expect(!store.tagIdentity.writesLinks)
        let service = MigrationService(context: container.mainContext, writer: store)

        let plan = try #require(await service.buildPlan())
        let result = await service.execute(plan)

        #expect(writer.setCardUIDsCalls.isEmpty)
        #expect(result.notStored.map(\.label) == [plan.spools[0].label])
        #expect(result.notStored.first?.reason?.contains("LOCAL01") == true)
        #expect(result.notStored.first?.reason?.contains(TagStoreText.linksOffNote(connectionRowLabel: "Spoolman")) == true)
        #expect(!result.isComplete)
        let remainingSpools = try container.mainContext.fetch(FetchDescriptor<LocalSpool>())
        #expect(remainingSpools.map { CardUIDsCodec.parse($0.extra?[CardUIDsCodec.fieldKey]) } == [["LOCAL01"]])
    }

    @Test func aCreatedSpoolCarriesNoTagLinksOutsideTagLinksAndTheRowIsKept() async throws {
        let (container, local) = try makeLocalStore()
        local.spools[0].extra = ["card_uids": CardUIDsCodec.encode(["AABBCCDD"])]
        try container.mainContext.save()
        let writer = MockMigrationWriter()
        let service = MigrationService(context: container.mainContext, writer: spoolIDStore(over: writer))

        let plan = try #require(await service.buildPlan())
        let result = await service.execute(plan)

        #expect(result.created == 3)
        #expect(try #require(writer.createdSpoolDrafts.first).cardUIDs == nil)
        #expect(result.notStored.map(\.label) == [plan.spools[0].label])
        #expect(result.notStored.first?.reason?.contains("AABBCCDD") == true)
        #expect(result.notStored.first?.reason?.contains(TagStoreText.linksOffNote(connectionRowLabel: "Spoolman")) == true)
        #expect(!result.isComplete)
        let remainingSpools = try container.mainContext.fetch(FetchDescriptor<LocalSpool>())
        #expect(remainingSpools.count == 1)
    }

    @Test func reuseSpoolMergesLocalCardUIDsIntoServerCardUIDs() async throws {
        let (container, local, writer) = try makeLocalStoreWithReusableServerSpool()

        // Server spool already has one UID in card_uids; local spool has two UIDs in card_uids.
        writer.spools[0] = Spool(
            id: writer.spools[0].id,
            filament: writer.spools[0].filament,
            initialWeight: writer.spools[0].initialWeight,
            extra: ["card_uids": CardUIDsCodec.encode(["SERVER01"])],
            statusId: nil, externalId: nil, purchaseDate: nil
        )
        local.spools[0].extra = ["card_uids": CardUIDsCodec.encode(["LOCAL01", "LOCAL02"])]
        try container.mainContext.save()

        let service = MigrationService(context: container.mainContext, writer: writer)

        let plan = try #require(await service.buildPlan())
        #expect(plan.spools[0].resolution == .reuse(serverId: writer.spools[0].id))

        let result = await service.execute(plan)

        #expect(result.reused == 3)
        #expect(writer.setCardUIDsCalls.count == 1)

        let call = writer.setCardUIDsCalls[0]
        #expect(call.spoolId == writer.spools[0].id)
        // Server card_uids are preserved first; both local UIDs appended (no cap).
        #expect(call.uids == ["SERVER01", "LOCAL01", "LOCAL02"])
    }

    /// Since spec 2 the Library keeps links in `card_uids`; a reused spool
    /// takes those. A `card_uid:` token in `lotNr` is lot text, not a link
    /// (2026-10-11).
    @Test func reuseSpoolTakesTheLibrarysLinksButNotLotNrTokens() async throws {
        let (container, local, writer) = try makeLocalStoreWithReusableServerSpool()
        local.spools[0].extra = ["card_uids": CardUIDsCodec.encode(["AABBCCDD"])]
        local.spools[0].lotNr = "card_uid:LOCAL01"
        try container.mainContext.save()
        let service = MigrationService(context: container.mainContext, writer: writer)

        let plan = try #require(await service.buildPlan())
        _ = await service.execute(plan)

        #expect(writer.setCardUIDsCalls.map(\.uids) == [["AABBCCDD"]])
    }

    /// A 0.27 server keeps links as Spoolman Tags, not in `card_uids`; the
    /// merge starts from them, because the write unlinks any native tag it
    /// does not name.
    @Test func reuseSpoolKeepsTheServerSpoolsNativeTags() async throws {
        let (container, local, writer) = try makeLocalStoreWithReusableServerSpool()
        writer.spools[0] = Spool(
            id: writer.spools[0].id,
            filament: writer.spools[0].filament,
            initialWeight: writer.spools[0].initialWeight,
            statusId: nil, externalId: nil, purchaseDate: nil,
            nativeTagUIDs: ["SERVER01"]
        )
        local.spools[0].extra = ["card_uids": CardUIDsCodec.encode(["AABBCCDD"])]
        local.spools[0].lotNr = nil
        try container.mainContext.save()
        let service = MigrationService(context: container.mainContext, writer: writer)

        let plan = try #require(await service.buildPlan())
        _ = await service.execute(plan)

        #expect(writer.setCardUIDsCalls.map(\.uids) == [["SERVER01", "AABBCCDD"]])
    }

    /// F1: with FilaMan Tags on the server spool's writable `rfid_uid` is a
    /// link the write could take away; the merge starts from it.
    @Test(arguments: [[String](), ["X"]])
    func reuseSpoolKeepsTheServerSpoolsWritableRFID(serverCards: [String]) async throws {
        let (container, local, writer) = try makeLocalStoreWithReusableServerSpool()
        writer.spools[0] = Spool(
            id: writer.spools[0].id,
            filament: writer.spools[0].filament,
            initialWeight: writer.spools[0].initialWeight,
            extra: serverCards.isEmpty ? nil : ["card_uids": CardUIDsCodec.encode(serverCards)],
            rfidUID: "a",
            statusId: nil, externalId: nil, purchaseDate: nil,
            rfidUIDWritable: true
        )
        local.spools[0].extra = ["card_uids": CardUIDsCodec.encode(["B"])]
        local.spools[0].lotNr = nil
        try container.mainContext.save()
        let service = MigrationService(context: container.mainContext, writer: writer)

        let plan = try #require(await service.buildPlan())
        _ = await service.execute(plan)

        #expect(writer.setCardUIDsCalls.map(\.uids) == [["A"] + serverCards + ["B"]])
    }

    /// A reused spool that left the server's list after planning still has
    /// its tags named, so its row is kept.
    @Test func reuseSpoolWhoseServerSpoolIsGoneKeepsItsRow() async throws {
        let (container, local, writer) = try makeLocalStoreWithReusableServerSpool()
        local.spools[0].extra = ["card_uids": CardUIDsCodec.encode(["AABBCCDD"])]
        try container.mainContext.save()
        let service = MigrationService(context: container.mainContext, writer: writer)

        let plan = try #require(await service.buildPlan())
        writer.spools.removeAll()
        let result = await service.execute(plan)

        #expect(result.notStored.first?.reason?.contains("AABBCCDD") == true)
        #expect(!result.isComplete)
    }

    @Test func reuseSpoolWithNoLocalCardUIDIssuesNoSetLotNrCall() async throws {
        let (container, local, writer) = try makeLocalStoreWithReusableServerSpool()

        // Local spool has no card_uid mapping; server spool already has one.
        local.spools[0].lotNr = nil
        writer.spools[0] = Spool(
            id: writer.spools[0].id,
            filament: writer.spools[0].filament,
            initialWeight: writer.spools[0].initialWeight,
            extra: ["card_uids": CardUIDsCodec.encode(["SERVER01"])],
            statusId: nil, externalId: nil, purchaseDate: nil
        )
        try container.mainContext.save()

        let service = MigrationService(context: container.mainContext, writer: writer)

        let plan = try #require(await service.buildPlan())
        let result = await service.execute(plan)

        #expect(result.reused == 3)
    }

    @Test func reuseSpoolWithExistingServerCardUIDsStillMigrates() async throws {
        let (container, local, writer) = try makeLocalStoreWithReusableServerSpool()

        // Server spool already carries card UIDs; the local UID merges in —
        // card_uids is uncapped, so migration still reuses the spool.
        writer.spools[0] = Spool(
            id: writer.spools[0].id,
            filament: writer.spools[0].filament,
            initialWeight: writer.spools[0].initialWeight,
            extra: ["card_uids": CardUIDsCodec.encode(["SERVER01", "SERVER02"])],
            statusId: nil, externalId: nil, purchaseDate: nil
        )
        local.spools[0].extra = ["card_uids": CardUIDsCodec.encode(["LOCAL01"])]
        try container.mainContext.save()

        let service = MigrationService(context: container.mainContext, writer: writer)

        let plan = try #require(await service.buildPlan())
        let result = await service.execute(plan)

        #expect(result.reused == 3)
    }

    // MARK: - Idempotency

    @Test func successfulRunMakesReRunPlanEmpty() async throws {
        let (container, _) = try makeLocalStore()
        let writer = MockMigrationWriter()
        let service = MigrationService(context: container.mainContext, writer: writer)

        let firstPlan = try #require(await service.buildPlan())
        _ = await service.execute(firstPlan)

        let secondPlan = try #require(await service.buildPlan())
        #expect(secondPlan.vendors.isEmpty)
        #expect(secondPlan.filaments.isEmpty)
        #expect(secondPlan.spools.isEmpty)
    }

    // MARK: - Build failure

    @Test func buildPlanReturnsNilAndSetsBuildErrorWhenFetchFails() async throws {
        let (container, _) = try makeLocalStore()
        let writer = MockMigrationWriter(fetchVendorsError: "Server unreachable")
        let service = MigrationService(context: container.mainContext, writer: writer)

        let plan = await service.buildPlan()

        #expect(plan == nil)
        #expect(service.buildError == "Server unreachable")
    }

    // MARK: - Trigger helper

    @Test func unsyncedLocalRowCountCountsOnlyUnsyncedRows() async throws {
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        #expect(MigrationService.unsyncedLocalRowCount(in: context) == .counted(0))

        let syncedVendor = LocalVendor(localId: 1, serverId: 10, name: "Synced")
        let unsyncedVendor = LocalVendor(localId: 2, name: "Unsynced")
        context.insert(syncedVendor)
        context.insert(unsyncedVendor)
        try context.save()

        #expect(MigrationService.unsyncedLocalRowCount(in: context) == .counted(1))
    }

    // MARK: - Migration offer (Task 20)
    //
    // Both entry points used to test the Spoolman URL and Spoolman's
    // connection flag, so the offer to upload the on-device Library was dead
    // on FilaMan. These pin the requirement — "the active backend is a server,
    // and there is something to send" — not the vendor.

    @Test func migrationOffersForAnyServerBackend() {
        #expect(MigrationService.shouldOfferMigration(capabilities: .spoolman, unsyncedLocalRows: 3))
        #expect(MigrationService.shouldOfferMigration(capabilities: .filaman, unsyncedLocalRows: 3))
    }

    @Test func migrationNeverOffersForOnDeviceStorage() {
        // Server→server is deliberately out of scope too, but that case cannot
        // arise: the rows counted here are on-device rows, and the on-device
        // backend is the only one that would be migrating to itself.
        #expect(MigrationService.shouldOfferMigration(capabilities: .local, unsyncedLocalRows: 3) == false)
    }

    @Test func migrationNeverOffersWithNothingToMigrate() {
        #expect(MigrationService.shouldOfferMigration(capabilities: .spoolman, unsyncedLocalRows: 0) == false)
    }

    @Test func migrationNeverOffersWhenTheLocalCountIsUnavailable() {
        // A store that would not answer is not an empty store. It reaches the
        // same screen state as "nothing to migrate", but only one of the two
        // is a bug, so the count says which and the decision is made here once
        // rather than collapsed into a zero at the fetch.
        #expect(MigrationService.shouldOfferMigration(
            capabilities: .spoolman, localRows: .unavailable
        ) == false)
        #expect(MigrationService.shouldOfferMigration(
            capabilities: .spoolman, localRows: .counted(0)
        ) == false)
        #expect(MigrationService.shouldOfferMigration(
            capabilities: .filaman, localRows: .counted(2)
        ))
    }

    @Test func migrationReviewNamesTheActiveBackend() async throws {
        // The review sheet's title, unreachable message, and upload headline
        // all said "Spoolman" regardless of where the rows were going. They
        // read this seam now, so the destination's own name reaches the copy.
        let (container, _) = try makeLocalStore()
        let filaManWriter = MockMigrationWriter(capabilities: .filaman)
        let filaManService = MigrationService(context: container.mainContext, writer: filaManWriter)
        #expect(filaManService.capabilities.displayName == "FilaMan")

        let spoolmanService = MigrationService(
            context: container.mainContext, writer: MockMigrationWriter()
        )
        #expect(spoolmanService.capabilities.displayName == "Spoolman")
    }

    // MARK: - Partial failure

    @Test func partialFailureSkipsDependentSpoolsAndKeepsRemainder() async throws {
        // Seed two filaments + one spool each so a failure on the first filament
        // skips its spool but the second filament and spool still upload.
        let (container, _) = try makeLocalStoreWithTwoFilaments()
        let writer = MockMigrationWriter(failFilamentAtIndex: 1)
        let service = MigrationService(context: container.mainContext, writer: writer)

        let plan = try #require(await service.buildPlan())
        let result = await service.execute(plan)

        #expect(result.created == 3)
        // Vendor always creates. Filament 1 fails. Filament 2 creates. Spool 1
        // skipped (parent failed). Spool 2 creates.
        #expect(result.failed.count == 1)
        #expect(result.skipped.count == 1)
        // Counts alone cannot be acted on: the failure carries the backend's
        // own message, and the row it blocked says what it was waiting for.
        #expect(result.failed.first?.reason == "Simulated filament failure")
        #expect(result.skipped.first?.reason == "Its filament was not uploaded.")
        #expect(writer.createdFilaments.count == 1)
        #expect(writer.createdSpools.count == 1)

        // Store is NOT wiped on partial failure.
        let remainingVendors = try container.mainContext.fetch(FetchDescriptor<LocalVendor>())
        let remainingFilaments = try container.mainContext.fetch(FetchDescriptor<LocalFilament>())
        let remainingSpools = try container.mainContext.fetch(FetchDescriptor<LocalSpool>())
        #expect(remainingVendors.count == 1)
        #expect(remainingFilaments.count == 2)
        #expect(remainingSpools.count == 2)

        // Synced rows carry serverId; the failed filament and its skipped spool do not.
        #expect(remainingVendors[0].serverId != nil)
        let syncedFilament = remainingFilaments.first { $0.serverId != nil }
        let failedFilament = remainingFilaments.first { $0.serverId == nil }
        #expect(syncedFilament != nil)
        #expect(failedFilament != nil)
    }

    // MARK: - Pre-flight + fixing a blocked row

    @Test func aFilamentWithNoManufacturerIsReportedBeforeTheUpload() async throws {
        let container = try makeLocalStoreWithoutAManufacturer()
        let writer = MockMigrationWriter()
        writer.requiresManufacturer = true
        let service = MigrationService(context: container.mainContext, writer: writer)

        let plan = try #require(await service.buildPlan())

        #expect(service.blockedFilaments(in: plan) == [1: [.manufacturer]])
    }

    @Test func aPlannedManufacturerSatisfiesThePreflightBeforeItHasAServerId() async throws {
        // The regression this guards: at pre-flight time no vendor has been
        // uploaded, so a naive check would call every filament unqualified.
        let (container, _) = try makeLocalStore()
        let writer = MockMigrationWriter()
        writer.requiresManufacturer = true
        let service = MigrationService(context: container.mainContext, writer: writer)

        let plan = try #require(await service.buildPlan())

        #expect(service.blockedFilaments(in: plan).isEmpty)
    }

    @Test func fixingTheRowCreatesTheManufacturerAndClearsTheBlock() async throws {
        let container = try makeLocalStoreWithoutAManufacturer()
        let writer = MockMigrationWriter()
        writer.requiresManufacturer = true
        let service = MigrationService(context: container.mainContext, writer: writer)
        _ = try #require(await service.buildPlan())

        let failure = await service.applyFilamentFix(
            MigrationFilamentFix(localId: 1, manufacturerName: "Polymaker")
        )
        #expect(failure == nil)

        // Re-planned from the local store, the row is no longer blocked and the
        // new manufacturer is itself something to upload.
        let replanned = try #require(await service.buildPlan())
        #expect(service.blockedFilaments(in: replanned).isEmpty)
        #expect(replanned.vendors.count == 1)
        #expect(service.manufacturerOptions() == ["Polymaker"])
    }

    /// The pre-flight used to run once, when the plan was built. A filament
    /// matched to a server one is linked, not created, so nothing is checked —
    /// flip it to Create on the review screen and the backend's rules apply.
    /// The review screen recomputes on `resolutions`; this pins both halves.
    @Test func aRowFlippedFromReuseToCreateIsCheckedAgainstTheBackend() async throws {
        let (container, _, writer) = try makeLocalStoreWithReusableServerSpool()
        writer.checksSpoolmanRequirements = true
        let service = MigrationService(context: container.mainContext, writer: writer)
        var plan = try #require(await service.buildPlan())
        let filament = try #require(plan.filaments.first)
        #expect(filament.resolution == .reuse(serverId: 43))
        #expect(service.blockedFilaments(in: plan).isEmpty)

        let before = plan.resolutions
        plan.filaments[0].resolution = .create

        #expect(plan.resolutions != before)
        #expect(service.blockedFilaments(in: plan)[filament.localId] == [.density])
    }

    @Test func fixingADensityWritesItToTheLocalRow() async throws {
        let container = try makeLocalStoreWithoutAManufacturer()
        let service = MigrationService(context: container.mainContext, writer: MockMigrationWriter())
        _ = try #require(await service.buildPlan())

        let failure = await service.applyFilamentFix(MigrationFilamentFix(localId: 1, density: 1.24))

        #expect(failure == nil)
        let filament = try #require(try container.mainContext.fetch(FetchDescriptor<LocalFilament>()).first)
        #expect(filament.density == 1.24)
    }

    @Test func aManufacturerAlreadyOnTheServerIsOfferedAndLinkedRatherThanDuplicated() async throws {
        let container = try makeLocalStoreWithoutAManufacturer()
        let serverVendor = Vendor(id: 42, name: "Polymaker")
        let writer = MockMigrationWriter(serverVendors: [serverVendor])
        writer.requiresManufacturer = true
        let service = MigrationService(context: container.mainContext, writer: writer)
        _ = try #require(await service.buildPlan())

        // Offered even though the Library has no manufacturers of its own.
        #expect(service.manufacturerOptions() == ["Polymaker"])

        let failure = await service.applyFilamentFix(
            MigrationFilamentFix(localId: 1, manufacturerName: "Polymaker")
        )
        #expect(failure == nil)

        // The local row it created matches the server's by the planner's own
        // rule, so the upload REUSES id 42 instead of creating a second
        // Polymaker — which is what makes choosing a server manufacturer safe.
        let replanned = try #require(await service.buildPlan())
        #expect(service.blockedFilaments(in: replanned).isEmpty)
        #expect(replanned.vendors.map(\.resolution) == [.reuse(serverId: 42)])
    }

    @Test func choosingAServerManufacturerMatchesRegardlessOfCaseAndSpacing() async throws {
        let container = try makeLocalStoreWithoutAManufacturer()
        let writer = MockMigrationWriter(serverVendors: [Vendor(id: 7, name: "Bambu Lab")])
        writer.requiresManufacturer = true
        let service = MigrationService(context: container.mainContext, writer: writer)
        _ = try #require(await service.buildPlan())

        _ = await service.applyFilamentFix(
            MigrationFilamentFix(localId: 1, manufacturerName: "  bambu lab ")
        )

        let replanned = try #require(await service.buildPlan())
        #expect(replanned.vendors.map(\.resolution) == [.reuse(serverId: 7)])
    }

    @Test func fixingWithAnExistingManufacturerReusesIt() async throws {
        let (container, seed) = try makeLocalStore()
        // Detach the seeded filament from its vendor so the fix has work to do.
        seed.filaments[0].vendor = nil
        try container.mainContext.save()

        let writer = MockMigrationWriter()
        writer.requiresManufacturer = true
        let service = MigrationService(context: container.mainContext, writer: writer)
        let plan = try #require(await service.buildPlan())
        #expect(service.blockedFilaments(in: plan) == [2: [.manufacturer]])

        let failure = await service.applyFilamentFix(
            MigrationFilamentFix(localId: 2, manufacturerName: seed.vendor.name)
        )
        #expect(failure == nil)
        // Reused, not duplicated.
        #expect(service.manufacturerOptions().count == 1)

        let replanned = try #require(await service.buildPlan())
        #expect(service.blockedFilaments(in: replanned).isEmpty)
    }

    // MARK: - Filament links (spec 4)

    @Test func aReusedFilamentsLinksAreLinkedOnTheServer() async throws {
        let (container, local, writer) = try makeLocalStoreWithReusableServerSpool()
        local.filaments[0].extra = ["card_uids": CardUIDsCodec.encode(["04AA"])]
        try container.mainContext.save()
        let service = MigrationService(context: container.mainContext, writer: writer)

        let plan = try #require(await service.buildPlan())
        _ = await service.execute(plan)

        #expect(writer.linkFilamentTagCalls.map(\.filamentId) == [43])
        #expect(writer.linkFilamentTagCalls.map(\.uid) == ["04AA"])
    }

    @Test func aCreatedFilamentIsLinkedAndItsDraftCarriesNoCardUIDs() async throws {
        let (container, local) = try makeLocalStore()
        local.filaments[0].extra = ["card_uids": CardUIDsCodec.encode(["04AA"]), "note": "keep"]
        try container.mainContext.save()
        let writer = MockMigrationWriter()
        let service = MigrationService(context: container.mainContext, writer: writer)

        let plan = try #require(await service.buildPlan())
        let result = await service.execute(plan)

        let draft = try #require(writer.createdFilamentDrafts.first)
        #expect(draft.extra.valueOnCreate?["card_uids"] == nil)
        #expect(draft.extra.valueOnCreate?["note"] == "keep")

        let created = try #require(writer.createdFilaments.first)
        #expect(writer.linkFilamentTagCalls.map(\.filamentId) == [created.id])
        #expect(writer.linkFilamentTagCalls.map(\.uid) == ["04AA"])
        #expect(result.notStored.isEmpty)
    }

    /// A refused filament link keeps the row, like a spool's (R13).
    @Test func aRefusedFilamentLinkKeepsTheRow() async throws {
        let (container, local) = try makeLocalStore()
        local.filaments[0].extra = ["card_uids": CardUIDsCodec.encode(["04AA"])]
        try container.mainContext.save()
        let writer = MockMigrationWriter()
        writer.linkFilamentTagOutcome = .failed("No filament store.")
        let service = MigrationService(context: container.mainContext, writer: writer)

        let plan = try #require(await service.buildPlan())
        let result = await service.execute(plan)

        #expect(result.notStored.map(\.label) == [plan.filaments[0].label])
        #expect(result.notStored.first?.reason?.contains("04AA") == true)
        #expect(result.notStored.first?.reason?.contains("No filament store.") == true)
        #expect(!result.isComplete)
    }

    // MARK: - Draft mapping (F38)

    /// A local spool stores `card_uids` in Spoolman's WRAPPED form. Handing
    /// `extra` to the destination verbatim wrote that form into FilaMan's
    /// free-form `custom_fields`, whose compat layer wraps it a SECOND time on
    /// read — so a migrated spool's tag mapping was unreadable to a
    /// SpoolLink/Snapmaker U1 client. The list travels typed instead, and each
    /// payload builder applies its own backend's encoding.
    @Test func aCreatedSpoolIsLinkedAfterItIsCreated() async throws {
        let (container, local) = try makeLocalStore()
        local.spools[0].extra = [
            "card_uids": CardUIDsCodec.encode(["AABBCCDD", "11223344"]),
            "note": "keep"
        ]
        try container.mainContext.save()
        let writer = MockMigrationWriter()
        let service = MigrationService(context: container.mainContext, writer: writer)
        let plan = try #require(await service.buildPlan())

        let result = await service.execute(plan)

        // Created without its tags, then linked through the one linking
        // path, so a 0.27 server gets Spoolman Tags (spec 2 §3).
        let draft = try #require(writer.createdSpoolDrafts.first)
        #expect(draft.cardUIDs == nil)
        #expect(draft.extra.valueOnCreate?["card_uids"] == nil)
        #expect(draft.extra.valueOnCreate?["note"] == "keep")
        let created = try #require(writer.createdSpools.first)
        #expect(writer.setCardUIDsCalls.map(\.spoolId) == [created.id])
        #expect(writer.setCardUIDsCalls.map(\.uids) == [["AABBCCDD", "11223344"]])
        #expect(result.notStored.isEmpty)
    }

    /// A created spool's link that fails keeps the row, like any note.
    @Test func aCreatedSpoolWhoseLinkFailsKeepsItsRow() async throws {
        let (container, local) = try makeLocalStore()
        local.spools[0].extra = ["card_uids": CardUIDsCodec.encode(["AABBCCDD"])]
        try container.mainContext.save()
        let writer = MockMigrationWriter()
        writer.setCardUIDsError = "Server refused the change."
        let service = MigrationService(context: container.mainContext, writer: writer)
        let plan = try #require(await service.buildPlan())

        let result = await service.execute(plan)

        #expect(result.created == 3)
        #expect(result.notStored.map(\.label) == [plan.spools[0].label])
        #expect(result.notStored.first?.reason?.contains("AABBCCDD") == true)
        #expect(result.notStored.first?.reason?.contains("Server refused the change.") == true)
        #expect(!result.isComplete)
        let remainingSpools = try container.mainContext.fetch(FetchDescriptor<LocalSpool>())
        #expect(remainingSpools.count == 1)
    }

    @Test func migratedSpoolWithNoMappingLeavesExtraAlone() async throws {
        let (container, local) = try makeLocalStore()
        local.spools[0].extra = ["note": "keep"]
        try container.mainContext.save()
        let writer = MockMigrationWriter()
        let service = MigrationService(context: container.mainContext, writer: writer)
        let plan = try #require(await service.buildPlan())

        _ = await service.execute(plan)

        let draft = try #require(writer.createdSpoolDrafts.first)
        #expect(draft.cardUIDs == nil)
        #expect(draft.extra == .set(["note": "keep"]))
    }

    // MARK: - Helpers

    private func makeLocalStore() throws -> (ModelContainer, LocalSeed) {
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let local = try seedLocalStore(in: context)
        return (container, local)
    }

    private func makeLocalStoreWithTwoFilaments() throws -> (ModelContainer, LocalSeed) {
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let local = try seedLocalStoreWithTwoFilaments(in: context)
        return (container, local)
    }

    private func makeLocalStoreWithReusableServerSpool() throws -> (ModelContainer, LocalSeed, MockMigrationWriter) {
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let local = try seedLocalStore(in: context)

        let serverVendor = Vendor(id: 42, name: local.vendor.name)
        let serverFilament = Filament(
            id: 43,
            name: local.filaments[0].name,
            material: local.filaments[0].material,
            vendor: serverVendor,
            diameter: local.filaments[0].diameter,
            weight: local.filaments[0].weight
        )
        let serverSpool = Spool(
            id: 44,
            filament: serverFilament,
            initialWeight: local.spools[0].initialWeight,
            statusId: nil, externalId: nil, purchaseDate: nil
        )
        let writer = MockMigrationWriter(
            serverVendors: [serverVendor],
            serverFilaments: [serverFilament],
            serverSpools: [serverSpool]
        )
        return (container, local, writer)
    }

    private func seedLocalStore(in context: ModelContext) throws -> LocalSeed {
        let vendor = LocalVendor(localId: 1, name: "Bambu Lab")
        let filament = LocalFilament(
            localId: 2,
            name: "PLA Basic",
            material: "PLA",
            diameter: 1.75,
            weight: 1000,
            vendor: vendor
        )
        let spool = LocalSpool(
            localId: 3,
            firstUsed: iso8601Date("2024-01-15T10:00:00Z"),
            lastUsed: iso8601Date("2024-06-01T08:00:00Z"),
            remainingWeight: 850,
            initialWeight: 1000,
            location: "Shelf A",
            lotNr: "card_uid:DEADBEEF",
            filament: filament
        )
        context.insert(vendor)
        context.insert(filament)
        context.insert(spool)
        try context.save()
        return LocalSeed(vendor: vendor, filaments: [filament], spools: [spool])
    }

    /// A filament with NO manufacturer — the shape that produced the device
    /// finding: a Library used without ever creating a manufacturer.
    private func makeLocalStoreWithoutAManufacturer() throws -> ModelContainer {
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let filament = LocalFilament(
            localId: 1, name: "PLA Basic", material: "PLA", diameter: 1.75, weight: 1000
        )
        let spool = LocalSpool(localId: 2, remainingWeight: 900, initialWeight: 1000, filament: filament)
        context.insert(filament)
        context.insert(spool)
        try context.save()
        return container
    }

    private func seedLocalStoreWithTwoFilaments(in context: ModelContext) throws -> LocalSeed {
        let vendor = LocalVendor(localId: 1, name: "Bambu Lab")
        let filament1 = LocalFilament(
            localId: 2,
            name: "PLA Basic",
            material: "PLA",
            diameter: 1.75,
            weight: 1000,
            vendor: vendor
        )
        let filament2 = LocalFilament(
            localId: 3,
            name: "PETG Basic",
            material: "PETG",
            diameter: 1.75,
            weight: 1000,
            vendor: vendor
        )
        let spool1 = LocalSpool(localId: 4, initialWeight: 1000, filament: filament1)
        let spool2 = LocalSpool(localId: 5, initialWeight: 1000, filament: filament2)
        context.insert(vendor)
        context.insert(filament1)
        context.insert(filament2)
        context.insert(spool1)
        context.insert(spool2)
        try context.save()
        return LocalSeed(vendor: vendor, filaments: [filament1, filament2], spools: [spool1, spool2])
    }

    private func iso8601Date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    private struct LocalSeed {
        let vendor: LocalVendor
        let filaments: [LocalFilament]
        let spools: [LocalSpool]
    }
}

// MARK: - Mock writer

    @MainActor
    final class MockMigrationWriter: ObservableObject, SpoolDataRepository {
    var spools: [Spool] = []
    var filaments: [Filament] = []
    var vendors: [Vendor] = []
    var locations: [String] = []
    var isLoading = false
    var errorMessage: String?
    let capabilities: BackendCapabilities
    var lastQuotaError: QuotaError?

    /// Mimics FilaMan's `FilamentCreate` requirement so the pre-flight has
    /// something to report; every other backend answers `[]` through the
    /// protocol's default.
    var requiresManufacturer = false

    private var nextServerId = 100
    private(set) var createdVendors: [Vendor] = []
    private(set) var createdFilaments: [Filament] = []
    private(set) var createdSpools: [Spool] = []
    /// The drafts as they arrived, so a test can pin what the destination's
    /// payload builder will be handed — the created `Spool` cannot show it.
    private(set) var createdSpoolDrafts: [SpoolDraft] = []
    private(set) var createdFilamentDrafts: [FilamentDraft] = []
    private(set) var setCardUIDsCalls: [(spoolId: Int, uids: [String])] = []
    var filamentTagStore: TagStore? = nil
    private(set) var linkFilamentTagCalls: [(filamentId: Int, uid: String)] = []
    var linkFilamentTagOutcome: SpoolmanService.TagLinkOutcome = .linked
    func linkFilamentTag(filamentId: Int, uid: String) async -> SpoolmanService.TagLinkOutcome {
        linkFilamentTagCalls.append((filamentId: filamentId, uid: uid))
        return linkFilamentTagOutcome
    }
    func unlinkFilamentTag(filamentId: Int, uid: String) async -> Bool { true }
    private(set) var tagScanReports: [TagScanReport] = []
    var supportsTagScanReporting = false
    func reportTagScan(_ report: TagScanReport) async -> TagScanReportOutcome {
        tagScanReports.append(report)
        return .reported
    }

    /// What a successful create leaves in `errorMessage`, as a real backend's
    /// "saved, but…" note does. Every server backend resets `errorMessage` on a
    /// successful create, so `nil` here is a clean save, not a stale message.
    var vendorCreateNote: String?
    var filamentCreateNote: String?
    var spoolCreateNote: String?
    /// Makes `setCardUIDs` fail with this message, as a refused PATCH would.
    var setCardUIDsError: String?
    /// Makes only these `setCardUIDs` calls fail (1-based, in call order), so a
    /// test can let a release land and refuse the claim after it.
    var failSetCardUIDsCalls: Set<Int> = []
    /// Models a FilaMan spool on write: `rfid_uid` becomes the first UID
    /// (lowercase) or nil, the rest land in `card_uids`. Off by default, so the
    /// other suites keep the double's inert behaviour.
    var modelsFilaManWrites = false
    /// The tag stores this double keeps, and whether that is an answer yet —
    /// Spoolman's waits on its version. The defaults (none, known) are the
    /// protocol's, which are the Library's.
    var availableTagStores: Set<TagStore> = []
    var tagStoresKnown = true
    /// What `fetchSpoolStatusOptions` answers, and how often it was asked.
    var spoolStatusOptionsStub: [FilaManSpoolStatus.Option] = []
    private(set) var fetchSpoolStatusOptionsCalls = 0

    func fetchSpoolStatusOptions() async -> [FilaManSpoolStatus.Option] {
        fetchSpoolStatusOptionsCalls += 1
        return spoolStatusOptionsStub
    }

    /// What `fetchFilamentCatalog` answers: `nil` is "no catalogue of its
    /// own", a failure is a backend that has one and could not deliver it.
    var filamentCatalogResult: Result<[SpoolmanDBFilament]?, Error> = .success(nil)

    func fetchFilamentCatalog() async throws -> [SpoolmanDBFilament]? {
        try filamentCatalogResult.get()
    }

    private let failFilamentAtIndex: Int?
    private var filamentCreateCount = 0
    private let fetchVendorsError: String?
    private let fetchSpoolsError: String?

    init(serverVendors: [Vendor] = [],
         serverFilaments: [Filament] = [],
         serverSpools: [Spool] = [],
         failFilamentAtIndex: Int? = nil,
         fetchVendorsError: String? = nil,
         fetchSpoolsError: String? = nil,
         capabilities: BackendCapabilities = .spoolman) {
        self.capabilities = capabilities
        self.vendors = serverVendors
        self.filaments = serverFilaments
        self.spools = serverSpools
        self.failFilamentAtIndex = failFilamentAtIndex
        self.fetchVendorsError = fetchVendorsError
        self.fetchSpoolsError = fetchSpoolsError
    }

    func fetchSpools() async {
        if let fetchSpoolsError {
            errorMessage = fetchSpoolsError
        }
    }
    func fetchFilaments() async {}
    func fetchVendors() async {
        if let fetchVendorsError {
            errorMessage = fetchVendorsError
        }
    }
    func fetchLocations() async {}
    func testConnection() async -> Bool { true }
    var connectionTarget = "mock"
    func checkReachability() async -> BackendReachability { .alwaysAvailable }

    func addVendor(draft: VendorDraft) async -> Vendor? {
        let vendor = Vendor(id: nextServerId, name: draft.name ?? "")
        nextServerId += 1
        createdVendors.append(vendor)
        vendors.append(vendor)
        errorMessage = vendorCreateNote
        return vendor
    }

    func addVendor(name: String) async -> Vendor? {
        await addVendor(draft: VendorDraft(name: name))
    }

    func updateVendor(id: Int, draft: VendorDraft) async -> Bool { true }
    @discardableResult func deleteVendor(id: Int) async -> Bool { true }
    func deleteVendorCascading(id: Int) async -> Bool { true }


    /// Answers with Spoolman's real rule, for tests where a row's
    /// requirements depend on how it resolves.
    var checksSpoolmanRequirements = false

    func missingFilamentRequirements(for draft: FilamentDraft) -> [FilamentCreateRequirement] {
        if checksSpoolmanRequirements { return SpoolmanRepository.missingRequirements(of: draft) }
        guard requiresManufacturer, draft.vendorId.valueOnCreate == nil else { return [] }
        return [.manufacturer]
    }

    func addFilament(draft: FilamentDraft) async -> Filament? {
        createdFilamentDrafts.append(draft)
        filamentCreateCount += 1
        if failFilamentAtIndex == filamentCreateCount {
            errorMessage = "Simulated filament failure"
            return nil
        }
        let vendor = draft.vendorId.valueOnCreate.flatMap { id in vendors.first { $0.id == id } }
        let filament = Filament(
            id: nextServerId,
            name: draft.name,
            material: draft.material,
            vendor: vendor,
            diameter: draft.diameter,
            weight: draft.weight.valueOnCreate
        )
        nextServerId += 1
        createdFilaments.append(filament)
        filaments.append(filament)
        errorMessage = filamentCreateNote
        return filament
    }

    func updateFilament(id: Int, draft: FilamentDraft) async -> Bool { true }
    @discardableResult func deleteFilament(id: Int) async -> Bool { true }
    func deleteFilamentCascading(id: Int) async -> Bool { true }

    func addSpool(draft: SpoolDraft) async -> Spool? {
        createdSpoolDrafts.append(draft)
        guard let filamentId = draft.filamentId,
              let filament = filaments.first(where: { $0.id == filamentId }) else {
            return nil
        }
        let spool = Spool(
            id: nextServerId,
            filament: filament,
            firstUsed: nil,
            lastUsed: nil,
            // Migration only creates, so `.ignore` and `.setNil` both mean
            // "created without this" — `valueOnCreate` says exactly that.
            remainingWeight: draft.remainingWeight.valueOnCreate,
            initialWeight: draft.initialWeight.valueOnCreate,
            location: location(from: draft.location),
            lotNr: draft.lotNr.valueOnCreate,
            statusId: nil, externalId: nil, purchaseDate: nil
        )
        nextServerId += 1
        createdSpools.append(spool)
        spools.append(spool)
        errorMessage = spoolCreateNote
        return spool
    }

    func updateSpool(id: Int, draft: SpoolDraft) async -> Bool { true }
    @discardableResult func deleteSpool(id: Int) async -> Bool { true }
    @discardableResult func setSpoolArchived(id: Int, archived: Bool) async -> Bool { true }

    /// Resolves like the real repositories, so `SpoolDataStore.unlinkTag` and
    /// a scan resolution can be exercised against this double.
    func findSpool(byCardUID uid: String) -> Spool? {
        let normalized = SpoolMappingService.normalizeUID(uid)
        return spools.first { $0.mappedCardUIDs.contains(normalized) }
    }
    func setCardUIDs(spoolId: Int, uids: [String]) async -> Bool {
        setCardUIDsCalls.append((spoolId: spoolId, uids: uids))
        if let setCardUIDsError {
            errorMessage = setCardUIDsError
            return false
        }
        if failSetCardUIDsCalls.contains(setCardUIDsCalls.count) {
            errorMessage = "Simulated write failure"
            return false
        }
        errorMessage = nil
        if modelsFilaManWrites, let index = spools.firstIndex(where: { $0.id == spoolId }) {
            let old = spools[index]
            var extra = old.extra ?? [:]
            extra[CardUIDsCodec.fieldKey] = CardUIDsCodec.encode(Array(uids.dropFirst()))
            spools[index] = Spool(
                id: old.id, filament: old.filament, extra: extra,
                rfidUID: uids.first?.lowercased(),
                statusId: nil, externalId: nil, purchaseDate: nil, rfidUIDWritable: old.rfidUIDWritable
            )
        }
        return true
    }
    func ensureCardUIDsField() async -> Bool { true }
    func deleteCardUIDsField() async -> Bool { true }
    func addLocation(name: String) async -> LocationCreateOutcome { .registeredOnDeviceOnly }
    func renameLocation(currentName: String, newName: String) async -> Bool { true }
    func deleteLocation(_ name: String) async -> Bool { true }

    private func location(from patch: SpoolmanPatchValue<String>) -> String? {
        if case .set(let value) = patch { return value }
        return nil
    }
}
