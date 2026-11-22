//
//  ScanHubCreateSpoolPreselectionTests.swift
//  SpoolKidTests
//
//  The create-spool form must open preselected with the filament the hub
//  showed — never SpoolFormView's legacy "last used filament" fallback pick.
//  Reported 2026-09: tapping "Create New Spool" / "Create New Spool from This
//  Tag" on a resolved-spool scan landed on the form with the PREVIOUS spool's
//  filament, because the hub's `.spool`-scenario create buttons never set
//  `newSpoolInitialFilamentId` and the form's fallback filled the gap.
//

import Testing
@testable import SpoolKid

struct ScanHubCreateSpoolPreselectionTests {
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

    @Test func aResolvedSpoolScanPreselectsTheSpoolsFilament() {
        let result = UnifiedScanResult.spool(
            Spool(id: 40, filament: Self.testFilament, statusId: nil, externalId: nil, purchaseDate: nil),
            nil,
            scannedUID: "045D7774CE2A81"
        )
        #expect(ScanResultHubView.initialFilamentIdForCreateSpool(result) == 10)
    }

    /// No filament is shown for a UID-only scan, so there is nothing to hand
    /// the form; the form's last-used fallback legitimately applies there.
    @Test func aUIDOnlyScanPreselectsNothing() {
        #expect(ScanResultHubView.initialFilamentIdForCreateSpool(.uidOnly("045D7774CE2A81")) == nil)
    }

    /// The `.filament` scenario resolves its filament asynchronously
    /// (find-or-create); the helper must not short-circuit that with the
    /// heuristic-matched filament.
    @Test func aFilamentScanLeavesPreselectionToFindOrCreate() {
        let result = UnifiedScanResult.filament(
            Self.tagData,
            Self.testFilament,
            scannedUID: nil
        )
        #expect(ScanResultHubView.initialFilamentIdForCreateSpool(result) == nil)
    }
}
