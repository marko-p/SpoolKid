import Foundation

// `nonisolated`: a pure value type with no state to protect. Without it the
// default MainActor isolation follows it into every `nonisolated` payload
// builder that reads a draft, which warns rather than errors — so it went
// unnoticed until the second wave of fields moved onto this type (R21).
nonisolated enum SpoolmanPatchValue<T> {
    case ignore
    case set(T)
    case setNil

    /// The value this patch asserts, or `nil` for both "say nothing" and
    /// "clear it".
    ///
    /// ONLY for create paths, where the distinction genuinely collapses: a
    /// record that does not exist yet has no field to leave alone, so
    /// `.ignore` and `.setNil` both mean "created without this". Using it on
    /// an update path would throw away exactly the distinction this type
    /// exists to carry (R21) — reach for a `switch` there.
    var valueOnCreate: T? {
        if case .set(let value) = self { return value }
        return nil
    }
}

// `nonisolated` for the same reason the type is: a `#expect(patch == .ignore)`
// in a test — or any comparison off the main actor — cannot use a MainActor
// conformance, and in Swift 6 language mode that is an error rather than a
// warning.
nonisolated extension SpoolmanPatchValue: Equatable where T: Equatable {}

/// Where a draft's TD leaves a filament's `extra` on Spoolman.
nonisolated enum TransmissionDistanceExtra: Equatable {
    case unchanged
    case extra([String: String])
    /// Not written, and why — the caller folds it into the save's note.
    case refused(String)
}

enum SpoolmanPayloadBuilder {
    /// Spoolman's `extra` PATCH REPLACES the whole object, so TD is applied on
    /// top of the filament's current extra, never sent alone. The wire form
    /// follows the registered field's type (`TransmissionDistance`).
    static func extraApplyingTransmissionDistance(
        _ patch: SpoolmanPatchValue<Double>,
        to current: [String: String],
        fieldType: String
    ) -> TransmissionDistanceExtra {
        var extra = current
        switch patch {
        case .ignore:
            return .unchanged
        case .set(let value):
            guard let wire = TransmissionDistance.spoolmanWireValue(value, fieldType: fieldType) else {
                return .refused("TD was not saved: this Spoolman's td field is \(fieldType), not a number.")
            }
            extra[TransmissionDistance.fieldKey] = wire
        case .setNil:
            extra[TransmissionDistance.fieldKey] = nil
            // Probed 2026-11-02: `{}` is a no-op, and `"null"` / `""` are 400s
            // for a float field — no request removes the last extra key.
            guard !extra.isEmpty else {
                return .refused("TD could not be cleared: Spoolman cannot remove a filament's last extra field.")
            }
        }
        return .extra(extra)
    }

    static func vendorPayload(from draft: VendorDraft) -> [String: Any] {
        var body: [String: Any] = [:]
        if let name = draft.name { body["name"] = name }
        if let comment = draft.comment { body["comment"] = comment }
        if let emptySpoolWeight = draft.emptySpoolWeight { body["empty_spool_weight"] = emptySpoolWeight }
        if let externalId = draft.externalId { body["external_id"] = externalId }
        if let extra = draft.extra { body["extra"] = extra }
        return body
    }

    static func filamentPayload(
        name: String?,
        vendorId: SpoolmanPatchValue<Int>,
        material: String?,
        price: SpoolmanPatchValue<Double>,
        density: Double?,
        diameter: Double?,
        weight: SpoolmanPatchValue<Double>,
        spoolWeight: SpoolmanPatchValue<Double>,
        articleNumber: SpoolmanPatchValue<String>,
        comment: SpoolmanPatchValue<String>,
        extruderTemp: SpoolmanPatchValue<Int>,
        bedTemp: SpoolmanPatchValue<Int>,
        colorHex: String?,
        multiColorHexes: SpoolmanPatchValue<String>,
        multiColorDirection: SpoolmanPatchValue<String>,
        externalId: SpoolmanPatchValue<String>,
        extra: SpoolmanPatchValue<[String: String]>
    ) -> [String: Any] {
        var body: [String: Any] = [:]
        // Set-only: no form offers a way to clear these, and Spoolman requires
        // `name`.
        if let name { body["name"] = name }
        if let material { body["material"] = material }
        if let density { body["density"] = density }
        if let diameter { body["diameter"] = diameter }
        if let colorHex { body["color_hex"] = colorHex }

        // Clearable, tri-state (R21 stage 4). This is where `clearFieldKeys`
        // used to be applied, one key name at a time, by `SpoolmanService`.
        // Spoolman is the backend whose key names those were, so the wire
        // output is unchanged — the point is that every OTHER backend no
        // longer has to translate them.
        put(&body, "vendor_id", vendorId)
        put(&body, "price", price)
        put(&body, "weight", weight)
        put(&body, "spool_weight", spoolWeight)
        put(&body, "article_number", articleNumber)
        put(&body, "comment", comment)
        put(&body, "settings_extruder_temp", extruderTemp)
        put(&body, "settings_bed_temp", bedTemp)
        // NOT two independent `put`s: Spoolman validates the PAIR.
        for (key, value) in multiColorKeys(hexes: multiColorHexes, direction: multiColorDirection) {
            body[key] = value
        }
        put(&body, "external_id", externalId)
        putExtra(&body, extra)
        return body
    }

