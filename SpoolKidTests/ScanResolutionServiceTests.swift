//
//  ScanResolutionServiceTests.swift
//  SpoolKid
//
//  Tests for ScanResolutionService: cascade priority order.
//

import Foundation
import Testing
@testable import SpoolKid

// MARK: - Helpers

private func makeSpool(
    id: Int = 1,
    material: String = "PLA",
    vendorName: String = "Elegoo",
    name: String? = "PLA Basic",
    colorHex: String? = "FF0000",
    diameter: Double? = 1.75,
    extruderTemp: Int? = 220,
    bedTemp: Int? = 65,
    lotNr: String? = nil,
    cardUIDs: [String] = [],
    archived: Bool? = nil
) -> Spool {
    Spool(
        id: id,
        filament: Filament(
            id: id * 10,
            name: name,
            material: material,
            vendor: Vendor(id: 1, name: vendorName),
            colorHex: colorHex,
            density: nil,
            diameter: diameter,
            settingsExtruderTemp: extruderTemp,
            settingsBedTemp: bedTemp
        ),
        remainingWeight: nil,
        initialWeight: nil,
        spoolWeight: nil,
        usedWeight: nil,
        price: nil,
        lotNr: lotNr,
        archived: archived,
        extra: cardUIDs.isEmpty ? nil : ["card_uids": CardUIDsCodec.encode(cardUIDs)],
        statusId: nil, externalId: nil, purchaseDate: nil
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

/// Nothing here may reach the host app's state. A `SpoolmanRepository` reads
/// the app's configured server URL, so on a Simulator pointed at a live
/// Spoolman the cascade's fetches replaced the seeded spools with the
/// server's; `.shared` is the app's real ledger, which these tests both read
/// and wrote (2026-09-28). The mock's fetches are no-ops.
@MainActor
private func makeResolutionService(
    spools: [Spool] = [],
    filaments: [Filament] = [],
    ledger: TagAssociationStore = makeIsolatedLedger()
) -> ScanResolutionService {
    ScanResolutionService(
        repository: MockMigrationWriter(serverFilaments: filaments, serverSpools: spools),
        spoolmanDBService: SpoolmanDBService.shared,
        webParserService: WebSpoolParserService.shared,
        identity: TagIdentityPolicy(mode: .spoolID, linkTargets: []),
        ledger: ledger
    )
}

/// Shared by every suite that builds a `ScanResolutionService`, whose default
/// ledger is the host app's `TagAssociationStore.shared`.
func makeIsolatedLedger() -> TagAssociationStore {
    TagAssociationStore(
        userDefaults: UserDefaults(suiteName: UUID().uuidString)!,
        key: "k"
    )
}

// MARK: - Cascade Priority Tests

@Suite("ScanResolutionService cascade priority")
@MainActor
struct ScanResolutionServiceTests {

    @Test("Embedded spool_id returns authoritativeSpool")
    func embeddedSpoolIdReturnsAuthoritative() async {
        let spool = makeSpool(id: 42)
        let service = makeResolutionService(spools: [spool])
        let tag = makeTag(spoolmanId: 42)
        let scan = ScanResult(cardUID: "aa", tagData: tag, format: .openSpool)

        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .authoritativeSpool(let s) = result {
            #expect(s.id == 42)
        } else {
            Issue.record("Expected .authoritativeSpool, got \(result)")
        }
    }

    @Test("Embedded spool_id beats UID match")
    func embeddedSpoolIdBeatsUIDMatch() async {
        let spool42 = makeSpool(id: 42)
        let spool99 = makeSpool(id: 99, cardUIDs: ["aa"])
        let service = makeResolutionService(spools: [spool42, spool99])
        let tag = makeTag(spoolmanId: 42)
        let scan = ScanResult(cardUID: "aa", tagData: tag, format: .openSpool)

        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .authoritativeSpool(let s) = result {
            #expect(s.id == 42)
        } else {
            Issue.record("Expected .authoritativeSpool(42), got \(result)")
        }
    }

    @Test("cardUID match returns cardUIDSpool when no embedded spool_id")
    func uidMatchReturnsCardUIDSpool() async {
        let spool = makeSpool(id: 7, cardUIDs: ["bb"])
        let service = makeResolutionService(spools: [spool])
        let tag = makeTag()
        let scan = ScanResult(cardUID: "bb", tagData: tag, format: .openSpool)

        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .cardUIDSpool(let s, _) = result {
            #expect(s.id == 7)
        } else {
            Issue.record("Expected .cardUIDSpool, got \(result)")
        }
    }

    /// Since 2026-10-11 a `lot_nr` token is lot text, not a link.
    @Test("A lot_nr card_uid: token alone no longer resolves")
    func lotNrTokenAloneNoLongerResolves() async {
        let spool = makeSpool(id: 7, lotNr: "card_uid:bb")
        let service = makeResolutionService(spools: [spool])
        let scan = ScanResult(cardUID: "bb", tagData: makeTag(), format: .openSpool)

        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .cardUIDSpool = result {
            Issue.record("A lot_nr token must not resolve, got \(result)")
        }
    }

    /// A token hit before 2026-10-11 recorded the UID in the ledger, which
    /// still identifies the spool — the ledger tier, never a link.
    @Test("A lot_nr token with a ledger row resolves through the ledger")
    func lotNrTokenWithALedgerRowResolvesThroughTheLedger() async {
        let spool = makeSpool(id: 7, lotNr: "card_uid:bb")
        let ledger = makeIsolatedLedger()
        ledger.record(uid: "bb", spoolId: 7)
        let service = makeResolutionService(spools: [spool], ledger: ledger)
        let scan = ScanResult(cardUID: "bb", tagData: makeTag(), format: .openSpool)

        let result = await service.resolve(scan, effectiveTagData: nil)

        guard case .cardUIDSpool(let s, let source) = result else {
            Issue.record("Expected .cardUIDSpool via the ledger, got \(result)")
            return
        }
        #expect(s.id == 7)
        #expect(source == .onDeviceLedger)
    }

    @Test("Heuristic match returns matchResults when no embedded id or UID match")
    func heuristicMatchReturnsMatchResults() async {
        let spool = makeSpool(id: 5, material: "PLA", vendorName: "Elegoo", name: "PLA Basic", colorHex: "FF0000")
        let service = makeResolutionService(spools: [spool])
        let tag = makeTag(material: "PLA", brand: "Elegoo", name: "PLA Basic", colorHex: "FF0000")
        let scan = ScanResult(cardUID: "cc", tagData: tag, format: .openSpool)

        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .matchResults(let matches) = result {
            #expect(!matches.isEmpty)
            #expect(matches.first?.spool.id == 5)
        } else {
            Issue.record("Expected .matchResults, got \(result)")
        }
    }

    @Test("UID only (no tag data) returns unknownTag")
    func uidOnlyReturnsUnknownTag() async {
        let service = makeResolutionService(spools: [makeSpool()])
        let scan = ScanResult(cardUID: "dd", tagData: nil, format: nil)

        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .unknownTag = result {
        } else {
            Issue.record("Expected .unknownTag, got \(result)")
        }
    }

    @Test("Empty library with tag data returns noMatch")
    func emptyLibraryReturnsNoMatch() async {
        let service = makeResolutionService(spools: [], filaments: [])
        let tag = makeTag()
        let scan = ScanResult(cardUID: "ff", tagData: tag, format: .openSpool)

        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .noMatch = result {
        } else {
            Issue.record("Expected .noMatch, got \(result)")
        }
    }

    @Test("Embedded spool_id not found in library falls through to UID match")
    func embeddedIdNotFoundFallsThrough() async {
        let spool = makeSpool(id: 99, cardUIDs: ["aa"])
        let service = makeResolutionService(spools: [spool])
        let tag = makeTag(spoolmanId: 42)
        let scan = ScanResult(cardUID: "aa", tagData: tag, format: .openSpool)

        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .cardUIDSpool(let s, _) = result {
            #expect(s.id == 99)
        } else {
            Issue.record("Expected .cardUIDSpool(99), got \(result)")
        }
    }

    @Test("UID match beats heuristic match")
    func uidMatchBeatsHeuristic() async {
        let uidSpool = makeSpool(id: 10, cardUIDs: ["aa"])
        let heuristicSpool = makeSpool(id: 20, material: "PLA", vendorName: "Elegoo", name: "PLA Basic", colorHex: "FF0000")
        let service = makeResolutionService(spools: [uidSpool, heuristicSpool])
        let tag = makeTag(material: "PLA", brand: "Elegoo", name: "PLA Basic", colorHex: "FF0000")
        let scan = ScanResult(cardUID: "aa", tagData: tag, format: .openSpool)

        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .cardUIDSpool(let s, _) = result {
            #expect(s.id == 10)
        } else {
            Issue.record("Expected .cardUIDSpool(10), got \(result)")
        }
    }

    @Test("Archived spool is ignored for embedded spool_id")
    func archivedSpoolIgnoredForEmbeddedId() async {
        let spool = makeSpool(id: 42, archived: true)
        let service = makeResolutionService(spools: [spool])
        let tag = makeTag(spoolmanId: 42)
        let scan = ScanResult(cardUID: "aa", tagData: tag, format: .openSpool)

        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .authoritativeSpool = result {
            Issue.record("Archived spool must not resolve as authoritative, got \(result)")
        }
    }

    @Test("Archived spool is ignored for cardUID match")
    func archivedSpoolIgnoredForCardUID() async {
        let spool = makeSpool(id: 7, cardUIDs: ["cc"], archived: true)
        let service = makeResolutionService(spools: [spool])
        let tag = makeTag()
        let scan = ScanResult(cardUID: "cc", tagData: tag, format: .openSpool)

        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .cardUIDSpool = result {
            Issue.record("Archived spool must not resolve via cardUID, got \(result)")
        }
    }

    // MARK: - Ledger fallback tests (G15)

    @Test("Ledger resolves when card_uids misses")
    func ledgerResolvesWhenCardUIDsMisses() async {
        let spool = makeSpool(id: 55)  // no card_uids entry
        let ledger = makeIsolatedLedger()
        ledger.record(uid: "ee", spoolId: 55)
        let service = makeResolutionService(spools: [spool], ledger: ledger)
        let tag = makeTag()
        let scan = ScanResult(cardUID: "ee", tagData: tag, format: .openSpool)

        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .cardUIDSpool(let s, _) = result {
            #expect(s.id == 55)
        } else {
            Issue.record("Expected .cardUIDSpool(55) via ledger fallback, got \(result)")
        }
    }

    @Test("card_uids wins over ledger")
    func cardUIDsWinsOverLedger() async {
        let spoolA = makeSpool(id: 10, cardUIDs: ["ff"])  // card_uids has "ff"
        let spoolB = makeSpool(id: 20)
        let ledger = makeIsolatedLedger()
        ledger.record(uid: "ff", spoolId: 20)  // ledger points to B
        let service = makeResolutionService(spools: [spoolA, spoolB], ledger: ledger)
        let tag = makeTag()
        let scan = ScanResult(cardUID: "ff", tagData: tag, format: .openSpool)

        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .cardUIDSpool(let s, _) = result {
            #expect(s.id == 10, "card_uids (spool A) must win over ledger (spool B)")
        } else {
            Issue.record("Expected .cardUIDSpool(10), got \(result)")
        }
    }

    @Test("Ledger skips archived owner")
    func ledgerSkipsArchivedOwner() async {
        let archived = makeSpool(id: 77, archived: true)
        let ledger = makeIsolatedLedger()
        ledger.record(uid: "gg", spoolId: 77)
        let service = makeResolutionService(spools: [archived], ledger: ledger)
        let tag = makeTag()
        let scan = ScanResult(cardUID: "gg", tagData: tag, format: .openSpool)

        let result = await service.resolve(scan, effectiveTagData: nil)

        if case .cardUIDSpool = result {
            Issue.record("Archived ledger owner must not resolve as cardUIDSpool, got \(result)")
        }
    }

    @Test("Scan records ledger on card_uids hit")
    func scanRecordsLedgerOnUIDHit() async {
        let spool = makeSpool(id: 33, cardUIDs: ["hh"])
        let ledger = makeIsolatedLedger()
        let service = makeResolutionService(spools: [spool], ledger: ledger)
        let tag = makeTag()
        let scan = ScanResult(cardUID: "hh", tagData: tag, format: .openSpool)

        _ = await service.resolve(scan, effectiveTagData: nil)

        let normUID = SpoolMappingService.normalizeUID("hh")
        #expect(ledger.snapshot()[normUID] == 33)
    }
}

// MARK: - Catalogue candidates ("Search … for Similar Filaments")

/// Records the URLs the catalogue asked for and answers each from `answer`.
private nonisolated final class CandidateFetch: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private let answer: @Sendable (URL) throws -> Data

    init(answer: @escaping @Sendable (URL) throws -> Data) {
        self.answer = answer
    }

    var requested: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }

    /// The requests for `/filaments` (the manufacturer lookups excluded).
    var filamentRequests: [URL] { requested.filter { $0.path.hasSuffix("/filaments") } }

    var catalog: FilaManDBCatalog {
        FilaManDBCatalog(fetch: { url in
            self.record(url)
            return try self.answer(url)
        })
    }

    private func record(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        urls.append(url)
    }

    static func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}

