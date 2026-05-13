import Foundation

enum SpoolmanPatchValue<T> {
    case ignore
    case set(T)
    case setNil
}

enum SpoolmanPayloadBuilder {
    static func vendorPayload(
        name: String?,
        comment: String?,
        emptySpoolWeight: Double?,
        externalId: String?,
        extra: [String: String]?
    ) -> [String: Any] {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let comment { body["comment"] = comment }
        if let emptySpoolWeight { body["empty_spool_weight"] = emptySpoolWeight }
        if let externalId { body["external_id"] = externalId }
        if let extra { body["extra"] = extra }
        return body
    }

    static func filamentPayload(
        name: String?,
        vendorId: Int?,
        material: String?,
        price: Double?,
        density: Double?,
        diameter: Double?,
        weight: Double?,
        spoolWeight: Double?,
        articleNumber: String?,
        comment: String?,
        extruderTemp: Int?,
        bedTemp: Int?,
        colorHex: String?,
        multiColorHexes: String?,
        multiColorDirection: String?,
        externalId: String?,
        extra: [String: String]?
    ) -> [String: Any] {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let vendorId { body["vendor_id"] = vendorId }
        if let material { body["material"] = material }
        if let price { body["price"] = price }
        if let density { body["density"] = density }
        if let diameter { body["diameter"] = diameter }
        if let weight { body["weight"] = weight }
        if let spoolWeight { body["spool_weight"] = spoolWeight }
        if let articleNumber { body["article_number"] = articleNumber }
        if let comment { body["comment"] = comment }
        if let extruderTemp { body["settings_extruder_temp"] = extruderTemp }
        if let bedTemp { body["settings_bed_temp"] = bedTemp }
        if let colorHex { body["color_hex"] = colorHex }
        if let multiColorHexes { body["multi_color_hexes"] = multiColorHexes }
        if let multiColorDirection { body["multi_color_direction"] = multiColorDirection }
        if let externalId { body["external_id"] = externalId }
        if let extra { body["extra"] = extra }
        return body
    }

    static func spoolPayload(
        filamentId: Int?,
        firstUsed: String?,
        lastUsed: String?,
        price: Double?,
        initialWeight: Double?,
        spoolWeight: Double?,
        remainingWeight: Double?,
        usedWeight: Double?,
        location: SpoolmanPatchValue<String>,
        lotNr: String?,
        comment: String?,
        archived: Bool?,
        extra: [String: String]?
    ) -> [String: Any] {
        var body: [String: Any] = [:]
        if let filamentId { body["filament_id"] = filamentId }
        if let firstUsed { body["first_used"] = firstUsed }
        if let lastUsed { body["last_used"] = lastUsed }
        if let price { body["price"] = price }
        if let initialWeight { body["initial_weight"] = initialWeight }
        if let spoolWeight { body["spool_weight"] = spoolWeight }
        if let remainingWeight { body["remaining_weight"] = remainingWeight }
        if let usedWeight { body["used_weight"] = usedWeight }

        switch location {
        case .ignore:
            break
        case .set(let value):
            body["location"] = value
        case .setNil:
            body["location"] = NSNull()
        }

        if let lotNr { body["lot_nr"] = lotNr }
        if let comment { body["comment"] = comment }
        if let archived { body["archived"] = archived }
        if let extra { body["extra"] = extra }
        return body
    }
}
