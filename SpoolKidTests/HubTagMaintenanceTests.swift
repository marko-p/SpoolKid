//
//  HubTagMaintenanceTests.swift
//  SpoolKidTests
//
//  Tests for the Scan Result Hub's tag-maintenance action seams: the
//  "Empty This Tag" (erase) offer gate, the "Unlink from <spool>" target
//  resolution, and the unlink caveat for UIDs a card_uids write cannot
//  fully detach.
//

import Foundation
import Testing
@testable import SpoolKid

struct HubTagMaintenanceTests {
    private static let testFilament = Filament(
        id: 10,
        name: "PLA+",
        material: "PLA",
        vendor: Vendor(id: 1, name: "TestVendor"),
        colorHex: "FF0000",
        density: 1.24
    )

    private static func makeSpool(
        id: Int,
        cardUIDs: [String] = [],
        lotNr: String? = nil,
        rfidUID: String? = nil,
        archived: Bool? = nil
    ) -> Spool {
        let extra: [String: String]? = cardUIDs.isEmpty
            ? nil
            : ["card_uids": CardUIDsCodec.encode(cardUIDs)]
        return Spool(
            id: id,
            filament: testFilament,
            lotNr: lotNr,
            archived: archived,
            extra: extra,
            rfidUID: rfidUID,
            statusId: nil,
            externalId: nil,
            purchaseDate: nil
        )
    }

    // MARK: - Erase offer gate

