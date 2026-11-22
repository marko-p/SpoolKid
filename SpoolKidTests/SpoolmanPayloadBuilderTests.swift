import Foundation
import Testing
@testable import SpoolKid

struct SpoolmanPayloadBuilderTests {
    @Test func vendorPayloadOmitsNilValues() {
        let draft = VendorDraft(name: "Polymaker")
        let payload = SpoolmanPayloadBuilder.vendorPayload(from: draft)

        #expect(payload["name"] as? String == "Polymaker")
        #expect(payload["comment"] == nil)
        #expect(payload["empty_spool_weight"] == nil)
        #expect(payload["external_id"] == nil)
        #expect(payload["extra"] == nil)
    }

    @Test func filamentPayloadIncludesMultiColorDirection() {
        let payload = SpoolmanPayloadBuilder.filamentPayload(
            name: "Tri-Color",
            vendorId: .set(2),
            material: "PLA",
            price: .set(19.99),
            density: 1.24,
            diameter: 1.75,
            weight: .set(1000),
            spoolWeight: .set(140),
            articleNumber: .set("TRI-1"),
            comment: .set("test"),
            extruderTemp: .set(210),
            bedTemp: .set(60),
            colorHex: nil,
            multiColorHexes: .set("FF0000,00FF00"),
            multiColorDirection: .set("coaxial"),
            externalId: .set("tri"),
            extra: .ignore
        )

        #expect(payload["multi_color_direction"] as? String == "coaxial")
    }

    @Test func spoolPayloadSupportsLocationClearWithNullPatch() {
        let payload = SpoolmanPayloadBuilder.spoolPayload(
            filamentId: 5,
            firstUsed: .ignore,
            lastUsed: .ignore,
            price: nil,
            initialWeight: .set(1000),
            spoolWeight: .set(140),
            remainingWeight: .set(800),
            usedWeight: .ignore,
            location: .setNil,
            lotNr: .ignore,
            comment: .ignore,
            archived: nil,
            extra: .ignore
        )

        #expect(payload["location"] is NSNull)
    }

    @Test func spoolPayloadOmitsLocationWhenPatchIgnoresField() {
        let payload = SpoolmanPayloadBuilder.spoolPayload(
            filamentId: 5,
            firstUsed: .ignore,
            lastUsed: .ignore,
            price: nil,
            initialWeight: .set(1000),
            spoolWeight: .set(140),
            remainingWeight: .set(800),
            usedWeight: .ignore,
            location: .ignore,
            lotNr: .ignore,
            comment: .ignore,
            archived: nil,
            extra: .ignore
        )

        #expect(payload["location"] == nil)
    }

    @Test func spoolPayloadSetsLocationWhenPatchProvidesValue() {
        let payload = SpoolmanPayloadBuilder.spoolPayload(
            filamentId: 5,
            firstUsed: .ignore,
            lastUsed: .ignore,
            price: nil,
            initialWeight: .set(1000),
            spoolWeight: .set(140),
            remainingWeight: .set(800),
            usedWeight: .ignore,
            location: .set("Shelf A"),
            lotNr: .ignore,
            comment: .ignore,
            archived: nil,
            extra: .ignore
        )

        #expect(payload["location"] as? String == "Shelf A")
    }

