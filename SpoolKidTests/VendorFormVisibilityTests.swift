import Foundation
import Testing
@testable import SpoolKid

struct VendorFormVisibilityTests {
    @Test func vendorCommentFieldHiddenWhenToggleOff() {
        let suite = "VendorFormVisibilityTests.hidden"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(false, forKey: AppConfig.visibilityVendorCommentKey)

        let ids = VendorFormView.visibleFieldIDs(store: SpoolmanFieldVisibilityStore(userDefaults: defaults))

        #expect(!ids.contains("comment"))
    }

    @Test func vendorPayloadIncludesOptionalFieldsWhenProvided() {
        let payload = VendorFormView.vendorPayload(
            name: "Polymaker",
            comment: "Premium brand",
            emptySpoolWeight: "140",
            externalId: "poly",
            extraJSON: "{\"origin\":\"catalog\"}"
        )

        #expect(payload["name"] as? String == "Polymaker")
        #expect(payload["comment"] as? String == "Premium brand")
        #expect(payload["empty_spool_weight"] as? Double == 140)
        #expect(payload["external_id"] as? String == "poly")

        let extra = payload["extra"] as? [String: String]
        #expect(extra?["origin"] == "catalog")
    }

    @Test func vendorPayloadNormalizesWhitespaceAndDecimalComma() {
        let payload = VendorFormView.vendorPayload(
            name: "  Polymaker  ",
            comment: "  Premium brand  ",
            emptySpoolWeight: "140,5",
            externalId: "  poly  ",
            extraJSON: ""
        )

        #expect(payload["name"] as? String == "Polymaker")
        #expect(payload["comment"] as? String == "Premium brand")
        #expect(payload["empty_spool_weight"] as? Double == 140.5)
        #expect(payload["external_id"] as? String == "poly")
    }

    @Test func vendorPayloadOmitsInvalidExtraJSON() {
        let payload = VendorFormView.vendorPayload(
            name: "Polymaker",
            comment: "",
            emptySpoolWeight: "",
            externalId: "",
            extraJSON: "{not-valid-json}"
        )

        #expect(payload["extra"] == nil)
    }
}
