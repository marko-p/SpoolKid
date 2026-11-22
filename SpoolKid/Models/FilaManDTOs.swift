//
//  FilaManDTOs.swift
//  SpoolKid
//
//  Purpose: Codable mirrors of FilaMan's native /api/v1 response shapes.
//  Verified against a live FilaMan 1.2.19 instance on 2026-08-18. These are
//  wire types only — FilaManRepository maps them to the app's Spool/Filament/
//  Vendor DTOs, and nothing outside that repository should see them.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// One JSON value of any shape, so `custom_fields` can be decoded without
/// asserting what is in it.
///
/// `custom_fields` is a **free-form** JSON object on FilaMan's native API:
/// values keep whatever type the writer used. Typing the dictionary as
/// `[String: String]` therefore throws `typeMismatch` on the very first
/// non-string value — and every record migrated from Spoolman carries
/// `{"spoolman_id": <Int>}`, so on a migrated instance that is *every* spool,
/// filament and manufacturer. The user-visible result was the whole Library
/// failing with "The data couldn't be read because it isn't in the correct
/// format", with no row loading at all.
///
/// `FilaManColor`'s doc comment already reasoned this out — "`custom_fields`
/// typed as `[String: String]?` would throw on any non-string value FilaMan
/// chose to put there" — and answered it by not decoding the field on colours.
/// The same sentence was true of the three types that DO decode it, where the
/// answer had to be a type that can hold the value rather than an omission.
///
/// Round-tripping matters as much as decoding: `custom_fields` is PATCHed as a
/// whole-object replacement, so a merge that re-encoded `spoolman_id: 43` as
/// `"43"` would rewrite every record's Spoolman linkage into a different type.
/// `.int` is therefore tried before `.double`, and every case encodes back to
/// the JSON form it was read from.
nonisolated enum FilaManJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    indirect case array([FilaManJSONValue])
    indirect case object([String: FilaManJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        // Bool before the numbers, Int before Double: JSON `true` and JSON `43`
        // must not come back as 1 or 43.0 when they are written out again.
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Int.self) { self = .int(value); return }
        if let value = try? container.decode(Double.self) { self = .double(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([FilaManJSONValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: FilaManJSONValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(
            in: container, debugDescription: "Unrepresentable JSON value in custom_fields"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// The value when it really is a string, and only then. Every key SpoolKid
    /// itself writes (`card_uids`, `comment`, `article_number`) is a string, so
    /// a caller reading one of those wants this: a number under `comment` is
    /// not a comment, and coercing it would invent content.
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// A string for the app's `extra` maps, which are `[String: String]`.
    /// Scalars render; `null` and the two container cases return nil, because
    /// flattening them into a flat string map would invent a representation no
    /// reader asked for.
    ///
    /// `extra` is **not** display-only, which is the trap: the spool, filament
    /// and vendor forms load it and the payload builders seed `custom_fields`
    /// from it, so this rendering comes back through
    /// `FilaManService.mergedCustomFields` on every save. That is why the merge
    /// treats a string equal to a value's `displayString` as an echo rather
    /// than an edit — without it, one save rewrites `spoolman_id: 43` to
    /// `"43"` on every record it touches.
    var displayString: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return String(value)
        case .null, .array, .object: return nil
        }
    }

    /// `JSONSerialization`-compatible form, for the payload dictionaries the
    /// service hands to `URLRequest`.
    var jsonObject: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        case .null: return NSNull()
        case .array(let value): return value.map(\.jsonObject)
        case .object(let value): return value.mapValues(\.jsonObject)
        }
    }
}

/// Literal conformances so a `custom_fields` fixture reads as the JSON it
/// mirrors — `["comment": "top shelf", "spoolman_id": 43]` — rather than as a
/// wall of `.string(…)` / `.int(…)` wrappers.
nonisolated extension FilaManJSONValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) { self = .string(value) }
}

nonisolated extension FilaManJSONValue: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) { self = .int(value) }
}

