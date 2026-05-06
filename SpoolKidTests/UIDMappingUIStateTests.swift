//
//  UIDMappingUIStateTests.swift
//  SpoolKidTests
//

import Testing
@testable import SpoolKid

struct UIDMappingUIStateTests {
    @Test func scanHubDisablesSaveActionWhenMappingSettingIsOff() {
        let state = ScanResultHubView.uidMappingActionState(
            persistCardUID: false,
            tagMapped: false,
            didJustAssociateCurrentTag: false,
            isSecondTagScanning: false,
            mappedUIDCount: 0
        )

        #expect(state == .saveCurrentTag(enabled: false))
    }

    @Test func scanHubDisablesSecondTagActionWhenMappingSettingIsOff() {
        let state = ScanResultHubView.uidMappingActionState(
            persistCardUID: false,
            tagMapped: true,
            didJustAssociateCurrentTag: true,
            isSecondTagScanning: false,
            mappedUIDCount: 1
        )

        #expect(state == .scanSecondTag(enabled: false))
    }

    @Test func scanHubShowsNoMappingActionWhenTagAlreadyMapped() {
        let state = ScanResultHubView.uidMappingActionState(
            persistCardUID: true,
            tagMapped: true,
            didJustAssociateCurrentTag: false,
            isSecondTagScanning: false,
            mappedUIDCount: 1
        )

        #expect(state == .none)
    }

    @Test func spoolFormKeepsExistingLotNumberWhenMappingSettingIsOff() {
        let lotNr = SpoolFormView.lotNrForSave(
            persistCardUID: false,
            existingLotNr: "card_uid:abc,card_uid:def",
            slot1: "",
            slot2: ""
        )

        #expect(lotNr == "card_uid:abc,card_uid:def")
    }

    @Test func spoolFormBuildsLotNumberFromSlotsWhenMappingSettingIsOn() {
        let lotNr = SpoolFormView.lotNrForSave(
            persistCardUID: true,
            existingLotNr: "card_uid:old",
            slot1: "045D7774CE2A81",
            slot2: "ABCDEF"
        )

        #expect(lotNr == "card_uid:045d7774ce2a81,card_uid:abcdef")
    }

    @Test func spoolFormOmitsLotNumberForNewSpoolWhenMappingSettingIsOff() {
        let lotNr = SpoolFormView.lotNrForSave(
            persistCardUID: false,
            existingLotNr: nil,
            slot1: "045D7774CE2A81",
            slot2: ""
        )

        #expect(lotNr == nil)
    }

    @Test func encryptedUIDActionsEnabledWhenMappingOnAndSpoolmanConfigured() {
        let state = ScanResultHubView.uidOnlyActionsState(
            cardUID: "045d7774ce2a81",
            persistCardUID: true,
            spoolmanConfigured: true
        )

        #expect(state == .enabled)
    }

    @Test func encryptedUIDActionsDisableAssociationWhenMappingSettingIsOff() {
        let state = ScanResultHubView.uidOnlyActionsState(
            cardUID: "045d7774ce2a81",
            persistCardUID: false,
            spoolmanConfigured: true
        )

        #expect(state == .disabledByMappingSetting)
    }

    @Test func encryptedUIDActionsDisabledWhenSpoolmanNotConfigured() {
        let state = ScanResultHubView.uidOnlyActionsState(
            cardUID: "045d7774ce2a81",
            persistCardUID: true,
            spoolmanConfigured: false
        )

        #expect(state == .disabledByConnection)
    }

    @Test func encryptedUIDActionsUnavailableWithoutUID() {
        let state = ScanResultHubView.uidOnlyActionsState(
            cardUID: nil,
            persistCardUID: true,
            spoolmanConfigured: true
        )

        #expect(state == .unavailable)
    }

    @Test func encryptedTagUsesUIDOnlyCreateFlow() {
        let action = ScanResultHubView.secondaryCreateAction(
            tagDataAvailable: false,
            showCreateSpool: false,
            showUIDActionsForEncryptedTag: true
        )

        #expect(action == .uidOnly)
    }

    @Test func decodedTagUsesBestMatchCreateFlow() {
        let action = ScanResultHubView.secondaryCreateAction(
            tagDataAvailable: true,
            showCreateSpool: true,
            showUIDActionsForEncryptedTag: false
        )

        #expect(action == .bestMatch)
    }

    @Test func existingSpoolAssociationDisabledWhenMappingSettingIsOff() {
        let state = ScanResultHubView.existingSpoolAssociationState(
            cardUID: "045d7774ce2a81",
            persistCardUID: false,
            spoolmanConfigured: true
        )

        #expect(state == .disabledByMappingSetting)
    }

    @Test func existingSpoolAssociationEnabledWhenUIDPresentAndMappingOn() {
        let state = ScanResultHubView.existingSpoolAssociationState(
            cardUID: "045d7774ce2a81",
            persistCardUID: true,
            spoolmanConfigured: true
        )

        #expect(state == .enabled)
    }

    @Test func existingSpoolAssociationDisabledWithoutUID() {
        let state = ScanResultHubView.existingSpoolAssociationState(
            cardUID: nil,
            persistCardUID: true,
            spoolmanConfigured: true
        )

        #expect(state == .unavailable)
    }
}
