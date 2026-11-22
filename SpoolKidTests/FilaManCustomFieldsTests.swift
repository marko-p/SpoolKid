//
//  FilaManCustomFieldsTests.swift
//  SpoolKidTests
//
//  `custom_fields` is a FREE-FORM JSON object on FilaMan's native API. Typing
//  it as `[String: String]` threw `typeMismatch` on the first non-string value
//  — and every record migrated from Spoolman carries `{"spoolman_id": <Int>}`,
//  so on the owner's instance that was all 38 spools, all 223 filaments and
//  all 6 manufacturers: the Library loaded nothing at all and reported "The
//  data couldn't be read because it isn't in the correct format" (2026-08-23).
//
//  Round-tripping is half the contract. `custom_fields` is PATCHed as a
//  whole-object replacement, so a merge that re-encoded `spoolman_id: 43` as
//  `"43"` would rewrite the Spoolman linkage of every record it touched into a
//  different type.
//

import Testing
import Foundation
@testable import SpoolKid

struct FilaManCustomFieldsTests {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - The defect

    /// Verbatim from `GET /api/v1/spools` on the owner's instance, spool 39 —
    /// the record that carries both a legacy mapping and a `spoolman_id`.
    @Test func decodesTheLivePayloadThatUsedToFailWholesale() throws {
        let json = """
        {"id":39,"filament_id":220,"status_id":1,
         "lot_number":"card_uid:53440308300004,card_uid:534f0107300004",
         "rfid_uid":null,"external_id":"spoolman:43","location_id":null,
         "purchase_date":null,"purchase_price":null,"stocked_in_at":null,
         "last_used_at":null,"initial_total_weight_g":1000.0,
         "empty_spool_weight_g":0.0,"remaining_weight_g":1000.0,
         "spool_outer_diameter_mm":null,"spool_width_mm":null,
         "spool_material":null,"low_weight_threshold_g":100,
         "created_at":"2026-05-28T12:37:57Z","custom_fields":{"spoolman_id":43}}
        """

        let spool = try decode(FilaManSpool.self, json)

        #expect(spool.id == 39)
        #expect(spool.customFields?["spoolman_id"] == .int(43))
    }

    @Test func everyJSONScalarSurvivesCustomFields() throws {
        let json = """
        {"custom_fields":{"s":"text","i":43,"d":1.5,"b":true,"n":null}}
        """
        struct Holder: Decodable { let custom_fields: [String: FilaManJSONValue]? }

        let fields = try decode(Holder.self, json).custom_fields

        #expect(fields?["s"] == .string("text"))
        #expect(fields?["i"] == .int(43))
        #expect(fields?["d"] == .double(1.5))
        #expect(fields?["b"] == .bool(true))
        #expect(fields?["n"] == .null)
    }

    // MARK: - Round-trip

    /// An Int that comes back as `43.0` or `"43"` has been rewritten, not
    /// preserved — and the PATCH that carries it replaces the whole object.
    @Test func anIntRoundTripsAsAnInt() throws {
        let value = FilaManJSONValue.int(43)

        let encoded = try JSONEncoder().encode([ "spoolman_id": value ])
        let text = String(decoding: encoded, as: UTF8.self)

        #expect(text.contains("43"))
        #expect(!text.contains("43.0"))
        #expect(!text.contains("\"43\""))
        #expect(try JSONDecoder().decode([String: FilaManJSONValue].self, from: encoded)["spoolman_id"] == .int(43))
    }

    @Test func jsonObjectFormKeepsEachValuesType() {
        let object: [String: FilaManJSONValue] = ["i": 43, "s": "x", "b": .bool(false), "n": .null]

        let json = object.jsonObject

        #expect(json["i"] as? Int == 43)
        #expect(json["s"] as? String == "x")
        #expect(json["b"] as? Bool == false)
        #expect(json["n"] is NSNull)
    }

    // MARK: - Merge

    /// The merge is the guard against the whole-object PATCH destroying the
    /// Spoolman linkage. It has to preserve the value's TYPE too, not just its
    /// presence.
    @Test func mergePreservesAnExistingIntWhileAddingAStringKey() {
        let merged = FilaManService.mergedCustomFields(
            existing: ["spoolman_id": 43],
            new: ["card_uids": "AABBCCDD"]
        )

        #expect(merged["spoolman_id"] == .int(43))
        #expect(merged["card_uids"] == .string("AABBCCDD"))
        #expect(merged.count == 2)
    }

