//
//  FilaManDTODecodingTests.swift
//  SpoolKidTests
//

import Testing
import Foundation
@testable import SpoolKid

struct FilaManDTODecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func decodesSpoolWithCustomFieldsAndRFID() throws {
        let json = """
        {"id":40,"filament_id":177,"status_id":1,"lot_number":null,
         "rfid_uid":"04A1B2C3D4E5F6","external_id":null,"location_id":null,
         "purchase_date":null,"purchase_price":null,"stocked_in_at":null,
         "last_used_at":null,"initial_total_weight_g":1000.0,
         "empty_spool_weight_g":0.0,"remaining_weight_g":1000.0,
         "spool_outer_diameter_mm":null,"spool_width_mm":null,
         "spool_material":null,"low_weight_threshold_g":50,
         "created_at":"2026-08-18T00:14:00","custom_fields":{"card_uids":"AABBCCDD,11223344"}}
        """

        let spool = try decode(FilaManSpool.self, json)

        #expect(spool.id == 40)
        #expect(spool.filamentId == 177)
        #expect(spool.statusId == 1)
        #expect(spool.rfidUid == "04A1B2C3D4E5F6")
        #expect(spool.initialTotalWeightG == 1000.0)
        #expect(spool.remainingWeightG == 1000.0)
        #expect(spool.customFields?["card_uids"] == "AABBCCDD,11223344")
    }

    @Test func decodesSpoolWithNullCustomFields() throws {
        let json = """
        {"id":1,"filament_id":2,"status_id":6,"lot_number":"L1","rfid_uid":null,
         "external_id":null,"location_id":3,"purchase_date":null,
         "purchase_price":12.5,"stocked_in_at":null,"last_used_at":null,
         "initial_total_weight_g":1000.0,"empty_spool_weight_g":250.0,
         "remaining_weight_g":400.0,"spool_outer_diameter_mm":null,
         "spool_width_mm":null,"spool_material":null,"low_weight_threshold_g":50,
         "created_at":"2026-08-18T00:14:00","custom_fields":null}
        """

        let spool = try decode(FilaManSpool.self, json)

        #expect(spool.customFields == nil)
        #expect(spool.rfidUid == nil)
        #expect(spool.locationId == 3)
        #expect(spool.statusId == 6)
    }

    @Test func decodesFilamentWithPositionalColours() throws {
        let json = """
        {"id":177,"manufacturer_id":5,"designation":"White","material_type":"PLA",
         "material_subgroup":"Basic","diameter_mm":1.75,
         "manufacturer_color_name":null,"finish_type":null,
         "raw_material_weight_g":1000.0,"default_spool_weight_g":250.0,
         "spool_outer_diameter_mm":null,"spool_width_mm":null,"spool_material":null,
         "price":19.99,"shop_url":null,"density_g_cm3":1.24,"color_mode":"single",
         "multi_color_style":null,"custom_fields":null,
         "colors":[{"id":177,"color_id":33,"position":1,"display_name_override":null,
                    "color":{"id":33,"name":"#3F3F3F","hex_code":"#3f3f3f",
                             "custom_fields":null,"usage_count":0}}]}
        """

        let filament = try decode(FilaManFilament.self, json)

        #expect(filament.designation == "White")
        #expect(filament.materialType == "PLA")
        #expect(filament.materialSubgroup == "Basic")
        #expect(filament.densityG_cm3 == 1.24)
        #expect(filament.colors?.count == 1)
        #expect(filament.colors?.first?.position == 1)
        #expect(filament.colors?.first?.color.hexCode == "#3f3f3f")
    }

    @Test func decodesManufacturerIgnoringComputedCounts() throws {
        let json = """
        {"id":5,"name":"Prusament","url":"https://prusa3d.com","logo_file":null,
         "label_logo_file":null,"empty_spool_weight_g":201.0,
         "spool_outer_diameter_mm":null,"spool_width_mm":null,"spool_material":null,
         "custom_fields":null,"filament_count":12,"spool_count":30,
         "archived_spool_count":2,"total_price_available":0,"total_price_all":0,
         "materials":[],"logo_url":null,"label_logo_url":null}
        """

        let vendor = try decode(FilaManManufacturer.self, json)

        #expect(vendor.id == 5)
        #expect(vendor.name == "Prusament")
        #expect(vendor.url == "https://prusa3d.com")
    }

    @Test func decodesLocation() throws {
        let json = """
        {"id":3,"name":"Shelf A","identifier":null,"custom_fields":null,"spool_count":4}
        """

        let location = try decode(FilaManLocation.self, json)

        #expect(location.id == 3)
        #expect(location.name == "Shelf A")
    }

    // MARK: - Locations

    /// `locations.identifier` is FilaMan's own NFC tag field — the "Identifier"
    /// column in its Locations list, filled by its "Write RFID Tag" action.
    @Test func aLocationCarriesItsTagIdentifier() throws {
        let json = Data("""
        {"id":3,"name":"Shelf A","identifier":"04:f5:02:3a","custom_fields":null,"spool_count":2}
        """.utf8)

        let location = try JSONDecoder().decode(FilaManLocation.self, from: json)

        #expect(location.id == 3)
        #expect(location.name == "Shelf A")
        #expect(location.identifier == "04:f5:02:3a")
    }

    /// An untagged location, and an older FilaMan that predates the column,
    /// both have to decode — the field is nullable server-side and the list
    /// endpoint is on the critical path for every FilaMan fetch.
    @Test func aLocationWithoutOneStillDecodes() throws {
        #expect(try JSONDecoder().decode(
            FilaManLocation.self,
            from: Data(#"{"id":4,"name":"Bin 2","identifier":null}"#.utf8)
        ).identifier == nil)

        #expect(try JSONDecoder().decode(
            FilaManLocation.self,
            from: Data(#"{"id":5,"name":"Bin 3"}"#.utf8)
        ).identifier == nil)
    }
}
