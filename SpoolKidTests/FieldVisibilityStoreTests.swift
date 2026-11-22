import Foundation
import Testing
@testable import SpoolKid

struct FieldVisibilityStoreTests {
    private struct MappingCase {
        let entity: LibraryEntity
        let fieldID: String
        let key: String
        /// The support table this mapping's toggle is proven against.
        /// Defaults to `.spoolmanShaped` (`FieldVisibilityStore`'s own
        /// default) — every field here used to be supported everywhere, so
        /// the default store could prove every case. Task 7's two FilaMan-only
        /// fields need `.filaman`: `.spoolmanShaped` excludes them from
        /// `visibleFieldIDs` before the preference is ever consulted, so
        /// enabling the key on that table could never show them.
        var support: BackendFieldSupport = .spoolmanShaped
    }

    private static let mappedOptionalFields: [MappingCase] = [
        .init(entity: .vendor, fieldID: "comment", key: AppConfig.visibilityVendorCommentKey),
        .init(entity: .vendor, fieldID: "empty_spool_weight", key: AppConfig.visibilityVendorEmptySpoolWeightKey),
        .init(entity: .vendor, fieldID: "external_id", key: AppConfig.visibilityVendorExternalIdKey),
        .init(entity: .filament, fieldID: "price", key: AppConfig.visibilityFilamentPriceKey),
        .init(entity: .filament, fieldID: "weight", key: AppConfig.visibilityFilamentWeightKey),
        .init(entity: .filament, fieldID: "spool_weight", key: AppConfig.visibilityFilamentSpoolWeightKey),
        .init(entity: .filament, fieldID: "article_number", key: AppConfig.visibilityFilamentArticleNumberKey),
        .init(entity: .filament, fieldID: "comment", key: AppConfig.visibilityFilamentCommentKey),
        .init(entity: .filament, fieldID: "external_id", key: AppConfig.visibilityFilamentExternalIdKey),
        .init(entity: .spool, fieldID: "used_weight", key: AppConfig.visibilitySpoolUsedWeightKey),
        .init(entity: .spool, fieldID: "comment", key: AppConfig.visibilitySpoolCommentKey),
        .init(entity: .spool, fieldID: "archived", key: AppConfig.visibilitySpoolArchivedKey),
        .init(entity: .spool, fieldID: "first_used", key: AppConfig.visibilitySpoolFirstUsedKey),
        .init(entity: .spool, fieldID: "last_used", key: AppConfig.visibilitySpoolLastUsedKey),
        .init(entity: .spool, fieldID: "external_id", key: AppConfig.visibilitySpoolExternalIdKey, support: .filaman),
        .init(entity: .spool, fieldID: "purchase_date", key: AppConfig.visibilitySpoolPurchaseDateKey, support: .filaman)
    ]

    private func makeDefaults(suffix: String) -> UserDefaults {
        let suiteName = "FieldVisibilityStoreTests.\(suffix).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func optionalFieldVisibilityUsesSettingsToggle() {
        let defaults = makeDefaults(suffix: "optional")
        defaults.set(false, forKey: AppConfig.visibilityVendorCommentKey)

        let store = FieldVisibilityStore(userDefaults: defaults)
        let visible = store.visibleFieldIDs(for: .vendor)

        #expect(!visible.contains("comment"))
    }

    @Test func essentialFieldsRemainVisibleWhenToggleOff() {
        let defaults = makeDefaults(suffix: "essential")
        defaults.set(false, forKey: AppConfig.visibilityVendorNameKey)

        let store = FieldVisibilityStore(userDefaults: defaults)
        let visible = store.visibleFieldIDs(for: .vendor)

        #expect(visible.contains("name"))
    }

    @Test func mappedOptionalFieldsCanBeToggledAndCoverageIsCompleteForDefaultHiddenFields() {
        let defaults = makeDefaults(suffix: "mapped-optional")

        for mapping in Self.mappedOptionalFields {
            let store = FieldVisibilityStore(userDefaults: defaults, support: mapping.support)

            defaults.removeObject(forKey: mapping.key)
            let before = store.visibleFieldIDs(for: mapping.entity)

            defaults.set(true, forKey: mapping.key)
            let after = store.visibleFieldIDs(for: mapping.entity)

            #expect(!before.contains(mapping.fieldID))
            #expect(after.contains(mapping.fieldID))
        }

        for entity in [LibraryEntity.vendor, .filament, .spool] {
            let mappedFieldIDs = Set(Self.mappedOptionalFields.filter { $0.entity == entity }.map(\.fieldID))
            let defaultHiddenOptionalFieldIDs = Set(
                FieldCatalog.fields(for: entity)
                    .filter { !$0.isEssential && !$0.defaultVisible }
                    .map(\.id)
            )

            #expect(mappedFieldIDs == defaultHiddenOptionalFieldIDs)
        }
    }

