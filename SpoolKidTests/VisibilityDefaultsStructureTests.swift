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

    @Test func settingsHierarchyContainsSpoolmanVisibilityPanes() throws {
        let rootSpecifiers = try preferenceSpecifiers(from: "Root.plist")
        #expect(hasChildPane(file: "SpoolmanFieldVisibility", in: rootSpecifiers))

        let visibilitySpecifiers = try preferenceSpecifiers(from: "SpoolmanFieldVisibility.plist")
        #expect(hasChildPane(file: "SpoolVisibility", in: visibilitySpecifiers))
        #expect(hasChildPane(file: "FilamentVisibility", in: visibilitySpecifiers))
        #expect(hasChildPane(file: "VendorVisibility", in: visibilitySpecifiers))
        #expect(hasChildPane(file: "LocationVisibility", in: visibilitySpecifiers))
    }

    @Test func settingsHierarchyContainsNFCVisibilityPanes() throws {
        let rootSpecifiers = try preferenceSpecifiers(from: "Root.plist")
        #expect(hasChildPane(file: "NFCFieldVisibility", in: rootSpecifiers))

        let nfcSpecifiers = try preferenceSpecifiers(from: "NFCFieldVisibility.plist")
        #expect(hasChildPane(file: "OpenSpoolVisibility", in: nfcSpecifiers))
        #expect(hasChildPane(file: "OpenPrintTagVisibility", in: nfcSpecifiers))
        #expect(hasChildPane(file: "OpenTag3DVisibility", in: nfcSpecifiers))
        #expect(hasChildPane(file: "AnycubicACEVisibility", in: nfcSpecifiers))
    }

    @Test func nfcVisibilityKeysExistInDefaults() {
        let defaults = AppConfig.fieldVisibilityDefaults
        #expect(defaults[AppConfig.visibilityNFCOpenSpoolNameKey] != nil)
        #expect(defaults[AppConfig.visibilityNFCOpenSpoolSubtypeKey] != nil)
        #expect(defaults[AppConfig.visibilityNFCOpenSpoolSpoolIDKey] != nil)
        #expect(defaults[AppConfig.visibilityNFCOpenPrintTagSpoolIDKey] != nil)
        #expect(defaults[AppConfig.visibilityNFCOpenTag3DSubtypeKey] != nil)
        #expect(defaults[AppConfig.visibilityNFCOpenTag3DNameKey] != nil)
    }

    @Test func visibilityToggleKeysStayInSyncWithConfigAndSchema() throws {
        let vendorKeys = try toggleKeys(from: "VendorVisibility.plist")
        let filamentKeys = try toggleKeys(from: "FilamentVisibility.plist")
        let spoolKeys = try toggleKeys(from: "SpoolVisibility.plist")
        let locationKeys = try toggleKeys(from: "LocationVisibility.plist")

        #expect(vendorKeys == Set([
            AppConfig.visibilityVendorCommentKey,
            AppConfig.visibilityVendorEmptySpoolWeightKey,
            AppConfig.visibilityVendorExternalIdKey,
            AppConfig.visibilityVendorExtraKey
        ]))

        #expect(filamentKeys == Set([
            AppConfig.visibilityFilamentPriceKey,
            AppConfig.visibilityFilamentWeightKey,
            AppConfig.visibilityFilamentSpoolWeightKey,
            AppConfig.visibilityFilamentArticleNumberKey,
            AppConfig.visibilityFilamentCommentKey,
            AppConfig.visibilityFilamentMultiColorHexesKey,
            AppConfig.visibilityFilamentMultiColorDirectionKey,
            AppConfig.visibilityFilamentExternalIdKey,
            AppConfig.visibilityFilamentExtraKey
        ]))

        #expect(spoolKeys == Set([
            AppConfig.visibilitySpoolUsedWeightKey,
            AppConfig.visibilitySpoolCommentKey,
            AppConfig.visibilitySpoolArchivedKey,
            AppConfig.visibilitySpoolFirstUsedKey,
            AppConfig.visibilitySpoolLastUsedKey,
            AppConfig.visibilitySpoolExtraKey
        ]))

        #expect(locationKeys.isEmpty)

        let allKeys = vendorKeys.union(filamentKeys).union(spoolKeys).union(locationKeys)
        let defaultKeys = Set(AppConfig.fieldVisibilityDefaults.keys)
        #expect(allKeys.isSubset(of: defaultKeys))

        for entity in [SpoolmanEntity.vendor, .filament, .spool, .location] {
            let expectedFieldKeys = Set(
                SpoolmanFieldCatalog.fields(for: entity)
                    .filter { !$0.isEssential && !$0.defaultVisible }
                    .compactMap { visibilityKey(for: entity, fieldID: $0.id) }
            )

            let paneFile = switch entity {
            case .vendor: "VendorVisibility.plist"
            case .filament: "FilamentVisibility.plist"
            case .spool: "SpoolVisibility.plist"
            case .location: "LocationVisibility.plist"
            }

            let paneKeys = try toggleKeys(from: paneFile)
            #expect(paneKeys == expectedFieldKeys)
        }
    }

    @Test func nfcVisibilityToggleKeysStayInSyncWithConfig() throws {
        let openSpoolKeys = try toggleKeys(from: "OpenSpoolVisibility.plist")
        let openPrintTagKeys = try toggleKeys(from: "OpenPrintTagVisibility.plist")
        let openTag3DKeys = try toggleKeys(from: "OpenTag3DVisibility.plist")
        let anycubicKeys = try toggleKeys(from: "AnycubicACEVisibility.plist")

        #expect(openSpoolKeys == Set([
            AppConfig.visibilityNFCOpenSpoolNameKey,
            AppConfig.visibilityNFCOpenSpoolSubtypeKey,
            AppConfig.visibilityNFCOpenSpoolSpoolIDKey
        ]))

        #expect(openPrintTagKeys == Set([
            AppConfig.visibilityNFCOpenPrintTagSpoolIDKey
        ]))

        #expect(openTag3DKeys == Set([
            AppConfig.visibilityNFCOpenTag3DSubtypeKey,
            AppConfig.visibilityNFCOpenTag3DNameKey
        ]))

        #expect(anycubicKeys.isEmpty)

        let allNFCKeys = openSpoolKeys.union(openPrintTagKeys).union(openTag3DKeys).union(anycubicKeys)
        let defaultKeys = Set(AppConfig.fieldVisibilityDefaults.keys)
        #expect(allNFCKeys.isSubset(of: defaultKeys))
    }

    private func preferenceSpecifiers(from fileName: String) throws -> [[String: Any]] {
        let settingsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SpoolKid")
            .appendingPathComponent("Settings.bundle")
            .appendingPathComponent(fileName)

        let data = try Data(contentsOf: settingsURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)

        if let dict = plist as? [String: Any], let specifiers = dict["PreferenceSpecifiers"] as? [[String: Any]] {
            return specifiers
        }

        if let specifiers = plist as? [[String: Any]] {
            return specifiers
        }

        Issue.record("\(fileName) does not contain valid preference specifiers")
        return []
    }

    private func hasChildPane(file: String, in specifiers: [[String: Any]]) -> Bool {
        specifiers.contains {
            ($0["Type"] as? String) == "PSChildPaneSpecifier"
                && ($0["File"] as? String) == file
        }
    }

    private func toggleKeys(from fileName: String) throws -> Set<String> {
        let specifiers = try preferenceSpecifiers(from: fileName)
        return Set(
            specifiers.compactMap { specifier in
                guard (specifier["Type"] as? String) == "PSToggleSwitchSpecifier" else {
                    return nil
                }
                return specifier["Key"] as? String
            }
        )
    }

    private func visibilityKey(for entity: SpoolmanEntity, fieldID: String) -> String? {
        switch (entity, fieldID) {
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
