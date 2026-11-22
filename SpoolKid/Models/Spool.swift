//
//  Spool.swift
//  SpoolKid
//
//  Purpose: Data models reflecting the JSON structure returned by the Spoolman API.
//  Contains:
//  - `Spool`: Represents a physical spool instance.
//  - `Filament`: Represents a filament definition (type, color, vendor).
//  - `Vendor`: Represents a manufacturer.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation

/// One entry of Spoolman 0.27's `tags` array. Only the UID is read: `format`
/// is informational and `added` is shown nowhere.
nonisolated struct SpoolmanTag: Codable, Equatable, Sendable {
    let uid: String

    /// Normalised, de-duplicated, empty entries dropped.
    static func normalizedUIDs(_ tags: [SpoolmanTag]?) -> [String] {
        var seen = Set<String>()
        return (tags ?? [])
            .map { SpoolMappingService.normalizeUID($0.uid) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

struct Spool: Codable, Identifiable, Sendable {
    let id: Int
    let filament: Filament
    let registered: Date?
    let firstUsed: Date?
    let lastUsed: Date?
    let remainingWeight: Double?
    let initialWeight: Double?
    let spoolWeight: Double?
    let usedWeight: Double?
    let price: Double?
    let location: String?
    /// The Lot/Batch field. Plain text: since 2026-10-11 a `card_uid:` token
    /// in it is not a tag link (`mappedCardUIDs` lists the links).
    let lotNr: String?
    let comment: String?
    let archived: Bool?
    let extra: [String: String]?
    /// FilaMan's native tag binding, read-only. Nil on every other backend, so
    /// `mappedCardUIDs` can union it unconditionally.
    let rfidUID: String?
    /// Whether `rfidUID` is writable: true while FilaMan Tags is on, read-only
    /// otherwise (2026-11-03). Set when the spool is mapped from the switch;
    /// never encoded, because the switch lives on this device, not on the server.
    var rfidUIDWritable: Bool = false
    /// FilaMan only; nil on Spoolman and the on-device Library.
    let statusId: Int?
    let externalId: String?
    let purchaseDate: Date?
    /// Spoolman 0.27+'s native tag links. Nil on older servers and on every
    /// other backend. Read through `nativeTagUIDs`.
    let tags: [SpoolmanTag]?

    init(
        id: Int,
        filament: Filament,
        registered: Date? = nil,
        firstUsed: Date? = nil,
        lastUsed: Date? = nil,
        remainingWeight: Double? = nil,
        initialWeight: Double? = nil,
        spoolWeight: Double? = nil,
        usedWeight: Double? = nil,
        price: Double? = nil,
        location: String? = nil,
        lotNr: String? = nil,
        comment: String? = nil,
        archived: Bool? = nil,
        extra: [String: String]? = nil,
        rfidUID: String? = nil,
        // No default: every call site should state, deliberately, what a
        // FilaMan-only field is on a fixture that has no FilaMan behind it
        // (usually `nil`) rather than have that fall out of an omission.
        statusId: Int?,
        externalId: String?,
        purchaseDate: Date?,
        // A default is right here, unlike the FilaMan-only fields above: an
        // absent key and an empty list mean the same thing.
        nativeTagUIDs: [String] = [],
        rfidUIDWritable: Bool = false
    ) {
        self.id = id
        self.filament = filament
        self.registered = registered
        self.firstUsed = firstUsed
        self.lastUsed = lastUsed
        self.remainingWeight = remainingWeight
        self.initialWeight = initialWeight
        self.spoolWeight = spoolWeight
        self.usedWeight = usedWeight
        self.price = price
        self.location = location
        self.lotNr = lotNr
        self.comment = comment
        self.archived = archived
        self.extra = extra
        self.rfidUID = rfidUID
        self.rfidUIDWritable = rfidUIDWritable
        self.statusId = statusId
        self.externalId = externalId
        self.purchaseDate = purchaseDate
        self.tags = nativeTagUIDs.isEmpty ? nil : nativeTagUIDs.map(SpoolmanTag.init(uid:))
    }

    enum CodingKeys: String, CodingKey {
        case id
        case filament
        case registered
        case firstUsed = "first_used"
        case lastUsed = "last_used"
        case remainingWeight = "remaining_weight"
        case initialWeight = "initial_weight"
        case spoolWeight = "spool_weight"
        case usedWeight = "used_weight"
        case price
        case location
        case lotNr = "lot_nr"
        case comment
        case archived
        case extra
        case rfidUID = "rfid_uid"
        case statusId = "status_id"
        case externalId = "external_id"
        case purchaseDate = "purchase_date"
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        filament = try container.decode(Filament.self, forKey: .filament)
        registered = try container.decodeFlexibleDateIfPresent(forKey: .registered)
        firstUsed = try container.decodeFlexibleDateIfPresent(forKey: .firstUsed)
        lastUsed = try container.decodeFlexibleDateIfPresent(forKey: .lastUsed)
        remainingWeight = try container.decodeIfPresent(Double.self, forKey: .remainingWeight)
        initialWeight = try container.decodeIfPresent(Double.self, forKey: .initialWeight)
        spoolWeight = try container.decodeIfPresent(Double.self, forKey: .spoolWeight)
        usedWeight = try container.decodeIfPresent(Double.self, forKey: .usedWeight)
        price = try container.decodeIfPresent(Double.self, forKey: .price)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        lotNr = try container.decodeIfPresent(String.self, forKey: .lotNr)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived)
        extra = try container.decodeIfPresent([String: String].self, forKey: .extra)
        // Spoolman payloads carry no `rfid_uid`/`status_id`/`external_id`/
        // `purchase_date` keys at all — decodeIfPresent keeps that path
        // decoding rather than throwing on a missing key.
        rfidUID = try container.decodeIfPresent(String.self, forKey: .rfidUID)
        statusId = try container.decodeIfPresent(Int.self, forKey: .statusId)
        externalId = try container.decodeIfPresent(String.self, forKey: .externalId)
        // `purchase_date` is a CALENDAR day, not an instant — unlike
        // registered/firstUsed/lastUsed above, it goes through
        // `CalendarDateCodec`, the same codec `FilaManRepository.mapSpool`
        // uses, so the field has one interpretation wherever it arrives
        // (Codable here, `mapSpool` there). Spoolman never sends this key
        // today, so this path is unreachable in live traffic — it exists so
        // the two never drift apart again the way `ddd35d8` had to fix.
        purchaseDate = try container.decodeCalendarDateIfPresent(forKey: .purchaseDate)
        // Spoolman 0.27+ only; older servers and the other backends send no key.
        tags = try container.decodeIfPresent([SpoolmanTag].self, forKey: .tags)
    }
}

private extension KeyedDecodingContainer where K == Spool.CodingKeys {
    func decodeFlexibleDateIfPresent(forKey key: K) throws -> Date? {
        guard contains(key) else {
            return nil
        }

        if try decodeNil(forKey: key) {
            return nil
        }

        if let secondsSince1970 = try? decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: secondsSince1970)
        }

        let value: String
        do {
            value = try decode(String.self, forKey: key)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Expected date to be a Unix timestamp or ISO8601 string."
            )
        }

        // String forms are `FlexibleDateParser`'s to decide (A4). Unix seconds
        // stay here: they are a *decoding* concern — which JSON type the key
        // holds — not a question about the shape of a timestamp string.
        guard let date = FlexibleDateParser.date(from: value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Invalid date string: \(value)"
            )
        }
        return date
    }

    /// `purchase_date`-only counterpart to `decodeFlexibleDateIfPresent`
    /// above: reads a calendar day through `CalendarDateCodec`, the same
    /// codec `FilaManRepository.mapSpool` uses, instead of treating the
    /// string as a UTC instant. Unreachable today — Spoolman never sends
    /// `purchase_date` — but kept in step so a future sender doesn't
    /// reintroduce the day-shift `ddd35d8` fixed.
    func decodeCalendarDateIfPresent(forKey key: K) throws -> Date? {
        guard contains(key) else {
            return nil
        }

        if try decodeNil(forKey: key) {
            return nil
        }

        let value = try decode(String.self, forKey: key)
        guard let date = CalendarDateCodec.date(from: value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Invalid calendar date string: \(value)"
            )
        }
        return date
    }
}

