import Foundation

struct SpoolmanFieldVisibilityStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func visibleFieldIDs(for entity: SpoolmanEntity) -> Set<String> {
        let fields = SpoolmanFieldCatalog.fields(for: entity)

        return Set(fields.compactMap { field in
            if field.isEssential {
                return field.id
            }

            guard let key = visibilityKey(for: entity, fieldID: field.id) else {
                if !field.defaultVisible {
                    assertionFailure("Missing visibility key for non-essential field '\(field.id)' in entity '\(entity.rawValue)'")
                }
                return field.defaultVisible ? field.id : nil
            }

            let enabled = if userDefaults.object(forKey: key) == nil {
                field.defaultVisible
            } else {
                userDefaults.bool(forKey: key)
            }

            return enabled ? field.id : nil
        })
    }

    private func visibilityKey(for entity: SpoolmanEntity, fieldID: String) -> String? {
        switch (entity, fieldID) {
        case (.vendor, "name"): return AppConfig.visibilityVendorNameKey
        case (.vendor, "comment"): return AppConfig.visibilityVendorCommentKey
        case (.vendor, "empty_spool_weight"): return AppConfig.visibilityVendorEmptySpoolWeightKey
        case (.vendor, "external_id"): return AppConfig.visibilityVendorExternalIdKey
        case (.vendor, "extra"): return AppConfig.visibilityVendorExtraKey
        case (.filament, "price"): return AppConfig.visibilityFilamentPriceKey
        case (.filament, "weight"): return AppConfig.visibilityFilamentWeightKey
        case (.filament, "spool_weight"): return AppConfig.visibilityFilamentSpoolWeightKey
        case (.filament, "article_number"): return AppConfig.visibilityFilamentArticleNumberKey
        case (.filament, "comment"): return AppConfig.visibilityFilamentCommentKey
        case (.filament, "multi_color_hexes"): return AppConfig.visibilityFilamentMultiColorHexesKey
        case (.filament, "multi_color_direction"): return AppConfig.visibilityFilamentMultiColorDirectionKey
        case (.filament, "external_id"): return AppConfig.visibilityFilamentExternalIdKey
        case (.filament, "extra"): return AppConfig.visibilityFilamentExtraKey
        case (.spool, "used_weight"): return AppConfig.visibilitySpoolUsedWeightKey
        case (.spool, "comment"): return AppConfig.visibilitySpoolCommentKey
        case (.spool, "archived"): return AppConfig.visibilitySpoolArchivedKey
        case (.spool, "first_used"): return AppConfig.visibilitySpoolFirstUsedKey
        case (.spool, "last_used"): return AppConfig.visibilitySpoolLastUsedKey
        case (.spool, "extra"): return AppConfig.visibilitySpoolExtraKey
        default: return nil
        }
    }
}
