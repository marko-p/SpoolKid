import Foundation

enum WriteTagFormAssembler {
    static func initialOverride(defaultRawValue: String) -> TagFormat {
        TagFormat(rawValue: defaultRawValue) ?? .openSpool
    }

    static func visibleFields(
        format: TagFormat,
        visibilityStore: NFCFieldVisibilityStore = .init()
    ) -> [NFCFieldDefinition] {
        let visibleFieldIDs = visibilityStore.visibleFieldIDs(for: format)
        return NFCFieldCatalog.fields(for: format).filter { visibleFieldIDs.contains($0.id) }
    }

    static func shouldShowNameField(
        format: TagFormat,
        visibleFieldIDs: Set<String>,
        isU1CompatActive: Bool
    ) -> Bool {
        guard visibleFieldIDs.contains("name") else { return false }
        // Legacy U1 behavior previously hid name for OpenSpool.
        // Visibility toggles now own this behavior; keep field visible when enabled.
        _ = format
        _ = isU1CompatActive
        return true
    }

    static func buildTagData(
        format: TagFormat,
        name: String,
        material: String,
        subtype: String,
        brand: String,
        colorHex: String,
        minNozzleTemp: Int,
        maxNozzleTemp: Int,
        minBedTemp: Int,
        maxBedTemp: Int,
        spoolmanId: Int?,
        writeSpoolID: Bool
    ) -> FilamentTagData {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSubtype = subtype.trimmingCharacters(in: .whitespacesAndNewlines)

        let nameToWrite: String? = switch format {
        case .openSpool, .openPrintTag, .openTag3D, .anycubicACE:
            normalizedName.isEmpty ? nil : normalizedName
        }

        let subtypeToWrite: String? = switch format {
        case .openSpool, .openTag3D:
            normalizedSubtype.isEmpty ? nil : normalizedSubtype
        case .openPrintTag, .anycubicACE:
            nil
        }

        let spoolIdToWrite: Int? = switch format {
        case .openSpool, .openPrintTag:
            writeSpoolID ? spoolmanId : nil
        case .openTag3D, .anycubicACE:
            nil
        }

        return FilamentTagData(
            name: nameToWrite,
            material: material,
            subtype: subtypeToWrite,
            brand: brand,
            colorHex: colorHex,
            minNozzleTemp: minNozzleTemp,
            maxNozzleTemp: maxNozzleTemp,
            minBedTemp: minBedTemp,
            maxBedTemp: maxBedTemp,
            spoolmanId: spoolIdToWrite
        )
    }

    static func unixSeconds(from date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded())
    }

    static func date(fromUnixSeconds unix: Int) -> Date? {
        guard unix >= 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(unix))
    }
}