/// Counts how often the SpoolmanDB list was asked for.
private final class CatalogAsks {
    private(set) var count = 0
    func ask() { count += 1 }
}

@Suite("ScanResolutionService catalogue candidates")
@MainActor
struct ScanResolutionCatalogueTests {
    /// One FilaManDB `/filaments` page (measured 2026-10-18), trimmed.
    private nonisolated static let filamentPage = Data("""
    {"total":2,"page":1,"page_size":200,"items":[
     {"id":18517,"color_name":"Galaxy Black","designation":"   Other    - Galaxy Black","hex_color":"#1A1A1A",
      "diameter_mm":1.75,"density_g_cm3":1.24,"nominal_weight_g":1000,
      "manufacturer":{"id":79,"name":"add:north"},"material":{"id":11,"key":"pla","name":"PLA"},
      "spool_profile":{"id":721,"name":"207g Spool","empty_weight_g":207.0,"spool_material":"Plastic"}},
     {"id":22631,"color_name":"30D White","designation":"   Other    - 30D White","hex_color":"#FFFFFF",
      "diameter_mm":1.75,"density_g_cm3":null,"nominal_weight_g":850,
      "manufacturer":{"id":293,"name":"Fiberlogy"},"material":{"id":43,"key":"tpu","name":"TPU"},
      "spool_profile":null}
    ]}
    """.utf8)

