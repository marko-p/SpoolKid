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
}