    @Test func spoolDraftPayloadMatchesParameterPayload() {
        let draft = SpoolDraft(
            filamentId: 5,
            firstUsed: .set("2026-01-01T00:00:00Z"),
            lastUsed: .set("2026-06-01T00:00:00Z"),
            price: 29.99,
            initialWeight: .set(1000),
            spoolWeight: .set(140),
            remainingWeight: .set(800),
            usedWeight: .ignore,
            location: .set("Shelf A"),
            lotNr: .set("card_uid:abc"),
            comment: .set("test comment"),
            archived: false,
            extra: .set(["key": "value"])
        )

        let fromDraft = SpoolmanPayloadBuilder.spoolPayload(from: draft)
        let fromParams = SpoolmanPayloadBuilder.spoolPayload(
            filamentId: draft.filamentId,
            firstUsed: draft.firstUsed,
            lastUsed: draft.lastUsed,
            price: draft.price,
            initialWeight: draft.initialWeight,
            spoolWeight: draft.spoolWeight,
            remainingWeight: draft.remainingWeight,
            usedWeight: draft.usedWeight,
            location: draft.location,
            lotNr: draft.lotNr,
            comment: draft.comment,
            archived: draft.archived,
            extra: draft.extra
        )

        #expect(fromDraft.count == fromParams.count)
        for key in fromParams.keys {
            let dv = fromDraft[key]
            let pv = fromParams[key]
            if let ds = dv as? String, let ps = pv as? String {
                #expect(ds == ps)
            } else if let dd = dv as? Double, let pd = pv as? Double {
                #expect(dd == pd)
            } else if let db = dv as? Bool, let pb = pv as? Bool {
                #expect(db == pb)
            } else if let di = dv as? Int, let pi = pv as? Int {
                #expect(di == pi)
            } else if let de = dv as? [String: String], let pe = pv as? [String: String] {
                #expect(de == pe)
            } else {
                #expect(dv == nil && pv == nil)
            }
        }
    }

    /// The same three states the weights and the location carry, now on the two
    /// text fields that used to travel in `clearFieldKeys` (R21).
    @Test func spoolDraftPayloadClearsTextFieldsWithAnExplicitNull() {
        var draft = SpoolDraft(filamentId: 3)
        draft.lotNr = .setNil
        draft.comment = .setNil

        let payload = SpoolmanPayloadBuilder.spoolPayload(from: draft)

        #expect(payload["lot_nr"] is NSNull)
        #expect(payload["comment"] is NSNull)
    }

    // MARK: - Probed live 2026-08-27: what Spoolman refuses
    //
    // Both of these were sent for real and both failed the ENTIRE write —
    // neither was findable by reading SpoolKid's code, because both sides
    // looked correct.

    /// `PATCH {"extra": null}` answers **500** on spools and filaments alike,
    /// even when `extra` is already empty. `{}` is not a fallback: it returns
    /// 200 and changes nothing, so there is no request that empties `extra`.
    @Test func clearingExtraSendsNothingBecauseSpoolmanCannotDoIt() {
        var spool = SpoolDraft(filamentId: 3)
        spool.extra = .setNil
        var filament = FilamentDraft()
        filament.extra = .setNil

        #expect(SpoolmanPayloadBuilder.spoolPayload(from: spool)["extra"] == nil)
        #expect(SpoolmanPayloadBuilder.filamentPayload(from: filament)["extra"] == nil)
    }

    /// The multi-colour keys are validated as a PAIR: either alone is a 422
    /// that fails the whole write. Same shape as F31's weight pair on FilaMan.
    @Test func aStatedMultiColourValueTravelsOnlyWithItsPartner() {
        typealias P = SpoolmanPatchValue<String>
        func keys(_ h: P, _ d: P) -> [String: Any] {
            SpoolmanPayloadBuilder.multiColorKeys(hexes: h, direction: d)
        }

        // The only way to state a multi-colour: the pair, plus `color_hex` cleared.
        #expect(keys(.set("FF0000,00FF00"), .set("coaxial")).count == 3)

        // Half a pair is refused rather than sent.
        #expect(keys(.set("FF0000,00FF00"), .ignore).isEmpty)
        #expect(keys(.set("FF0000,00FF00"), .setNil).isEmpty)
        #expect(keys(.ignore, .set("coaxial")).isEmpty)
        #expect(keys(.setNil, .set("coaxial")).isEmpty)

        // Nulls are lenient (measured): whatever is left is still consistent.
        #expect(keys(.setNil, .ignore)["multi_color_hexes"] is NSNull)
        #expect(keys(.ignore, .setNil)["multi_color_direction"] is NSNull)
        #expect(keys(.setNil, .setNil).count == 2)

        #expect(keys(.ignore, .ignore).isEmpty)
    }