nonisolated extension Dictionary where Key == String, Value == FilaManJSONValue {
    /// The whole object in `JSONSerialization` form, for a replacement PATCH.
    var jsonObject: [String: Any] { mapValues(\.jsonObject) }

    /// The string-valued view the app's `extra` maps expect.
    var displayStrings: [String: String] { compactMapValues(\.displayString) }
}

nonisolated struct FilaManSpool: Codable, Equatable, Sendable {
    let id: Int
    let filamentId: Int
    let statusId: Int
    let lotNumber: String?
    /// FilaMan's own tag binding, written by its ESP32 scale. SpoolKid READS
    /// this as a resolution fallback and never writes it.
    let rfidUid: String?
    let externalId: String?
    let locationId: Int?
    /// A calendar date, not a timestamp — decoded and re-encoded verbatim as a
    /// string, the same way `stockedInAt`/`lastUsedAt` are. Threaded through
    /// to `Spool.purchaseDate` (Task 7) so the form can prefill it on edit.
    let purchaseDate: String?
    let purchasePrice: Double?
    let stockedInAt: String?
    let lastUsedAt: String?
    /// **GROSS** — filament PLUS the empty spool, exactly as the name says.
    /// Does NOT map 1:1 onto the app's NET `initialWeight`: the basis comes off
    /// on read and goes back on on write, via
    /// `FilaManRepository.netInitialWeight` and
    /// `FilaManPayloadBuilder.spoolWeightKeys`.
    ///
    /// This comment claimed the opposite ("NET despite the name",
    /// owner-confirmed 2026-08-18) until the owner corrected their own answer
    /// and it was proven live on 2026-08-21 (plan defect F31). Note the
    /// neighbour: `remainingWeightG` really IS net, on read and on create,
    /// while `measured_weight_g` on the adjustments route is gross — this one
    /// resource exposes both frames, so no weight field here may be inferred
    /// from another.
    let initialTotalWeightG: Double?
    let emptySpoolWeightG: Double?
    let remainingWeightG: Double?
    let createdAt: String?
    /// Free-form JSON object. `card_uids` and `comment` live here.
    let customFields: [String: FilaManJSONValue]?

    enum CodingKeys: String, CodingKey {
        case id
        case filamentId = "filament_id"
        case statusId = "status_id"
        case lotNumber = "lot_number"
        case rfidUid = "rfid_uid"
        case externalId = "external_id"
        case locationId = "location_id"
        case purchaseDate = "purchase_date"
        case purchasePrice = "purchase_price"
        case stockedInAt = "stocked_in_at"
        case lastUsedAt = "last_used_at"
        case initialTotalWeightG = "initial_total_weight_g"
        case emptySpoolWeightG = "empty_spool_weight_g"
        case remainingWeightG = "remaining_weight_g"
        case createdAt = "created_at"
        case customFields = "custom_fields"
    }
}

/// A FilaMan colour is a first-class entity under `/api/v1/colors`, not a
/// string on a filament (F27, verified live 2026-08-21). Filaments reference
/// one by integer FK, so a colour write has to resolve a hex to an `id` — or
/// create the row — before it can name it. `hexCode` is stored verbatim
/// including its leading `#`; every existing row on the owner's instance
/// follows the convention `name = "#RRGGBB"` (upper), `hex_code = "#rrggbb"`
/// (lower), which `FilaManPayloadBuilder.colorPayload` reproduces.
///
/// The wire carries `custom_fields` and `usage_count` on a colour too; neither
/// is decoded (review finding M1). Mirroring them cost nothing and bought
/// nothing — no consumer ever read them — while `custom_fields` typed as
/// `[String: String]?` would throw on any non-string value FilaMan chose to
/// put there, and take not just `fetchColors` down with it but `fetchFilaments`
/// as well, since this type is nested inside `FilaManFilament.colors`. Fields
/// SpoolKid does not use are better left undecoded than decoded strictly.
nonisolated struct FilaManColor: Codable, Equatable, Sendable {
    let id: Int
    let name: String?
    let hexCode: String?

    /// Explicit rather than memberwise so a colour fixture can be just an id.
    init(id: Int, name: String? = nil, hexCode: String? = nil) {
        self.id = id
        self.name = name
        self.hexCode = hexCode
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case hexCode = "hex_code"
    }
}