    private nonisolated static let manufacturerPage = Data("""
    {"total":1,"page":1,"page_size":200,"items":[{"id":79,"name":"add:north"}]}
    """.utf8)

    /// A `/filaments` page of 200 plain PLA rows whose ids start at `page * 1000`.
    private nonisolated static func pagedFilaments(_ url: URL, total: Int) -> Data {
        let page = Int(CandidateFetch.query(url, "page") ?? "1") ?? 1
        let rows = (0..<200).map { index in
            """
            {"id":\(page * 1000 + index),"color_name":"Colour \(page)-\(index)","hex_color":"#1A1A1A",
             "diameter_mm":1.75,"nominal_weight_g":1000,
             "manufacturer":{"id":79,"name":"add:north"},"material":{"id":11,"key":"pla","name":"PLA"},
             "spool_profile":null}
            """
        }
        return Data("{\"total\":\(total),\"page\":\(page),\"page_size\":200,\"items\":[\(rows.joined(separator: ","))]}".utf8)
    }

    /// The manufacturers page and the fixture: what FilaManDB answers for add:north.
    private nonisolated static func addNorth(_ url: URL) throws -> Data {
        url.path.hasSuffix("/manufacturers") ? manufacturerPage : filamentPage
    }

    private static func localFilament() -> Filament {
        Filament(
            id: 5, name: "Basic", material: "PLA", vendor: Vendor(id: 1, name: "Elegoo"),
            colorHex: "1A1A1A", density: 1.24, diameter: 1.75
        )
    }

