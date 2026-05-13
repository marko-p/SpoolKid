import Foundation
import Testing
@testable import SpoolKid

struct SpoolFormVisibilityTests {
    @Test func spoolOptionalArchivedFieldHiddenWhenToggleOff() {
        let suite = "SpoolFormVisibilityTests.hidden"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(false, forKey: AppConfig.visibilitySpoolArchivedKey)

        let ids = SpoolFormView.visibleFieldIDs(store: SpoolmanFieldVisibilityStore(userDefaults: defaults))

        #expect(!ids.contains("archived"))
    }

    @Test func spoolPayloadCanClearLocation() {
        let payload = SpoolFormView.spoolPayload(
            filamentId: 1,
            price: "",
            initialWeight: "1000",
            spoolWeight: "140",
            remainingWeight: "800",
            usedWeight: "",
            location: "",
            clearLocationWhenEmpty: true,
            lotNr: "card_uid:abc",
            comment: "",
            archived: false,
            firstUsedISO8601: "",
            lastUsedISO8601: "",
            extraJSON: ""
        )

        #expect(payload["location"] is NSNull)
    }

    @Test func locationPatchUsesIgnoreWhenEmptyAndClearDisabled() {
        let patch = SpoolFormView.locationPatch(for: "", clearLocationWhenEmpty: false)

        switch patch {
        case .ignore:
            #expect(Bool(true))
        default:
            #expect(Bool(false))
        }
    }

    @Test func clearFieldKeysIncludeEmptyFirstAndLastUsed() {
        let keys = SpoolFormView.clearFieldKeysForUpdate(
            comment: "",
            firstUsedISO8601: "",
            lastUsedISO8601: "",
            extraJSON: "",
            lotNr: ""
        )

        #expect(keys.contains("first_used"))
        #expect(keys.contains("last_used"))
        #expect(keys.contains("comment"))
        #expect(keys.contains("extra"))
        #expect(keys.contains("lot_nr"))
    }
}
