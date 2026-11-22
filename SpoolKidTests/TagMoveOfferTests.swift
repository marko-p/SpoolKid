//
//  TagMoveOfferTests.swift
//  SpoolKidTests
//
//  The tags a new spool or a transfer takes from the spool the scanned tag
//  belongs to (spec 2026-09-27, D3–D5).
//

import Foundation
import Testing
@testable import SpoolKid

struct TagMoveOfferTests {
    private static let filament = Filament(
        id: 10, name: "PLA+", material: "PLA", vendor: Vendor(id: 1, name: "TestVendor"),
        colorHex: "FF0000", density: 1.24
    )

    private static func spool(
        id: Int, cardUIDs: [String], lotNr: String? = nil, rfidUID: String? = nil, nativeTagUIDs: [String] = []
    ) -> Spool {
        Spool(
            id: id,
            filament: filament,
            lotNr: lotNr,
            extra: cardUIDs.isEmpty ? nil : ["card_uids": CardUIDsCodec.encode(cardUIDs)],
            rfidUID: rfidUID,
            statusId: nil, externalId: nil, purchaseDate: nil, nativeTagUIDs: nativeTagUIDs
        )
    }

    // MARK: - Spoolman 0.27 native tags (final review P-1)

    /// On a 0.27 server `setCardUIDs` unlinks every native tag missing from the
    /// list, so a native tag absent from `card_uids` must survive the move.
    @Test func theDestinationKeepsANativeTagMissingFromItsCardUIDs() {
        let destination = Self.spool(id: 2, cardUIDs: [], nativeTagUIDs: ["04NN"])
        #expect(TagMoveOffer.destinationUIDs(of: destination, adding: ["04AA"]) == ["04NN", "04AA"])
    }

    @Test func theSourceKeepsANativeTagMissingFromItsCardUIDs() {
        let source = Self.spool(id: 1, cardUIDs: ["04AA"], nativeTagUIDs: ["04NN"])
        #expect(TagMoveOffer.remainingSourceUIDs(of: source, moved: ["04AA"]) == ["04NN"])
    }

    /// A moved tag that was also native on the source leaves it.
    @Test func aMovedNativeTagLeavesTheSource() {
        let source = Self.spool(id: 1, cardUIDs: ["04AA", "04bb"], nativeTagUIDs: ["04AA"])
        #expect(TagMoveOffer.remainingSourceUIDs(of: source, moved: ["04aa"]) == ["04BB"])
    }

