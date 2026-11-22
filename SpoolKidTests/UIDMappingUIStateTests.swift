//
//  UIDMappingUIStateTests.swift
//  SpoolKidTests
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct UIDMappingUIStateTests {
    private static let testFilament = Filament(
        id: 10,
        name: "PLA+",
        material: "PLA",
        vendor: Vendor(id: 1, name: "TestVendor"),
        colorHex: "FF0000",
        density: 1.24
    )

    private static func spool(lotNr: String?) -> Spool {
        Spool(id: 42, filament: testFilament, lotNr: lotNr, statusId: nil, externalId: nil, purchaseDate: nil)
    }

    /// Every scan lands on the hub now, SpoolLink on or off. The old
    /// `persistCardUID ? .scanHub : .writeTag` predated the 2026-08-25
    /// "keep + explain" work, which taught the hub to render every mapping
    /// action only where the identity mode writes links.
    /// Skipping the hub with SpoolLink off meant a resolved spool was never
    /// shown at all — the user could not tell what the tag had matched
    /// (bench pass 2026-09-04).
    @Test func tagsTabRoutesScanResultToHubWithMappingOff() {
        let route = TagsTabView.scanCompletionRoute(
            hasScanResult: true,
            hasLegacyData: false,
            hasLocationTag: false
        )

        #expect(route == .scanHub)
    }

    @Test func tagsTabRoutesScanResultToHubWithMappingOn() {
        let route = TagsTabView.scanCompletionRoute(
            hasScanResult: true,
            hasLegacyData: false,
            hasLocationTag: false
        )

        #expect(route == .scanHub)
    }

    @Test func tagsTabRoutesALocationTagToTheHub() {
        let route = TagsTabView.scanCompletionRoute(
            hasScanResult: true,
            hasLegacyData: false,
            hasLocationTag: true
        )

        #expect(route == .scanHub)
    }

    @Test func tagsTabRoutesALocationTagToTheHubEvenAlongsideLegacyData() {
        let route = TagsTabView.scanCompletionRoute(
            hasScanResult: true,
            hasLegacyData: true,
            hasLocationTag: true
        )

        #expect(route == .scanHub)
    }

    /// The one surviving `.writeTag` route: a legacy read that produced tag
    /// data but no `ScanResult` has nothing for the hub to resolve.
    @Test func tagsTabRoutesLegacyDataOnlyToWriteTag() {
        let route = TagsTabView.scanCompletionRoute(
            hasScanResult: false,
            hasLegacyData: true,
            hasLocationTag: false
        )

        #expect(route == .writeTag)
    }

    @Test func tagsTabRoutesNothingWhenAScanProducedNothing() {
        let route = TagsTabView.scanCompletionRoute(
            hasScanResult: false,
            hasLegacyData: false,
            hasLocationTag: false
        )

        #expect(route == .none)
    }

    @Test func spoolMatchSelectionShowsMappedTagOverwriteWarning() {
        let text = TagTargetPicker.mappedTagDisclosureText(
            for: Spool(
                id: 42, filament: Self.testFilament,
                extra: ["card_uids": CardUIDsCodec.encode(["first", "second"])],
                statusId: nil, externalId: nil, purchaseDate: nil
            )
        )

        #expect(text == "Mapped tags (will be overwritten): FIRST, SECOND")
    }

    @Test func spoolMatchSelectionOmitsMappedTagWarningWhenNoMappingsExist() {
        let text = TagTargetPicker.mappedTagDisclosureText(for: Self.spool(lotNr: nil))

        #expect(text == nil)
    }

    @Test func chooserBlocksSelectionWhenATransferHasNoTagTicked() throws {
        let source = Spool(
            id: 42, filament: Self.testFilament,
            extra: ["card_uids": CardUIDsCodec.encode(["04AA", "04BB"])],
            statusId: nil, externalId: nil, purchaseDate: nil
        )
        let offer = try #require(TagMoveOffer.make(scannedUID: "04AA", source: source))

        #expect(TagTargetPicker.selectionBlocked(offer: offer, selection: []))
        #expect(!TagTargetPicker.selectionBlocked(offer: offer, selection: ["04BB"]))
        // No offer = a plain link or write chooser; nothing to tick.
        #expect(!TagTargetPicker.selectionBlocked(offer: nil, selection: []))
    }

    @Test func secondTagScanShownWhenJustMapped() {
        let state = ScanResultHubView.uidMappingActionState(
            writesLinks: true,
            didJustMapCurrentTag: true,
            isSecondTagScanning: false
        )

        #expect(state == .scanSecondTag(enabled: true))
    }

    @Test func secondTagScanStaysAvailableWhenAlreadyMappedManyTags() {
        // Unlimited card_uids: there is no per-spool cap, so "Scan another tag"
        // remains available no matter how many tags are already linked.
        let state = ScanResultHubView.uidMappingActionState(
            writesLinks: true,
            didJustMapCurrentTag: true,
            isSecondTagScanning: false
        )

        #expect(state == .scanSecondTag(enabled: true))
    }

    @Test func secondTagScanDisabledWhenLinksOff() {
        let state = ScanResultHubView.uidMappingActionState(
            writesLinks: false,
            didJustMapCurrentTag: true,
            isSecondTagScanning: false
        )

        #expect(state == .scanSecondTag(enabled: false))
    }

    @Test func secondTagScanDisabledWhileScanning() {
        let state = ScanResultHubView.uidMappingActionState(
            writesLinks: true,
            didJustMapCurrentTag: true,
            isSecondTagScanning: true
        )

        #expect(state == .scanSecondTag(enabled: false))
    }

    @Test func secondTagScanHiddenWhenNothingJustMapped() {
        let state = ScanResultHubView.uidMappingActionState(
            writesLinks: true,
            didJustMapCurrentTag: false,
            isSecondTagScanning: false
        )

        #expect(state == .none)
    }

    // MARK: - Single-owner assign outcomes (Task 19, Step 4)
    //
    // `assignCardUID` runs two writes with no rollback between them, and until
    // Task 19 it discarded both results. These pin the RULE the reporting now
    // follows; the wiring itself — three call sites in `ScanResultHubView` that
    // used to drop `setCardUIDs`' `Bool` — has no seam a unit test can reach,
    // so it is not what is covered here.

    @Test func assignIsACleanSaveWhenEveryPreviousOwnerReleasedTheTag() {
        #expect(TagLinkService.assignOutcome(unclearedOwners: [], undetachableOwners: []) == .saved)
    }

    /// The tag IS on the new spool, so this can never report the mapping as
    /// failed — but it must not pass as a clean save either: single-owner is
    /// broken and only the user can settle it.
    @Test func assignIsACaveatNotAFailureWhenAPreviousOwnerKeepsTheTag() {
        let outcome = TagLinkService.assignOutcome(
            unclearedOwners: ["TestVendor PLA+"], undetachableOwners: []
        )

        #expect(outcome.didWrite)
        #expect(outcome.feedback != .success)
        #expect(outcome.followUpNote?.contains("TestVendor PLA+") == true)
    }

    @Test func assignNamesEveryOwnerStillHoldingTheTag() {
        let note = TagLinkService.assignOutcome(
            unclearedOwners: ["Spool #3", "Spool #9"], undetachableOwners: []
        ).followUpNote

        #expect(note?.contains("Spool #3") == true)
        #expect(note?.contains("Spool #9") == true)
    }

    // MARK: - New spool prefill only when nobody owns the tag (I1, fix round 1)
    //
    // `newSpoolInitialCardUIDs` used to always pre-fill the scanned UID. When
    // `TagMoveOffer.make` returns nil because the tag is linked only through
    // `rfid_uid`, that posted the UID into the new spool's
    // `card_uids` while the old spool kept it too — two owners, no message.

    @Test func newSpoolPrefillsTheScannedTagWhenNobodyOwnsIt() {
        #expect(ScanResultHubView.newSpoolPrefillUIDs(scannedUID: "04aa", owner: .none) == ["04AA"])
    }

    @Test func newSpoolDoesNotPrefillATagASpoolAlreadyHolds() {
        #expect(ScanResultHubView.newSpoolPrefillUIDs(
            scannedUID: "04AA", owner: .spool(id: 7, label: "Other Spool")
        ) == [])
    }

    @Test func newSpoolDoesNotPrefillATagALocationHolds() {
        #expect(ScanResultHubView.newSpoolPrefillUIDs(
            scannedUID: "04AA", owner: .location(name: "Shelf A")
        ) == [])
    }

    @Test func newSpoolPrefillIsEmptyWithNoOrBlankScannedUID() {
        #expect(ScanResultHubView.newSpoolPrefillUIDs(scannedUID: nil, owner: .none) == [])
        #expect(ScanResultHubView.newSpoolPrefillUIDs(scannedUID: " ", owner: .none) == [])
    }
}
