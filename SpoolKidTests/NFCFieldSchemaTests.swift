import Foundation
import Testing
@testable import SpoolKid

struct NFCFieldSchemaTests {
    @Test func openspoolContainsSubtypeAndSpoolID() {
        let ids = Set(NFCFieldCatalog.fields(for: .openSpool).map(\.id))
        #expect(ids.contains("material"))
        #expect(ids.contains("subtype"))
        #expect(ids.contains("spool_id"))
    }

    @Test func anycubicDoesNotExposeSubtype() {
        let ids = Set(NFCFieldCatalog.fields(for: .anycubicACE).map(\.id))
        #expect(!ids.contains("subtype"))
    }

    @Test func schemaInvariantsHoldAcrossFormats() {
        for format in TagFormat.allCases {
            let fields = NFCFieldCatalog.fields(for: format)
            let ids = fields.map(\.id)
            #expect(Set(ids).count == ids.count)
            #expect(fields.allSatisfy { !$0.label.isEmpty && !$0.section.isEmpty })
            #expect(fields.allSatisfy { !$0.isEssential || $0.defaultVisible })
        }
    }

    @Test func openPrintTagContainsExpandedOptionalFields() {
        let ids = Set(NFCFieldCatalog.fields(for: .openPrintTag).map(\.id))

        #expect(ids.contains("density"))
        #expect(ids.contains("transmission_distance"))
        #expect(ids.contains("gtin"))
        #expect(ids.contains("manufactured_date"))
        #expect(ids.contains("country_of_origin"))
        #expect(ids.contains("preheat_temperature"))
        #expect(ids.contains("drying_temperature"))
        #expect(ids.contains("drying_time"))
        #expect(ids.contains("nominal_netto_full_weight"))
        #expect(ids.contains("actual_netto_full_weight"))
        #expect(ids.contains("empty_container_weight"))
        #expect(ids.contains("material_type"))
        #expect(ids.contains("material_tags"))
        #expect(ids.contains("certifications"))
        #expect(ids.contains("tag_url"))
    }
}
