import Foundation

enum NFCFieldInputType: Sendable, Hashable {
    case text
    case multilineText
    case integer
    case hexColor
    case temperatureRange
    case picker
    case combo
}

struct NFCFieldDefinition: Sendable, Hashable, Identifiable {
    let id: String
    let label: String
    let section: String
    let inputType: NFCFieldInputType
    let isEssential: Bool
    let defaultVisible: Bool

    init(
        id: String,
        label: String,
        section: String,
        inputType: NFCFieldInputType,
        isEssential: Bool,
        defaultVisible: Bool
    ) {
        self.id = id
        self.label = label
        self.section = section
        self.inputType = inputType
        self.isEssential = isEssential
        self.defaultVisible = isEssential ? true : defaultVisible
    }
}

enum NFCFieldCatalog {
    static func fields(for format: TagFormat) -> [NFCFieldDefinition] {
        switch format {
        case .openSpool:
            openSpool
        case .openPrintTag:
            openPrintTag
        case .openTag3D:
            openTag3D
        case .anycubicACE:
            anycubic
        }
    }

    static let openSpool: [NFCFieldDefinition] = [
        .init(id: "material", label: "Material", section: "Filament", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "color_hex", label: "Color", section: "Filament", inputType: .hexColor, isEssential: true, defaultVisible: true),
        .init(id: "brand", label: "Brand", section: "Filament", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "temp_range", label: "Temperatures", section: "Printing", inputType: .temperatureRange, isEssential: true, defaultVisible: true),
        .init(id: "name", label: "Name", section: "Filament", inputType: .text, isEssential: false, defaultVisible: true),
        .init(id: "subtype", label: "Subtype", section: "Filament", inputType: .combo, isEssential: false, defaultVisible: true),
        .init(id: "spool_id", label: "Spool ID", section: "Linked Data", inputType: .integer, isEssential: false, defaultVisible: true)
    ]

    static let openPrintTag: [NFCFieldDefinition] = [
        .init(id: "material", label: "Material", section: "Material", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "material_type", label: "Material Type", section: "Material", inputType: .picker, isEssential: false, defaultVisible: false),
        .init(id: "name", label: "Material Name", section: "Material", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "brand", label: "Brand", section: "Material", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "color_hex", label: "Color", section: "Material", inputType: .hexColor, isEssential: true, defaultVisible: true),
        .init(id: "temp_range", label: "Temperatures", section: "Printing", inputType: .temperatureRange, isEssential: true, defaultVisible: true),
        .init(id: "density", label: "Density", section: "Material", inputType: .text, isEssential: false, defaultVisible: false),
        .init(id: "transmission_distance", label: "Transmission Distance", section: "Material", inputType: .text, isEssential: false, defaultVisible: false),
        .init(id: "gtin", label: "GTIN", section: "Material", inputType: .text, isEssential: false, defaultVisible: false),
        .init(id: "manufactured_date", label: "Manufactured Date", section: "Material", inputType: .text, isEssential: false, defaultVisible: false),
        .init(id: "country_of_origin", label: "Country Of Origin", section: "Material", inputType: .text, isEssential: false, defaultVisible: false),
        .init(id: "preheat_temperature", label: "Preheat Temperature", section: "Printing", inputType: .integer, isEssential: false, defaultVisible: false),
        .init(id: "drying_temperature", label: "Drying Temperature", section: "Printing", inputType: .integer, isEssential: false, defaultVisible: false),
        .init(id: "drying_time", label: "Drying Time", section: "Printing", inputType: .integer, isEssential: false, defaultVisible: false),
        .init(id: "nominal_netto_full_weight", label: "Nominal Weight", section: "Weight", inputType: .integer, isEssential: false, defaultVisible: false),
        .init(id: "actual_netto_full_weight", label: "Actual Weight", section: "Weight", inputType: .integer, isEssential: false, defaultVisible: false),
        .init(id: "empty_container_weight", label: "Empty Container", section: "Weight", inputType: .integer, isEssential: false, defaultVisible: false),
        .init(id: "material_tags", label: "Material Tags", section: "Material", inputType: .multilineText, isEssential: false, defaultVisible: false),
        .init(id: "certifications", label: "Certifications", section: "Material", inputType: .multilineText, isEssential: false, defaultVisible: false),
        .init(id: "tag_url", label: "Tag URL", section: "NFC", inputType: .text, isEssential: false, defaultVisible: false),
        .init(id: "spool_id", label: "Spool ID", section: "Linked Data", inputType: .integer, isEssential: false, defaultVisible: false)
    ]

    static let openTag3D: [NFCFieldDefinition] = [
        .init(id: "material", label: "Material", section: "Filament", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "subtype", label: "Modifier", section: "Filament", inputType: .combo, isEssential: false, defaultVisible: true),
        .init(id: "name", label: "Color Name", section: "Filament", inputType: .text, isEssential: false, defaultVisible: true),
        .init(id: "brand", label: "Manufacturer", section: "Filament", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "color_hex", label: "Color", section: "Filament", inputType: .hexColor, isEssential: true, defaultVisible: true),
        .init(id: "temp_range", label: "Temperatures", section: "Printing", inputType: .temperatureRange, isEssential: true, defaultVisible: true)
    ]

    static let anycubic: [NFCFieldDefinition] = [
        .init(id: "material", label: "Material", section: "Filament", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "name", label: "SKU/Name", section: "Filament", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "brand", label: "Brand", section: "Filament", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "color_hex", label: "Color", section: "Filament", inputType: .hexColor, isEssential: true, defaultVisible: true),
        .init(id: "temp_range", label: "Temperatures", section: "Printing", inputType: .temperatureRange, isEssential: true, defaultVisible: true)
    ]
}
