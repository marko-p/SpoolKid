import Foundation
import Testing
@testable import SpoolKid

struct SpoolmanModelsDecodingTests {
    @Test func decodesExpandedVendorFields() throws {
        let json = """
        {"id":1,"name":"Polymaker","comment":"notes","empty_spool_weight":140.0,"external_id":"poly","registered":"2026-01-01T00:00:00Z","extra":{"origin":"\\\"catalog\\\""}}
        """.data(using: .utf8)!
        let vendor = try JSONDecoder().decode(SpoolmanVendor.self, from: json)

        #expect(vendor.id == 1)
        #expect(vendor.name == "Polymaker")
        #expect(vendor.comment == "notes")
        #expect(vendor.emptySpoolWeight == 140.0)
        #expect(vendor.externalId == "poly")
        #expect(vendor.extra?["origin"] == "\"catalog\"")
    }

    @Test func decodesExpandedFilamentFields() throws {
        let json = """
        {"id":11,"name":"PLA Black","vendor":{"id":1,"name":"Polymaker"},"material":"PLA","price":19.99,"density":1.24,"diameter":1.75,"weight":1000.0,"spool_weight":140.0,"article_number":"PM70820","comment":"batch A","settings_extruder_temp":210,"settings_bed_temp":60,"color_hex":"111111","multi_color_hexes":"FF0000,00FF00","multi_color_direction":"coaxial","external_id":"poly_pla_black","extra":{"profile":"\\\"fast\\\""}}
        """.data(using: .utf8)!
        let filament = try JSONDecoder().decode(SpoolmanFilament.self, from: json)

        #expect(filament.id == 11)
        #expect(filament.name == "PLA Black")
        #expect(filament.vendor?.id == 1)
        #expect(filament.vendor?.name == "Polymaker")
        #expect(filament.material == "PLA")
        #expect(filament.price == 19.99)
        #expect(filament.density == 1.24)
        #expect(filament.diameter == 1.75)
        #expect(filament.weight == 1000.0)
        #expect(filament.spoolWeight == 140.0)
        #expect(filament.articleNumber == "PM70820")
        #expect(filament.comment == "batch A")
        #expect(filament.settingsExtruderTemp == 210)
        #expect(filament.settingsBedTemp == 60)
        #expect(filament.colorHex == "111111")
        #expect(filament.multiColorHexes == "FF0000,00FF00")
        #expect(filament.multiColorDirection == "coaxial")
        #expect(filament.externalId == "poly_pla_black")
        #expect(filament.extra?["profile"] == "\"fast\"")
    }

    @Test func decodesExpandedSpoolFields() throws {
        let json = """
        {"id":42,"filament":{"id":11,"name":"PLA Black","vendor":{"id":1,"name":"Polymaker"},"material":"PLA","density":1.24,"diameter":1.75},"first_used":"2026-01-02T00:00:00Z","last_used":"2026-01-03T00:00:00Z","price":22.5,"initial_weight":1000.0,"spool_weight":140.0,"used_weight":120.0,"remaining_weight":880.0,"location":"Shelf A","lot_nr":"52342","comment":"printer-ready","archived":false,"extra":{"slot":"\\\"A3\\\""}}
        """.data(using: .utf8)!
        let spool = try JSONDecoder().decode(SpoolmanSpool.self, from: json)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        #expect(spool.id == 42)
        #expect(spool.filament.id == 11)
        #expect(spool.filament.name == "PLA Black")
        #expect(spool.filament.vendor?.id == 1)
        #expect(spool.filament.vendor?.name == "Polymaker")
        #expect(spool.filament.material == "PLA")
        #expect(spool.filament.density == 1.24)
        #expect(spool.filament.diameter == 1.75)
        #expect(spool.firstUsed == formatter.date(from: "2026-01-02T00:00:00Z"))
        #expect(spool.lastUsed == formatter.date(from: "2026-01-03T00:00:00Z"))
        #expect(spool.price == 22.5)
        #expect(spool.initialWeight == 1000.0)
        #expect(spool.spoolWeight == 140.0)
        #expect(spool.usedWeight == 120.0)
        #expect(spool.remainingWeight == 880.0)
        #expect(spool.location == "Shelf A")
        #expect(spool.lotNr == "52342")
        #expect(spool.comment == "printer-ready")
        #expect(spool.archived == false)
        #expect(spool.extra?["slot"] == "\"A3\"")
    }

    @Test func decodesSpoolDateFromUnixTimestamp() throws {
        let json = """
        {"id":42,"filament":{"id":11},"first_used":1735776000}
        """.data(using: .utf8)!

        let spool = try JSONDecoder().decode(SpoolmanSpool.self, from: json)

        #expect(spool.firstUsed == Date(timeIntervalSince1970: 1735776000))
    }

    @Test func decodesSpoolDateFromFractionalSecondsISO8601() throws {
        let json = """
        {"id":42,"filament":{"id":11},"first_used":"2026-01-02T12:34:56.789Z"}
        """.data(using: .utf8)!

        let spool = try JSONDecoder().decode(SpoolmanSpool.self, from: json)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(spool.firstUsed == formatter.date(from: "2026-01-02T12:34:56.789Z"))
    }

    @Test func invalidSpoolDateStringThrows() throws {
        let json = """
        {"id":42,"filament":{"id":11},"first_used":"not-a-date"}
        """.data(using: .utf8)!

        do {
            _ = try JSONDecoder().decode(SpoolmanSpool.self, from: json)
            #expect(false, "Expected invalid date string to throw")
        } catch let error as DecodingError {
            if case .dataCorrupted(let context) = error {
                #expect(context.codingPath.last?.stringValue == "first_used")
            } else {
                #expect(false, "Expected dataCorrupted, got \(error)")
            }
        }
    }
}