    @Test func optionalFieldDefaultsForVendorWithEmptySettings() {
        let defaults = makeDefaults(suffix: "vendor-defaults")
        let store = FieldVisibilityStore(userDefaults: defaults)

        let visible = store.visibleFieldIDs(for: .vendor)
        let optional = FieldCatalog.fields(for: .vendor).filter { !$0.isEssential }
        let expectedVisibleOptionalIDs = Set(optional.filter(\.defaultVisible).map(\.id))
        let actualVisibleOptionalIDs = Set(optional.map(\.id)).intersection(visible)

        #expect(actualVisibleOptionalIDs == expectedVisibleOptionalIDs)
    }

    @Test func optionalFieldDefaultsForFilamentWithEmptySettings() {
        let defaults = makeDefaults(suffix: "filament-defaults")
        let store = FieldVisibilityStore(userDefaults: defaults)

        let visible = store.visibleFieldIDs(for: .filament)
        let optional = FieldCatalog.fields(for: .filament).filter { !$0.isEssential }
        let expectedVisibleOptionalIDs = Set(optional.filter(\.defaultVisible).map(\.id))
        let actualVisibleOptionalIDs = Set(optional.map(\.id)).intersection(visible)

        #expect(actualVisibleOptionalIDs == expectedVisibleOptionalIDs)
    }

    @Test func optionalFieldDefaultsForSpoolWithEmptySettings() {
        let defaults = makeDefaults(suffix: "spool-defaults")
        let store = FieldVisibilityStore(userDefaults: defaults)

        let visible = store.visibleFieldIDs(for: .spool)
        // Filtered to what the store's own default support (`.spoolmanShaped`)
        // actually has — Task 7 added three FilaMan-only spool fields to the
        // catalogue, and `visibleFieldIDs` never shows a field this support
        // table doesn't declare, regardless of `defaultVisible`.
        let optional = FieldCatalog.fields(for: .spool)
            .filter { !$0.isEssential && BackendFieldSupport.spoolmanShaped.supports($0.id, in: .spool) }
        let expectedVisibleOptionalIDs = Set(optional.filter(\.defaultVisible).map(\.id))
        let actualVisibleOptionalIDs = Set(optional.map(\.id)).intersection(visible)

        #expect(actualVisibleOptionalIDs == expectedVisibleOptionalIDs)
    }

    // MARK: - Support narrows visibility (2026-08-28)

    /// A preference the user switched ON for a field the backend does not have
    /// must still not render it. Support is a fact; visibility is a wish.
    @Test func anEnabledPreferenceCannotShowAnUnsupportedField() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        defaults.set(true, forKey: AppConfig.visibilitySpoolFirstUsedKey)
        let support = BackendFieldSupport(entities: [
            .spool: EntitySupport(supportedIDs: ["filament_id", "initial_weight", "spool_weight"])
        ])

        let visible = FieldVisibilityStore(userDefaults: defaults, support: support)
            .visibleFieldIDs(for: .spool)

        #expect(visible.contains("first_used") == false)
    }

    /// The other direction: support does not override the user's choice to hide
    /// something the backend does have.
    @Test func aDisabledPreferenceStaysHiddenOnASupportedField() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        defaults.set(false, forKey: AppConfig.visibilitySpoolFirstUsedKey)
        let support = BackendFieldSupport(entities: [
            .spool: EntitySupport(supportedIDs: ["filament_id", "first_used"])
        ])

        let visible = FieldVisibilityStore(userDefaults: defaults, support: support)
            .visibleFieldIDs(for: .spool)

        #expect(visible.contains("first_used") == false)
    }

    /// An ESSENTIAL field the backend lacks must still disappear. "Essential"
    /// means the form cannot omit it by preference, not that the server has it.
    @Test func anEssentialFieldIsStillDroppedWhenUnsupported() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let support = BackendFieldSupport(entities: [
            .spool: EntitySupport(supportedIDs: ["filament_id"])
        ])

        let visible = FieldVisibilityStore(userDefaults: defaults, support: support)
            .visibleFieldIDs(for: .spool)

        #expect(visible.contains("filament_id"))
        #expect(visible.contains("initial_weight") == false)
    }

    /// The default table is the whole catalogue, so every existing call site
    /// and test behaves exactly as before this task.
    @Test func theDefaultSupportTableNarrowsNothing() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        defaults.set(true, forKey: AppConfig.visibilitySpoolFirstUsedKey)

        let visible = FieldVisibilityStore(userDefaults: defaults).visibleFieldIDs(for: .spool)

        #expect(visible.contains("first_used"))
    }
}