nonisolated struct FilaManColorSlot: Codable, Equatable, Sendable {
    let position: Int
    let color: FilaManColor
}

nonisolated struct FilaManFilament: Codable, Equatable, Sendable {
    let id: Int
    let manufacturerId: Int
    let designation: String
    let materialType: String
    let materialSubgroup: String?
    let diameterMm: Double?
    let rawMaterialWeightG: Double?
    let defaultSpoolWeightG: Double?
    let price: Double?
    let densityG_cm3: Double?
    let colorMode: String?
    let multiColorStyle: String?
    let customFields: [String: FilaManJSONValue]?
    let colors: [FilaManColorSlot]?

    enum CodingKeys: String, CodingKey {
        case id, designation, price, colors
        case manufacturerId = "manufacturer_id"
        case materialType = "material_type"
        case materialSubgroup = "material_subgroup"
        case diameterMm = "diameter_mm"
        case rawMaterialWeightG = "raw_material_weight_g"
        case defaultSpoolWeightG = "default_spool_weight_g"
        case densityG_cm3 = "density_g_cm3"
        case colorMode = "color_mode"
        case multiColorStyle = "multi_color_style"
        case customFields = "custom_fields"
    }
}

nonisolated struct FilaManManufacturer: Codable, Equatable, Sendable {
    let id: Int
    let name: String
    let url: String?
    let emptySpoolWeightG: Double?
    let customFields: [String: FilaManJSONValue]?

    enum CodingKeys: String, CodingKey {
        case id, name, url
        case emptySpoolWeightG = "empty_spool_weight_g"
        case customFields = "custom_fields"
    }
}

nonisolated struct FilaManLocation: Codable, Equatable, Sendable {
    let id: Int
    let name: String
    /// FilaMan's NFC tag UID for this location — the "Identifier" column in its
    /// own Locations list, written by its "Write RFID Tag" action.
    ///
    /// Stored **colon-separated lowercase hex, each segment zero-padded to two**
    /// (`04:f5:02:3a`). FilaMan shipped a migration whose sole job is padding
    /// leading zeros back onto identifiers an older scale firmware stripped, so
    /// the padding is load-bearing on their side, not cosmetic.
    /// `FilaManPayloadBuilder.locationIdentifier(fromUID:)` converts SpoolKid's
    /// normalization (uppercase, unseparated) into it.
    let identifier: String?

    enum CodingKeys: String, CodingKey {
        case id, name, identifier
    }
}

/// FilaMan's fixed spool statuses, verified against
/// `GET /api/v1/spools/statuses` on 1.2.19. Ids are server data, not guesses.
nonisolated enum FilaManSpoolStatus {
    static let new = 1
    static let opened = 2
    static let drying = 3
    static let active = 4
    static let empty = 5
    static let archived = 6

    /// The single home for SpoolKid's archived-flag ⇄ FilaMan-status mapping.
    /// FilaMan has no "unarchived" status and the pre-archive status is not
    /// recoverable from the API, so unarchiving deliberately lands on `active`.
    static func id(archived: Bool) -> Int {
        archived ? Self.archived : Self.active
    }

    /// The `status` string `POST /api/v1/spools/{id}/status` actually wants
    /// (verified live 2026-08-20 against a 1.2.19 instance's `/openapi.json`
    /// and `GET /api/v1/spools/statuses`): the request body's `StatusChangeRequest.status`
    /// field is a free string matching each status's `key` ("active",
    /// "archived", …) — NOT the numeric `status_id` `.id(archived:)` returns,
    /// which is a GET-response field only and is rejected (422, missing
    /// required `status`) if sent to this endpoint instead.
    static func key(archived: Bool) -> String {
        archived ? "archived" : "active"
    }

    /// One row of `GET /api/v1/spools/statuses`, for the Status picker's
    /// labels. The constants above stay: they are what SpoolKid's own
    /// archived⇄status mapping is written against, and they must not depend on
    /// a fetch having succeeded. This adds the six human labels, nothing else.
    nonisolated struct Option: Codable, Equatable, Sendable, Identifiable {
        let id: Int
        let key: String
        let label: String
        let sortOrder: Int

        enum CodingKeys: String, CodingKey {
            case id, key, label
            case sortOrder = "sort_order"
        }
    }
}