    /// Spec 2026-10-11 §4: a tag linked only natively can move.
    @Test func aNativeOnlyTagIsOnTheChecklist() throws {
        let offer = try #require(TagMoveOffer.make(
            scannedUID: "04AA", source: Self.spool(id: 1, cardUIDs: ["04AA"], nativeTagUIDs: ["04NN"])
        ))
        #expect(offer.uids == ["04AA", "04NN"])
    }

    @Test func aScannedNativeOnlyTagGetsAnOffer() throws {
        let offer = try #require(TagMoveOffer.make(
            scannedUID: "04nn", source: Self.spool(id: 1, cardUIDs: ["04AA"], nativeTagUIDs: ["04NN"])
        ))
        #expect(offer.uids == ["04NN", "04AA"])
        #expect(offer.scannedUID == "04NN")
    }

    @Test func aTagThatIsNativeAndInCardUIDsIsListedOnce() throws {
        let offer = try #require(TagMoveOffer.make(
            scannedUID: "04AA", source: Self.spool(id: 1, cardUIDs: ["04aa", "04BB"], nativeTagUIDs: ["04AA"])
        ))
        #expect(offer.uids == ["04AA", "04BB"])
    }

    @Test func aNativeTagThatIsAlsoTheRFIDUIDIsLeftOff() throws {
        let offer = try #require(TagMoveOffer.make(
            scannedUID: "04AA", source: Self.spool(id: 1, cardUIDs: ["04AA"], rfidUID: "04NN", nativeTagUIDs: ["04NN"])
        ))
        #expect(offer.uids == ["04AA"])
    }

    /// Neither list picks up `lot_nr` tokens or `rfid_uid`.
    @Test func theUnionCarriesNoLotNrOrRFIDUID() {
        let destination = Self.spool(id: 2, cardUIDs: [], lotNr: "uid:04LL", rfidUID: "04EE", nativeTagUIDs: ["04NN"])
        #expect(TagMoveOffer.destinationUIDs(of: destination, adding: ["04AA"]) == ["04NN", "04AA"])
    }

    @Test func noOfferWhenTheSourceDoesNotHoldTheScannedTag() {
        #expect(TagMoveOffer.make(scannedUID: "04AA", source: Self.spool(id: 1, cardUIDs: ["04BB"])) == nil)
        #expect(TagMoveOffer.make(scannedUID: nil, source: Self.spool(id: 1, cardUIDs: ["04BB"])) == nil)
        #expect(TagMoveOffer.make(scannedUID: " ", source: Self.spool(id: 1, cardUIDs: ["04BB"])) == nil)
    }

    @Test func theScannedTagComesFirstNormalizedAndDeduplicated() throws {
        let offer = try #require(TagMoveOffer.make(
            scannedUID: "04bb", source: Self.spool(id: 53, cardUIDs: ["04AA", "04BB", "04aa"])
        ))
        #expect(offer.uids == ["04BB", "04AA"])
        #expect(offer.scannedUID == "04BB")
        #expect(offer.sourceSpoolID == 53)
    }

    /// D4 (owner, 2026-09-27): both ticked by default — the default of the
    /// toggle this replaces.
    @Test func everyTagStartsTicked() throws {
        let offer = try #require(TagMoveOffer.make(
            scannedUID: "04AA", source: Self.spool(id: 1, cardUIDs: ["04AA", "04BB"])
        ))
        #expect(offer.defaultSelection == ["04AA", "04BB"])
        #expect(offer.movedUIDs(selection: offer.defaultSelection) == ["04AA", "04BB"])
    }

    /// A spool with only the scanned tag offers just that tag, ticked — the
    /// row the form's scan-to-link ticks when that tag is scanned again.
    @Test func aSingleTagSpoolOffersOnlyTheScannedTag() throws {
        let offer = try #require(TagMoveOffer.make(
            scannedUID: "04aa", source: Self.spool(id: 7, cardUIDs: ["04AA"])
        ))
        #expect(offer.uids == ["04AA"])
        #expect(offer.defaultSelection == ["04AA"])
    }

    @Test func onlyTickedTagsMoveInOfferOrder() throws {
        let offer = try #require(TagMoveOffer.make(
            scannedUID: "04BB", source: Self.spool(id: 1, cardUIDs: ["04AA", "04BB", "04CC"])
        ))
        #expect(offer.movedUIDs(selection: ["04CC", "04BB"]) == ["04BB", "04CC"])
        #expect(offer.movedUIDs(selection: []) == [])
    }

    /// The probable bug D3 retires: "Create New Spool from This Tag" left the
    /// tag on the old spool. The source keeps exactly what was not moved.
    @Test func theSourceLosesExactlyTheMovedTags() {
        #expect(TagMoveOffer.remainingSourceUIDs(of: Self.spool(id: 1, cardUIDs: ["04AA", "04BB", "04CC"]), moved: ["04bb"])
            == ["04AA", "04CC"])
        #expect(TagMoveOffer.remainingSourceUIDs(of: Self.spool(id: 1, cardUIDs: ["04AA", "04BB"]), moved: ["04AA", "04BB"])
            == [])
        #expect(TagMoveOffer.remainingSourceUIDs(of: Self.spool(id: 1, cardUIDs: ["04AA"]), moved: [])
            == ["04AA"])
    }

    // MARK: - Which hub scans get an offer

    @Test func aKnownTagGetsAnOffer() throws {
        let source = Self.spool(id: 53, cardUIDs: ["04AA", "04BB"])
        let offer = try #require(ScanResultHubView.tagMoveOffer(for: .spool(source, nil, scannedUID: "04AA")))
        #expect(offer.uids == ["04AA", "04BB"])
    }

    @Test func aTagThatIsNotTheSpoolsOwnGetsNoOffer() {
        // State 2: an unknown tag carrying the spool's ID.
        let source = Self.spool(id: 53, cardUIDs: [])
        #expect(ScanResultHubView.tagMoveOffer(for: .spool(source, nil, scannedUID: "04AA")) == nil)
        #expect(ScanResultHubView.tagMoveOffer(for: .uidOnly("04AA")) == nil)
    }

    // MARK: - Create New Spool cleanup (final review 2026-10-11)

    /// Only the tags the created spool holds leave the source; one its link
    /// write did not land stays where it was rather than on no spool.
    @Test func onlyTagsTheCreatedSpoolHoldsAreTaken() {
        let created = Self.spool(id: 9, cardUIDs: ["04AA"], nativeTagUIDs: ["04NN"])
        #expect(ScanResultHubView.tagsTakenByCreatedSpool(moved: ["04aa", "04NN", "04BB"], created: created)
            == ["04aa", "04NN"])
    }

    @Test func aCreatedSpoolHoldingNoneTakesNothing() {
        let created = Self.spool(id: 9, cardUIDs: [])
        #expect(ScanResultHubView.tagsTakenByCreatedSpool(moved: ["04AA"], created: created).isEmpty)
    }

    // MARK: - Only what SpoolKid can release (I1)

    /// FilaMan's `rfid_uid` is a hardware binding SpoolKid never writes, so a
    /// tag linked only through it cannot be moved — the old spool would keep it.
    @Test func aTagLinkedOnlyThroughRFIDUIDIsNotOffered() {
        #expect(TagMoveOffer.make(scannedUID: "04AA", source: Self.spool(id: 1, cardUIDs: [], rfidUID: "04AA")) == nil)
    }

    @Test func aMixedSpoolOffersOnlyItsCardUIDs() throws {
        let offer = try #require(TagMoveOffer.make(
            scannedUID: "04AA", source: Self.spool(id: 1, cardUIDs: ["04AA"], rfidUID: "04CC")
        ))
        #expect(offer.uids == ["04AA"])
    }

    /// Computing what stays from `mappedCardUIDs` wrote the source's
    /// `rfid_uid` into its `card_uids`.
    @Test func theSourceKeepsOnlyTheCardUIDsItHad() {
        let source = Self.spool(id: 1, cardUIDs: ["04AA", "04BB"], rfidUID: "04CC")
        #expect(TagMoveOffer.remainingSourceUIDs(of: source, moved: ["04aa"]) == ["04BB"])
    }

    @Test func theDestinationNeverGainsItsOwnRFIDUID() {
        let destination = Self.spool(id: 2, cardUIDs: ["04DD"], rfidUID: "04EE")
        let uids = TagMoveOffer.destinationUIDs(of: destination, adding: ["04AA"])
        #expect(uids == ["04DD", "04AA"])
        #expect(!uids.contains("04EE"))
    }

    /// A tag the destination already holds, in any case, is listed once.
    @Test func aTagTheDestinationAlreadyHoldsIsListedOnce() {
        let destination = Self.spool(id: 2, cardUIDs: ["04DD"])
        #expect(TagMoveOffer.destinationUIDs(of: destination, adding: ["04dd"]) == ["04dd"])
    }

    /// A `lot_nr` token is not a link: nothing to move.
    @Test func aTagLinkedOnlyThroughLotNrIsNotOffered() {
        #expect(TagMoveOffer.make(scannedUID: "04AA", source: Self.spool(id: 1, cardUIDs: [], lotNr: "card_uid:04AA")) == nil)
    }

    // MARK: - A card_uids copy is not enough (final review FR-3)

    /// Moving the `card_uids` copy would leave the `rfid_uid` copy resolving
    /// the tag to the source — a move reported that did not happen.
    @Test func noOfferWhenTheScannedTagIsAlsoTheRFIDUID() {
        #expect(TagMoveOffer.make(
            scannedUID: "04AA", source: Self.spool(id: 1, cardUIDs: ["04AA", "04BB"], rfidUID: "04aa")
        ) == nil)
    }

    /// Since 2026-10-11 a `lot_nr` token is lot text, not a second copy.
    @Test func aLotNrTokenNoLongerBlocksTheOffer() throws {
        let offer = try #require(TagMoveOffer.make(
            scannedUID: "04AA", source: Self.spool(id: 1, cardUIDs: ["04AA", "04BB"], lotNr: "card_uid:04AA")
        ))
        #expect(offer.uids == ["04AA", "04BB"])
    }

    @Test func aSecondTagThatIsAlsoTheRFIDUIDIsLeftOffTheChecklist() throws {
        let offer = try #require(TagMoveOffer.make(
            scannedUID: "04AA", source: Self.spool(id: 1, cardUIDs: ["04AA", "04BB"], rfidUID: "04BB")
        ))
        #expect(offer.uids == ["04AA"])
    }
}