    private static func service(
        capabilities: BackendCapabilities,
        filaments: [Filament] = [],
        spoolmanDB: SpoolmanDBService? = nil,
        fetch: CandidateFetch
    ) -> ScanResolutionService {
        ScanResolutionService(
            repository: MockMigrationWriter(serverFilaments: filaments, capabilities: capabilities),
            spoolmanDBService: spoolmanDB ?? SpoolmanDBService(publicCatalog: { [] }),
            webParserService: WebSpoolParserService.shared,
            identity: TagIdentityPolicy(mode: .spoolID, linkTargets: []),
            ledger: makeIsolatedLedger(),
            filamanDB: fetch.catalog
        )
    }

    private static func catalogueIDs(_ load: ScanResolutionService.CandidateLoad) -> [String] {
        catalogueIDs(load.candidates)
    }

    private static func catalogueIDs(_ candidates: [ScanResolutionService.NewSpoolSource]) -> [String] {
        candidates.compactMap {
            if case .spoolmanDB(let entry) = $0 { return entry.id }
            return nil
        }
    }

    private static func allLocal(_ candidates: [ScanResolutionService.NewSpoolSource]) -> Bool {
        candidates.allSatisfy {
            if case .local = $0 { return true }
            return false
        }
    }

    @Test("FilaMan's candidates are the tag brand's FilaManDB filaments")
    func filamanCandidatesComeFromFilaManDB() async throws {
        let fetch = CandidateFetch(answer: Self.addNorth)
        let asks = CatalogAsks()
        let service = Self.service(
            capabilities: .filaman,
            spoolmanDB: SpoolmanDBService(publicCatalog: { asks.ask(); return [] }),
            fetch: fetch
        )

        let load = await service.newSpoolSourceCandidates(
            for: makeTag(brand: "add:north", name: "Galaxy Black", colorHex: "1A1A1A")
        )

        #expect(load.catalogue == .answered)
        #expect(Self.catalogueIDs(load).contains("filamandb-18517"))
        // The brand's filaments are asked for by manufacturer, not by search text.
        let filamentRequest = try #require(fetch.filamentRequests.first)
        #expect(CandidateFetch.query(filamentRequest, "manufacturer_id") == "79")
        #expect(CandidateFetch.query(filamentRequest, "search") == nil)
        // The SpoolmanDB list is not used on FilaMan, so it is not downloaded.
        #expect(asks.count == 0)
    }

