//
//  TagIdentityResolutionTests.swift
//  SpoolKidTests
//
//  Spec §3: a tag's spool_id identifies only in Spool ID mode; links and the
//  ledger resolve in every mode.
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct TagIdentityResolutionTests {
    nonisolated static let spoolID = TagIdentityPolicy(mode: .spoolID, linkTargets: [])
    nonisolated static let links = TagIdentityPolicy(mode: .tagLinks, linkTargets: [.cardUIDs])
    nonisolated static let neither = TagIdentityPolicy(mode: .neither, linkTargets: [])

    private static func spool(_ id: Int, cardUIDs: [String] = []) -> Spool {
        Spool(
            id: id,
            filament: Filament(id: id * 10, name: "PLA Basic", material: "PLA", vendor: Vendor(id: 1, name: "Elegoo"), colorHex: "FF0000"),
            extra: cardUIDs.isEmpty ? nil : ["card_uids": CardUIDsCodec.encode(cardUIDs)],
            statusId: nil, externalId: nil, purchaseDate: nil
        )
    }

    private static func tag(spoolmanId: Int?) -> FilamentTagData {
        FilamentTagData(
            name: "PLA Basic", material: "PLA", subtype: nil, brand: "Elegoo", colorHex: "FF0000",
            minNozzleTemp: 190, maxNozzleTemp: 240, minBedTemp: 35, maxBedTemp: 65, spoolmanId: spoolmanId
        )
    }

    private func service(_ identity: TagIdentityPolicy, spools: [Spool], ledger: TagAssociationStore = makeIsolatedLedger()) -> ScanResolutionService {
        ScanResolutionService(
            repository: MockMigrationWriter(serverFilaments: spools.map(\.filament), serverSpools: spools),
            spoolmanDBService: SpoolmanDBService.shared,
            webParserService: WebSpoolParserService.shared,
            identity: identity,
            ledger: ledger
        )
    }

    /// The tag says spool 42; its UID is linked to spool 7.
    private func conflictingScan() -> ScanResult {
        ScanResult(cardUID: "04AA", tagData: Self.tag(spoolmanId: 42), format: .openSpool)
    }

    private func resolvedID(_ r: ScanResolutionService.Resolution) -> Int? {
        switch r {
        case .authoritativeSpool(let s), .cardUIDSpool(let s, _): s.id
        default: nil
        }
    }

    @Test func spoolIDModeTrustsTheSpoolIDOverALink() async {
        let r = await service(Self.spoolID, spools: [Self.spool(42), Self.spool(7, cardUIDs: ["04AA"])]).resolve(conflictingScan(), effectiveTagData: nil)
        guard case .authoritativeSpool(let s) = r else { Issue.record("expected authoritative, got \(r)"); return }
        #expect(s.id == 42)
    }

    @Test(arguments: [links, neither])
    func otherModesIgnoreTheSpoolID(identity: TagIdentityPolicy) async {
        let r = await service(identity, spools: [Self.spool(42), Self.spool(7, cardUIDs: ["04AA"])]).resolve(conflictingScan(), effectiveTagData: nil)
        #expect(resolvedID(r) == 7)
        if case .authoritativeSpool = r { Issue.record("the spool ID must not identify in \(identity.mode)") }
    }

    /// Neither mode, no link: the spool ID still does not identify.
    @Test func neitherModeWithoutALinkFallsThrough() async {
        let r = await service(Self.neither, spools: [Self.spool(42)]).resolve(
            ScanResult(cardUID: "04BB", tagData: Self.tag(spoolmanId: 42), format: .openSpool), effectiveTagData: nil
        )
        if case .authoritativeSpool = r { Issue.record("spool ID identified in Neither") }
    }

    @Test(arguments: [spoolID, links, neither])
    func theLedgerResolvesInEveryMode(identity: TagIdentityPolicy) async {
        let ledger = makeIsolatedLedger()
        ledger.record(uid: "04CC", spoolId: 7)
        let r = await service(identity, spools: [Self.spool(7)], ledger: ledger).resolve(
            ScanResult(cardUID: "04CC", tagData: nil, format: nil), effectiveTagData: nil
        )
        guard case .cardUIDSpool(let s, .onDeviceLedger) = r else { Issue.record("expected ledger hit, got \(r)"); return }
        #expect(s.id == 7)
    }
}
