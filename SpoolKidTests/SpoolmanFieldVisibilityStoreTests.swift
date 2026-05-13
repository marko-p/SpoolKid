import Foundation
import Testing
@testable import SpoolKid

struct SpoolmanFieldVisibilityStoreTests {
    private struct MappingCase {
        let entity: SpoolmanEntity
        let fieldID: String
        let key: String
    }

    private static let mappedOptionalFields: [MappingCase] = [
        .init(entity: .vendor, fieldID: "comment", key: AppConfig.visibilityVendorCommentKey),
        .init(entity: .vendor, fieldID: "empty_spool_weight", key: AppConfig.visibilityVendorEmptySpoolWeightKey),
        .init(entity: .vendor, fieldID: "external_id", key: AppConfig.visibilityVendorExternalIdKey),
        .init(entity: .vendor, fieldID: "extra", key: AppConfig.visibilityVendorExtraKey),
        .init(entity: .filament, fieldID: "price", key: AppConfig.visibilityFilamentPriceKey),
        .init(entity: .filament, fieldID: "weight", key: AppConfig.visibilityFilamentWeightKey),
        .init(entity: .filament, fieldID: "spool_weight", key: AppConfig.visibilityFilamentSpoolWeightKey),
        .init(entity: .filament, fieldID: "article_number", key: AppConfig.visibilityFilamentArticleNumberKey),
        .init(entity: .filament, fieldID: "comment", key: AppConfig.visibilityFilamentCommentKey),
        .init(entity: .filament, fieldID: "multi_color_hexes", key: AppConfig.visibilityFilamentMultiColorHexesKey),
        .init(entity: .filament, fieldID: "multi_color_direction", key: AppConfig.visibilityFilamentMultiColorDirectionKey),
        .init(entity: .filament, fieldID: "external_id", key: AppConfig.visibilityFilamentExternalIdKey),
        .init(entity: .filament, fieldID: "extra", key: AppConfig.visibilityFilamentExtraKey),
        .init(entity: .spool, fieldID: "used_weight", key: AppConfig.visibilitySpoolUsedWeightKey),
        .init(entity: .spool, fieldID: "comment", key: AppConfig.visibilitySpoolCommentKey),
        .init(entity: .spool, fieldID: "archived", key: AppConfig.visibilitySpoolArchivedKey),
        .init(entity: .spool, fieldID: "first_used", key: AppConfig.visibilitySpoolFirstUsedKey),
        .init(entity: .spool, fieldID: "last_used", key: AppConfig.visibilitySpoolLastUsedKey),
        .init(entity: .spool, fieldID: "extra", key: AppConfig.visibilitySpoolExtraKey)
    ]

    private func makeDefaults(suffix: String) -> UserDefaults {
        let suiteName = "SpoolmanFieldVisibilityStoreTests.\(suffix).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func optionalFieldVisibilityUsesSettingsToggle() {
        let defaults = makeDefaults(suffix: "optional")
        defaults.set(false, forKey: AppConfig.visibilityVendorCommentKey)

        let store = SpoolmanFieldVisibilityStore(userDefaults: defaults)
        let visible = store.visibleFieldIDs(for: .vendor)

        #expect(!visible.contains("comment"))
    }

    @Test func essentialFieldsRemainVisibleWhenToggleOff() {
        let defaults = makeDefaults(suffix: "essential")
        defaults.set(false, forKey: AppConfig.visibilityVendorNameKey)

        let store = SpoolmanFieldVisibilityStore(userDefaults: defaults)
        let visible = store.visibleFieldIDs(for: .vendor)

        #expect(visible.contains("name"))
    }

    @Test func mappedOptionalFieldsCanBeToggledAndCoverageIsCompleteForDefaultHiddenFields() {
        let defaults = makeDefaults(suffix: "mapped-optional")
        let store = SpoolmanFieldVisibilityStore(userDefaults: defaults)

        for mapping in Self.mappedOptionalFields {
            defaults.removeObject(forKey: mapping.key)
            let before = store.visibleFieldIDs(for: mapping.entity)

            defaults.set(true, forKey: mapping.key)
            let after = store.visibleFieldIDs(for: mapping.entity)

            #expect(!before.contains(mapping.fieldID))
            #expect(after.contains(mapping.fieldID))
        }

        for entity in [SpoolmanEntity.vendor, .filament, .spool] {
            let mappedFieldIDs = Set(Self.mappedOptionalFields.filter { $0.entity == entity }.map(\.fieldID))
            let defaultHiddenOptionalFieldIDs = Set(
                SpoolmanFieldCatalog.fields(for: entity)
                    .filter { !$0.isEssential && !$0.defaultVisible }
                    .map(\.id)
            )

            #expect(mappedFieldIDs == defaultHiddenOptionalFieldIDs)
        }
    }

    @Test func optionalFieldDefaultsForVendorWithEmptySettings() {
        let defaults = makeDefaults(suffix: "vendor-defaults")
        let store = SpoolmanFieldVisibilityStore(userDefaults: defaults)

        let visible = store.visibleFieldIDs(for: .vendor)
        let optional = SpoolmanFieldCatalog.fields(for: .vendor).filter { !$0.isEssential }
        let expectedVisibleOptionalIDs = Set(optional.filter(\.defaultVisible).map(\.id))
        let actualVisibleOptionalIDs = Set(optional.map(\.id)).intersection(visible)

        #expect(actualVisibleOptionalIDs == expectedVisibleOptionalIDs)
    }

    @Test func optionalFieldDefaultsForFilamentWithEmptySettings() {
        let defaults = makeDefaults(suffix: "filament-defaults")
        let store = SpoolmanFieldVisibilityStore(userDefaults: defaults)

        let visible = store.visibleFieldIDs(for: .filament)
        let optional = SpoolmanFieldCatalog.fields(for: .filament).filter { !$0.isEssential }
        let expectedVisibleOptionalIDs = Set(optional.filter(\.defaultVisible).map(\.id))
        let actualVisibleOptionalIDs = Set(optional.map(\.id)).intersection(visible)

        #expect(actualVisibleOptionalIDs == expectedVisibleOptionalIDs)
    }

    @Test func optionalFieldDefaultsForSpoolWithEmptySettings() {
        let defaults = makeDefaults(suffix: "spool-defaults")
        let store = SpoolmanFieldVisibilityStore(userDefaults: defaults)

        let visible = store.visibleFieldIDs(for: .spool)
        let optional = SpoolmanFieldCatalog.fields(for: .spool).filter { !$0.isEssential }
        let expectedVisibleOptionalIDs = Set(optional.filter(\.defaultVisible).map(\.id))
        let actualVisibleOptionalIDs = Set(optional.map(\.id)).intersection(visible)

        #expect(actualVisibleOptionalIDs == expectedVisibleOptionalIDs)
    }
}