struct Filament: Codable, Identifiable, Sendable {
    let id: Int
    let name: String?
    let material: String?
    let vendor: Vendor?
    let price: Double?
    let colorHex: String?
    let density: Double?
    let diameter: Double?
    let weight: Double?
    let spoolWeight: Double?
    let articleNumber: String?
    let comment: String?
    let settingsExtruderTemp: Int?
    let settingsBedTemp: Int?
    let multiColorHexes: String?
    let multiColorDirection: String?
    let externalId: String?
    let extra: [String: String]?
    /// Spoolman 0.27+'s tags on the filament type itself. Read through
    /// `nativeTagUIDs`.
    let tags: [SpoolmanTag]?

    init(
        id: Int,
        name: String? = nil,
        material: String? = nil,
        vendor: Vendor? = nil,
        price: Double? = nil,
        colorHex: String? = nil,
        density: Double? = nil,
        diameter: Double? = nil,
        weight: Double? = nil,
        spoolWeight: Double? = nil,
        articleNumber: String? = nil,
        comment: String? = nil,
        settingsExtruderTemp: Int? = nil,
        settingsBedTemp: Int? = nil,
        multiColorHexes: String? = nil,
        multiColorDirection: String? = nil,
        externalId: String? = nil,
        extra: [String: String]? = nil,
        nativeTagUIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.material = material
        self.vendor = vendor
        self.price = price
        self.colorHex = colorHex
        self.density = density
        self.diameter = diameter
        self.weight = weight
        self.spoolWeight = spoolWeight
        self.articleNumber = articleNumber
        self.comment = comment
        self.settingsExtruderTemp = settingsExtruderTemp
        self.settingsBedTemp = settingsBedTemp
        self.multiColorHexes = multiColorHexes
        self.multiColorDirection = multiColorDirection
        self.externalId = externalId
        self.extra = extra
        self.tags = nativeTagUIDs.isEmpty ? nil : nativeTagUIDs.map(SpoolmanTag.init(uid:))
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case material
        case vendor
        case price
        case colorHex = "color_hex"
        case density
        case diameter
        case weight
        case spoolWeight = "spool_weight"
        case articleNumber = "article_number"
        case comment
        case settingsExtruderTemp = "settings_extruder_temp"
        case settingsBedTemp = "settings_bed_temp"
        case multiColorHexes = "multi_color_hexes"
        case multiColorDirection = "multi_color_direction"
        case externalId = "external_id"
        case extra
        case tags
    }
}