    @Test("FilaMan reads every page of the brand, at most ten")
    func filamanReadsEveryPageOfTheBrandUpToTen() async {
        let fetch = CandidateFetch { url in
            url.path.hasSuffix("/manufacturers") ? Self.manufacturerPage : Self.pagedFilaments(url, total: 3_000)
        }
        let service = Self.service(capabilities: .filaman, fetch: fetch)

        let load = await service.newSpoolSourceCandidates(for: makeTag(brand: "add:north"))

        let pages = fetch.filamentRequests.compactMap { CandidateFetch.query($0, "page").flatMap(Int.init) }
        #expect(pages == Array(1...10))
        #expect(load.catalogue == .answered)
        let ids = Self.catalogueIDs(load)
        #expect(ids.contains("filamandb-10000"))
        #expect(!ids.contains("filamandb-11000"))
    }

    @Test("FilaMan without a brand offers local candidates only and asks nothing")
    func filamanWithoutABrandOffersLocalOnly() async {
        let fetch = CandidateFetch(answer: Self.addNorth)
        let service = Self.service(capabilities: .filaman, filaments: [Self.localFilament()], fetch: fetch)

        let load = await service.newSpoolSourceCandidates(for: makeTag(brand: "  "))

        #expect(!load.candidates.isEmpty)
        #expect(Self.allLocal(load.candidates))
        #expect(load.catalogue == .noBrand)
        #expect(fetch.requested.isEmpty)
    }

    @Test("FilaMan with a brand FilaManDB does not list offers local candidates only")
    func filamanWithAnUnknownManufacturerOffersLocalOnly() async {
        let fetch = CandidateFetch { url in
            guard url.path.hasSuffix("/manufacturers") else { throw URLError(.badServerResponse) }
            return Data("{\"total\":0,\"page\":1,\"page_size\":200,\"items\":[]}".utf8)
        }
        let service = Self.service(capabilities: .filaman, filaments: [Self.localFilament()], fetch: fetch)

        let load = await service.newSpoolSourceCandidates(for: makeTag(brand: "Nobody Makes This"))

        #expect(!load.candidates.isEmpty)
        #expect(Self.allLocal(load.candidates))
        #expect(load.catalogue == .noBrand)
        #expect(fetch.filamentRequests.isEmpty)
    }

