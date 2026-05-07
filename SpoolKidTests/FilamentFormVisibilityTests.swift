import Foundation
import Testing
@testable import SpoolKid

struct FilamentFormVisibilityTests {
    @Test func filamentOptionalCommentHiddenWhenToggleOff() {
        let suite = "FilamentFormVisibilityTests.hidden"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(false, forKey: AppConfig.visibilityFilamentCommentKey)

        let ids = FilamentFormView.visibleFieldIDs(store: SpoolmanFieldVisibilityStore(userDefaults: defaults))

        #expect(!ids.contains("comment"))
    }

    @Test func filamentPayloadIncludesArticleAndWeight() {
        let payload = FilamentFormView.filamentPayload(
            name: "PLA Black",
            vendorId: 1,
            material: "PLA",
            colorHex: "111111",
            density: "1.24",
            diameter: "1.75",
            extruderTemp: "210",
            bedTemp: "60",
            price: "19.99",
            weight: "1000",
            spoolWeight: "140",
            articleNumber: "PM70820",
            comment: "fast profile",
            multiColorHexes: "",
            multiColorDirection: "",
            externalId: "poly_pla_black",
            extraJSON: ""
        )

        #expect(payload["article_number"] as? String == "PM70820")
        #expect(payload["weight"] as? Double == 1000)
    }

    @Test func filamentUpdateClearFieldKeysIncludeEmptyOptionalInputs() {
        let keys = FilamentFormView.filamentUpdateClearFieldKeys(
            vendorId: nil,
            price: "",
            weight: "",
            spoolWeight: "",
            articleNumber: "",
            comment: "",
            multiColorHexes: "",
            multiColorDirection: "",
            externalId: "",
            extraJSON: ""
        )

        #expect(keys.contains("vendor_id"))
        #expect(keys.contains("comment"))
        #expect(keys.contains("extra"))
    }

    @Test func filamentExtraJSONValidationRejectsInvalidJSON() {
        let error = FilamentFormView.extraJSONValidationError("{invalid-json}")
        #expect(error != nil)
    }
}
