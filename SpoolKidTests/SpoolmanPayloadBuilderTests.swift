import Foundation
import Testing
@testable import SpoolKid

struct SpoolmanPayloadBuilderTests {
    @Test func vendorPayloadOmitsNilValues() {
        let payload = SpoolmanPayloadBuilder.vendorPayload(
            name: "Polymaker",
            comment: nil,
            emptySpoolWeight: nil,
            externalId: nil,
            extra: nil
        )

        #expect(payload["name"] as? String == "Polymaker")
        #expect(payload["comment"] == nil)
        #expect(payload["empty_spool_weight"] == nil)
        #expect(payload["external_id"] == nil)
        #expect(payload["extra"] == nil)
    }

    @Test func filamentPayloadIncludesMultiColorDirection() {
        let payload = SpoolmanPayloadBuilder.filamentPayload(
            name: "Tri-Color",
            vendorId: 2,
            material: "PLA",
            price: 19.99,
            density: 1.24,
            diameter: 1.75,
            weight: 1000,
            spoolWeight: 140,
            articleNumber: "TRI-1",
            comment: "test",
            extruderTemp: 210,
            bedTemp: 60,
            colorHex: nil,
            multiColorHexes: "FF0000,00FF00",
            multiColorDirection: "coaxial",
            externalId: "tri",
            extra: nil
        )

        #expect(payload["multi_color_direction"] as? String == "coaxial")
    }

    @Test func spoolPayloadSupportsLocationClearWithNullPatch() {
        let payload = SpoolmanPayloadBuilder.spoolPayload(
            filamentId: 5,
            firstUsed: nil,
            lastUsed: nil,
            price: nil,
            initialWeight: 1000,
            spoolWeight: 140,
            remainingWeight: 800,
            usedWeight: nil,
            location: .setNil,
            lotNr: nil,
            comment: nil,
            archived: nil,
            extra: nil
        )

        #expect(payload["location"] is NSNull)
    }

    @Test func spoolPayloadOmitsLocationWhenPatchIgnoresField() {
        let payload = SpoolmanPayloadBuilder.spoolPayload(
            filamentId: 5,
            firstUsed: nil,
            lastUsed: nil,
            price: nil,
            initialWeight: 1000,
            spoolWeight: 140,
            remainingWeight: 800,
            usedWeight: nil,
            location: .ignore,
            lotNr: nil,
            comment: nil,
            archived: nil,
            extra: nil
        )

        #expect(payload["location"] == nil)
    }

    @Test func spoolPayloadSetsLocationWhenPatchProvidesValue() {
        let payload = SpoolmanPayloadBuilder.spoolPayload(
            filamentId: 5,
            firstUsed: nil,
            lastUsed: nil,
            price: nil,
            initialWeight: 1000,
            spoolWeight: 140,
            remainingWeight: 800,
            usedWeight: nil,
            location: .set("Shelf A"),
            lotNr: nil,
            comment: nil,
            archived: nil,
            extra: nil
        )

        #expect(payload["location"] as? String == "Shelf A")
    }
}
