import Testing
@testable import SpoolKid

struct FieldVisibilityEditorTests {
    @Test func spoolmanEditorListsOptionalFieldsOnly() async throws {
        // The editor should offer exactly the catalog's non-essential fields.
        let optionalSpoolFields = FieldCatalog.fields(for: .spool).filter { !$0.isEssential }
        let expectedIDs = Set(optionalSpoolFields.map(\.id))
        #expect(expectedIDs.contains("used_weight"))
        #expect(expectedIDs.contains("comment"))
        #expect(!expectedIDs.contains("filament_id"))  // essential
        #expect(!expectedIDs.contains("initial_weight")) // essential
    }

    @Test func nfcEditorListsOptionalFieldsOnly() async throws {
        let optionalOpenSpool = NFCFieldCatalog.fields(for: .openSpool).filter { !$0.isEssential }
        let ids = Set(optionalOpenSpool.map(\.id))
        #expect(ids.contains("name"))
        #expect(ids.contains("subtype"))
        #expect(ids.contains("spool_id"))
        #expect(!ids.contains("material"))  // essential
        #expect(!ids.contains("color_hex")) // essential
    }

    /// A toggle for a field the backend lacks is a control wired to nothing:
    /// switching it on cannot make the field appear, because support beats
    /// preference.
    @Test func theEditorDoesNotOfferTogglesForUnsupportedFields() {
        let labels = FieldVisibilityEditor(entity: .spool, capabilities: .filaman).fieldLabels

        #expect(labels.contains("Comment") == false)
        #expect(labels.contains("First Used") == false)
        #expect(labels.contains("Last Used") == false)
        #expect(labels.contains("Used Weight") == false)
    }

    @Test func theEditorStillOffersEverythingTheBackendHas() {
        let labels = FieldVisibilityEditor(entity: .spool, capabilities: .spoolman).fieldLabels

        #expect(labels.contains("Comment"))
        #expect(labels.contains("First Used"))
    }
}
