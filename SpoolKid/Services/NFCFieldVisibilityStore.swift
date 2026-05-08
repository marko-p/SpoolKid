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

    private func visibilityKey(for format: TagFormat, fieldID: String) -> String? {
        switch (format, fieldID) {
        case (.openSpool, "name"): return AppConfig.visibilityNFCOpenSpoolNameKey
        case (.openSpool, "subtype"): return AppConfig.visibilityNFCOpenSpoolSubtypeKey
        case (.openSpool, "spool_id"): return AppConfig.visibilityNFCOpenSpoolSpoolIDKey
        case (.openPrintTag, "spool_id"): return AppConfig.visibilityNFCOpenPrintTagSpoolIDKey
        case (.openTag3D, "subtype"): return AppConfig.visibilityNFCOpenTag3DSubtypeKey
        case (.openTag3D, "name"): return AppConfig.visibilityNFCOpenTag3DNameKey
        default: return nil
        }
    }
}
