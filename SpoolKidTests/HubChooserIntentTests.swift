import Testing
@testable import SpoolKid

struct HubChooserIntentTests {
    private static let testFilament = Filament(
        id: 10,
        name: "PLA+",
        material: "PLA",
        vendor: Vendor(id: 1, name: "TestVendor"),
        colorHex: "FF0000",
        density: 1.24
    )

    private static let testSpool = Spool(id: 42, filament: testFilament, statusId: nil, externalId: nil, purchaseDate: nil)

    /// The write screen links the written tag by this ID; whether it reaches the
    /// tag is the assembler's call (Spool ID mode).
    @Test func overwriteTagCarriesTheSpoolsIDToTheWriteScreen() {
        let action = ScanResultHubView.chooserSelectionAction(
            intent: .overwriteTag,
            spool: Self.testSpool
        )

        if case .navigateToWriteTag(let tagData) = action {
            #expect(tagData.spoolmanId == 42)
            #expect(tagData.material == "PLA")
            #expect(tagData.brand == "TestVendor")
            #expect(tagData.colorHex == "FF0000")
        } else {
            Issue.record("Expected .navigateToWriteTag, got \(action)")
        }
    }

    @Test func mapUIDToSpoolPersistsUID() {
        let action = ScanResultHubView.chooserSelectionAction(
            intent: .mapUIDToSpool,
            spool: Self.testSpool
        )

        if case .persistUID(let spoolID) = action {
            #expect(spoolID == 42)
        } else {
            Issue.record("Expected .persistUID, got \(action)")
        }
    }

    @Test func nilIntentDefaultsToPersistUID() {
        let action = ScanResultHubView.chooserSelectionAction(
            intent: nil,
            spool: Self.testSpool
        )

        if case .persistUID(let spoolID) = action {
            #expect(spoolID == 42)
        } else {
            Issue.record("Expected .persistUID, got \(action)")
        }
    }
}

struct WriteSpoolIdButtonVisibilityTests {
    private static let testFilament = Filament(
        id: 10,
        name: "PLA+",
        material: "PLA",
        vendor: Vendor(id: 1, name: "TestVendor"),
        colorHex: "FF0000",
        density: 1.24
    )

    private static let testSpool = Spool(id: 42, filament: testFilament, statusId: nil, externalId: nil, purchaseDate: nil)

    private static let tagDataWithoutSpoolId = FilamentTagData(
        name: "PLA+",
        material: "PLA",
        brand: "TestVendor",
        colorHex: "FF0000",
        minNozzleTemp: 200,
        maxNozzleTemp: 220,
        minBedTemp: 60,
        maxBedTemp: 80,
        spoolmanId: nil
    )

    private static let tagDataWithSpoolId = FilamentTagData(
        name: "PLA+",
        material: "PLA",
        brand: "TestVendor",
        colorHex: "FF0000",
        minNozzleTemp: 200,
        maxNozzleTemp: 220,
        minBedTemp: 60,
        maxBedTemp: 80,
        spoolmanId: 42
    )

    @Test func showsButtonWhenConditionsMet() {
        let result = UnifiedScanResult.spool(Self.testSpool, Self.tagDataWithoutSpoolId, scannedUID: "045d7774ce2a81")
        let shouldShow = HubActionPlan.shouldShowWriteSpoolIdButton(
            result: result,
            tagFormat: .openSpool,
            writeSpoolIdEnabled: true
        )
        #expect(shouldShow == true)
    }

    @Test func hidesButtonWhenSettingOff() {
        let result = UnifiedScanResult.spool(Self.testSpool, Self.tagDataWithoutSpoolId, scannedUID: "045d7774ce2a81")
        let shouldShow = HubActionPlan.shouldShowWriteSpoolIdButton(
            result: result,
            tagFormat: .openSpool,
            writeSpoolIdEnabled: false
        )
        #expect(shouldShow == false)
    }

    @Test func hidesButtonWhenTagAlreadyHasSpoolId() {
        let result = UnifiedScanResult.spool(Self.testSpool, Self.tagDataWithSpoolId, scannedUID: "045d7774ce2a81")
        let shouldShow = HubActionPlan.shouldShowWriteSpoolIdButton(
            result: result,
            tagFormat: .openSpool,
            writeSpoolIdEnabled: true
        )
        #expect(shouldShow == false)
    }

    @Test func hidesButtonWhenFormatIsNotOpenSpool() {
        let result = UnifiedScanResult.spool(Self.testSpool, Self.tagDataWithoutSpoolId, scannedUID: "045d7774ce2a81")
        let shouldShow = HubActionPlan.shouldShowWriteSpoolIdButton(
            result: result,
            tagFormat: .openTag3D,
            writeSpoolIdEnabled: true
        )
        #expect(shouldShow == false)
    }

    @Test func hidesButtonWhenFormatIsNil() {
        let result = UnifiedScanResult.spool(Self.testSpool, Self.tagDataWithoutSpoolId, scannedUID: "045d7774ce2a81")
        let shouldShow = HubActionPlan.shouldShowWriteSpoolIdButton(
            result: result,
            tagFormat: nil,
            writeSpoolIdEnabled: true
        )
        #expect(shouldShow == false)
    }

    @Test func hidesButtonWhenResultIsNotSpool() {
        let result = UnifiedScanResult.filament(Self.tagDataWithoutSpoolId, Self.testFilament, scannedUID: nil)
        let shouldShow = HubActionPlan.shouldShowWriteSpoolIdButton(
            result: result,
            tagFormat: .openSpool,
            writeSpoolIdEnabled: true
        )
        #expect(shouldShow == false)
    }

    @Test func showsButtonWhenTagDataIsNil() {
        let result = UnifiedScanResult.spool(Self.testSpool, nil, scannedUID: "045d7774ce2a81")
        let shouldShow = HubActionPlan.shouldShowWriteSpoolIdButton(
            result: result,
            tagFormat: .openSpool,
            writeSpoolIdEnabled: true
        )
        #expect(shouldShow == true)
    }
}
