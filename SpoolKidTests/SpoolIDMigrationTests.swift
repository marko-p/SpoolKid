//
//  SpoolIDMigrationTests.swift
//  SpoolKidTests
//
//  Spec §3: in Tag Links, a tag carrying spool_id N with no link is linked to
//  N when its filament matches N's, else the hub asks.
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct SpoolIDMigrationTests {
    private static func spool(_ id: Int, archived: Bool? = nil, colorHex: String = "FF0000") -> Spool {
        Spool(
            id: id,
            filament: Filament(id: id * 10, name: "PLA Basic", material: "PLA", vendor: Vendor(id: 1, name: "Elegoo"), colorHex: colorHex),
            archived: archived,
            statusId: nil, externalId: nil, purchaseDate: nil
        )
    }

    private static func tag(spoolmanId: Int?, colorHex: String = "FF0000") -> FilamentTagData {
        FilamentTagData(
            name: "Anything", material: "PLA", subtype: nil, brand: "Elegoo", colorHex: colorHex,
            minNozzleTemp: 190, maxNozzleTemp: 240, minBedTemp: 35, maxBedTemp: 65, spoolmanId: spoolmanId
        )
    }

    private func step(_ tag: FilamentTagData?, uid: String? = "04AA", spools: [Spool], owner: TagOwner = .none) -> ScanResolutionService.SpoolIDMigrationStep {
        ScanResolutionService.spoolIDMigrationStep(tagData: tag, uid: uid, activeSpools: spools, owner: owner)
    }

    @Test func aMatchingTagLinks() {
        guard case .link(let s) = step(Self.tag(spoolmanId: 5), spools: [Self.spool(5)]) else { Issue.record("expected link"); return }
        #expect(s.id == 5)
    }

    /// Name is never compared (HubActionPlan.tagDiffers).
    @Test func aDifferentNameAloneStillLinks() {
        guard case .link = step(Self.tag(spoolmanId: 5), spools: [Self.spool(5)]) else { Issue.record("expected link"); return }
    }

    @Test func aDifferentColourAsks() {
        guard case .ask(let m) = step(Self.tag(spoolmanId: 5, colorHex: "00FF00"), spools: [Self.spool(5)]) else {
            Issue.record("expected ask"); return
        }
        #expect(m.spool.id == 5)
        #expect(m.tagSummary == "Elegoo PLA · #00FF00")
        #expect(m.spoolSummary == "Elegoo PLA · #FF0000")
        #expect(m.linkError == nil)
    }

    @Test func aMissingOrUnknownSpoolSkips() {
        if case .skip = step(Self.tag(spoolmanId: nil), spools: [Self.spool(5)]) {} else { Issue.record("no spool ID") }
        if case .skip = step(Self.tag(spoolmanId: 9), spools: [Self.spool(5)]) {} else { Issue.record("unknown spool") }
        if case .skip = step(Self.tag(spoolmanId: 5), uid: nil, spools: [Self.spool(5)]) {} else { Issue.record("no UID") }
    }

    /// `activeSpools` excludes archived ones; the caller passes it.
    @Test func anOwnedUIDSkips() {
        let owned = step(Self.tag(spoolmanId: 5), spools: [Self.spool(5)], owner: .location(name: "Shelf A"))
        if case .skip = owned {} else { Issue.record("a location's tag must not be taken") }
    }

    @Test func aFailedLinkCarriesItsError() {
        guard case .ask(let m) = step(Self.tag(spoolmanId: 5, colorHex: "00FF00"), spools: [Self.spool(5)]) else {
            Issue.record("expected ask"); return
        }
        #expect(m.withLinkError("Spoolman said no.").linkError == "Spoolman said no.")
    }

    // MARK: - The link itself (needs the facade)

    /// A connected FilaMan-like backend in Tag Links, through the defaults seam.
    private static func linkingStore(_ writer: MockMigrationWriter) -> SpoolDataStore {
        writer.availableTagStores = [.cardUIDs]
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("tagLinks", forKey: AppConfig.tagIdentityModeKey)
        defaults.set(true, forKey: AppConfig.filamanConnectionValidKey)
        return SpoolDataStore(repository: writer, defaults: defaults)
    }

    private static func service(over store: SpoolDataStore, ledger: TagAssociationStore) -> ScanResolutionService {
        ScanResolutionService(
            repository: store, spoolmanDBService: .shared, webParserService: .shared,
            identity: store.tagIdentity, ledger: ledger
        )
    }

    @Test func aMatchingTagIsLinkedAndResolvesAsLinked() async {
        let writer = MockMigrationWriter(serverSpools: [Self.spool(5)], capabilities: .filaman)
        let store = Self.linkingStore(writer)
        let ledger = makeIsolatedLedger()
        let scan = ScanResult(cardUID: "04AA", tagData: Self.tag(spoolmanId: 5), format: .openSpool)

        guard case .cardUIDSpool(let spool, let source) = await Self.service(over: store, ledger: ledger)
            .resolve(scan, effectiveTagData: nil)
        else { Issue.record("expected the linked spool"); return }

        #expect(spool.id == 5)
        #expect(source == .spoolIDMigration)
        #expect(writer.setCardUIDsCalls.map(\.uids) == [["04AA"]])
        #expect(ledger.snapshot()["04AA"] == 5)
    }

    /// A link that did not land never resolves as linked: it is the card,
    /// carrying the backend's reason.
    @Test func aFailedLinkBecomesTheCardWithItsError() async {
        let writer = MockMigrationWriter(serverSpools: [Self.spool(5)], capabilities: .filaman)
        writer.setCardUIDsError = "FilaMan said no."
        let store = Self.linkingStore(writer)
        let ledger = makeIsolatedLedger()
        let scan = ScanResult(cardUID: "04AA", tagData: Self.tag(spoolmanId: 5), format: .openSpool)

        guard case .spoolIDMismatch(let mismatch, _) = await Self.service(over: store, ledger: ledger)
            .resolve(scan, effectiveTagData: nil)
        else { Issue.record("expected the card"); return }

        #expect(mismatch.spool.id == 5)
        #expect(mismatch.linkError?.contains("FilaMan said no.") == true)
        #expect(ledger.snapshot()["04AA"] == nil)
    }

    /// Weigh Spools never shows the card: a mismatch is "not mapped" there.
    @Test func resolveMappedSpoolTreatsAMismatchAsUnmapped() async {
        let service = ScanResolutionService(
            repository: MockMigrationWriter(serverFilaments: [], serverSpools: [Self.spool(5)]),
            spoolmanDBService: .shared, webParserService: .shared,
            identity: TagIdentityPolicy(mode: .tagLinks, linkTargets: [.cardUIDs]),
            ledger: makeIsolatedLedger()
        )
        let scan = ScanResult(cardUID: "04AA", tagData: Self.tag(spoolmanId: 5, colorHex: "00FF00"), format: .openSpool)
        let mapped = await service.resolveMappedSpool(scan)
        #expect(mapped == nil)
        guard case .spoolIDMismatch(let m, _) = await service.resolve(scan, effectiveTagData: nil) else {
            Issue.record("expected the card"); return
        }
        #expect(m.spool.id == 5)
    }
}
