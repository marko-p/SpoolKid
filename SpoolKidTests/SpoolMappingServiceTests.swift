//
//  SpoolMappingServiceTests.swift
//  SpoolKidTests
//

import Testing
@testable import SpoolKid

struct SpoolMappingServiceTests {
    @Test func parsesCardUIDsFromLotNumberCaseInsensitively() {
        let uids = SpoolMappingService.cardUIDs(in: "batch-7,card_uid:045D7774CE2A81,CARD_UID:ABCDEF")

        #expect(uids == ["045d7774ce2a81", "abcdef"])
    }

    @Test func serializesAtMostTwoCardUIDsInFirmwareCompatibleFormat() {
        let lotNr = SpoolMappingService.lotNumber(for: ["045D7774CE2A81", "abcdef", "ignored"])

        #expect(lotNr == "card_uid:045d7774ce2a81,card_uid:abcdef")
    }

    @Test func appendsUIDWhenSingleSlotIsAvailable() {
        let result = SpoolMappingService.updatedLotNumber(
            existingLotNumber: "card_uid:045d7774ce2a81",
            adding: "ABCDEF"
        )

        #expect(result == .updated("card_uid:045d7774ce2a81,card_uid:abcdef"))
    }

    @Test func asksWhichSlotToReplaceWhenBothSlotsAreOccupied() {
        let result = SpoolMappingService.updatedLotNumber(
            existingLotNumber: "card_uid:first,card_uid:second",
            adding: "third"
        )

        #expect(result == .needsSlotReplacement(existingUIDs: ["first", "second"], newUID: "third"))
    }

    @Test func canReplaceSelectedSlotWhenBothSlotsAreOccupied() {
        let lotNr = SpoolMappingService.replacingUID(
            in: "card_uid:first,card_uid:second",
            slot: .second,
            with: "THIRD"
        )

        #expect(lotNr == "card_uid:first,card_uid:third")
    }
}
