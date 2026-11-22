//
//  LocalScanResolutionTests.swift
//  SpoolKidTests
//
//  Purpose: Covers the scan resolution cascade running against a local-backed
//  repository (in-memory SwiftData). Verifies embedded-id hit (using persistent
//  local id), card_uid hit, heuristic match, and no-match → .noMatch.
//

import Foundation
import SwiftData
import Testing
@testable import SpoolKid

@MainActor
struct LocalScanResolutionTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
            configurations: config
        )
    }

    private func makeRepo() throws -> LocalRepository {
        let container = try makeContainer()
        return LocalRepository(context: ModelContext(container))
    }

    private func makeResolutionService(repository: any SpoolDataRepository) -> ScanResolutionService {
        ScanResolutionService(
            repository: repository,
            spoolmanDBService: SpoolmanDBService.shared,
            webParserService: WebSpoolParserService.shared,
            identity: TagIdentityPolicy(mode: .spoolID, linkTargets: []),
            ledger: makeIsolatedLedger()
        )
    }

    private func makeTag(
        material: String = "PLA",
        brand: String = "Elegoo",
        name: String? = "PLA Basic",
        colorHex: String = "FF0000",
        spoolmanId: Int? = nil
    ) -> FilamentTagData {
        FilamentTagData(
            name: name,
            material: material,
            subtype: nil,
            brand: brand,
            colorHex: colorHex,
            minNozzleTemp: 190,
            maxNozzleTemp: 240,
            minBedTemp: 35,
            maxBedTemp: 65,
            spoolmanId: spoolmanId
        )
    }

    // MARK: - Embedded-id hit (persistent local id)

    @Test("Local: embedded spool_id (persistent local id) returns authoritativeSpool")
    func localEmbeddedIdReturnsAuthoritative() async throws {
        let repo = try makeRepo()
        let service = makeResolutionService(repository: repo)

        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA Basic")))
        let spool = try #require(await repo.addSpool(draft: SpoolDraft(filamentId: filament.id)))

        let tag = makeTag(spoolmanId: spool.id)
        let scan = ScanResult(cardUID: "aa", tagData: tag, format: .openSpool)

        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .authoritativeSpool(let s) = result {
            #expect(s.id == spool.id)
        } else {
            Issue.record("Expected .authoritativeSpool, got \(result)")
        }
    }

    // MARK: - Ledger scope (P-3)

    /// A ledger row recorded on a Spoolman server must not resolve a
    /// same-numbered Library spool after a switch to the Library.
    @Test("Local: a ledger row from another backend does not resolve a same-id Library spool")
    func ledgerRowFromOtherBackendDoesNotResolve() async throws {
        let repo = try makeRepo()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("http://10.0.0.5:7912", forKey: AppConfig.spoolmanUrlKey)
        let ledger = TagAssociationStore(userDefaults: defaults, key: "k")
        let service = ScanResolutionService(
            repository: repo,
            spoolmanDBService: SpoolmanDBService.shared,
            webParserService: WebSpoolParserService.shared,
            identity: TagIdentityPolicy(mode: .neither, linkTargets: []),
            ledger: ledger
        )
        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA Basic")))
        let spool = try #require(await repo.addSpool(draft: SpoolDraft(filamentId: filament.id)))

        ledger.activeBackend = .spoolman
        ledger.record(uid: "cc", spoolId: spool.id)
        ledger.activeBackend = .local

        let result = await service.resolve(ScanResult(cardUID: "cc", tagData: nil, format: .openSpool), effectiveTagData: nil)
        if case .cardUIDSpool(_, .onDeviceLedger) = result {
            Issue.record("Spoolman's ledger row resolved a Library spool: \(result)")
        }

        ledger.activeBackend = .spoolman
        #expect(ledger.snapshot() == ["CC": spool.id])
    }

    // MARK: - card_uid hit

    /// Since 2026-10-11 a `lot_nr` token is lot text, not a link.
    @Test("Local: a lot_nr card_uid: token alone does not resolve")
    func localLotNrTokenAloneDoesNotResolve() async throws {
        let repo = try makeRepo()
        let service = makeResolutionService(repository: repo)

        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA Basic")))
        _ = try #require(await repo.addSpool(draft: SpoolDraft(filamentId: filament.id, lotNr: .set("card_uid:bb"))))

        await repo.fetchSpools()
        let tag = makeTag()
        let scan = ScanResult(cardUID: "bb", tagData: tag, format: .openSpool)

        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .cardUIDSpool = result {
            Issue.record("A lot_nr token must not resolve, got \(result)")
        }
    }

    /// Spec 2: a link the Library keeps in `card_uids` resolves the scan.
    @Test("Local: a card_uids link returns cardUIDSpool")
    func localCardUIDsLinkReturnsCardUIDSpool() async throws {
        let repo = try makeRepo()
        let service = makeResolutionService(repository: repo)

        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA Basic")))
        let spool = try #require(await repo.addSpool(draft: SpoolDraft(filamentId: filament.id)))
        #expect(await repo.setCardUIDs(spoolId: spool.id, uids: ["04AABBCC"]))

        let scan = ScanResult(cardUID: "04aabbcc", tagData: makeTag(), format: .openSpool)
        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .cardUIDSpool(let s, _) = result {
            #expect(s.id == spool.id)
        } else {
            Issue.record("Expected .cardUIDSpool, got \(result)")
        }
    }

    // MARK: - Heuristic match

    @Test("Local: heuristic match returns matchResults")
    func localHeuristicMatchReturnsMatchResults() async throws {
        let repo = try makeRepo()
        let service = makeResolutionService(repository: repo)

        let vendor = try #require(await repo.addVendor(name: "Elegoo"))
        let filament = try #require(await repo.addFilament(draft: FilamentDraft(
            name: "PLA Basic",
            vendorId: .set(vendor.id),
            material: "PLA",
            colorHex: "FF0000"
        )))
        _ = try #require(await repo.addSpool(draft: SpoolDraft(filamentId: filament.id)))

        await repo.fetchSpools()
        await repo.fetchFilaments()

        let tag = makeTag(material: "PLA", brand: "Elegoo", name: "PLA Basic", colorHex: "FF0000")
        let scan = ScanResult(cardUID: "cc", tagData: tag, format: .openSpool)

        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .matchResults(let matches) = result {
            #expect(!matches.isEmpty)
        } else {
            Issue.record("Expected .matchResults, got \(result)")
        }
    }

    // MARK: - No match

    @Test("Local: no match returns noMatch")
    func localNoMatchReturnsNoMatch() async throws {
        let repo = try makeRepo()
        let service = makeResolutionService(repository: repo)

        let tag = makeTag()
        let scan = ScanResult(cardUID: "dd", tagData: tag, format: .openSpool)

        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .noMatch = result {
        } else {
            Issue.record("Expected .noMatch, got \(result)")
        }
    }

    // MARK: - Write-spool-id round-trip (local mode)

    @Test("Local: write-spool-id embeds persistent local id and re-resolves via authoritative path")
    func localWriteSpoolIdRoundTrip() async throws {
        let repo = try makeRepo()
        let service = makeResolutionService(repository: repo)

        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA Basic")))
        let spool = try #require(await repo.addSpool(draft: SpoolDraft(filamentId: filament.id)))

        let tagData = FilamentTagData.from(spool: spool)
        #expect(tagData.spoolmanId == spool.id)

        let scan = ScanResult(cardUID: "ee", tagData: tagData, format: .openSpool)
        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .authoritativeSpool(let s) = result {
            #expect(s.id == spool.id)
        } else {
            Issue.record("Expected .authoritativeSpool, got \(result)")
        }
    }

    // MARK: - Priority order preserved

    @Test("Local: embedded id beats UID match")
    func localEmbeddedIdBeatsUIDMatch() async throws {
        let repo = try makeRepo()
        let service = makeResolutionService(repository: repo)

        let filament = try #require(await repo.addFilament(draft: FilamentDraft(name: "PLA Basic")))
        let spool42 = try #require(await repo.addSpool(draft: SpoolDraft(filamentId: filament.id)))
        _ = try #require(await repo.addSpool(draft: SpoolDraft(filamentId: filament.id, cardUIDs: ["aa"])))

        let tag = makeTag(spoolmanId: spool42.id)
        let scan = ScanResult(cardUID: "aa", tagData: tag, format: .openSpool)

        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .authoritativeSpool(let s) = result {
            #expect(s.id == spool42.id)
        } else {
            Issue.record("Expected .authoritativeSpool(\(spool42.id)), got \(result)")
        }
    }
}
