import Foundation
import Testing
@testable import SpoolKid

struct VendorFormVisibilityTests {
    /// The form helper routes through the support∩preference intersection and
    /// returns this entity's fields. It asserts the DEFAULT only: the helper
    /// takes capabilities, not a `UserDefaults`, so a toggle cannot be injected
    /// here. Toggle behaviour is covered directly, against an injected suite,
    /// in `FieldVisibilityStoreTests`.
    @Test func vendorFormHidesCommentByDefault() {
        let ids = VendorFormView.visibleFieldIDs(for: BackendCapabilities.spoolman)

        #expect(!ids.contains("comment"))
    }

    @Test func vendorPayloadIncludesOptionalFieldsWhenProvided() {
        let draft = VendorFormView.vendorDraft(
            name: "Polymaker",
            comment: "Premium brand",
            emptySpoolWeight: "140",
            externalId: "poly"
        )

        #expect(draft.name == "Polymaker")
        #expect(draft.comment == "Premium brand")
        #expect(draft.emptySpoolWeight == 140)
        #expect(draft.externalId == "poly")
    }

    @Test func vendorPayloadNormalizesWhitespaceAndDecimalComma() {
        let draft = VendorFormView.vendorDraft(
            name: "  Polymaker  ",
            comment: "  Premium brand  ",
            emptySpoolWeight: "140,5",
            externalId: "  poly  "
        )

        #expect(draft.name == "Polymaker")
        #expect(draft.comment == "Premium brand")
        #expect(draft.emptySpoolWeight == 140.5)
        #expect(draft.externalId == "poly")
    }

    // `vendorPayloadOmitsInvalidExtraJSON` lived here. The Extra JSON box it
    // tested is gone as of 2026-08-28 (task 4, backend-aware fields).
}