    /// `extra`, which is the ONE clearable field Spoolman will not let go of.
    ///
    /// Probed live 2026-08-27, on both spools and filaments, and on records
    /// whose `extra` was already empty:
    ///
    ///     PATCH {"extra": null}  -> 500 Internal Server Error
    ///     PATCH {"extra": {}}    -> 200, and the existing keys are UNCHANGED
    ///
    /// So a `.setNil` had been failing the entire save with a 500 — not
    /// dropping the extra fields, losing the whole edit — and `{}` is not a
    /// fallback, because Spoolman reads an empty object as "no change" rather
    /// than "remove everything". There is no request that empties `extra`.
    ///
    /// `.setNil` therefore sends NOTHING — there is no request that empties
    /// `extra` on Spoolman, so a `.setNil` is silently dropped rather than
    /// sent as a 500.
    ///
    /// A NON-empty object does replace: `{variant: A, td: 1.5}` PATCHed with
    /// `{variant: B}` leaves `{variant: B}` and `td` is gone.
    private static func putExtra(_ body: inout [String: Any], _ extra: SpoolmanPatchValue<[String: String]>) {
        switch extra {
        case .ignore:
            break
        case .set(let fields):
            body["extra"] = fields
        case .setNil:
            break
        }
    }

    /// Spoolman's two multi-colour keys, as ONE unit (a stated pair also nulls
    /// `color_hex`).
    ///
    /// Probed live 2026-08-27: the server validates them **together**, and
    /// rejects the whole PATCH with a 422 if they disagree.
    ///
    ///     PATCH {multi_color_hexes: "FF0000,00FF00"}   -> 422
    ///       "Multi-color filament must have multi_color_direction"
    ///     PATCH {multi_color_direction: "coaxial"}     -> 422
    ///       "Single-color filament must not have multi_color_direction"
    ///     PATCH {both}                                  -> 200
    ///
    /// Emitting them as two independent `if let`s therefore did not drop a
    /// colour — it failed the ENTIRE write. Reachable from `FilamentFormView`,
    /// where the two are free text fields and nothing pairs them: filling in
    /// the hexes and leaving the direction blank made the filament CREATE
    /// return 422, so the filament the user asked for did not exist.
    ///
    /// The same shape as `FilaManPayloadBuilder.spoolWeightKeys` (F31), and
    /// resolved the same way — the builder refuses a combination it cannot
    /// make safe rather than sending half of it and hoping.
    ///
    /// **Nulls are lenient** (measured): clearing either key alone is a 200,
    /// because a filament that ends up with neither is consistent. Only a
    /// STATED value needs its partner.
    static func multiColorKeys(
        hexes: SpoolmanPatchValue<String>,
        direction: SpoolmanPatchValue<String>
    ) -> [String: Any] {
        switch (hexes, direction) {
        case (.ignore, .ignore):
            return [:]

        // The whole pair, which is the only way to state a multi-colour. The
        // single `color_hex` is nulled alongside it: Spoolman keeps a stated
        // one next to the list otherwise (probed 2026-10-28).
        case (.set(let h), .set(let d)):
            return ["multi_color_hexes": h, "multi_color_direction": d, "color_hex": NSNull()]

        // Clears travel alone safely: whatever is left is still consistent.
        case (.setNil, .setNil):
            return ["multi_color_hexes": NSNull(), "multi_color_direction": NSNull()]
        case (.setNil, .ignore):
            return ["multi_color_hexes": NSNull()]
        case (.ignore, .setNil):
            return ["multi_color_direction": NSNull()]

        // A value whose partner is unstated or cleared. There is no local
        // answer — a direction cannot be invented, and Spoolman refuses the
        // half-pair outright — so send NEITHER and let the caller report it
        // (`droppedMultiColorNote`). Losing the multi-colour list is bad;
        // losing the whole filament is worse.
        case (.set, _), (_, .set):
            return [:]
        }
    }

