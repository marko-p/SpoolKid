//
//  FilaManPayloadBuilder.swift
//  SpoolKid
//
//  Purpose: Typed draft → FilaMan JSON-dict mapping. The ONLY place FilaMan
//  API field names appear, mirroring SpoolmanPayloadBuilder's role.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

nonisolated enum FilaManPayloadBuilder {
    // MARK: - Vendors (FilaMan calls them manufacturers)

    static func vendorPayload(from draft: VendorDraft) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let name = draft.name { payload["name"] = name }
        if let emptySpoolWeight = draft.emptySpoolWeight {
            payload["empty_spool_weight_g"] = emptySpoolWeight
        }

        // `extra` is the base layer; typed fields overwrite it on key collision.
        //
        // `comment` used to be emulated here inside free-form custom_fields.
        // Task 5 stopped rendering it on FilaMan's vendor form, so nothing can
        // ask to write it any more (2026-08-28) — `addVendor` reports a
        // migrated comment it could not store instead.
        let custom = draft.extra ?? [:]
        if !custom.isEmpty { payload["custom_fields"] = custom }

        return payload
    }

    // MARK: - Filaments

    /// Colour is NOT part of this payload. On create it is merged in by the
    /// caller from `colorsPayload` (FilaMan's `FilamentCreate` accepts the same
    /// three colour keys inline, so a create needs no second call); on update
    /// it can only be written by `PUT /filaments/{id}/colors`, because
    /// `FilamentUpdate` has no `colors` property at all. See `colorsPayload`.
    static func filamentPayload(from draft: FilamentDraft, manufacturerId: Int) -> [String: Any] {
        var payload: [String: Any] = ["manufacturer_id": manufacturerId]
        if let name = draft.name { payload["designation"] = name }
        if let material = draft.material { payload["material_type"] = material }
        if let diameter = draft.diameter { payload["diameter_mm"] = diameter }
        if let density = draft.density { payload["density_g_cm3"] = density }
        // Probed live 2026-08-25: all three take an explicit null and a re-GET
        // confirms the clear. `manufacturer_id` does NOT — it 500s — which is
        // why it is a plain parameter here and its refusal is reported by
        // `FilaManRepository.unclearableFilamentNote` rather than handled.
        putNullable(&payload, "raw_material_weight_g", draft.weight)
        putNullable(&payload, "default_spool_weight_g", draft.spoolWeight)
        putNullable(&payload, "price", draft.price)

        // `comment`, `article_number` and the two temperatures used to be
        // emulated here inside free-form custom_fields. Task 5 stopped
        // rendering all four on FilaMan's filament form, so nothing can ask
        // to write them any more (2026-08-28) — only `extra` remains.
        let custom = draft.extra.valueOnCreate ?? [:]
        if !custom.isEmpty { payload["custom_fields"] = custom }

        return payload
    }

    /// Writes a patch value into a FilaMan payload for a key the server is
    /// KNOWN to accept a null on. Deliberately not used for the keys that 500
    /// (`manufacturer_id`) or that would wipe a sibling (the colour keys) —
    /// those are reported, not sent.
    private static func putNullable<T>(
        _ payload: inout [String: Any], _ key: String, _ patch: SpoolmanPatchValue<T>
    ) {
        switch patch {
        case .ignore:
            break
        case .set(let value):
            payload[key] = value
        case .setNil:
            payload[key] = NSNull()
        }
    }

    // MARK: - Colours
    //
    // FilaMan colours are first-class entities under `/api/v1/colors`; a
    // filament references them by integer FK. Verified live 2026-08-21 against
    // the owner's instance and its OpenAPI schema (plan defect F27): an earlier
    // version of `colorsPayload` sent positional `hex_code` entries and no
    // `color_mode`, which `FilamentColorsReplace` rejects outright.

    /// Canonical match/write form of a colour hex: trimmed, no leading `#`,
    /// lowercased. The single definition of what "the same colour" means on
    /// FilaMan — `GET /colors` has no hex filter, so `FilaManRepository` fetches
    /// every row and matches on this key locally, and `colorPayload` builds the
    /// create body from it. Drafts carry a bare hex (`mapFilament` strips the
    /// `#` on read), so the write direction has to add it back or the
    /// round-trip diverges.
    static func normalizedHex(_ hex: String) -> String {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let bare = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        return bare.lowercased()
    }

    /// `POST /api/v1/colors` body. Both fields are required, and uniqueness is
    /// on the **(name, hex_code) pair** — an exact-pair duplicate returns 500,
    /// so callers must resolve against the existing rows before creating.
    /// `name` upper / `hex_code` lower is the convention every existing row on
    /// the owner's instance follows.
    static func colorPayload(hex: String) -> [String: Any] {
        let normalized = normalizedHex(hex)
        return ["name": "#\(normalized.uppercased())", "hex_code": "#\(normalized)"]
    }

    /// `FilamentColorsReplace`: the body of `PUT /api/v1/filaments/{id}/colors`,
    /// and — merged into `filamentPayload`'s result — the colour half of a
    /// `POST /api/v1/filaments` create.
    ///
    /// `color_mode` is required. An entry is `color_id` (an integer FK into
    /// `/api/v1/colors`) plus a 1-based `position`; there is no `hex_code` in an
    /// entry, which is why `colorIds` and not hexes are the input — resolving
    /// hex → id is `FilaManRepository`'s job.
    ///
    /// `multi_color_style` is sent only alongside `color_mode: "multi"`, where
    /// it is the gradient/stripe direction `mapFilament` reads back as
    /// `multiColorDirection`; on a single colour it describes nothing.
    ///
    /// This never produces an empty `colors` array in practice, and must not:
    /// `PUT …/colors` is a full REPLACE, so `colors: []` wipes every colour a
    /// filament has. An empty `FilaManRepository.writableHexes(_:)` therefore
    /// means *skip the request entirely* rather than "send an empty one" —
    /// that distinction is the whole point of the helper.
    static func colorsPayload(colorIds: [Int], multiColorStyle: String?) -> [String: Any] {
        let isMulti = colorIds.count > 1
        var payload: [String: Any] = [
            "color_mode": isMulti ? "multi" : "single",
            "colors": colorIds.enumerated().map { index, colorId in
                ["color_id": colorId, "position": index + 1] as [String: Any]
            }
        ]
        if isMulti, let style = supportedMultiColorStyle(multiColorStyle) {
            payload["multi_color_style"] = style
        }
        return payload
    }

    /// The only two values `FilamentColorsReplace.multi_color_style` accepts
    /// (`^(striped|gradient)$`, verified live 2026-08-21), plus `nil` for
    /// "don't say".
    static let multiColorStyles = ["striped", "gradient"]

    /// Narrows a free-text multi-colour direction to FilaMan's vocabulary,
    /// returning `nil` for anything it does not recognise (plan defect C1/R19).
    ///
    /// SpoolKid's `multi_color_direction` is a free-text field
    /// (`FilamentFormView`) whose values otherwise come from Spoolman, which
    /// uses a different vocabulary entirely — and `MigrationService` pipes
    /// those straight into a `FilamentDraft`. Forwarding one verbatim fails the
    /// pattern, and because `colorsPayload`'s output is merged **inline** into
    /// `POST /filaments`, that 422 destroys the whole create rather than just
    /// the colour: the filament the user asked for would not exist.
    ///
    /// Returning `nil` omits the key, so the create still succeeds — the
    /// caller is expected to name the dropped value in its partial-failure
    /// message rather than let it vanish silently.
    ///
    /// Case and whitespace are normalised, so `"Gradient "` is accepted.
    ///
    /// Spoolman's directions map by the owner's decision (2026-10-28):
    /// Coextruded (`coaxial`) is `striped`, and Gradient (`longitudinal`) is
    /// `gradient`. Anything else is not mapped onto a nearest neighbour — a
    /// value outside those is dropped, so it never silently restyles a filament.
    static func supportedMultiColorStyle(_ style: String?) -> String? {
        guard let normalized = style?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else { return nil }
        let mapped = FilamentColors.Pattern(rawValue: normalized)?.filaManStyle ?? normalized
        guard multiColorStyles.contains(mapped) else { return nil }
        return mapped
    }

    // MARK: - Spools

    /// The scalar body BOTH spool writes share — and deliberately not a
    /// remaining weight, because `SpoolUpdate` has no such field (verified
    /// live 2026-08-21). A PATCH carrying a key the endpoint does not know
    /// returns 200 and writes nothing, which is exactly how every
    /// remaining-weight edit on FilaMan was lost while the form reported
    /// success (plan defect I2). `spoolCreatePayload` adds the key for the one
    /// endpoint that accepts it; `FilaManRepository.updateSpool` posts an
    /// adjustment event instead.
    ///
    /// `location`'s three cases preserve the same "don't touch" / "set" /
    /// "clear" distinction `SpoolmanPayloadBuilder.spoolPayload`'s own
    /// `location: SpoolmanPatchValue<String>` parameter carries — `.setNil`
    /// sends an explicit `NSNull()` for `location_id` rather than omitting
    /// the key. Verified live 2026-08-20 against the owner's instance:
    /// `PATCH /spools/{id}` with `{"location_id": null}` returns 200 and a
    /// re-GET confirms `location_id` is actually cleared, matching
    /// `SpoolUpdate.location_id`'s `anyOf[integer, null]` schema — FilaMan
    /// does accept an explicit null here.
    static func spoolPayload(from draft: SpoolDraft, location: SpoolmanPatchValue<Int>) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let filamentId = draft.filamentId { payload["filament_id"] = filamentId }
        switch location {
        case .ignore:
            break
        case .set(let locationId):
            payload["location_id"] = locationId
        case .setNil:
            payload["location_id"] = NSNull()
        }
        // NEITHER date is here, and both used to be. Probed live 2026-08-25:
        // `PATCH /spools/{id}` accepts `stocked_in_at` and `last_used_at` with
        // a 200 and stores NEITHER, so every First Used / Last Used edit on an
        // existing FilaMan spool was reported as saved and thrown away — made
        // invisible by `updateSpool` re-reading the spool afterwards, which
        // redisplayed FilaMan's unchanged values with nothing looking wrong.
        // Corroborated by the data: both null on all 38 of the owner's spools,
        // while `created_at` is populated on all 38.
        //
        // `spoolCreatePayload` adds `stocked_in_at` back, because a CREATE
        // does keep it (201, and it survives a re-GET). `last_used_at` is
        // FilaMan's own derived figure and no endpoint accepts it.
        // `FilaManRepository.unwritableDateNoteOnCreate` reports what this
        // drops on create — the update-side note was deleted 2026-08-28,
        // since FilaMan's spool form no longer renders either date.
        if let price = draft.price { payload["purchase_price"] = price }
        // Native FilaMan columns (Task 7). Tri-state like `lot_number` above:
        // `.setNil` sends an explicit null rather than omitting the key.
        putNullable(&payload, "external_id", draft.externalId)
        putNullable(&payload, "purchase_date", draft.purchaseDate)
        // Net → gross, basis included. One call, not two `if let`s: see
        // `spoolWeightKeys` for why the pair is indivisible (F31).
        for (key, value) in spoolWeightKeys(netInitial: draft.initialWeight, spoolWeight: draft.spoolWeight) {
            payload[key] = value
        }
        // Probed live 2026-08-25: `lot_number` takes an explicit null and a
        // re-GET confirms it is cleared, so the whole tri-state survives the
        // trip. It did not before — `clearFieldKeys` named Spoolman's
        // `lot_nr`, which nothing here ever read (R21).
        switch draft.lotNr {
        case .ignore:
            break
        case .set(let lot):
            payload["lot_number"] = lot
        case .setNil:
            payload["lot_number"] = NSNull()
        }

        // `extra` is the base layer; typed fields overwrite it on key collision.
        // `card_uids` lives here — this must never be dropped.
        //
        // `.setNil` contributes NOTHING rather than emptying the object.
        // `extra` IS `custom_fields` on FilaMan, so honouring the clear would
        // take `card_uids` and a migrated instance's `spoolman_id` with it.
        var custom = draft.extra.valueOnCreate ?? [:]
        // `comment` used to be emulated here inside free-form custom_fields.
        // Task 5 stopped rendering it on FilaMan's spool form, so nothing can
        // ask to write it any more (2026-08-28).
        //
        // BARE, not `CardUIDsCodec.encode` — FilaMan's compat layer JSON-encodes
        // each custom field on read, so the wrapped form double-wraps and
        // breaks every third-party SpoolLink/Snapmaker U1 client (F38). The
        // draft carries the UID list typed so this choice is made here, once
        // per backend, instead of in the shared spool form that used to make it.
        custom = CardUIDsCodec.applyingBare(draft.cardUIDs, to: custom) ?? custom
        if !custom.isEmpty { payload["custom_fields"] = custom }

        return payload
    }

    /// `POST /api/v1/spools`. `SpoolCreate` **has** `remaining_weight_g` while
    /// `SpoolUpdate` does not (verified live 2026-08-21), so create and update
    /// are two functions rather than one with a flag: a flag would let a
    /// caller ask the update endpoint for a key it silently drops, which is
    /// the defect this exists to close (I2).
    ///
    /// `remainingWeight` is NET filament — no conversion, unlike
    /// `initial_total_weight_g`. Probed live 2026-08-21, because the frame
    /// could not be inferred from its neighbours:
    ///
    ///     POST /spools {initial_total_weight_g: 1250,
    ///                   empty_spool_weight_g: 250,
    ///                   remaining_weight_g: 400}
    ///       -> reported remaining_weight_g = 400
    ///          (preserved; GROSS would have reported 150)
    ///     then PATCH {empty_spool_weight_g: 300}
    ///       -> reported remaining_weight_g = 350   ( = 650 - 300 )
    ///
    /// The second call is F32's re-base: the basis moved by +50, so the net
    /// remaining moved by −50, holding the gross figure constant.
    ///
    /// This one resource exposes BOTH frames — `remaining_weight_g` is net on
    /// read and on create, while `measured_weight_g` is gross — so neither
    /// can be inferred from the other, in either direction. Every weight
    /// field here has to be probed on its own.
    ///
    /// `nil` means the draft named no weight; a weight that was named but
    /// could not be worked out is `FilaManRepository`'s `.unsupported` to
    /// report, not a `nil` to pass down here.
    static func spoolCreatePayload(
        from draft: SpoolDraft,
        location: SpoolmanPatchValue<Int>,
        remainingWeight: Double?
    ) -> [String: Any] {
        var payload = spoolPayload(from: draft, location: location)
        if let remainingWeight { payload["remaining_weight_g"] = remainingWeight }
        // Create-only, and this is the second key that earns its place here
        // rather than in the shared body: `POST /spools` stores
        // `stocked_in_at`, `PATCH /spools/{id}` silently drops it. Exactly the
        // reason this function exists rather than a flag on `spoolPayload` —
        // a flag would let a caller ask the update endpoint for a key it
        // discards, which is the defect both keys were found in.
        if let firstUsed = draft.firstUsed.valueOnCreate, !firstUsed.isEmpty {
            payload["stocked_in_at"] = firstUsed
        }
        return payload
    }

    /// FilaMan's two spool-weight keys, as ONE unit.
    ///
    /// `initial_total_weight_g` is GROSS — filament plus the empty spool —
    /// while `SpoolDraft.initialWeight` is NET filament (plan defect F31,
    /// owner-corrected and proven live 2026-08-21). Writing the net figure
    /// into the gross field made FilaMan subtract the spool weight a second
    /// time, so every round-trip drifted by one spool weight.
    ///
    /// The basis travels WITH the gross figure, even when it is 0, and that
    /// pairing is why this returns both keys together instead of each being an
    /// independent `if let` in `spoolPayload`. Verified live 2026-08-21: a
    /// create carrying `initial_total_weight_g: 1250` and no
    /// `empty_spool_weight_g` makes FilaMan inherit the FILAMENT's
    /// `default_spool_weight_g` as the basis — it used 164 and derived 1086 —
    /// so omitting the basis silently rewrites the number just sent.
    ///
    /// A basis with no gross figure is still emitted alone: there is nothing
    /// to convert, but the user did change the core weight and dropping that
    /// edit would be a silent success of its own.
    /// Tri-state since R21, and the pair is still indivisible — more so now.
    ///
    /// `spoolWeight ?? 0` used to be harmless: with bare optionals, "no spool
    /// weight" and "a basis of zero" were the same input. Patch values
    /// separate them, and that exposes a combination with no local answer —
    /// **a gross figure to send with a basis the draft declines to state.**
    /// Assuming 0 would be wrong whenever the server holds a basis the user
    /// simply did not edit, and omitting the key makes FilaMan inherit the
    /// filament's `default_spool_weight_g` and silently rewrite the number
    /// just sent (F31).
    ///
    /// Resolved at the form layer instead: `SpoolFormView` emits the basis as
    /// `.set` whenever it states a gross figure, so `.set` + `.ignore` does
    /// not arise from the app. It is still handled here — by sending
    /// **neither** key — because a builder that quietly invents a basis is how
    /// F31 happened, and `MigrationService` assembles drafts too.
    static func spoolWeightKeys(
        netInitial: SpoolmanPatchValue<Double>,
        spoolWeight: SpoolmanPatchValue<Double>
    ) -> [String: Any] {
        switch (netInitial, spoolWeight) {
        // Nothing stated about either.
        case (.ignore, .ignore):
            return [:]

        // A basis alone: nothing to convert, but the user did change the core
        // weight, and dropping that edit would be a silent success of its own.
        case (.ignore, .set(let basis)):
            return [emptySpoolWeightKey: basis]
        case (.ignore, .setNil):
            return [emptySpoolWeightKey: NSNull()]

        // The whole pair. The basis travels WITH the gross figure even at 0 —
        // that pairing is why this returns both keys together rather than
        // being two independent `if let`s in `spoolPayload`.
        case (.set(let net), .set(let basis)):
            return ["initial_total_weight_g": net + basis, emptySpoolWeightKey: basis]
        case (.set(let net), .setNil):
            // A cleared basis is zero for the conversion, and stated as null so
            // FilaMan cannot fall back to the filament's default.
            return ["initial_total_weight_g": net, emptySpoolWeightKey: NSNull()]

        // A gross figure with an unstated basis cannot be converted. Refusing
        // BOTH keys is the only safe answer: sending the gross figure alone
        // would let the server pick the basis and rewrite the number.
        case (.set, .ignore):
            return [:]

        // Clearing the gross figure says nothing about the basis.
        case (.setNil, .ignore):
            return ["initial_total_weight_g": NSNull()]
        case (.setNil, .set(let basis)):
            return ["initial_total_weight_g": NSNull(), emptySpoolWeightKey: basis]
        case (.setNil, .setNil):
            return ["initial_total_weight_g": NSNull(), emptySpoolWeightKey: NSNull()]
        }
    }

    /// The spool-weight basis key, named once so `spoolWeightKeys` (which
    /// emits it) and `movesWeightBasis` (which looks for it) cannot drift
    /// apart.
    static let emptySpoolWeightKey = "empty_spool_weight_g"

    /// Whether this payload will move the spool's REPORTED remaining weight
    /// as a side effect, without naming it.
    ///
    /// A PATCH that CHANGES `empty_spool_weight_g` makes FilaMan re-base the
    /// remaining weight by the same amount, opposite in sign, to hold the
    /// gross figure constant (plan fact F32; `initial_total_weight_g` does not
    /// participate). A user correcting a core weight from 250 g to 400 g
    /// watches the spool lose 150 g of filament it never used.
    ///
    /// This answers on the presence of the key, not on a change of value, so
    /// it OVER-reports: re-sending the same basis moves nothing, and neither
    /// does giving a spool its first one. Deliberate — the false positive
    /// costs one pre-PATCH read, the false negative costs the user's number.
    ///
    /// `FilaManRepository.updateSpool` uses this to decide whether it must
    /// read the spool's remaining weight BEFORE the PATCH so it can hold it
    /// steady afterwards (R20).
    /// Answers on key PRESENCE, which now includes an explicit `NSNull()` —
    /// clearing the basis moves the reported remaining weight exactly as
    /// changing it does, so `.setNil` must count (R21).
    static func movesWeightBasis(_ payload: [String: Any]) -> Bool {
        payload[emptySpoolWeightKey] != nil
    }

    /// The same body as `statusPayload(archived:)`, for a status the user
    /// picked by name rather than a boolean. `POST /spools/{id}/status` takes
    /// the status **key**; sending `status_id` is a 422.
    static func statusPayload(key: String) -> [String: Any] {
        ["status": key]
    }

    /// Archiving is a status transition on FilaMan, not a boolean field. The
    /// archived⇄status mapping itself lives on FilaManSpoolStatus (A4). Uses
    /// `.key`, not `.id` — `POST /spools/{id}/status` takes a `status` string
    /// (verified live 2026-08-20; see `FilaManSpoolStatus.key`'s doc comment).
    /// Expressed in terms of `statusPayload(key:)` so the boolean and the
    /// picker cannot drift over the wire format.
    static func statusPayload(archived: Bool) -> [String: Any] {
        statusPayload(key: FilaManSpoolStatus.key(archived: archived))
    }

    /// `AdjustmentRequest`: the body of `POST /api/v1/spools/{id}/adjustments`.
    /// Remaining weight is event-sourced — `SpoolUpdate` carries no
    /// `remaining_weight_g`, so a correction is posted as an adjustment event.
    ///
    /// `adjustment_type` is required, and only `"absolute"` and `"relative"`
    /// are accepted (anything else 500s). SpoolKid only ever sends `"relative"`
    /// (plan defect F28/R17, verified live 2026-08-21): `"absolute"` pairs with
    /// `measured_weight_g`, which is **GROSS** — spool plus filament. On a spool
    /// with `empty_spool_weight_g = 200`, posting `measured_weight_g: 500`
    /// yields `remaining_weight_g = 300`. SpoolKid's `remainingWeight` is net
    /// filament, so posting it as `measured_weight_g` would under-report every
    /// spool by its own spool weight — silently, with a 200 response.
    ///
    /// A relative delta depends only on `remaining_weight_g`, which is net on
    /// both sides, and needs no spool-weight arithmetic; `absolute` would need
    /// `empty_spool_weight_g`, which is nullable and whose null-handling is
    /// undocumented. FilaMan clamps the result at 0.
    static func adjustmentPayload(deltaGrams: Double) -> [String: Any] {
        ["adjustment_type": "relative", "delta_weight_g": deltaGrams]
    }

    /// Wraps `fields` as a `custom_fields` REPLACEMENT body — used by the
    /// card_uids writer (Task 19). NOT a partial merge: FilaMan's
    /// `PATCH /api/v1/spools/{id}` overwrites the whole `custom_fields` object
    /// server-side (verified live 2026-08-19), so `fields` here must already
    /// be the complete object the caller wants to end up with. The merge
    /// itself lives in `FilaManService.mergedCustomFields` /
    /// `patchSpoolCustomFields`, which read the spool's current
    /// `custom_fields` and merge locally before calling this.
    /// Body for `POST /api/v1/system-extra-fields`. `target_type` and `key`
    /// and `label` are the required trio; `field_type` defaults to `"text"`
    /// server-side but is stated because `card_uids` is a comma-separated list
    /// and must never be offered as a number or a dropdown.
    ///
    /// `default_value` is deliberately omitted: a default would put an empty
    /// value into `custom_fields` on records that have no mapping, and an empty
    /// `card_uids` is not the same thing as no `card_uids`. `source` is omitted
    /// too — it marks plugin-owned rows as undeletable, and SpoolKid must be
    /// able to remove what it created.
    static func systemExtraFieldPayload(
        targetType: String,
        key: String,
        label: String,
        fieldType: String = "text",
        config: [String: Any]? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "target_type": targetType,
            "key": key,
            "label": label,
            "field_type": fieldType
        ]
        if let config { payload["config"] = config }
        return payload
    }

    /// TD rides in free-form `custom_fields` as a JSON number — FilaMan has no
    /// TD column. Its PATCH replaces `custom_fields` whole, so `current` must
    /// be the fresh object, and omitting the key is a real clear.
    static func customFieldsApplyingTransmissionDistance(
        _ patch: SpoolmanPatchValue<Double>,
        to current: [String: FilaManJSONValue]
    ) -> [String: FilaManJSONValue] {
        var fields = current
        switch patch {
        case .ignore: break
        case .set(let value): fields[TransmissionDistance.fieldKey] = .double(value)
        case .setNil: fields[TransmissionDistance.fieldKey] = nil
        }
        return fields
    }

    /// Body for `POST /api/v1/spools/{id}/measurements`. `measured_weight_g`
    /// is GROSS — the scale reading, spool included — which is exactly what
    /// the form's Measured mode collects, so it travels whole.
    ///
    /// `event_at` and `note` are deliberately omitted. The server defaults the
    /// timestamp to now, and stamping a client clock onto an event log is how
    /// two devices come to disagree about the order of prints.
    static func measurementPayload(measuredWeight: Double) -> [String: Any] {
        ["measured_weight_g": measuredWeight]
    }

    static func customFieldsPayload(_ fields: [String: FilaManJSONValue]) -> [String: Any] {
        ["custom_fields": fields.jsonObject]
    }

    /// Body for a spool tag write: the merged `custom_fields` (when `card_uids`
    /// changes) and `rfid_uid` in one PATCH. `rfid_uid` is the lowercased wire
    /// form, or JSON `null` to clear it. `""` is never written: FilaMan stores
    /// it and then answers 500 for the second spool that does (probed live
    /// 2026-11-03). `.keep` omits the key.
    static func spoolTagPayload(
        customFields: [String: FilaManJSONValue]?,
        rfid: FilaManTagPlan.RFIDChange
    ) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let customFields { payload["custom_fields"] = customFields.jsonObject }
        switch rfid {
        case .keep: break
        case .set(let uid): payload["rfid_uid"] = FilaManTagPlan.wireValue(uid)
        case .clear: payload["rfid_uid"] = NSNull()
        }
        return payload
    }

    // MARK: - Locations

    /// `name` is the whole body of both `POST /api/v1/locations` (create) and
    /// `PATCH /api/v1/locations/{id}` (rename) — the two share one builder
    /// because they share one shape.
    static func locationPayload(name: String) -> [String: Any] {
        ["name": name]
    }

    /// SpoolKid's normalized UID rendered in FilaMan's `identifier` format:
    /// colon-separated lowercase hex, two characters per segment
    /// (`04A1B2C3` → `04:a1:b2:c3`).
    ///
    /// `nil` for anything that is not an even-length run of hex digits. FilaMan
    /// puts no constraint on the column, so a malformed value would be stored
    /// happily and would then read back as a tag binding that matches nothing —
    /// refusing to write is the honest answer.
    static func locationIdentifier(fromUID uid: String) -> String? {
        let normalized = SpoolMappingService.normalizeUID(uid)
        guard !normalized.isEmpty, normalized.count % 2 == 0,
              normalized.allSatisfy({ $0.isHexDigit })
        else { return nil }

        return stride(from: 0, to: normalized.count, by: 2).map { offset in
            let start = normalized.index(normalized.startIndex, offsetBy: offset)
            let end = normalized.index(start, offsetBy: 2)
            return normalized[start..<end].lowercased()
        }.joined(separator: ":")
    }

    /// `PATCH /api/v1/locations/{id}` with `identifier` alone. FilaMan's
    /// `LocationUpdate` is `exclude_unset`, so a body carrying only this key
    /// leaves `name` and `custom_fields` untouched.
    static func locationIdentifierPayload(_ identifier: String?) -> [String: Any] {
        ["identifier": identifier ?? NSNull()]
    }
}
