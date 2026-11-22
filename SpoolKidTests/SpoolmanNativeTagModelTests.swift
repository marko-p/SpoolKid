//
//  SpoolmanNativeTagModelTests.swift
//  SpoolKidTests
//
//  Spoolman 0.27 links tags to spools natively (`spool.tags`). These pin how
//  the model reads them and that a native link wins every lookup, so a stale
//  `card_uids` copy on another spool can never answer for the tag.
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct SpoolmanNativeTagModelTests {
    private let filament = Filament(id: 1, name: "PLA", material: "PLA")

    private func spool(
        _ id: Int, cardUIDs: String? = nil, lotNr: String? = nil, rfid: String? = nil, native: [String] = []
    ) -> Spool {
        Spool(
            id: id, filament: filament, lotNr: lotNr,
            extra: cardUIDs.map { ["card_uids": $0] }, rfidUID: rfid,
            statusId: nil, externalId: nil, purchaseDate: nil, nativeTagUIDs: native
        )
    }

    @Test func decodesSpoolTagsNormalised() throws {
        let json = """
        {"id":1,"filament":{"id":2,"name":"F","tags":[{"uid":"11223344","added":"2026-10-07T22:36:49Z"}]},
         "tags":[{"uid":"04a2b3c4","format":"ntag","added":"2026-10-07T22:36:49Z"},{"uid":"04A2B3C4","added":"x"}]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Spool.self, from: json)
        #expect(decoded.nativeTagUIDs == ["04A2B3C4"])
        #expect(decoded.filament.nativeTagUIDs == ["11223344"])
    }

    @Test func absentTagsKeyMeansNoNativeTags() throws {
        let json = #"{"id":1,"filament":{"id":2,"name":"F"}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Spool.self, from: json)
        #expect(decoded.nativeTagUIDs.isEmpty)
        #expect(decoded.filament.nativeTagUIDs.isEmpty)
    }

    @Test func mappedCardUIDsPutsNativeFirstAndDeduplicates() {
        let s = spool(1, cardUIDs: "\"BB,AA\"", lotNr: "card_uid:CC", rfid: "DD", native: ["AA"])
        #expect(s.mappedCardUIDs == ["AA", "BB", "DD"])
    }

    @Test func writableCardUIDsIncludesNativeButNeverRFID() {
        let s = spool(1, cardUIDs: "\"BB\"", lotNr: "card_uid:CC", rfid: "DD", native: ["AA"])
        #expect(s.writableCardUIDs == ["AA", "BB"])
    }

    @Test func nativeHolderWinsOverAnEarlierCardUIDsCopy() {
        let stale = spool(1, cardUIDs: "\"AA\"")
        let holder = spool(2, native: ["AA"])
        #expect(SpoolMappingService.spool(in: [stale, holder], claiming: "aa")?.id == 2)
    }

    @Test func fallsBackToMappedUIDsWithoutANativeHolder() {
        let a = spool(1, cardUIDs: "\"AA\"")
        #expect(SpoolMappingService.spool(in: [a], claiming: "AA")?.id == 1)
        #expect(SpoolMappingService.spool(in: [a], claiming: "  ") == nil)
        #expect(SpoolMappingService.spool(in: [a], claiming: "EE") == nil)
    }

    /// Since 2026-10-11 a `lot_nr` token is lot text, not a link.
    @Test func aLotNrTokenClaimsNoSpool() {
        #expect(SpoolMappingService.spool(in: [spool(1, lotNr: "card_uid:AA")], claiming: "AA") == nil)
    }

    /// Native first, else the first spool claiming the UID by any route; a
    /// `lot_nr` token claims nothing.
    @Test func theIndexAppliesThePrecedence() {
        let spools = [
            spool(1, cardUIDs: "\"AA,BB\""),
            spool(2, native: ["AA"]),
            spool(3, cardUIDs: "\"BB\"", lotNr: "card_uid:CC"),
            spool(4, rfid: "DD"),
        ]
        #expect(SpoolMappingService.resolvingSpoolIDs(in: spools) == ["AA": 2, "BB": 1, "DD": 4])
    }
}
