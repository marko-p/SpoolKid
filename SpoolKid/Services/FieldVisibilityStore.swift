import Foundation

struct FieldVisibilityStore {
    private let userDefaults: UserDefaults
    private let support: BackendFieldSupport

    /// `support` defaults to `.spoolmanShaped` — not the whole catalogue, it
    /// excludes the three FilaMan-only spool fields (`status`,
    /// `external_id`, `purchase_date`) — so callers that have no backend in
    /// hand — tests, previews — behave as they always did, pre-2026-08-28.
    /// The three form views and the visibility editor pass
    /// `store.capabilities.fieldSupport`.
    init(userDefaults: UserDefaults = .standard, support: BackendFieldSupport = .spoolmanShaped) {
        self.userDefaults = userDefaults
        self.support = support
    }

    /// The user's preference INTERSECTED with what the backend actually has.
    ///
    /// Two different facts, conflated until 2026-08-28 because there was only
    /// ever one field set. Support wins over preference in both directions: a
    /// field the server lacks cannot be switched on, and an essential field is
    /// essential to the FORM, not evidence the server has it.
    func visibleFieldIDs(for entity: LibraryEntity) -> Set<String> {
        let fields = FieldCatalog.fields(for: entity)
            .filter { support.supports($0.id, in: entity) }

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

    func visibilityKey(for entity: LibraryEntity, fieldID: String) -> String? {
        switch (entity, fieldID) {
        case (.vendor, "name"): return AppConfig.visibilityVendorNameKey
        case (.vendor, "comment"): return AppConfig.visibilityVendorCommentKey
        case (.vendor, "empty_spool_weight"): return AppConfig.visibilityVendorEmptySpoolWeightKey
        case (.vendor, "external_id"): return AppConfig.visibilityVendorExternalIdKey
        case (.filament, "price"): return AppConfig.visibilityFilamentPriceKey
        case (.filament, "weight"): return AppConfig.visibilityFilamentWeightKey
        case (.filament, "spool_weight"): return AppConfig.visibilityFilamentSpoolWeightKey
        case (.filament, "article_number"): return AppConfig.visibilityFilamentArticleNumberKey
        case (.filament, "comment"): return AppConfig.visibilityFilamentCommentKey
        case (.filament, "external_id"): return AppConfig.visibilityFilamentExternalIdKey
        case (.spool, "used_weight"): return AppConfig.visibilitySpoolUsedWeightKey
        case (.spool, "comment"): return AppConfig.visibilitySpoolCommentKey
        case (.spool, "archived"): return AppConfig.visibilitySpoolArchivedKey
        case (.spool, "first_used"): return AppConfig.visibilitySpoolFirstUsedKey
        case (.spool, "last_used"): return AppConfig.visibilitySpoolLastUsedKey
        case (.spool, "status"): return AppConfig.visibilitySpoolStatusKey
        case (.spool, "external_id"): return AppConfig.visibilitySpoolExternalIdKey
        case (.spool, "purchase_date"): return AppConfig.visibilitySpoolPurchaseDateKey
        default: return nil
        }
    }
}
