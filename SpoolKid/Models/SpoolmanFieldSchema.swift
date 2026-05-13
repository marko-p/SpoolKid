import Foundation

enum SpoolmanEntity: String, CaseIterable, Sendable {
    case spool
    case filament
    case vendor
    case location
}

enum SpoolmanFieldInputType: Sendable, Hashable {
    case text
    case multilineText
    case integer
    case decimal
    case toggle
    case date
    case picker
}

struct SpoolmanFieldDefinition: Sendable, Hashable, Identifiable {
    let id: String
    let apiKey: String?
    let label: String
    let section: String
    let inputType: SpoolmanFieldInputType
    let isEssential: Bool
    let defaultVisible: Bool
    let isRisky: Bool

    init(
        id: String,
        apiKey: String?,
        label: String,
        section: String,
        inputType: SpoolmanFieldInputType,
        isEssential: Bool,
        defaultVisible: Bool,
        isRisky: Bool = false
    ) {
        self.id = id
        self.apiKey = apiKey
        self.label = label
        self.section = section
        self.inputType = inputType
        self.isEssential = isEssential
        self.defaultVisible = isEssential ? true : defaultVisible
        self.isRisky = isRisky
    }
}

enum SpoolmanFieldCatalog {
    static func fields(for entity: SpoolmanEntity) -> [SpoolmanFieldDefinition] {
        switch entity {
        case .spool: spoolFields
        case .filament: filamentFields
        case .vendor: vendorFields
        case .location: locationFields
        }
    }

    static let vendorFields: [SpoolmanFieldDefinition] = [
        .init(id: "name", apiKey: "name", label: "Name", section: "Vendor", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "comment", apiKey: "comment", label: "Comment", section: "Vendor", inputType: .multilineText, isEssential: false, defaultVisible: false),
        .init(id: "empty_spool_weight", apiKey: "empty_spool_weight", label: "Default Empty Spool Weight", section: "Vendor", inputType: .decimal, isEssential: false, defaultVisible: false),
        .init(id: "external_id", apiKey: "external_id", label: "External ID", section: "Vendor", inputType: .text, isEssential: false, defaultVisible: false),
        .init(id: "extra", apiKey: "extra", label: "Extra JSON", section: "Vendor", inputType: .multilineText, isEssential: false, defaultVisible: false, isRisky: true)
    ]

    static let filamentFields: [SpoolmanFieldDefinition] = [
        .init(id: "name", apiKey: "name", label: "Name", section: "Basic", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "vendor_id", apiKey: "vendor_id", label: "Vendor", section: "Basic", inputType: .picker, isEssential: true, defaultVisible: true),
        .init(id: "material", apiKey: "material", label: "Material", section: "Basic", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "color_hex", apiKey: "color_hex", label: "Color", section: "Color", inputType: .text, isEssential: true, defaultVisible: true),
        .init(id: "density", apiKey: "density", label: "Density", section: "Physical", inputType: .decimal, isEssential: true, defaultVisible: true),
        .init(id: "diameter", apiKey: "diameter", label: "Diameter", section: "Physical", inputType: .decimal, isEssential: true, defaultVisible: true),
        .init(id: "settings_extruder_temp", apiKey: "settings_extruder_temp", label: "Extruder Temp", section: "Temperatures", inputType: .integer, isEssential: true, defaultVisible: true),
        .init(id: "settings_bed_temp", apiKey: "settings_bed_temp", label: "Bed Temp", section: "Temperatures", inputType: .integer, isEssential: true, defaultVisible: true),
        .init(id: "price", apiKey: "price", label: "Price", section: "Advanced", inputType: .decimal, isEssential: false, defaultVisible: false),
        .init(id: "weight", apiKey: "weight", label: "Net Weight", section: "Advanced", inputType: .decimal, isEssential: false, defaultVisible: false),
        .init(id: "spool_weight", apiKey: "spool_weight", label: "Default Spool Weight", section: "Advanced", inputType: .decimal, isEssential: false, defaultVisible: false),
        .init(id: "article_number", apiKey: "article_number", label: "Article Number", section: "Advanced", inputType: .text, isEssential: false, defaultVisible: false),
        .init(id: "comment", apiKey: "comment", label: "Comment", section: "Advanced", inputType: .multilineText, isEssential: false, defaultVisible: false),
        .init(id: "multi_color_hexes", apiKey: "multi_color_hexes", label: "Multi-Color Hexes", section: "Advanced", inputType: .text, isEssential: false, defaultVisible: false),
        .init(id: "multi_color_direction", apiKey: "multi_color_direction", label: "Multi-Color Direction", section: "Advanced", inputType: .picker, isEssential: false, defaultVisible: false),
        .init(id: "external_id", apiKey: "external_id", label: "External ID", section: "Advanced", inputType: .text, isEssential: false, defaultVisible: false),
        .init(id: "extra", apiKey: "extra", label: "Extra JSON", section: "Advanced", inputType: .multilineText, isEssential: false, defaultVisible: false, isRisky: true)
    ]

    static let spoolFields: [SpoolmanFieldDefinition] = [
        .init(id: "filament_id", apiKey: "filament_id", label: "Filament", section: "Basic", inputType: .picker, isEssential: true, defaultVisible: true),
        .init(id: "initial_weight", apiKey: "initial_weight", label: "Initial Weight", section: "Weights", inputType: .decimal, isEssential: true, defaultVisible: true),
        .init(id: "spool_weight", apiKey: "spool_weight", label: "Empty Spool Weight", section: "Weights", inputType: .decimal, isEssential: true, defaultVisible: true),
        .init(id: "remaining_weight", apiKey: "remaining_weight", label: "Remaining Weight", section: "Weights", inputType: .decimal, isEssential: false, defaultVisible: true),
        .init(id: "used_weight", apiKey: "used_weight", label: "Used Weight", section: "Weights", inputType: .decimal, isEssential: false, defaultVisible: false),
        .init(id: "price", apiKey: "price", label: "Price", section: "Basic", inputType: .decimal, isEssential: false, defaultVisible: true),
        .init(id: "location", apiKey: "location", label: "Location", section: "Inventory", inputType: .picker, isEssential: false, defaultVisible: true),
        .init(id: "lot_nr", apiKey: "lot_nr", label: "Lot/Batch", section: "Inventory", inputType: .text, isEssential: false, defaultVisible: true),
        .init(id: "comment", apiKey: "comment", label: "Comment", section: "Inventory", inputType: .multilineText, isEssential: false, defaultVisible: false),
        .init(id: "archived", apiKey: "archived", label: "Archived", section: "Inventory", inputType: .toggle, isEssential: false, defaultVisible: false),
        .init(id: "first_used", apiKey: "first_used", label: "First Used", section: "Advanced", inputType: .date, isEssential: false, defaultVisible: false),
        .init(id: "last_used", apiKey: "last_used", label: "Last Used", section: "Advanced", inputType: .date, isEssential: false, defaultVisible: false),
        .init(id: "extra", apiKey: "extra", label: "Extra JSON", section: "Advanced", inputType: .multilineText, isEssential: false, defaultVisible: false, isRisky: true)
    ]

    static let locationFields: [SpoolmanFieldDefinition] = [
        .init(id: "name", apiKey: nil, label: "Name", section: "Location", inputType: .text, isEssential: true, defaultVisible: true)
    ]
}
