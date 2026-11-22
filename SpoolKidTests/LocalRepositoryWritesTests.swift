//
//  LocalRepositoryWritesTests.swift
//  SpoolKidTests
//
//  Purpose: Covers the LocalRepository filament/spool write surface — CRUD,
//  vendor/filament resolution, quota on create, patch values + location
//  tri-state on update, UID mapping, location rename, and that the type is
//  usable through the SpoolDataRepository protocol. In-memory store.
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
struct LocalRepositoryWritesTests {
    private func makeRepo(quotaLimit: Int? = nil) throws -> LocalRepository {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: config
        )
        return LocalRepository(context: ModelContext(container), quotaLimit: quotaLimit)
    }

    // MARK: - Filaments

    @Test func addFilamentLinksResolvedVendor() async throws {
        let repo = try makeRepo()
        let vendor = try #require(await repo.addVendor(name: "Polymaker"))
        let filament = try #require(
            await repo.addFilament(draft: FilamentDraft(name: "PolyTerra", vendorId: .set(vendor.id), material: "PLA"))
        )
        #expect(filament.name == "PolyTerra")
        #expect(filament.vendor?.id == vendor.id)
        #expect(repo.filaments.count == 1)
    }

    @Test func freeTierBlocksSixteenthFilament() async throws {
        let repo = try makeRepo(quotaLimit: 15)
        for i in 1...15 {
            #expect(await repo.addFilament(draft: FilamentDraft(name: "f\(i)")) != nil)
        }
        #expect(await repo.addFilament(draft: FilamentDraft(name: "f16")) == nil)
        #expect(repo.filaments.count == 15)
        #expect(repo.lastQuotaError == QuotaError(entity: .filaments, limit: 15))
    }

    @Test func updateFilamentSetsAndClearsFields() async throws {
        let repo = try makeRepo()
        let created = try #require(
            await repo.addFilament(draft: FilamentDraft(name: "PLA", material: "PLA", comment: .set("keep")))
        )
        // Provide a new material; clear the comment. The clear used to be
        // `clearFieldKeys: ["comment"]` — same idea, said in the type (R21).
        let ok = await repo.updateFilament(
            id: created.id,
            draft: FilamentDraft(material: "PLA+", comment: .setNil)
        )
        #expect(ok)
        let updated = try #require(repo.filaments.first { $0.id == created.id })
        #expect(updated.material == "PLA+")
        #expect(updated.name == "PLA")        // untouched (not provided, not cleared)
        #expect(updated.comment == nil)       // cleared
    }

    /// TD lives in `extra["td"]` in Spoolman's float form, so a migration to
    /// Spoolman carries it unchanged; a junk value another tool wrote survives
    /// a save that did not touch TD.
    @Test func localStoresAndClearsTD() async throws {
        let repo = try makeRepo()
        let created = try #require(
            await repo.addFilament(draft: FilamentDraft(name: "PLA", transmissionDistance: .set(3.5)))
        )
        #expect(created.transmissionDistance == 3.5)
        #expect(created.extra?["td"] == "3.5")

        #expect(await repo.updateFilament(id: created.id, draft: FilamentDraft(transmissionDistance: .setNil)))
        let cleared = try #require(repo.filaments.first { $0.id == created.id })
        #expect(cleared.transmissionDistance == nil)
        #expect(cleared.extra?["td"] == nil)

        #expect(await repo.updateFilament(id: created.id, draft: FilamentDraft(extra: .set(["td": "junk"]))))
        #expect(await repo.updateFilament(id: created.id, draft: FilamentDraft(name: "PLA+")))
        let untouched = try #require(repo.filaments.first { $0.id == created.id })
        #expect(untouched.extra?["td"] == "junk")
    }

    /// A multi-colour list replaces the single colour, as Spoolman does with
    /// `color_hex: null`. The Library must not keep a stale `colorHex` beside it.
    @Test func multiSetClearsColorHex() async throws {
        let repo = try makeRepo()
        let created = try #require(await repo.addFilament(draft: FilamentDraft(name: "Tri", colorHex: "FF0000")))

        let draft = FilamentDraft(colorHex: nil, multiColorHexes: .set("2D39C9,A51A52"), multiColorDirection: .set("coaxial"))
        #expect(await repo.updateFilament(id: created.id, draft: draft))

        let stored = try #require(repo.filaments.first { $0.id == created.id })
        #expect(stored.colorHex == nil)
        #expect(stored.multiColorHexes == "2D39C9,A51A52")
        #expect(stored.multiColorDirection == "coaxial")
    }

    /// Going back to single: the draft carries the primary colour and clears
    /// the pair, so the stored filament reads back as single-colour.
    @Test func multiToSingleDraftRestoresColorHex() async throws {
        let repo = try makeRepo()
        let created = try #require(await repo.addFilament(draft: FilamentDraft(name: "Tri", colorHex: "FF0000")))

        let multi = FilamentColors(hexes: ["2D39C9", "A51A52"])
        let toMulti = multi.draftFields(loaded: nil)
        #expect(await repo.updateFilament(id: created.id, draft: FilamentDraft(
            colorHex: toMulti.colorHex,
            multiColorHexes: toMulti.multiColorHexes,
            multiColorDirection: toMulti.multiColorDirection
        )))

        let toSingle = FilamentColors(hexes: ["FF0000"]).draftFields(loaded: multi)
        #expect(await repo.updateFilament(id: created.id, draft: FilamentDraft(
            colorHex: toSingle.colorHex,
            multiColorHexes: toSingle.multiColorHexes,
            multiColorDirection: toSingle.multiColorDirection
        )))

        let stored = try #require(repo.filaments.first { $0.id == created.id })
        #expect(stored.colorHex == "FF0000")
        #expect(stored.multiColorHexes == nil)
        #expect(stored.multiColorDirection == nil)
        #expect(stored.colors.isMulti == false)
    }

    /// Replaces `deleteFilamentCascadesToSpools`: a plain delete used to take
    /// the spools silently through SwiftData's `.cascade` rule. Owner decision
    /// P1 (2026-09-15) — a plain delete refuses dependents on every backend;
    /// only `deleteFilamentCascading` removes them.
    @Test func deleteFilamentRefusesWhileSpoolsReferenceIt() async throws {
        let repo = try makeRepo()
        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PETG")))
        _ = await repo.addSpool(draft: SpoolDraft(filamentId: filament.id, remainingWeight: .set(800)))

        let deleted = await repo.deleteFilament(id: filament.id)
        #expect(!deleted)
        #expect(repo.filaments.count == 1)
        #expect(repo.spools.count == 1)
        #expect(repo.errorMessage != nil)
    }

    @Test func deleteFilamentCascadingRemovesItsSpoolsOnly() async throws {
        let repo = try makeRepo()
        let doomed = try #require(await repo.addFilament(draft: FilamentDraft(name: "PETG")))
        let kept = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA")))
        _ = await repo.addSpool(draft: SpoolDraft(filamentId: doomed.id))
        _ = await repo.addSpool(draft: SpoolDraft(filamentId: doomed.id))
        let keptSpool = try #require(await repo.addSpool(draft: SpoolDraft(filamentId: kept.id)))

        let deleted = await repo.deleteFilamentCascading(id: doomed.id)
        #expect(deleted)
        #expect(repo.filaments.map(\.id) == [kept.id])
        #expect(repo.spools.map(\.id) == [keptSpool.id])
    }

    // MARK: - Spools

    @Test func addSpoolRequiresAFilament() async throws {
        let repo = try makeRepo()
        let spool = await repo.addSpool(draft: SpoolDraft(filamentId: nil, remainingWeight: .set(1000)))
        #expect(spool == nil)
        #expect(repo.spools.isEmpty)
        #expect(repo.errorMessage != nil)
    }

    @Test func addSpoolStoresLocationLotAndDate() async throws {
        let repo = try makeRepo()
        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA")))
        let spool = try #require(
            await repo.addSpool(draft: SpoolDraft(
                filamentId: filament.id,
                firstUsed: .set("2026-06-13T10:00:00Z"),
                remainingWeight: .set(1000),
                location: .set("Shelf A"),
                lotNr: .set("batch-7")
            ))
        )
        #expect(spool.location == "Shelf A")
        #expect(spool.lotNr == "batch-7")
        #expect(spool.firstUsed != nil)
        #expect(repo.locations == ["Shelf A"])
    }

    /// The Recently Added section reads this date (owner 2026-11-10).
    @Test func addSpoolRecordsWhenItWasAdded() async throws {
        let repo = try makeRepo()
        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA")))
        let before = Date.now
        let spool = try #require(await repo.addSpool(draft: SpoolDraft(filamentId: filament.id, remainingWeight: .set(1000))))
        let registered = try #require(spool.registered)
        #expect(registered >= before && registered <= .now)
        #expect(repo.spools.first?.registered == registered)
    }

    @Test func freeTierBlocksSixteenthSpool() async throws {
        let repo = try makeRepo(quotaLimit: 15)
        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA")))
        for _ in 1...15 {
            #expect(await repo.addSpool(draft: SpoolDraft(filamentId: filament.id, remainingWeight: .set(1000))) != nil)
        }
        #expect(await repo.addSpool(draft: SpoolDraft(filamentId: filament.id, remainingWeight: .set(1000))) == nil)
        #expect(repo.spools.count == 15)
        #expect(repo.lastQuotaError == QuotaError(entity: .spools, limit: 15))
    }

    @Test func updateSpoolLocationTriStateAndClearLot() async throws {
        let repo = try makeRepo()
        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA")))
        let created = try #require(
            await repo.addSpool(draft: SpoolDraft(filamentId: filament.id, location: .set("Old"), lotNr: .set("batch-7")))
        )
        // Set a new location, clear the lot number. The clear used to be
        // `clearFieldKeys: ["lot_nr"]` — same idea, said in the type (R21).
        _ = await repo.updateSpool(id: created.id, draft: SpoolDraft(location: .set("New"), lotNr: .setNil))
        var spool = try #require(repo.spools.first { $0.id == created.id })
        #expect(spool.location == "New")
        #expect(spool.lotNr == nil)

        // .ignore leaves the location unchanged; .setNil clears it.
        _ = await repo.updateSpool(id: created.id, draft: SpoolDraft(location: .ignore))
        spool = try #require(repo.spools.first { $0.id == created.id })
        #expect(spool.location == "New")
        _ = await repo.updateSpool(id: created.id, draft: SpoolDraft(location: .setNil))
        spool = try #require(repo.spools.first { $0.id == created.id })
        #expect(spool.location == nil)
    }

    // MARK: - UID mapping & locations

    @Test func findSpoolByCardUIDNormalizes() async throws {
        let repo = try makeRepo()
        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA")))
        let created = try #require(
            await repo.addSpool(draft: SpoolDraft(filamentId: filament.id, cardUIDs: ["04A1B2C3"]))
        )
        #expect(repo.findSpool(byCardUID: "04:a1:b2:c3")?.id == created.id)
        #expect(repo.findSpool(byCardUID: "deadbeef") == nil)
    }

    /// F38: the draft's typed UID list is honoured on CREATE, in the local
    /// store's own encoding — the same wrapped form `setCardUIDs` writes, so a
    /// spool created with a mapping is indistinguishable from one mapped
    /// afterwards.
    @Test func addSpoolStoresTheDraftsCardUIDs() async throws {
        let repo = try makeRepo()
        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA")))
        let created = try #require(
            await repo.addSpool(draft: SpoolDraft(filamentId: filament.id, cardUIDs: ["04a1b2c3"]))
        )
        let stored = try #require(repo.spools.first { $0.id == created.id })

        #expect(stored.cardUIDs == ["04A1B2C3"])
        #expect(stored.extra?["card_uids"] == CardUIDsCodec.encode(["04A1B2C3"]))
    }

    @Test func addSpoolKeepsOtherExtraKeysAlongsideTheCardUIDs() async throws {
        let repo = try makeRepo()
        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA")))
        let created = try #require(
            await repo.addSpool(draft: SpoolDraft(
                filamentId: filament.id, extra: .set(["note": "keep"]), cardUIDs: ["04A1B2C3"]
            ))
        )
        let stored = try #require(repo.spools.first { $0.id == created.id })

        #expect(stored.extra?["note"] == "keep")
        #expect(stored.cardUIDs == ["04A1B2C3"])
    }

    @Test func renameLocationUpdatesEverySpool() async throws {
        let repo = try makeRepo()
        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA")))
        _ = await repo.addSpool(draft: SpoolDraft(filamentId: filament.id, location: .set("Bin 1")))
        _ = await repo.addSpool(draft: SpoolDraft(filamentId: filament.id, location: .set("Bin 1")))

        #expect(await repo.renameLocation(currentName: "Bin 1", newName: "Bin 2"))
        #expect(repo.locations == ["Bin 2"])
        #expect(repo.spools.allSatisfy { $0.location == "Bin 2" })
    }

    @Test func deleteLocationClearsItFromEverySpoolButKeepsTheSpools() async throws {
        let repo = try makeRepo()
        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA")))
        _ = await repo.addSpool(draft: SpoolDraft(filamentId: filament.id, location: .set("Bin 1")))
        _ = await repo.addSpool(draft: SpoolDraft(filamentId: filament.id, location: .set("Bin 1")))
        _ = await repo.addSpool(draft: SpoolDraft(filamentId: filament.id, location: .set("Bin 2")))
        #expect(repo.locations.contains("Bin 1"))

        #expect(await repo.deleteLocation("Bin 1"))
        // The location is gone, its spools survive with no location, "Bin 2" untouched.
        #expect(repo.locations == ["Bin 2"])
        #expect(repo.spools.count == 3)
        #expect(repo.spools.filter { $0.location == "Bin 1" }.isEmpty)
    }

    // MARK: - Delete return values

    @Test func deleteVendorReturnsTrueOnSuccessAndFalseWhenMissing() async throws {
        let repo = try makeRepo()
        let created = await repo.addVendor(name: "Acme")
        let id = try #require(created?.id)

        let ok = await repo.deleteVendor(id: id)
        #expect(ok == true)

        let again = await repo.deleteVendor(id: id)   // already gone
        #expect(again == false)
    }

    // MARK: - Archive

    /// A plain vendor delete used to orphan its filaments through `.nullify`
    /// (owner decision P1, 2026-09-15).
    @Test func deleteVendorRefusesWhileFilamentsReferenceIt() async throws {
        let repo = try makeRepo()
        let vendor = try #require(await repo.addVendor(name: "Polymaker"))
        _ = await repo.addFilament(draft: FilamentDraft(name: "PolyTerra", vendorId: .set(vendor.id)))

        let deleted = await repo.deleteVendor(id: vendor.id)
        #expect(!deleted)
        #expect(repo.vendors.count == 1)
        #expect(repo.filaments.first?.vendor?.id == vendor.id)
        #expect(repo.errorMessage != nil)
    }

    @Test func deleteVendorCascadingRemovesItsFilamentsAndTheirSpools() async throws {
        let repo = try makeRepo()
        let doomed = try #require(await repo.addVendor(name: "Polymaker"))
        let kept = try #require(await repo.addVendor(name: "Prusament"))
        let f1 = try #require(await repo.addFilament(draft: FilamentDraft(name: "PolyTerra", vendorId: .set(doomed.id))))
        _ = await repo.addFilament(draft: FilamentDraft(name: "PolyLite", vendorId: .set(doomed.id)))
        let keptFilament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PETG", vendorId: .set(kept.id))))
        _ = await repo.addSpool(draft: SpoolDraft(filamentId: f1.id))
        let keptSpool = try #require(await repo.addSpool(draft: SpoolDraft(filamentId: keptFilament.id)))

        let deleted = await repo.deleteVendorCascading(id: doomed.id)
        #expect(deleted)
        #expect(repo.vendors.map(\.id) == [kept.id])
        #expect(repo.filaments.map(\.id) == [keptFilament.id])
        #expect(repo.spools.map(\.id) == [keptSpool.id])
    }

    @Test func cascadingDeletesReportAMissingRecord() async throws {
        let repo = try makeRepo()
        #expect(await repo.deleteFilamentCascading(id: 999_999) == false)
        #expect(await repo.deleteVendorCascading(id: 999_999) == false)
    }

    @Test func setSpoolArchivedFlipsArchivedFlag() async throws {
        let repo = try makeRepo()
        let vendor = await repo.addVendor(name: "V")
        let fil = await repo.addFilament(draft: FilamentDraft(name: "F", vendorId: vendor.map { .set($0.id) } ?? .ignore))
        let spool = await repo.addSpool(draft: SpoolDraft(filamentId: fil?.id))
        let id = try #require(spool?.id)

        let ok = await repo.setSpoolArchived(id: id, archived: true)
        #expect(ok == true)
        #expect(repo.spools.first(where: { $0.id == id })?.archived == true)
    }

    // MARK: - Conformance

    @Test func usableThroughProtocol() async throws {
        let repo: any SpoolDataRepository = try makeRepo()
        #expect(await repo.testConnection())
        let vendor = try #require(await repo.addVendor(name: "Via Protocol"))
        #expect(repo.vendors.contains { $0.id == vendor.id })
    }
}