extension Filament {
    /// The filament's HueForge TD, from `extra["td"]` — where the Library and
    /// Spoolman store it and where FilaMan's mapper puts `custom_fields["td"]`.
    nonisolated var transmissionDistance: Double? {
        TransmissionDistance.decode(extra?[TransmissionDistance.fieldKey])
    }

    /// UIDs Spoolman 0.27+ links to this filament type itself. A tag here
    /// belongs to no spool (spec 4).
    nonisolated var nativeTagUIDs: [String] { SpoolmanTag.normalizedUIDs(tags) }

    /// The on-device Library's filament links (spec 4), kept in
    /// `extra["card_uids"]` like a spool's. Empty on a server.
    nonisolated var cardUIDs: [String] { CardUIDsCodec.parse(extra?[CardUIDsCodec.fieldKey]) }

    /// Every UID linked to this filament: native tags first, then the
    /// Library's `card_uids`. Normalized, each once.
    nonisolated var mappedTagUIDs: [String] {
        var seen = Set<String>()
        return (nativeTagUIDs + cardUIDs).filter { seen.insert($0).inserted }
    }

    nonisolated var variant: String {
        if let v = extra?["variant"], !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return v.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let v = extra?["subtype"], !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return v.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let n = name {
            return SubtypeOptionService.derive(from: n)
        }
        return "Basic"
    }

