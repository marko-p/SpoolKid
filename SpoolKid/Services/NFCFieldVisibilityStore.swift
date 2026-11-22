import Foundation

struct NFCFieldVisibilityStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func visibleFieldIDs(for format: TagFormat) -> Set<String> {
        let fields = NFCFieldCatalog.fields(for: format)

        return Set(fields.compactMap { field in
            if field.isEssential {
                return field.id
            }

            guard let key = visibilityKey(for: format, fieldID: field.id) else {
                if !field.defaultVisible {
                    assertionFailure("Missing visibility key for non-essential field '\(field.id)' in format '\(format.rawValue)'")
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

    func visibilityKey(for format: TagFormat, fieldID: String) -> String? {
        switch (format, fieldID) {
        case (.openSpool, "name"): return AppConfig.visibilityNFCOpenSpoolNameKey
        case (.openSpool, "subtype"): return AppConfig.visibilityNFCOpenSpoolSubtypeKey
        case (.openSpool, "spool_id"): return AppConfig.visibilityNFCOpenSpoolSpoolIDKey
        case (.openTag3D, "subtype"): return AppConfig.visibilityNFCOpenTag3DSubtypeKey
        case (.openTag3D, "name"): return AppConfig.visibilityNFCOpenTag3DNameKey
        case (.openTag3D, "diameter"): return AppConfig.visibilityNFCOpenTag3DDiameterKey
        case (.openTag3D, "nominal_weight"): return AppConfig.visibilityNFCOpenTag3DNominalWeightKey
        case (.openTag3D, "empty_weight"): return AppConfig.visibilityNFCOpenTag3DEmptyWeightKey
        case (.openTag3D, "drying_temp"): return AppConfig.visibilityNFCOpenTag3DDryingTempKey
        case (.openTag3D, "drying_time"): return AppConfig.visibilityNFCOpenTag3DDryingTimeKey
        case (.openTag3D, "manufactured_date"): return AppConfig.visibilityNFCOpenTag3DManufacturedKey
        case (.anycubicACE, "diameter"): return AppConfig.visibilityNFCAnycubicDiameterKey
        case (.anycubicACE, "nominal_weight"): return AppConfig.visibilityNFCAnycubicNominalWeightKey
        case (.openPrintTag, "name"): return AppConfig.visibilityNFCOpenPrintTagNameKey
        case (.openPrintTag, "density"): return AppConfig.visibilityNFCOpenPrintTagDensityKey
        case (.openPrintTag, "diameter"): return AppConfig.visibilityNFCOpenPrintTagDiameterKey
        case (.openPrintTag, "preheat_temp"): return AppConfig.visibilityNFCOpenPrintTagPreheatKey
        case (.openPrintTag, "nominal_weight"): return AppConfig.visibilityNFCOpenPrintTagNominalWeightKey
        case (.openPrintTag, "empty_weight"): return AppConfig.visibilityNFCOpenPrintTagEmptyWeightKey
        case (.openPrintTag, "remaining"): return AppConfig.visibilityNFCOpenPrintTagRemainingKey
        case (.openPrintTag, "drying_temp"): return AppConfig.visibilityNFCOpenPrintTagDryingTempKey
        case (.openPrintTag, "drying_time"): return AppConfig.visibilityNFCOpenPrintTagDryingTimeKey
        case (.openPrintTag, "gtin"): return AppConfig.visibilityNFCOpenPrintTagGTINKey
        case (.openPrintTag, "country"): return AppConfig.visibilityNFCOpenPrintTagCountryKey
        case (.openPrintTag, "manufactured_date"): return AppConfig.visibilityNFCOpenPrintTagManufacturedKey
        case (.openPrintTag, "url"): return AppConfig.visibilityNFCOpenPrintTagURLKey
        case (.tigerTag, "name"): return AppConfig.visibilityNFCTigerTagNameKey
        case (.tigerTag, "subtype"): return AppConfig.visibilityNFCTigerTagSubtypeKey
        case (.tigerTag, "diameter"): return AppConfig.visibilityNFCTigerTagDiameterKey
        case (.tigerTag, "nominal_weight"): return AppConfig.visibilityNFCTigerTagNominalWeightKey
        default: return nil
        }
    }
}
