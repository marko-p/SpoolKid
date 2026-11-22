import Foundation

enum NFCFieldInputType: Sendable, Hashable {
    case text
    case multilineText
    case integer
    case decimal
    case date
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
        case .elegoo:
            elegoo
        case .tigerTag:
            tigerTag
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

    static let openTag3D: [NFCFieldDefinition] = [
        .init(id: "material", label: "Material", section: "Filament", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "subtype", label: "Modifier", section: "Filament", inputType: .combo, isEssential: false, defaultVisible: true),
        .init(id: "name", label: "Color Name", section: "Filament", inputType: .text, isEssential: false, defaultVisible: true),
        .init(id: "brand", label: "Manufacturer", section: "Filament", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "color_hex", label: "Color", section: "Filament", inputType: .hexColor, isEssential: true, defaultVisible: true),
        .init(id: "temp_range", label: "Temperatures", section: "Printing", inputType: .temperatureRange, isEssential: true, defaultVisible: true),
        // Diameter and net weight are required by the OpenTag3D spec, so the
        // form has to be able to state them rather than always writing defaults.
        .init(id: "diameter", label: "Diameter (mm)", section: "Filament", inputType: .decimal, isEssential: false, defaultVisible: true),
        .init(id: "nominal_weight", label: "Net Weight (g)", section: "Weight", inputType: .integer, isEssential: false, defaultVisible: true),
        .init(id: "empty_weight", label: "Empty Spool (g)", section: "Weight", inputType: .integer, isEssential: false, defaultVisible: true),
        // The tag's field is the MAXIMUM safe drying temperature.
        .init(id: "drying_temp", label: "Max Drying Temp", section: "Drying", inputType: .integer, isEssential: false, defaultVisible: true),
        // Stored on the tag in whole hours; the form's minutes are rounded.
        .init(id: "drying_time", label: "Drying Time (min)", section: "Drying", inputType: .integer, isEssential: false, defaultVisible: true),
        // Hidden by default: the date picker starts on today, and a visible row
        // would stamp every tag with the day it was written.
        .init(id: "manufactured_date", label: "Manufactured", section: "Identification", inputType: .date, isEssential: false, defaultVisible: false)
    ]

    static let openPrintTag: [NFCFieldDefinition] = [
        .init(id: "material", label: "Material", section: "Filament", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "brand", label: "Brand", section: "Filament", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "color_hex", label: "Color", section: "Filament", inputType: .hexColor, isEssential: true, defaultVisible: true),
        .init(id: "temp_range", label: "Temperatures", section: "Printing", inputType: .temperatureRange, isEssential: true, defaultVisible: true),
        .init(id: "name", label: "Name", section: "Filament", inputType: .text, isEssential: false, defaultVisible: true),
        .init(id: "density", label: "Density (g/cm³)", section: "Filament", inputType: .decimal, isEssential: false, defaultVisible: true),
        .init(id: "diameter", label: "Diameter (mm)", section: "Filament", inputType: .decimal, isEssential: false, defaultVisible: true),
        .init(id: "preheat_temp", label: "Preheat Temp", section: "Printing", inputType: .integer, isEssential: false, defaultVisible: true),
        .init(id: "nominal_weight", label: "Net Weight (g)", section: "Weight", inputType: .integer, isEssential: false, defaultVisible: true),
        .init(id: "empty_weight", label: "Empty Spool (g)", section: "Weight", inputType: .integer, isEssential: false, defaultVisible: true),
        .init(id: "remaining", label: "Remaining (g)", section: "Weight", inputType: .integer, isEssential: false, defaultVisible: true),
        .init(id: "drying_temp", label: "Drying Temp", section: "Drying", inputType: .integer, isEssential: false, defaultVisible: true),
        .init(id: "drying_time", label: "Drying Time (min)", section: "Drying", inputType: .integer, isEssential: false, defaultVisible: true),
        .init(id: "gtin", label: "GTIN", section: "Identification", inputType: .text, isEssential: false, defaultVisible: true),
        .init(id: "country", label: "Country (ISO-2)", section: "Identification", inputType: .text, isEssential: false, defaultVisible: true),
        .init(id: "manufactured_date", label: "Manufactured", section: "Identification", inputType: .date, isEssential: false, defaultVisible: true),
        .init(id: "url", label: "URL Record", section: "NFC Tag Options", inputType: .text, isEssential: false, defaultVisible: true)
    ]

    static let anycubic: [NFCFieldDefinition] = [
        .init(id: "material", label: "Material", section: "Filament", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "name", label: "SKU/Name", section: "Filament", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "brand", label: "Brand", section: "Filament", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "color_hex", label: "Color", section: "Filament", inputType: .hexColor, isEssential: true, defaultVisible: true),
        .init(id: "temp_range", label: "Temperatures", section: "Printing", inputType: .temperatureRange, isEssential: true, defaultVisible: true),
        // Pages 30 and 31 of a factory tag carry diameter and net weight, so the
        // form has to be able to state them rather than always writing defaults.
        .init(id: "diameter", label: "Diameter (mm)", section: "Filament", inputType: .decimal, isEssential: false, defaultVisible: true),
        .init(id: "nominal_weight", label: "Net Weight (g)", section: "Weight", inputType: .integer, isEssential: false, defaultVisible: true)
    ]

    /// What the ELEGOO block holds. Material is a Canvas filament picked from
    /// `ElegooCanvasCatalog`; there is no brand, name or bed range on the tag,
    /// so the form offers none. Diameter and net weight are on it, so they are
    /// always shown; left blank they write the app defaults (1.75 mm, 1000 g),
    /// as OpenTag3D's do.
    static let elegoo: [NFCFieldDefinition] = [
        .init(id: "material", label: "Canvas Filament", section: "Filament", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "color_hex", label: "Color", section: "Filament", inputType: .hexColor, isEssential: true, defaultVisible: true),
        .init(id: "temp_range", label: "Temperatures", section: "Printing", inputType: .temperatureRange, isEssential: true, defaultVisible: true),
        .init(id: "diameter", label: "Diameter (mm)", section: "Filament", inputType: .decimal, isEssential: true, defaultVisible: true),
        .init(id: "nominal_weight", label: "Net Weight (g)", section: "Weight", inputType: .integer, isEssential: true, defaultVisible: true)
    ]

    /// TigerTag's material and brand are registry IDs, resolved live in the
    /// write form; diameter writes the nearest of 1.75/2.85 (the registry's
    /// only values), and net weight rides the required Measure field.
    static let tigerTag: [NFCFieldDefinition] = [
        .init(id: "material", label: "Material", section: "Filament", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "brand", label: "Brand", section: "Filament", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "color_hex", label: "Color", section: "Filament", inputType: .hexColor, isEssential: true, defaultVisible: true),
        .init(id: "temp_range", label: "Temperatures", section: "Printing", inputType: .temperatureRange, isEssential: true, defaultVisible: true),
        .init(id: "name", label: "Message", section: "Filament", inputType: .text, isEssential: false, defaultVisible: true),
        .init(id: "subtype", label: "Aspects", section: "Filament", inputType: .text, isEssential: false, defaultVisible: true),
        .init(id: "diameter", label: "Diameter (mm)", section: "Filament", inputType: .decimal, isEssential: false, defaultVisible: true),
        .init(id: "nominal_weight", label: "Net Weight (g)", section: "Weight", inputType: .integer, isEssential: false, defaultVisible: true)
    ]
}