    /// Diameter formatted for list rows, e.g. "1.75 mm". Nil when unset.
    nonisolated var diameterText: String? {
        diameter.map { String(format: "%.2f mm", $0) }
    }

    /// Net filament weight formatted for list rows, e.g. "1000 g". Nil when unset.
    var weightText: String? {
        weight.map { String(format: "%.0f g", $0) }
    }

    /// Headline for list rows: brand (vendor) followed by the filament name.
    nonisolated var listTitle: String {
        let parts = [vendor?.name, name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Unknown" : parts.joined(separator: " ")
    }

    /// The single detail row beneath the title: material, variant, diameter,
    /// weight. Empty/unset fields are omitted.
    var listSpecParts: [String] {
        var parts: [String] = []
        if let material, !material.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(material)
        }
        parts.append(variant)
        if let diameterText { parts.append(diameterText) }
        if let weightText { parts.append(weightText) }
        return parts
    }
}

extension Spool {
    /// SpoolLink card UIDs decoded from `extra["card_uids"]`.
    /// Empty when the field is missing, nil, or empty.
    nonisolated var cardUIDs: [String] {
        CardUIDsCodec.parse(extra?["card_uids"])
    }

    /// UIDs linked to this spool as Spoolman 0.27+ native tags. Empty on older
    /// servers and on every other backend. Reading them needs no version
    /// check: the key is simply absent where the feature is.
    nonisolated var nativeTagUIDs: [String] { SpoolmanTag.normalizedUIDs(tags) }

    /// The UIDs a mapping write may carry back: `rfidUID` first while it is
    /// writable (FilaMan Tags on), then Spoolman's native tags, then
    /// `card_uids`, normalized and de-duplicated. While FilaMan Tags is off,
    /// `rfidUID` is never in this list: it is FilaMan's hardware binding and
    /// SpoolKid must not copy it into `card_uids`. On a 0.27 server a
    /// `setCardUIDs` write unlinks every native tag missing from its list, so
    /// a list built from `cardUIDs` alone would drop a native tag `card_uids`
    /// does not mirror (final review P-1).
    ///
    /// Every write that puts a spool's own list back (plus or minus a UID)
    /// starts here, never from `mappedCardUIDs`, which carries `rfidUID` and
    /// copied it as a side effect (I1). Lived on `TagLinkService` until the
    /// final review of 2026-09-28 found `unlinkTag` and the spool form still
    /// writing `mappedCardUIDs` back (FR-2). Spoolman's native tags come
    /// first: a native link wins every read.
    nonisolated var writableCardUIDs: [String] {
        var seen = Set<String>()
        var result: [String] = []
        var candidates = nativeTagUIDs + cardUIDs
        if rfidUIDWritable, let rfidUID {
            let normalized = SpoolMappingService.normalizeUID(rfidUID)
            if !normalized.isEmpty { candidates.insert(normalized, at: 0) }
        }
        for uid in candidates where seen.insert(uid).inserted {
            result.append(uid)
        }
        return result
    }

    /// UIDs that resolve to this spool and that **no write path can remove**:
    /// FilaMan's `rfid_uid` while it is read-only (FilaMan Tags off). A detach
    /// aimed at it returns 200 and changes nothing — the tag stays mapped here.
    /// While FilaMan Tags is on (2026-11-03) `rfid_uid` is writable, so it is
    /// not reported here.
    ///
    /// Note this is not "UIDs missing from `card_uids`": a UID present in BOTH
    /// `card_uids` and `rfid_uid` is still undetachable, because removing the
    /// first copy leaves the second resolving.
    ///
    /// Callers use it to REPORT, never to write.
    nonisolated var undetachableCardUIDs: [String] {
        guard !rfidUIDWritable, let rfidUID else { return [] }
        let normalized = SpoolMappingService.normalizeUID(rfidUID)
        return normalized.isEmpty ? [] : [normalized]
    }

