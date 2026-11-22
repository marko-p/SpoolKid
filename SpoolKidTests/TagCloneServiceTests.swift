//
//  TagCloneServiceTests.swift
//  SpoolKidTests
//
//  Clone Tag's decisions outside the NFC session: when the hub offers it,
//  which tags the copy may not land on, and what the user is asked once it
//  lands. Nothing here may link a tag the user did not say yes to, or unlink
//  one before the copy is on it.
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct TagCloneServiceTests {

    private static let filament = Filament(
        id: 10,
        name: "PLA+",
        material: "PLA",
        vendor: Vendor(id: 1, name: "TestVendor"),
        colorHex: "FF0000",
        density: 1.24
    )
    private static let spool = Spool(id: 40, filament: filament, remainingWeight: 750, statusId: nil, externalId: nil, purchaseDate: nil)
    private static let shelf = LocationRecord(uuid: UUID(), name: "Shelf A", tagUIDs: ["aabbccdd"])
    private static let ndefSnapshot = TagSnapshot.ndef([
        NDEFRecordSnapshot(typeNameFormat: 0x02, type: Data("application/json".utf8), identifier: Data(), payload: Data("{}".utf8))
    ])

    private func scan(format: ScanResult.DetectedFormat?, snapshot: TagSnapshot?, location: LocationTagPayload? = nil) -> ScanResult {
        ScanResult(cardUID: "04A1B2C3", tagData: nil, format: format, locationTag: location, tagSnapshot: snapshot)
    }

    // MARK: - The button

    @Test func aScanWithNothingToCopyOffersNoClone() {
        #expect(!TagCloneService.showsCloneButton(result: scan(format: nil, snapshot: nil), hubState: .unknownTag))
        #expect(!TagCloneService.showsCloneButton(result: scan(format: .openSpool, snapshot: .ndef([])), hubState: .noSpoolman))
    }

    /// The button would sit above a spinner while the hub is still resolving.
    @Test func theButtonWaitsForResolutionToSettle() throws {
        let result = scan(format: .webUrl, snapshot: Self.ndefSnapshot)
        let url = try #require(URL(string: "https://example.com"))
        #expect(!TagCloneService.showsCloneButton(result: result, hubState: .loading))
        #expect(!TagCloneService.showsCloneButton(result: result, hubState: .parsingWebUrl(url)))
        #expect(!TagCloneService.showsCloneButton(result: result, hubState: .webChallenge(url)))
    }

    @Test func everySettledStateOffersTheButton() {
        let result = scan(format: .openSpool, snapshot: Self.ndefSnapshot)
        let settled: [ScanResultHubView.HubState] = [
            .authoritativeSpool(Self.spool), .cardUIDSpool(Self.spool), .matchResults([]),
            .unknownTag, .noSpoolman, .locationTag(LocationTagPayload(uuid: UUID(), name: "Shelf A"))
        ]
        for state in settled {
            #expect(TagCloneService.showsCloneButton(result: result, hubState: state))
        }
    }

    /// The one part of the old caption that is a warning, not a description:
    /// shown as the Clone Tag menu item's subtitle.
    @Test func onlyAnElegooCloneCarriesAnUntestedWarning() {
        let elegoo = TagCloneService.untestedWarning(
            for: scan(format: .elegoo, snapshot: .rawPages(firstPage: 4, bytes: [1, 2, 3, 4]))
        )
        #expect(elegoo == "Copies of ELEGOO tags haven't been tested on an ELEGOO printer yet.")
        #expect(TagCloneService.untestedWarning(
            for: scan(format: .anycubicACE, snapshot: .rawPages(firstPage: 4, bytes: [1, 2, 3, 4]))
        ) == nil)
        #expect(TagCloneService.untestedWarning(for: scan(format: .openSpool, snapshot: Self.ndefSnapshot)) == nil)
    }

    // MARK: - Whose tag it is

    @Test func aResolvedSpoolOwnsTheScannedTagWithItsLedgerUIDs() {
        let owner = TagCloneService.sourceOwner(
            hubState: .cardUIDSpool(Self.spool), locationRecord: nil,
            ledger: ["aabbccdd": 40, "11223344": 41]
        )
        #expect(owner == .spool(id: 40, label: Self.spool.listTitle, uids: ["AABBCCDD"]))
    }

    @Test func anEmbeddedSpoolIDOwnsTheScannedTagToo() {
        let owner = TagCloneService.sourceOwner(hubState: .authoritativeSpool(Self.spool), locationRecord: nil, ledger: [:])
        #expect(owner == .spool(id: 40, label: Self.spool.listTitle, uids: []))
    }

    @Test func aKnownLocationOwnsItsTag() {
        let owner = TagCloneService.sourceOwner(
            hubState: .locationTag(LocationTagPayload(uuid: Self.shelf.uuid, name: "Shelf A")),
            locationRecord: Self.shelf, ledger: [:]
        )
        #expect(owner == .location(uuid: Self.shelf.uuid, name: "Shelf A", uids: ["AABBCCDD"]))
    }

    @Test func anUnknownLocationAndAnUnmatchedFilamentOwnNothing() {
        let payload = LocationTagPayload(uuid: UUID(), name: "Shelf Z")
        #expect(TagCloneService.sourceOwner(hubState: .locationTag(payload), locationRecord: nil, ledger: [:]) == .none)
        #expect(TagCloneService.sourceOwner(hubState: .matchResults([]), locationRecord: nil, ledger: ["aabbccdd": 40]) == .none)
    }

    /// A spool's own second tag is not "something else's".
    @Test func theOwnersOwnTagsAreNotBlocked() {
        let owner = TagCloneService.Owner.spool(id: 40, label: "PLA+", uids: ["AABBCCDD"])
        #expect(TagCloneService.blockedUIDs(claimed: ["aabbccdd", "11223344", "55:66:77:88"], owner: owner)
            == ["11223344", "55667788"])
    }

    /// The hub's spool is a resolve-time copy and the ledger outlives backend
    /// changes: a ledger row for a tag another spool now holds is not the owner's.
    @Test func aLedgerRowForATagAnotherSpoolNowHoldsIsNotTheOwners() {
        let other = Spool(id: 41, filament: Self.filament, extra: ["card_uids": "AABBCCDD"], statusId: nil, externalId: nil, purchaseDate: nil)
        let owner = TagCloneService.sourceOwner(
            hubState: .cardUIDSpool(Self.spool), locationRecord: nil,
            ledger: ["aabbccdd": 40, "55667788": 40], spools: [Self.spool, other]
        )
        #expect(owner == .spool(id: 40, label: Self.spool.listTitle, uids: ["55667788"]))
    }

    @Test func theStoresCurrentSpoolReplacesTheResolveTimeCopy() {
        let current = Spool(id: 40, filament: Self.filament, extra: ["card_uids": "99887766"], statusId: nil, externalId: nil, purchaseDate: nil)
        let owner = TagCloneService.sourceOwner(
            hubState: .authoritativeSpool(Self.spool), locationRecord: nil, ledger: [:], spools: [current]
        )
        #expect(owner == .spool(id: 40, label: current.listTitle, uids: ["99887766"]))
    }

    // MARK: - After the write

    @Test func refusalsAndCancellationsFollowUpWithNothing() {
        let owner = TagCloneService.Owner.spool(id: 40, label: "PLA+", uids: [])
        for result: NFCManager.CloneWriteResult? in [nil, .sameTag, .failed("Tag is not writable.")] {
            #expect(TagCloneService.followUp(after: result, pendingUnlinkUID: nil, owner: owner, writesLinks: true) == .nothing)
        }
    }

    @Test func aBlockedTagOffersUnlinkAndContinue() {
        #expect(TagCloneService.followUp(after: .blocked(uid: "11223344"), pendingUnlinkUID: nil, owner: .none, writesLinks: true)
            == .offerUnlink(uid: "11223344"))
    }

    /// Write first, unlink after — and only for the tag the user agreed to.
    @Test func theAgreedTagIsReleasedOnlyOnceTheCopyLandsOnIt() {
        let owner = TagCloneService.Owner.spool(id: 40, label: "PLA+", uids: [])
        #expect(TagCloneService.followUp(after: .written(uid: "11223344"), pendingUnlinkUID: "11:22:33:44", owner: owner, writesLinks: true)
            == .releaseThenLink(uid: "11223344", then: .askToLinkSpool(spoolID: 40, label: "PLA+", uid: "11223344")))
    }

    @Test func aCopyOnADifferentTagReleasesNothing() {
        let owner = TagCloneService.Owner.spool(id: 40, label: "PLA+", uids: [])
        #expect(TagCloneService.followUp(after: .written(uid: "55667788"), pendingUnlinkUID: "11223344", owner: owner, writesLinks: true)
            == .link(.askToLinkSpool(spoolID: 40, label: "PLA+", uid: "55667788")))
    }

    @Test func aCopyWithoutAUIDHasNothingToLink() {
        let owner = TagCloneService.Owner.spool(id: 40, label: "PLA+", uids: [])
        #expect(TagCloneService.followUp(after: .written(uid: nil), pendingUnlinkUID: "11223344", owner: owner, writesLinks: true) == .nothing)
    }

    @Test func aCopyOfAnUnownedTagAsksNothing() {
        #expect(TagCloneService.followUp(after: .written(uid: "55667788"), pendingUnlinkUID: nil, owner: .none, writesLinks: true) == .nothing)
    }

    /// An unowned source (an ELEGOO spool nobody mapped) cloned onto another
    /// spool's tag still releases the tag the user agreed to take.
    @Test func anUnownedSourceStillReleasesTheAgreedTag() {
        #expect(TagCloneService.followUp(after: .written(uid: "11223344"), pendingUnlinkUID: "11223344", owner: .none, writesLinks: true)
            == .releaseThenLink(uid: "11223344", then: .none))
    }

    // MARK: - Releases and shelves

    @Test func aReleaseThatClearedEveryClaimSaysNothing() {
        #expect(TagCloneService.releaseNote(unlinked: true, ownerAfterRelease: .none) == nil)
    }

    @Test func aFailedUnlinkIsReported() {
        #expect(TagCloneService.releaseNote(unlinked: false, ownerAfterRelease: .none)
            == "The copy was written, but another spool still claims that tag.")
    }

    /// `unlinkTag` never writes FilaMan's `rfid_uid`, so a UID there survives
    /// a PATCH that succeeded.
    @Test func aSpoolStillHoldingTheTagAfterASuccessfulUnlinkIsReported() {
        #expect(TagCloneService.releaseNote(unlinked: true, ownerAfterRelease: .spool(id: 41, label: "PETG Black"))
            == "The copy was written, but PETG Black still holds that tag in a field SpoolKid cannot change.")
    }

    @Test func aShelfStillClaimingTheTagIsReported() {
        #expect(TagCloneService.releaseNote(unlinked: true, ownerAfterRelease: .location(name: "Shelf B"))
            == "The copy was written, but Shelf B still claims that tag.")
    }

    @Test func aFilamentStillClaimingTheTagIsReported() {
        #expect(TagCloneService.releaseNote(unlinked: true, ownerAfterRelease: .filament(id: 7, label: "PLA"))
            == "The copy was written, but the filament PLA still claims that tag.")
    }

    @Test func aShelfCannotTakeATagASpoolStillHolds() {
        #expect(TagCloneService.locationLinkRefusal(currentOwner: .spool(id: 41, label: "PETG Black"), name: "Shelf A")
            == "That tag is linked to PETG Black. A tag belongs to one spool or one location, never both.")
    }

    @Test func aShelfCanTakeAnUnclaimedOrShelfHeldTag() {
        #expect(TagCloneService.locationLinkRefusal(currentOwner: .none, name: "Shelf A") == nil)
        #expect(TagCloneService.locationLinkRefusal(currentOwner: .location(name: "Shelf B"), name: "Shelf A") == nil)
    }

    @Test func aSpoolCopyIsNotLinkedWhenTheModeWritesNoLinks() {
        let owner = TagCloneService.Owner.spool(id: 40, label: "PLA+", uids: [])
        // Outside Tag Links the copy is simply not linked — the mode said so.
        #expect(TagCloneService.linkStep(owner: owner, uid: "55667788", writesLinks: false) == .none)
    }

    /// A location's tag list is on the device, so the identity mode does not gate it.
    @Test func aLocationCopyIsOfferedWhateverTheModeWrites() {
        let owner = TagCloneService.Owner.location(uuid: Self.shelf.uuid, name: "Shelf A", uids: ["AABBCCDD"])
        #expect(TagCloneService.linkStep(owner: owner, uid: "55667788", writesLinks: false)
            == .askToAddToLocation(uuid: Self.shelf.uuid, name: "Shelf A", uid: "55667788"))
    }

    @Test func aTagTheOwnerAlreadyHoldsNeedsNoLink() {
        let owner = TagCloneService.Owner.spool(id: 40, label: "PLA+", uids: ["55667788"])
        #expect(TagCloneService.linkStep(owner: owner, uid: "55:66:77:88", writesLinks: true) == .none)
    }

    // MARK: - Copy

    @Test func theUnlinkAlertNamesTheCurrentOwner() {
        #expect(TagCloneService.ownerName(.spool(id: 41, label: "PETG Black")) == "PETG Black")
        #expect(TagCloneService.ownerName(.location(name: "Shelf B")) == "Shelf B")
        #expect(TagCloneService.ownerName(.none) == "a spool")
    }

    @Test func onlyAQuestionHasAlertCopy() {
        #expect(TagCloneService.linkAlertCopy(for: .askToLinkSpool(spoolID: 40, label: "PLA+", uid: "55667788"))
            == TagCloneService.LinkAlertCopy(
                title: "Link the Copy to PLA+?",
                confirm: "Link",
                message: "The copy carries the same data. Linking also records its tag ID on PLA+, so either tag finds the spool."
            ))
        #expect(TagCloneService.linkAlertCopy(for: .askToAddToLocation(uuid: Self.shelf.uuid, name: "Shelf A", uid: "55667788"))
            == TagCloneService.LinkAlertCopy(
                title: "Add the Copy to Shelf A?",
                confirm: "Add",
                message: "The copy already reads as Shelf A. Adding it lists it among Shelf A's tags, so renaming the shelf offers to rewrite it too."
            ))
        #expect(TagCloneService.linkAlertCopy(for: .none) == nil)
    }

    /// A tag Spoolman links to a filament is not free for a shelf either.
    @Test func aLocationCannotTakeAFilamentTag() {
        #expect(TagCloneService.locationLinkRefusal(currentOwner: .filament(id: 7, label: "PLA"), name: "Shelf") != nil)
        #expect(TagCloneService.ownerName(.filament(id: 7, label: "PLA")) == "PLA")
    }
}