/// One row of FilaMan's system-wide extra-field registry
/// (`GET /api/v1/system-extra-fields`), the list the Admin Panel shows.
///
/// FilaMan's `custom_fields` are free-form, so a value can be written to a
/// record whether or not the key is registered here — which is why SpoolKid
/// worked for a month without touching this endpoint, and why `card_uids`
/// appeared only on the spools it had actually mapped. Registering the key is
/// what makes it a field of every spool, visible in FilaMan's own UI and
/// declared to any Spoolman-compatible client that reads
/// `GET /spoolman/api/v1/field/spool`.
nonisolated struct FilaManSystemExtraField: Codable, Equatable, Sendable {
    let id: Int
    let targetType: String
    let key: String
    let label: String
    /// Set by a plugin (`"bambulab"`, …); such rows are protected from manual
    /// deletion. SpoolKid never writes it — a field it can delete again is the
    /// only kind it may create.
    let source: String?

    enum CodingKeys: String, CodingKey {
        case id
        case targetType = "target_type"
        case key
        case label
        case source
    }
}

/// One row of `GET /api/v1/spools/{id}/events` — FilaMan's own history for a
/// spool. Probed live 2026-09-04: the endpoint is paginated like every other
/// FilaMan list, and `event_type` takes `measurement`, `manual_adjust`,
/// `opened`, `archived`, `empty`.
///
/// `GET /api/v1/spools/{id}/measurements` is a **404** — that route is
/// POST-only. This is the read side, and it was the only one.
///
/// Deliberately NOT decoded: `source` and `device_id`. `source` reads `"ui"`
/// both for a measurement POSTed through the API and for one entered in
/// FilaMan's own web page, and `device_id` was null for every event on a live
/// instance — so neither can attribute a measurement to an app, and decoding
/// them would invite a UI that claims otherwise.
nonisolated struct FilaManSpoolEvent: Codable, Equatable, Sendable {
    let id: Int
    let spoolId: Int
    let eventType: String
    let eventAt: String
    /// The GROSS reading, on a `measurement`. Null on every other event type.
    let measuredWeightG: Double?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case id, note
        case spoolId = "spool_id"
        case eventType = "event_type"
        case eventAt = "event_at"
        case measuredWeightG = "measured_weight_g"
    }

    /// The event type that carries a scale reading. Adjustments (`manual_adjust`)
    /// state a delta, not a weighing, and belong in no history of measurements.
    static let measurementType = "measurement"
}

/// `POST /api/v1/spools/{id}/measurements` response — the event row it wrote.
///
/// Only `meta` is decoded, and only because of `tara_missing`. The rest of the
/// event (ids, timestamps, status/location transitions) is FilaMan's history to
/// keep; SpoolKid re-reads the spool for anything it needs to display.
nonisolated struct FilaManMeasurementEvent: Codable, Equatable, Sendable {
    let meta: [String: FilaManJSONValue]?

    /// FilaMan sets this when a measurement was RECORDED but could not be
    /// APPLIED: with no `empty_spool_weight_g` on the spool and no
    /// `default_spool_weight_g` on its filament, there is no tara to subtract,
    /// so `measured_weight_g` cannot become a remaining weight.
    ///
    /// Probed live 2026-08-25 — `meta: {"tara_missing": true}`, status **200**,
    /// and `remaining_weight_g` unchanged at 750 across the call. Reachable
    /// only once a tara has been EXPLICITLY nulled: a create that names no
    /// `empty_spool_weight_g` is defaulted to 250 g by the server.
    var taraMissing: Bool {
        if case .bool(true) = meta?["tara_missing"] { return true }
        return false
    }
}