    /// All card UIDs that resolve to this spool: Spoolman's native tags, the
    /// SpoolLink `card_uids` set and FilaMan's own `rfid_uid` (nil on every
    /// other backend). Deduped, in that order — Spoolman's native tags come
    /// first: a native link wins every read. A `card_uid:` token in `lotNr`
    /// is not one of them (2026-10-11).
    ///
    /// `rfid_uid` is WRITABLE while FilaMan Tags is on (2026-11-03) and
    /// read-only otherwise. Native tags and `card_uids` are always writable.
    /// A caller that writes this list back while `rfid_uid` is read-only would
    /// copy it into `card_uids`; writes start from `writableCardUIDs` instead.
    ///
    /// The consequence that bites is REMOVAL: while `rfid_uid` is read-only,
    /// dropping it from this list and writing the rest cannot un-map it. Ask
    /// `undetachableCardUIDs` before reporting a detach as done.
    nonisolated var mappedCardUIDs: [String] {
        var result = writableCardUIDs
        if let rfidUID {
            let normalized = SpoolMappingService.normalizeUID(rfidUID)
            if !normalized.isEmpty, !result.contains(normalized) { result.append(normalized) }
        }
        return result
    }

    /// Recency ordering key: the spool's last-used date, or its registration
    /// date when never used (`COALESCE(last_used, registered)`). Nil only when
    /// Spoolman returns neither.
    nonisolated var recencyDate: Date? {
        lastUsed ?? registered
    }

    /// Headline for list rows: the filament's brand + name, falling back to the
    /// spool id when the filament has neither.
    nonisolated var listTitle: String {
        let title = filament.listTitle
        return title == "Unknown" ? "Spool #\(id)" : title
    }

    /// Remaining filament weight formatted for list rows, e.g. "850 g". Nil when unset.
    nonisolated var remainingWeightText: String? {
        remainingWeight.map { String(format: "%.0f g", $0) }
    }

    /// The single detail row beneath a spool's title (brand + name): id, the
    /// filament specs, remaining weight, location, and the mapped-tag count.
    /// Empty/unset fields (and a zero tag count) are omitted.
    nonisolated var listDetailParts: [String] { listDetailParts(includingLocation: true) }

    /// `includingLocation: false` is for a row rendered UNDER its location's
    /// own header, where repeating the shelf is noise. One formatter, one
    /// suppression flag — not a second parts array.
    nonisolated func listDetailParts(includingLocation: Bool) -> [String] {
        var parts = ["#\(id)"]
        if let material = filament.material, !material.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(material)
        }
        parts.append(filament.variant)
        if let diameterText = filament.diameterText { parts.append(diameterText) }
        if let remainingWeightText { parts.append(remainingWeightText) }
        if includingLocation,
           let location = location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            parts.append(location)
        }
        let tagCount = mappedCardUIDs.count
        if tagCount > 0 {
            parts.append("Tags: \(tagCount)")
        }
        return parts
    }
}

struct Vendor: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let comment: String?
    let emptySpoolWeight: Double?
    let externalId: String?
    let extra: [String: String]?

    init(
        id: Int,
        name: String,
        comment: String? = nil,
        emptySpoolWeight: Double? = nil,
        externalId: String? = nil,
        extra: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.comment = comment
        self.emptySpoolWeight = emptySpoolWeight
        self.externalId = externalId
        self.extra = extra
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case comment
        case emptySpoolWeight = "empty_spool_weight"
        case externalId = "external_id"
        case extra
    }
}