    @Test("An unreachable FilaManDB offers local candidates only")
    func filamanDBUnreachableOffersLocalOnly() async {
        let fetch = CandidateFetch { _ in throw URLError(.notConnectedToInternet) }
        let service = Self.service(capabilities: .filaman, filaments: [Self.localFilament()], fetch: fetch)

        let load = await service.newSpoolSourceCandidates(for: makeTag(brand: "add:north"))

        #expect(!load.candidates.isEmpty)
        #expect(Self.allLocal(load.candidates))
        #expect(load.catalogue == .failed)
        #expect(!fetch.requested.isEmpty)
    }

    /// A closed list cancels its load: that is neither a failure to show nor
    /// a reason to say the brand has nothing.
    @Test("A cancelled FilaManDB load is not reported as a failure")
    func aCancelledLoadIsNotAFailure() async {
        let fetch = CandidateFetch { _ in throw CancellationError() }
        let service = Self.service(capabilities: .filaman, filaments: [Self.localFilament()], fetch: fetch)

        let load = await service.newSpoolSourceCandidates(for: makeTag(brand: "add:north"))

        #expect(load.catalogue != .failed)
        #expect(load.catalogue != .noBrand)
        #expect(Self.allLocal(load.candidates))
    }

    @Test("A failure on the brand's later pages keeps the local candidates")
    func aFailedLaterPageOffersLocalOnly() async {
        let fetch = CandidateFetch { url in
            if url.path.hasSuffix("/manufacturers") { return Self.manufacturerPage }
            if CandidateFetch.query(url, "page") == "2" { throw URLError(.timedOut) }
            return Self.pagedFilaments(url, total: 450)
        }
        let service = Self.service(capabilities: .filaman, filaments: [Self.localFilament()], fetch: fetch)

        let load = await service.newSpoolSourceCandidates(for: makeTag(brand: "add:north"))

        #expect(!load.candidates.isEmpty)
        #expect(Self.allLocal(load.candidates))
        #expect(load.catalogue == .failed)
    }

    @Test("Elsewhere the candidates are still the SpoolmanDB list")
    func spoolmanCandidatesStillComeFromSpoolmanDB() async {
        let entry = SpoolmanDBFilament(
            id: "elegoo_pla_basic_red", manufacturer: "Elegoo", name: "Basic Red", material: "PLA",
            spoolType: nil, density: 1.24, weight: 1000, spoolWeight: 150, diameter: 1.75,
            colorHex: "FF0000", extruderTemp: nil, bedTemp: nil
        )
        let fetch = CandidateFetch(answer: Self.addNorth)
        let service = Self.service(
            capabilities: .spoolman,
            spoolmanDB: SpoolmanDBService(publicCatalog: { [entry] }),
            fetch: fetch
        )

        let load = await service.newSpoolSourceCandidates(for: makeTag())

        #expect(Self.catalogueIDs(load) == ["elegoo_pla_basic_red"])
        #expect(load.catalogue == .answered)
        #expect(fetch.requested.isEmpty)
    }

    @Test("A SpoolmanDB list that could not be loaded is reported, and the local candidates stand")
    func spoolmanDBUnreachableIsReported() async {
        let fetch = CandidateFetch(answer: Self.addNorth)
        let service = Self.service(
            capabilities: .spoolman,
            filaments: [Self.localFilament()],
            spoolmanDB: SpoolmanDBService(publicCatalog: { throw URLError(.notConnectedToInternet) }),
            fetch: fetch
        )

        let load = await service.newSpoolSourceCandidates(for: makeTag(brand: "Elegoo"))

        #expect(load.catalogue == .failed)
        #expect(!load.candidates.isEmpty)
        #expect(Self.allLocal(load.candidates))
    }
}
