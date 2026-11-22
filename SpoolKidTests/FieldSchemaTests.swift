import Foundation
import Testing
@testable import SpoolKid

struct FieldSchemaTests {
    @Test func spoolCatalogContainsLocationAndArchiveFields() {
        let ids = Set(FieldCatalog.fields(for: .spool).map(\.id))
        #expect(ids.contains("filament_id"))
        #expect(ids.contains("location"))
        #expect(ids.contains("archived"))
    }

    @Test func filamentCatalogExcludesLocationField() {
        let ids = Set(FieldCatalog.fields(for: .filament).map(\.id))
        #expect(!ids.contains("location"))
    }

    @Test func essentialFieldsAreAlwaysDefaultVisible() {
        let essential = FieldCatalog.fields(for: .vendor).filter(\.isEssential)
        #expect(essential.allSatisfy { $0.defaultVisible })
    }

    @Test func catalogInvariantsHoldAcrossEntities() {
        for entity in LibraryEntity.allCases {
            let fields = FieldCatalog.fields(for: entity)
            let ids = fields.map(\.id)

            #expect(Set(ids).count == ids.count)

            for field in fields {
                #expect(!field.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!field.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!field.section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!field.isEssential || field.defaultVisible)

                if entity != .location {
                    #expect(!(field.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
                }
            }
        }
    }
}