    /// Spoolman keeps a stated `color_hex` alongside the list (probed
    /// 2026-10-28), so a multi write must null it explicitly. A clear-both
    /// has no colour to null and must not mention it.
    @Test func multiPairNullsColorHex() {
        let set = SpoolmanPayloadBuilder.multiColorKeys(
            hexes: .set("2D39C9,A51A52"), direction: .set("coaxial")
        )
        #expect(set["color_hex"] is NSNull)

        let cleared = SpoolmanPayloadBuilder.multiColorKeys(hexes: .setNil, direction: .setNil)
        #expect(cleared["color_hex"] == nil)
    }

    /// A refused half-pair must not vanish: the filament still saves, and the
    /// user is told which half did not.
    @Test func aRefusedMultiColourHalfIsReported() {
        #expect(
            SpoolmanPayloadBuilder.droppedMultiColorNote(
                hexes: .set("FF0000,00FF00"), direction: .ignore
            )?.contains("direction") == true
        )
        #expect(
            SpoolmanPayloadBuilder.droppedMultiColorNote(
                hexes: .ignore, direction: .set("coaxial")
            )?.contains("colours") == true
        )
        #expect(
            SpoolmanPayloadBuilder.droppedMultiColorNote(
                hexes: .set("FF0000,00FF00"), direction: .set("coaxial")
            ) == nil
        )
        #expect(SpoolmanPayloadBuilder.droppedMultiColorNote(hexes: .ignore, direction: .ignore) == nil)
    }

    @Test func spoolDraftPayloadOmitsNilFields() {
        let draft = SpoolDraft(filamentId: 3)
        let payload = SpoolmanPayloadBuilder.spoolPayload(from: draft)

        #expect(payload["filament_id"] as? Int == 3)
        #expect(payload["price"] == nil)
        #expect(payload["initial_weight"] == nil)
        #expect(payload["spool_weight"] == nil)
        #expect(payload["remaining_weight"] == nil)
        #expect(payload["used_weight"] == nil)
        #expect(payload["location"] == nil)
        #expect(payload["lot_nr"] == nil)
        #expect(payload["comment"] == nil)
        #expect(payload["archived"] == nil)
        #expect(payload["extra"] == nil)
    }

    @Test func filamentDraftPayloadMatchesParameterPayload() {
        let draft = FilamentDraft(
            name: "PLA Black",
            vendorId: .set(2),
            material: "PLA",
            price: .set(19.99),
            density: 1.24,
            diameter: 1.75,
            weight: .set(1000),
            spoolWeight: .set(140),
            articleNumber: .set("PM70820"),
            comment: .set("test comment"),
            extruderTemp: .set(210),
            bedTemp: .set(60),
            colorHex: "111111",
            multiColorHexes: .set("FF0000,00FF00"),
            multiColorDirection: .set("coaxial"),
            externalId: .set("poly_pla_black"),
            extra: .set(["key": "value"])
        )

        let fromDraft = SpoolmanPayloadBuilder.filamentPayload(from: draft)
        let fromParams = SpoolmanPayloadBuilder.filamentPayload(
            name: draft.name,
            vendorId: draft.vendorId,
            material: draft.material,
            price: draft.price,
            density: draft.density,
            diameter: draft.diameter,
            weight: draft.weight,
            spoolWeight: draft.spoolWeight,
            articleNumber: draft.articleNumber,
            comment: draft.comment,
            extruderTemp: draft.extruderTemp,
            bedTemp: draft.bedTemp,
            colorHex: draft.colorHex,
            multiColorHexes: draft.multiColorHexes,
            multiColorDirection: draft.multiColorDirection,
            externalId: draft.externalId,
            extra: draft.extra
        )

        #expect(fromDraft.count == fromParams.count)
        for key in fromParams.keys {
            let dv = fromDraft[key]
            let pv = fromParams[key]
            if let ds = dv as? String, let ps = pv as? String {
                #expect(ds == ps)
            } else if let dd = dv as? Double, let pd = pv as? Double {
                #expect(dd == pd)
            } else if let db = dv as? Bool, let pb = pv as? Bool {
                #expect(db == pb)
            } else if let di = dv as? Int, let pi = pv as? Int {
                #expect(di == pi)
            } else if let de = dv as? [String: String], let pe = pv as? [String: String] {
                #expect(de == pe)
            } else if dv is NSNull, pv is NSNull {
                // Both paths null `color_hex` alongside a multi pair: parity holds.
                #expect(key == "color_hex")
            } else {
                #expect(dv == nil && pv == nil)
            }
        }
    }

    /// The catalogue write-back (Task 4) changes the filament's spool weight and
    /// nothing else.
    @Test func spoolWeightOnlyUpdate() {
        let payload = SpoolmanPayloadBuilder.filamentPayload(from: FilamentDraft(spoolWeight: .set(193)))

        #expect(Set(payload.keys) == ["spool_weight"])
        #expect(payload["spool_weight"] as? Double == 193)
    }

    @Test func filamentDraftPayloadOmitsNilFields() {
        let draft = FilamentDraft(name: "PLA Black")
        let payload = SpoolmanPayloadBuilder.filamentPayload(from: draft)

        #expect(payload["name"] as? String == "PLA Black")
        #expect(payload["vendor_id"] == nil)
        #expect(payload["material"] == nil)
        #expect(payload["price"] == nil)
        #expect(payload["density"] == nil)
        #expect(payload["diameter"] == nil)
        #expect(payload["weight"] == nil)
        #expect(payload["spool_weight"] == nil)
        #expect(payload["article_number"] == nil)
        #expect(payload["comment"] == nil)
        #expect(payload["settings_extruder_temp"] == nil)
        #expect(payload["settings_bed_temp"] == nil)
        #expect(payload["color_hex"] == nil)
        #expect(payload["multi_color_hexes"] == nil)
        #expect(payload["multi_color_direction"] == nil)
        #expect(payload["external_id"] == nil)
        #expect(payload["extra"] == nil)
    }

    // MARK: - TD (registered `td` extra field)

    @Test func floatFieldWritesBareTD() {
        let result = SpoolmanPayloadBuilder.extraApplyingTransmissionDistance(
            .set(3.5), to: ["variant": "\"Silk\""], fieldType: "float"
        )
        #expect(result == .extra(["variant": "\"Silk\"", "td": "3.5"]))
    }

    @Test func textFieldWritesWrappedTD() {
        let result = SpoolmanPayloadBuilder.extraApplyingTransmissionDistance(.set(3.5), to: [:], fieldType: "text")
        #expect(result == .extra(["td": "\"3.5\""]))
    }

    @Test func integerFieldRefusesTD() {
        let result = SpoolmanPayloadBuilder.extraApplyingTransmissionDistance(.set(3.5), to: [:], fieldType: "integer")
        guard case .refused(let note) = result else { Issue.record("expected a refusal, got \(result)"); return }
        #expect(note.contains("integer"))
    }

    @Test func clearingTDKeepsOtherKeys() {
        let result = SpoolmanPayloadBuilder.extraApplyingTransmissionDistance(
            .setNil, to: ["td": "3.5", "variant": "\"Silk\""], fieldType: "float"
        )
        #expect(result == .extra(["variant": "\"Silk\""]))
    }

    /// Probed 2026-11-02: `{}` is a no-op, `"null"` and `""` are 400s — the
    /// last extra key cannot be removed.
    @Test func clearingSoleTDIsRefused() {
        let result = SpoolmanPayloadBuilder.extraApplyingTransmissionDistance(.setNil, to: ["td": "3.5"], fieldType: "float")
        guard case .refused = result else { Issue.record("expected a refusal, got \(result)"); return }
    }

    @Test func ignoredTDLeavesExtraAlone() {
        #expect(SpoolmanPayloadBuilder.extraApplyingTransmissionDistance(.ignore, to: ["td": "x"], fieldType: "float") == .unchanged)
    }
}