    @Test func eraseOfferedForResolvedNFCScanWithUID() {
        #expect(ScanResultHubView.showsEraseButton(
            cardUID: "042F1356C92A81",
            hubState: .unknownTag
        ))
    }

    @Test func eraseOfferedForMappedSpoolResolution() {
        #expect(ScanResultHubView.showsEraseButton(
            cardUID: "042F1356C92A81",
            hubState: .cardUIDSpool(Self.makeSpool(id: 1, cardUIDs: ["042F1356C92A81"]))
        ))
    }

    @Test func eraseOfferedForLocationTagScan() {
        let payload = LocationTagPayload(uuid: UUID(), name: "Shelf A")
        #expect(ScanResultHubView.showsEraseButton(
            cardUID: "042F1356C92A81",
            hubState: .locationTag(payload)
        ))
    }

    @Test func eraseHiddenWithoutUID() {
        // A QR/OCR scan has no physical tag to erase.
        #expect(!ScanResultHubView.showsEraseButton(
            cardUID: nil,
            hubState: .noSpoolman
        ))
    }

    @Test func eraseHiddenForBlankUID() {
        #expect(!ScanResultHubView.showsEraseButton(
            cardUID: "  ",
            hubState: .unknownTag
        ))
    }

    @Test func eraseHiddenWhileResolutionUnsettled() {
        #expect(!ScanResultHubView.showsEraseButton(
            cardUID: "042F1356C92A81",
            hubState: .loading
        ))
        #expect(!ScanResultHubView.showsEraseButton(
            cardUID: "042F1356C92A81",
            hubState: .parsingWebUrl(URL(string: "https://example.com")!)
        ))
        #expect(!ScanResultHubView.showsEraseButton(
            cardUID: "042F1356C92A81",
            hubState: .webChallenge(URL(string: "https://example.com")!)
        ))
    }

    // MARK: - Link state (one answer for Link Tag and Unlink)

    @Test func cardUIDsClaimIsMappedAndReleasable() {
        let spool = Self.makeSpool(id: 42, cardUIDs: ["042F1356C92A81"])
        let state = HubLinkState.resolve(
            uid: "042f1356c92a81", resolvedViaLedger: false, spools: [spool], ledger: [:]
        )
        #expect(state == .mapped(spoolID: 42, releasable: true))
        #expect(state.unlinkSpoolID == 42)
        #expect(!state.offersLinkTag)
    }

    @Test func ledgerClaimCountsWhenTheScanResolvedThroughIt() {
        // Only this iPhone's record knows the tag: it is not linked on the
        // backend, so Link Tag is offered and Unlink is not (issue #24).
        let spool = Self.makeSpool(id: 7)
        let state = HubLinkState.resolve(
            uid: "042F1356C92A81", resolvedViaLedger: true, spools: [spool], ledger: ["042F1356C92A81": 7]
        )
        #expect(state == .ledger(spoolID: 7))
        #expect(state.unlinkSpoolID == nil)
        #expect(state.offersLinkTag)
        #expect(!state.isLinked)
    }

    /// H8 (audit 2026-09-27): `ScanResolutionService.mappedSpool` writes a
    /// ledger row when it resolves a tag by its embedded spool ID. That row is
    /// bookkeeping from this very scan, not a link — counting it offered
    /// "Link This Tag" and "Unlink from …" on the same screen.
    @Test func ledgerRowFromAnEmbeddedIDLookupIsNotALink() {
        let spool = Self.makeSpool(id: 53)
        let state = HubLinkState.resolve(
            uid: "04AABBCCDDEE01", resolvedViaLedger: false, spools: [spool], ledger: ["04AABBCCDDEE01": 53]
        )
        #expect(state == .notLinked)
        #expect(state.unlinkSpoolID == nil)
        #expect(state.offersLinkTag)
    }

    /// Since 2026-10-11 a `lot_nr` token is lot text, not a link.
    @Test func aLotNrTokenAloneIsNotALink() {
        let spool = Self.makeSpool(id: 5, lotNr: "card_uid:042F1356C92A81, batch 7")
        let state = HubLinkState.resolve(
            uid: "042F1356C92A81", resolvedViaLedger: false, spools: [spool], ledger: [:]
        )
        #expect(state == .notLinked)
        #expect(state.offersLinkTag)
    }

    @Test func rfidUIDOnlyClaimIsLinkedButNotReleasable() {
        let spool = Self.makeSpool(id: 5, rfidUID: "042F1356C92A81")
        let state = HubLinkState.resolve(
            uid: "042F1356C92A81", resolvedViaLedger: false, spools: [spool], ledger: [:]
        )
        #expect(state == .mapped(spoolID: 5, releasable: false))
        #expect(state.unlinkSpoolID == nil)
    }

    /// A `card_uids` copy is not enough: removing it leaves the `rfid_uid`
    /// copy resolving the tag to this spool, so a Transfer or an Unlink would
    /// report a release that did not happen (final review FR-3). Earlier
    /// versions wrote `mappedCardUIDs` back, so real FilaMan spools can hold
    /// exactly this.
    @Test func aUIDInCardUIDsAndRFIDUIDIsNotReleasable() {
        let spool = Self.makeSpool(id: 5, cardUIDs: ["042F1356C92A81"], rfidUID: "042f1356c92a81")
        let state = HubLinkState.resolve(
            uid: "042F1356C92A81", resolvedViaLedger: false, spools: [spool], ledger: [:]
        )
        #expect(state == .mapped(spoolID: 5, releasable: false))
        #expect(state.unlinkSpoolID == nil)
    }

    @Test func aLotNrTokenBesideCardUIDsDoesNotBlockRelease() {
        let spool = Self.makeSpool(id: 5, cardUIDs: ["042F1356C92A81"], lotNr: "card_uid:042F1356C92A81")
        let state = HubLinkState.resolve(
            uid: "042F1356C92A81", resolvedViaLedger: false, spools: [spool], ledger: [:]
        )
        #expect(state == .mapped(spoolID: 5, releasable: true))
        #expect(state.unlinkSpoolID == 5)
    }

    @Test func noClaimIsNotLinked() {
        let state = HubLinkState.resolve(
            uid: "042F1356C92A81", resolvedViaLedger: false,
            spools: [Self.makeSpool(id: 1, cardUIDs: ["FFFFFFFFFFFF"])], ledger: [:]
        )
        #expect(state == .notLinked)
    }

    @Test func nilOrEmptyUIDIsNotLinked() {
        #expect(HubLinkState.resolve(
            uid: nil, resolvedViaLedger: true, spools: [Self.makeSpool(id: 1)], ledger: ["042F1356C92A81": 1]
        ) == .notLinked)
        #expect(HubLinkState.resolve(
            uid: "", resolvedViaLedger: true, spools: [Self.makeSpool(id: 1)], ledger: [:]
        ) == .notLinked)
    }

    @Test func ledgerClaimToUnknownSpoolIsNotLinked() {
        #expect(HubLinkState.resolve(
            uid: "042F1356C92A81", resolvedViaLedger: true, spools: [Self.makeSpool(id: 1)],
            ledger: ["042F1356C92A81": 99]
        ) == .notLinked)
    }

    @Test func ledgerClaimToArchivedSpoolIsNotLinked() {
        // The resolution fallback only follows the ledger to an active spool.
        #expect(HubLinkState.resolve(
            uid: "042F1356C92A81", resolvedViaLedger: true, spools: [Self.makeSpool(id: 7, archived: true)],
            ledger: ["042F1356C92A81": 7]
        ) == .notLinked)
    }

    @Test func cardUIDsClaimWinsOverLedger() {
        let cardUIDsSpool = Self.makeSpool(id: 1, cardUIDs: ["042F1356C92A81"])
        let other = Self.makeSpool(id: 2)
        #expect(HubLinkState.resolve(
            uid: "042F1356C92A81", resolvedViaLedger: true, spools: [cardUIDsSpool, other],
            ledger: ["042F1356C92A81": 2]
        ) == .mapped(spoolID: 1, releasable: true))
    }

    @Test func aLotNrTokenDoesNotCompeteWithACardUIDsHolder() {
        let lotNrSpool = Self.makeSpool(id: 1, lotNr: "card_uid:042F1356C92A81")
        let cardUIDsSpool = Self.makeSpool(id: 2, cardUIDs: ["042F1356C92A81"])
        #expect(HubLinkState.resolve(
            uid: "042F1356C92A81", resolvedViaLedger: false, spools: [lotNrSpool, cardUIDsSpool], ledger: [:]
        ) == .mapped(spoolID: 2, releasable: true))
    }

    @Test func linkTagAndUnlinkAreNeverOfferedTogether() {
        let states: [HubLinkState] = [
            .notLinked,
            .mapped(spoolID: 1, releasable: true),
            .mapped(spoolID: 1, releasable: false),
            .ledger(spoolID: 1),
        ]
        for state in states {
            #expect(!(state.offersLinkTag && state.unlinkSpoolID != nil))
        }
    }

    // MARK: - Unlink caveat

    /// A `lot_nr` token no longer holds the tag, so unlinking the
    /// `card_uids` copy releases it cleanly.
    @Test func noCaveatForALotNrTokenBesideCardUIDs() {
        let spool = Self.makeSpool(
            id: 5,
            cardUIDs: ["042F1356C92A81"],
            lotNr: "card_uid:042F1356C92A81"
        )
        #expect(TagLinkService.unlinkCaveat(uid: "042f1356c92a81", spool: spool) == nil)
    }

    @Test func caveatWhenSpoolAlsoHoldsUIDViaRfidBinding() {
        let spool = Self.makeSpool(
            id: 5,
            cardUIDs: ["042F1356C92A81"],
            rfidUID: "042F1356C92A81"
        )
        #expect(TagLinkService.unlinkCaveat(uid: "042F1356C92A81", spool: spool) != nil)
    }

    @Test func noCaveatForCleanCardUIDsRemoval() {
        let spool = Self.makeSpool(id: 5, cardUIDs: ["042F1356C92A81"])
        #expect(TagLinkService.unlinkCaveat(uid: "042F1356C92A81", spool: spool) == nil)
    }

    @Test func noCaveatForLedgerOnlyRelease() {
        // Nothing on the spool held the UID, so removing the ledger row is
        // the whole unlink and it is clean.
        let spool = Self.makeSpool(id: 5)
        #expect(TagLinkService.unlinkCaveat(uid: "042F1356C92A81", spool: spool) == nil)
    }
}