    @Test func mergedPayloadSerialisesWithoutRestringingTheLinkage() throws {
        let payload = FilaManPayloadBuilder.customFieldsPayload(
            FilaManService.mergedCustomFields(existing: ["spoolman_id": 43], new: ["card_uids": "AABBCCDD"])
        )

        let data = try JSONSerialization.data(withJSONObject: payload)
        let back = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let fields = back?["custom_fields"] as? [String: Any]

        #expect(fields?["spoolman_id"] as? Int == 43)
        #expect(fields?["card_uids"] as? String == "AABBCCDD")
    }

    /// The form round-trip. `extra` is loaded as `displayStrings` and handed
    /// back on save, so an untouched `spoolman_id: 43` arrives at the merge as
    /// the string "43". Taking it literally rewrote the linkage's type on every
    /// save — observed on the owner's spool 39, 2026-08-23.
    @Test func anEchoOfAnExistingValueIsNotAnEdit() {
        let existing: [String: FilaManJSONValue] = ["spoolman_id": 43, "card_uids": "AABBCCDD"]

        let merged = FilaManService.mergedCustomFields(
            existing: existing,
            new: existing.displayStrings   // exactly what a form save hands back
        )

        #expect(merged["spoolman_id"] == .int(43))
        #expect(merged["card_uids"] == .string("AABBCCDD"))
    }

    /// …but a value the user actually changed still wins, whatever the old
    /// type was. The rule is "an echo is not an edit", not "strings never
    /// overwrite".
    @Test func aRealEditStillOverwritesADifferentlyTypedValue() {
        let merged = FilaManService.mergedCustomFields(
            existing: ["spoolman_id": 43, "comment": 7],
            new: ["spoolman_id": "44", "comment": "now a real comment"]
        )

        #expect(merged["spoolman_id"] == .string("44"))
        #expect(merged["comment"] == .string("now a real comment"))
    }

    /// A key that only exists on the incoming side is always an edit.
    @Test func aNewKeyIsAlwaysWritten() {
        let merged = FilaManService.mergedCustomFields(
            existing: ["spoolman_id": 43],
            new: ["card_uids": "AABBCCDD"]
        )

        #expect(merged["card_uids"] == .string("AABBCCDD"))
        #expect(merged["spoolman_id"] == .int(43))
    }

    // MARK: - Folding the typed UID list into an `extra` patch (R21 stage 3c)

    /// A stated UID list always produces a `.set`: the mapping is what the
    /// draft definitely means to write, and `.ignore` describes the bucket it
    /// happens to live in, not the mapping.
    @Test func aStatedUIDListOverridesAnIgnoredExtra() {
        let patch = CardUIDsCodec.applyingWrapped(["AABBCCDD"], to: SpoolmanPatchValue<[String: String]>.ignore)

        #expect(patch == .set(["card_uids": CardUIDsCodec.encode(["AABBCCDD"])]))
    }

    @Test func aStatedUIDListMergesIntoASetExtra() {
        let patch = CardUIDsCodec.applyingWrapped(["AABBCCDD"], to: .set(["note": "keep"]))

        #expect(patch.valueOnCreate?["note"] == "keep")
        #expect(patch.valueOnCreate?["card_uids"] == CardUIDsCodec.encode(["AABBCCDD"]))
    }

    /// No list means the draft says nothing about the mapping, so the patch
    /// passes through untouched — `.ignore` included, which is what stops an
    /// untouched form re-asserting the whole object.
    @Test func noUIDListLeavesThePatchExactlyAsItCame() {
        #expect(CardUIDsCodec.applyingWrapped(nil, to: SpoolmanPatchValue<[String: String]>.ignore) == .ignore)
        #expect(CardUIDsCodec.applyingWrapped(nil, to: .setNil) == SpoolmanPatchValue<[String: String]>.setNil)
        #expect(CardUIDsCodec.applyingWrapped(nil, to: .set(["k": "v"])) == .set(["k": "v"]))
    }

    // MARK: - Reading

    /// `stringValue` is deliberately not a coercion: a number under `comment`
    /// is not a comment.
    @Test func stringValueOnlyAnswersForActualStrings() {
        #expect(FilaManJSONValue.string("hi").stringValue == "hi")
        #expect(FilaManJSONValue.int(43).stringValue == nil)
        #expect(FilaManJSONValue.null.stringValue == nil)
    }

    /// `displayStrings` renders scalars for the app's `[String: String]` extra
    /// maps and drops what has no flat string form.
    @Test func displayStringsRenderScalarsAndDropContainers() {
        let object: [String: FilaManJSONValue] = [
            "s": "text", "i": 43, "b": .bool(true), "n": .null, "a": .array([1, 2])
        ]

        #expect(object.displayStrings == ["s": "text", "i": "43", "b": "true"])
    }
}
