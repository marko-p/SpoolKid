import Foundation
import Testing
@testable import SpoolKid

struct VisibilityDefaultsStructureTests {
    @Test func visibilityDefaultsContainCoreOptionalKeys() {
        let defaults = AppConfig.fieldVisibilityDefaults
        #expect(defaults[AppConfig.visibilityVendorCommentKey] != nil)
        #expect(defaults[AppConfig.visibilityFilamentCommentKey] != nil)
        #expect(defaults[AppConfig.visibilitySpoolArchivedKey] != nil)
    }

    @Test func nfcVisibilityKeysExistInDefaults() {
        let defaults = AppConfig.fieldVisibilityDefaults
        #expect(defaults[AppConfig.visibilityNFCOpenSpoolNameKey] != nil)
        #expect(defaults[AppConfig.visibilityNFCOpenSpoolSubtypeKey] != nil)
        #expect(defaults[AppConfig.visibilityNFCOpenSpoolSpoolIDKey] != nil)
        #expect(defaults[AppConfig.visibilityNFCOpenTag3DSubtypeKey] != nil)
        #expect(defaults[AppConfig.visibilityNFCOpenTag3DNameKey] != nil)
    }

    @Test func spoolmanVisibilityDefaultsMatchCatalog() {
        let store = FieldVisibilityStore()
        let defaults = AppConfig.fieldVisibilityDefaults

        for entity in LibraryEntity.allCases {
            for field in FieldCatalog.fields(for: entity).filter({ !$0.isEssential }) {
                guard let key = store.visibilityKey(for: entity, fieldID: field.id) else {
                    // Fields without a visibility key are always shown (defaultVisible)
                    // and are not toggleable, so they don't need a defaults entry.
                    continue
                }
                #expect(defaults[key] != nil, "\(key) for \(entity.rawValue).\(field.id) must be in fieldVisibilityDefaults")
            }
        }
    }

    @Test func nfcVisibilityDefaultsMatchCatalog() {
        let store = NFCFieldVisibilityStore()
        let defaults = AppConfig.fieldVisibilityDefaults

        for format in TagFormat.allCases {
            for field in NFCFieldCatalog.fields(for: format).filter({ !$0.isEssential }) {
                guard let key = store.visibilityKey(for: format, fieldID: field.id) else {
                    continue
                }
                #expect(defaults[key] != nil, "\(key) for \(format.rawValue).\(field.id) must be in fieldVisibilityDefaults")
            }
        }
    }

    @Test func fieldVisibilityDefaultsContainsOnlyKnownKeys() {
        // Every key in fieldVisibilityDefaults must map to a real catalog field
        // (essential or non-essential) so the stores/editors know what it means.
        var knownKeys = Set<String>()

        let spoolmanStore = FieldVisibilityStore()
        for entity in LibraryEntity.allCases {
            for field in FieldCatalog.fields(for: entity) {
                if let key = spoolmanStore.visibilityKey(for: entity, fieldID: field.id) {
                    knownKeys.insert(key)
                }
            }
        }

        let nfcStore = NFCFieldVisibilityStore()
        for format in TagFormat.allCases {
            for field in NFCFieldCatalog.fields(for: format) {
                if let key = nfcStore.visibilityKey(for: format, fieldID: field.id) {
                    knownKeys.insert(key)
                }
            }
        }

        for key in AppConfig.fieldVisibilityDefaults.keys {
            #expect(knownKeys.contains(key), "fieldVisibilityDefaults contains unknown key \(key)")
        }
    }
}
