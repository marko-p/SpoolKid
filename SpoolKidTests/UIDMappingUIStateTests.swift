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
            didJustMapCurrentTag: false,
            isSecondTagScanning: false,
            mappedUIDCount: 0
        )

        #expect(state == .saveCurrentTag(enabled: false))
    }

    @Test func scanHubDisablesSecondTagActionWhenMappingSettingIsOff() {
        let state = ScanResultHubView.uidMappingActionState(
            persistCardUID: false,
            tagMapped: true,
            didJustMapCurrentTag: true,
            isSecondTagScanning: false,
            mappedUIDCount: 1
        )

        #expect(state == .scanSecondTag(enabled: false))
    }

    @Test func scanHubShowsNoMappingActionWhenTagAlreadyMapped() {
        let state = ScanResultHubView.uidMappingActionState(
            persistCardUID: true,
            tagMapped: true,
            didJustMapCurrentTag: false,
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

    @Test func encryptedUIDActionsDisableMappingWhenMappingSettingIsOff() {
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

    @Test func existingSpoolMappingDisabledWhenMappingSettingIsOff() {
        let state = ScanResultHubView.existingSpoolMappingState(
            cardUID: "045d7774ce2a81",
            persistCardUID: false,
            spoolmanConfigured: true
        )

        #expect(state == .disabledByMappingSetting)
    }

    @Test func existingSpoolMappingEnabledWhenUIDPresentAndMappingOn() {
        let state = ScanResultHubView.existingSpoolMappingState(
            cardUID: "045d7774ce2a81",
            persistCardUID: true,
            spoolmanConfigured: true
        )

        #expect(state == .enabled)
    }

    @Test func existingSpoolMappingDisabledWithoutUID() {
        let state = ScanResultHubView.existingSpoolMappingState(
            cardUID: nil,
            persistCardUID: true,
            spoolmanConfigured: true
        )

        #expect(state == .unavailable)
    }

    @Test func moveSourceUIDSelectionDisabledWhenSourceHasSingleUID() {
        let state = ScanResultHubView.moveSourceUIDSelectionState(
            sourceMappedUIDs: ["first"]
        )

        #expect(state == .hidden)
    }

    @Test func moveSourceUIDSelectionAvailableWhenSourceHasTwoUIDs() {
        let state = ScanResultHubView.moveSourceUIDSelectionState(
            sourceMappedUIDs: ["first", "second"]
        )

        #expect(state == .visible(defaultMoveBoth: true))
    }

    @Test func reusableMoveSelectsBothUIDsWhenEnabledAndTwoAreMapped() {
        let selected = ScanResultHubView.selectedUIDsForReusableMove(
            scannedUID: "first",
            sourceMappedUIDs: ["first", "second"],
            moveBothWhenAvailable: true
        )

        #expect(selected == ["first", "second"])
    }

    @Test func reusableMoveSelectsOnlyScannedUIDWhenMoveBothOff() {
        let selected = ScanResultHubView.selectedUIDsForReusableMove(
            scannedUID: "first",
            sourceMappedUIDs: ["first", "second"],
            moveBothWhenAvailable: false
        )

        #expect(selected == ["first"])
    }

    @Test func tagsTabRoutesScanResultToWriteViewWhenMappingSettingIsOff() {
        let route = TagsTabView.scanCompletionRoute(
            persistCardUID: false,
            hasScanResult: true,
            hasLegacyData: false
        )

        #expect(route == .writeTag)
    }

    @Test func tagsTabRoutesScanResultToHubWhenMappingSettingIsOn() {
        let route = TagsTabView.scanCompletionRoute(
            persistCardUID: true,
            hasScanResult: true,
            hasLegacyData: false
        )

        #expect(route == .scanHub)
    }

    @Test func addSpoolSaveAndWriteButtonHiddenAfterSave() {
        let isVisible = SpoolFormView.shouldShowSaveAndWriteButton(
            isEditingExistingSpool: false,
            isSaved: true
        )

        #expect(!isVisible)
    }

    @Test func spoolMatchSelectionFormatsSpoolIDText() {
        let text = SpoolMatchSelectionView.spoolIDText(id: 42)

        #expect(text == "Spool #42")
    }

    @Test func spoolMatchSelectionShowsMappedTagOverwriteWarning() {
        let text = SpoolMatchSelectionView.mappedTagDisclosureText(
            lotNr: "card_uid:first,card_uid:second"
        )

        #expect(text == "Mapped tags (will be overwritten): first, second")
    }

    @Test func spoolMatchSelectionOmitsMappedTagWarningWhenNoMappingsExist() {
        let text = SpoolMatchSelectionView.mappedTagDisclosureText(lotNr: nil)

        #expect(text == nil)
    }
}
