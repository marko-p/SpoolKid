//
//  FilamentTagResolutionTests.swift
//  SpoolKidTests
//
//  Spec 4: a filament link is a resolution tier — after spool links (and a
//  tag's own spool ID in Spool ID mode), before the ledger.
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct FilamentTagResolutionTests {
    private let linkedFilament = Filament(
        id: 5, name: "PLA Basic", material: "PLA", extra: ["card_uids": CardUIDsCodec.encode(["04AA"])]
    )

    private func service(
        _ writer: MockMigrationWriter, mode: TagIdentityMode, ledger: TagAssociationStore = makeIsolatedLedger()
    ) -> ScanResolutionService {
        ScanResolutionService(
            repository: writer,
            spoolmanDBService: SpoolmanDBService.shared,
            webParserService: WebSpoolParserService.shared,
            identity: TagIdentityPolicy(mode: mode, linkTargets: mode == .tagLinks ? [.cardUIDs] : []),
            ledger: ledger
        )
    }

    @Test func aFilamentLinkResolvesToTheFilament() async {
        let writer = MockMigrationWriter(serverFilaments: [linkedFilament])
        let result = await service(writer, mode: .tagLinks)
            .resolve(ScanResult(cardUID: "04aa", tagData: nil, format: nil), effectiveTagData: nil)
        guard case .filamentTag(let filament) = result else {
            Issue.record("expected .filamentTag, got \(result)")
            return
        }
        #expect(filament.id == 5)
    }

    @Test func aSpoolLinkWinsOverAFilamentLink() async {
        let spool = Spool(
            id: 9, filament: linkedFilament, extra: ["card_uids": CardUIDsCodec.encode(["04AA"])],
            statusId: nil, externalId: nil, purchaseDate: nil
        )
        let writer = MockMigrationWriter(serverFilaments: [linkedFilament], serverSpools: [spool])
        let result = await service(writer, mode: .tagLinks)
            .resolve(ScanResult(cardUID: "04AA", tagData: nil, format: nil), effectiveTagData: nil)
        guard case .cardUIDSpool(let resolved, _) = result else {
            Issue.record("expected .cardUIDSpool, got \(result)")
            return
        }
        #expect(resolved.id == 9)
    }

    /// In Spool ID mode a tag's own spool ID wins over a filament link.
    @Test func aSpoolIDWinsInSpoolIDMode() async {
        let spool = Spool(id: 9, filament: linkedFilament, statusId: nil, externalId: nil, purchaseDate: nil)
        let writer = MockMigrationWriter(serverFilaments: [linkedFilament], serverSpools: [spool])
        let tag = FilamentTagData(
            name: "PLA Basic", material: "PLA", subtype: nil, brand: "Elegoo", colorHex: "FF0000",
            minNozzleTemp: 190, maxNozzleTemp: 240, minBedTemp: 35, maxBedTemp: 65, spoolmanId: 9
        )
        let result = await service(writer, mode: .spoolID)
            .resolve(ScanResult(cardUID: "04AA", tagData: tag, format: .openSpool), effectiveTagData: nil)
        guard case .authoritativeSpool(let resolved) = result else {
            Issue.record("expected .authoritativeSpool, got \(result)")
            return
        }
        #expect(resolved.id == 9)
    }

    /// The link wins over the ledger, which only remembers.
    @Test func aFilamentLinkWinsOverTheLedger() async {
        let spool = Spool(id: 9, filament: linkedFilament, statusId: nil, externalId: nil, purchaseDate: nil)
        let writer = MockMigrationWriter(serverFilaments: [linkedFilament], serverSpools: [spool])
        let ledger = makeIsolatedLedger()
        ledger.record(uid: "04AA", spoolId: 9)
        let result = await service(writer, mode: .neither, ledger: ledger)
            .resolve(ScanResult(cardUID: "04AA", tagData: nil, format: nil), effectiveTagData: nil)
        guard case .filamentTag(let filament) = result else {
            Issue.record("expected .filamentTag, got \(result)")
            return
        }
        #expect(filament.id == 5)
    }

    @Test func theCardDescribesTheFilament() {
        let filament = Filament(id: 1, name: "PLA Basic", material: "PLA", vendor: Vendor(id: 2, name: "Elegoo"))
        #expect(FilamentTagCard.detail(for: filament) == "Elegoo · PLA")
        #expect(FilamentTagCard.detail(for: Filament(id: 1, name: "X")) == "")
    }
}
