//
//  NFCPendingWriteTests.swift
//  SpoolKidTests
//
//  Purpose: The pending-write enum's accessors. NFCManager's sessions need
//  hardware and are not unit-testable; this pins the pure projection so the
//  refactor cannot silently change what a filament write carries.
//

import Foundation
import Testing
@testable import SpoolKid

struct NFCPendingWriteTests {
    private let tagData = FilamentTagData(
        material: "PLA",
        brand: "Prusament",
        colorHex: "FF0000",
        minNozzleTemp: 215,
        maxNozzleTemp: 225,
        minBedTemp: 55,
        maxBedTemp: 60
    )

    @Test func aFilamentWriteProjectsItsDataFormatAndUID() {
        let pending = NFCManager.PendingWrite.filament(tagData, .openSpool, cardUID: "AABBCCDD")

        // `FilamentTagData` is Codable/Identifiable/Sendable but NOT Equatable,
        // so the projection is checked by identity plus a couple of fields
        // rather than by `==`. Do not add an Equatable conformance to it just
        // to shorten this test — that is a public contract change nothing else
        // needs.
        #expect(pending.filamentData?.id == tagData.id)
        #expect(pending.filamentData?.brand == "Prusament")
        #expect(pending.filamentData?.material == "PLA")
        #expect(pending.tagFormat == .openSpool)
        #expect(pending.cardUID == "AABBCCDD")
        #expect(pending.locationPayload == nil)
    }

    @Test func aLocationWriteCarriesNoFilamentData() {
        let payload = LocationTagPayload(uuid: UUID(), name: "Shelf A")
        let pending = NFCManager.PendingWrite.location(payload)

        #expect(pending.filamentData == nil)
        #expect(pending.tagFormat == nil)
        #expect(pending.locationPayload == payload)
    }

    /// A clone carries bytes, not filament data — nothing downstream of a
    /// filament write (Recent Tags, the tag ledger) may mistake it for one.
    @Test func aCloneCarriesNoFilamentOrLocationData() {
        let snapshot = TagSnapshot.rawPages(firstPage: 4, bytes: [0x7B, 0x00, 0x65, 0x00])
        let pending = NFCManager.PendingWrite.clone(
            snapshot, sourceUID: "04A1B2C3", blockedUIDs: ["AABBCCDD"], allowedUID: nil
        )

        #expect(pending.filamentData == nil)
        #expect(pending.tagFormat == nil)
        #expect(pending.cardUID == nil)
        #expect(pending.locationPayload == nil)
    }
}
