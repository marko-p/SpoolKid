import Foundation
import Testing
@testable import SpoolKid

struct NFCFieldVisibilityStoreTests {
    private struct MappingCase {
        let format: TagFormat
        let fieldID: String
        let key: String
    }

    private static let mappedOptionalFields: [MappingCase] = [
        .init(format: .openSpool, fieldID: "name", key: AppConfig.visibilityNFCOpenSpoolNameKey),
        .init(format: .openSpool, fieldID: "subtype", key: AppConfig.visibilityNFCOpenSpoolSubtypeKey),
        .init(format: .openSpool, fieldID: "spool_id", key: AppConfig.visibilityNFCOpenSpoolSpoolIDKey),
        .init(format: .openPrintTag, fieldID: "spool_id", key: AppConfig.visibilityNFCOpenPrintTagSpoolIDKey),
        .init(format: .openTag3D, fieldID: "subtype", key: AppConfig.visibilityNFCOpenTag3DSubtypeKey),
        .init(format: .openTag3D, fieldID: "name", key: AppConfig.visibilityNFCOpenTag3DNameKey)
    ]

    private func makeDefaults(suffix: String) -> UserDefaults {
        let suiteName = "NFCFieldVisibilityStoreTests.\(suffix).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func essentialFieldsAlwaysVisible() {
        let defaults = makeDefaults(suffix: "essential")
        defaults.set(false, forKey: AppConfig.visibilityNFCOpenSpoolNameKey)

        let store = NFCFieldVisibilityStore(userDefaults: defaults)
        let visible = store.visibleFieldIDs(for: .openSpool)

        #expect(visible.contains("material"))
    }

    @Test func optionalFieldRespectsToggle() {
        let defaults = makeDefaults(suffix: "optional")
        defaults.set(false, forKey: AppConfig.visibilityNFCOpenSpoolSubtypeKey)

        let store = NFCFieldVisibilityStore(userDefaults: defaults)
        let visible = store.visibleFieldIDs(for: .openSpool)

        #expect(!visible.contains("subtype"))
    }

    @Test func mappedOptionalFieldsCanBeToggledAndCoverageMatchesFormats() {
        let defaults = makeDefaults(suffix: "mapped-optional")
        let store = NFCFieldVisibilityStore(userDefaults: defaults)

        for mapping in Self.mappedOptionalFields {
            defaults.removeObject(forKey: mapping.key)
            let before = store.visibleFieldIDs(for: mapping.format)

            guard let field = NFCFieldCatalog.fields(for: mapping.format).first(where: { $0.id == mapping.fieldID }) else {
                #expect(Bool(false), "Missing mapped field '\(mapping.fieldID)' in NFC schema for format '\(mapping.format.rawValue)'")
                continue
            }

            defaults.set(!field.defaultVisible, forKey: mapping.key)
            let after = store.visibleFieldIDs(for: mapping.format)

            #expect(before.contains(mapping.fieldID) != after.contains(mapping.fieldID))
            #expect(!field.isEssential)
        }

        for format in [TagFormat.openSpool, .openPrintTag, .openTag3D, .anycubicACE] {
            let mappedFieldIDs = Set(Self.mappedOptionalFields.filter { $0.format == format }.map(\.fieldID))
            let defaultHiddenNonEssentialFieldIDs = Set(
                NFCFieldCatalog.fields(for: format)
                    .filter { !$0.isEssential && !$0.defaultVisible }
                    .map(\.id)
            )

            #expect(defaultHiddenNonEssentialFieldIDs.isSubset(of: mappedFieldIDs))
        }
    }
}
