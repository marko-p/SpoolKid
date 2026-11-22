//
//  ScanHubCardTapTests.swift
//  SpoolKidTests
//
//  Tapping the resolved-spool card in the scan hub opened `SpoolFormView` with
//  no `spoolToEdit`, i.e. the CREATE form, seeded with the scanned tag's UID.
//  Reported from a device pass on FilaMan, 2026-08-24: the owner tapped their
//  spool #40, typed a remaining weight, saved — and got a new spool #41
//  holding the weight and the tag, while #40 kept neither.
//

import Testing
@testable import SpoolKid

struct ScanHubCardTapTests {
    private static let testFilament = Filament(
        id: 10,
        name: "PLA+",
        material: "PLA",
        vendor: Vendor(id: 1, name: "TestVendor"),
        colorHex: "FF0000",
        density: 1.24
    )

    private static let tagData = FilamentTagData(
        material: "PLA",
        brand: "TestVendor",
        colorHex: "FF0000",
        minNozzleTemp: 200,
        maxNozzleTemp: 220,
        minBedTemp: 60,
        maxBedTemp: 60
    )

    private static let testSpool = Spool(id: 40, filament: testFilament, remainingWeight: 750, statusId: nil, externalId: nil, purchaseDate: nil)

    @Test func tappingAResolvedSpoolCardEditsThatSpool() {
        let result = UnifiedScanResult.spool(Self.testSpool, Self.tagData, scannedUID: "045D7774CE2A81")
        #expect(ScanResultHubView.spoolToEditOnCardTap(result)?.id == 40)
    }

    /// The filament card's tap opens OCR review, not a form; it has no spool.
    @Test func tappingAFilamentCardEditsNothing() {
        let result = UnifiedScanResult.filament(Self.tagData, Self.testFilament, scannedUID: "045D7774CE2A81")
        #expect(ScanResultHubView.spoolToEditOnCardTap(result) == nil)
    }

    @Test func tappingAnUnknownTagCardEditsNothing() {
        #expect(ScanResultHubView.spoolToEditOnCardTap(.uidOnly("045D7774CE2A81")) == nil)
    }

    // MARK: - Returning from the edit

    /// The hub holds its own copy of the spool, so an edit made in the form
    /// leaves the card showing the values the user just changed.
    @Test func theHubTakesTheStoresCopyBackAfterAnEdit() {
        let edited = Spool(id: 40, filament: Self.testFilament, remainingWeight: 512, statusId: nil, externalId: nil, purchaseDate: nil)
        let refreshed = ScanResultHubView.refreshedSpool(
            id: 40, from: [Spool(id: 39, filament: Self.testFilament, statusId: nil, externalId: nil, purchaseDate: nil), edited]
        )
        #expect(refreshed?.remainingWeight == 512)
    }

    /// A spool deleted while the form was open must not resurrect the stale
    /// copy as though it were current.
    @Test func aSpoolTheStoreNoLongerHasRefreshesToNothing() {
        #expect(ScanResultHubView.refreshedSpool(id: 40, from: []) == nil)
    }
}