    /// What `multiColorKeys` refused to send, for the caller's caveat.
    ///
    /// Silent unless a stated value was actually dropped — the common case is
    /// a single-colour filament, where both are `.ignore` and there is nothing
    /// to say.
    static func droppedMultiColorNote(
        hexes: SpoolmanPatchValue<String>,
        direction: SpoolmanPatchValue<String>
    ) -> String? {
        guard multiColorKeys(hexes: hexes, direction: direction).isEmpty else { return nil }
        if case .set = hexes {
            return "The multi-colour list was not saved: Spoolman needs a direction to go with it."
        }
        if case .set = direction {
            return "The multi-colour direction was not saved: Spoolman only accepts one "
                + "alongside a list of colours."
        }
        return nil
    }

    /// Writes one patch value into a Spoolman body: omit / value / explicit
    /// `null`. Generic over `T` so the twelve clearable filament fields —
    /// three different value types between them — cannot drift apart.
    private static func put<T>(_ body: inout [String: Any], _ key: String, _ patch: SpoolmanPatchValue<T>) {
        switch patch {
        case .ignore:
            break
        case .set(let value):
            body[key] = value
        case .setNil:
            body[key] = NSNull()
        }
    }

    static func filamentPayload(from draft: FilamentDraft) -> [String: Any] {
        filamentPayload(
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
    }

    static func spoolPayload(
        filamentId: Int?,
        firstUsed: SpoolmanPatchValue<String>,
        lastUsed: SpoolmanPatchValue<String>,
        price: Double?,
        initialWeight: SpoolmanPatchValue<Double>,
        spoolWeight: SpoolmanPatchValue<Double>,
        remainingWeight: SpoolmanPatchValue<Double>,
        usedWeight: SpoolmanPatchValue<Double>,
        location: SpoolmanPatchValue<String>,
        lotNr: SpoolmanPatchValue<String>,
        comment: SpoolmanPatchValue<String>,
        archived: Bool?,
        extra: SpoolmanPatchValue<[String: String]>
    ) -> [String: Any] {
        var body: [String: Any] = [:]
        if let filamentId { body["filament_id"] = filamentId }
        if let price { body["price"] = price }
        // The four weights are tri-state like `location` (R21). They were bare
        // optionals, so "the form did not touch this" and "set this value" were
        // the same thing and every save re-asserted whatever the form loaded —
        // a lost update whenever two people edit one spool.
        for (key, patch) in [
            ("initial_weight", initialWeight),
            ("spool_weight", spoolWeight),
            ("remaining_weight", remainingWeight),
            ("used_weight", usedWeight)
        ] {
            switch patch {
            case .ignore:
                continue
            case .set(let value):
                body[key] = value
            case .setNil:
                body[key] = NSNull()
            }
        }

        // The three text patches, clearing the same way the weights do — an
        // explicit `null`. Spoolman is the backend whose key names these are,
        // so this is the one builder that needed no translation table, which is
        // exactly why `clearFieldKeys` looked workable for so long (R21).
        for (key, patch) in [
            ("location", location),
            ("lot_nr", lotNr),
            ("comment", comment),
            ("first_used", firstUsed),
            ("last_used", lastUsed)
        ] {
            switch patch {
            case .ignore:
                continue
            case .set(let value):
                body[key] = value
            case .setNil:
                body[key] = NSNull()
            }
        }

        if let archived { body["archived"] = archived }
        putExtra(&body, extra)
        return body
    }

    static func spoolPayload(from draft: SpoolDraft) -> [String: Any] {
        spoolPayload(
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
            // Spoolman's `extra` values are JSON-encoded, so the mapping goes
            // on the wire WRAPPED. The draft carries the list untyped-by-wire
            // precisely so this choice is made per backend rather than by the
            // shared spool form (F38).
            extra: CardUIDsCodec.applyingWrapped(draft.cardUIDs, to: draft.extra)
        )
    }
}
