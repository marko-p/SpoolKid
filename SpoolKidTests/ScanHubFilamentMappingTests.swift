//
//  ScanHubFilamentMappingTests.swift
//  SpoolKidTests
//
//  A scanned tag that resolves to a *filament* — ranked spool candidates, or
//  none — used to lose its UID on the way into `UnifiedScanResult`, and with it
//  every way to map the tag to an existing spool. The only actions on offer
//  were "create a new spool" and "browse spools with this filament"; the latter
//  pushes the ordinary Manage Spools list, whose Save saves spool fields and
//  never the mapping. Reported from a device pass on FilaMan, 2026-08-24.
//

import Testing
@testable import SpoolKid

struct ScanHubFilamentMappingTests {
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

    private static let testSpool = Spool(id: 42, filament: testFilament, statusId: nil, externalId: nil, purchaseDate: nil)

    private static let uid = "045D7774CE2A81"

    // MARK: - The model keeps the UID

    /// The root cause: `.filament` had no UID slot at all, so `uid` answered
    /// `nil` for a tag the user had physically just held to the phone.
    @Test func filamentResultCarriesTheScannedUID() {
        let result = UnifiedScanResult.filament(Self.tagData, Self.testFilament, scannedUID: Self.uid)
        #expect(result.uid == Self.uid)
    }

    /// A filament that arrived by QR or OCR has no tag and no UID — the slot
    /// stays empty rather than being invented.
    @Test func filamentScannedWithoutATagHasNoUID() {
        let result = UnifiedScanResult.filament(Self.tagData, Self.testFilament, scannedUID: nil)
        #expect(result.uid == nil)
    }

    // MARK: - The affordance

    @Test func mapToExistingSpoolIsOfferedForAnUnmappedScannedTag() {
        let result = UnifiedScanResult.filament(Self.tagData, Self.testFilament, scannedUID: Self.uid)
        #expect(
            HubActionPlan.shouldShowMapToExistingSpoolButton(
                result: result
            )
        )
    }

    /// `.noMatch` — tag data, a reachable backend, and zero ranked candidates —
    /// also lands here, and the user may still want to map the tag to a spool
    /// whose filament differs from what the tag claims.
    @Test func mapToExistingSpoolIsOfferedEvenWithNoRankedCandidates() {
        let result = UnifiedScanResult.filament(Self.tagData, nil, scannedUID: Self.uid)
        #expect(
            HubActionPlan.shouldShowMapToExistingSpoolButton(
                result: result
            )
        )
    }

    @Test func mapToExistingSpoolIsHiddenWhenNoTagWasScanned() {
        let result = UnifiedScanResult.filament(Self.tagData, Self.testFilament, scannedUID: nil)
        #expect(
            HubActionPlan.shouldShowMapToExistingSpoolButton(
                result: result
            ) == false
        )
    }

    @Test func anEmptyUIDIsNotAScannedTag() {
        let result = UnifiedScanResult.filament(Self.tagData, Self.testFilament, scannedUID: "")
        #expect(
            HubActionPlan.shouldShowMapToExistingSpoolButton(
                result: result
            ) == false
        )
    }

    /// The `.spool` and `.uidOnly` branches render their own mapping buttons;
    /// this helper answers for `.filament` alone.
    @Test func theOtherScenariosDoNotGainASecondMappingButton() {
        let spool = UnifiedScanResult.spool(Self.testSpool, Self.tagData, scannedUID: Self.uid)
        let uidOnly = UnifiedScanResult.uidOnly(Self.uid)

        #expect(
            HubActionPlan.shouldShowMapToExistingSpoolButton(
                result: spool
            ) == false
        )
        #expect(
            HubActionPlan.shouldShowMapToExistingSpoolButton(
                result: uidOnly
            ) == false
        )
    }
}
