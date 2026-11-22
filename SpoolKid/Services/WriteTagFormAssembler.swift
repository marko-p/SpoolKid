import Foundation

/// What the Write Tag form's rich rows start as for a piece of tag data. An
/// absent value is 0, "" or nil, which is each row's own empty state.
nonisolated struct WriteTagPrefill: Equatable, Sendable {
    let nominalWeight: Int
    let emptyWeight: Int
    /// Nil is a full spool; 0 is an empty one.
    let remaining: Int?
    let density: String
    let diameter: String
    let preheat: Int
    let dryingTemp: Int
    let dryingTime: Int
    let gtin: String
    let country: String
    let manufactured: Date?
    let url: String
}

enum WriteTagFormAssembler {
    /// The format the write form opens on.
    ///
    /// Falls back to OpenSpool for an unknown raw value AND for a known one the
    /// app cannot write: the Settings.bundle picker lists every format because
    /// it also governs reads, so a read-only format could be the stored
    /// default. Landing on it here would open the form on a format missing
    /// from its own picker. (ELEGOO was that format until 2026-10-05.)
    ///
    /// `recordedFormat` is the format a Recent Tag was written in, when the
    /// user keeps Recent Tags in their format; it wins over the default
    /// whenever it can still be written.
    static func initialOverride(defaultRawValue: String, recordedFormat: TagFormat? = nil) -> TagFormat {
        if let recordedFormat, recordedFormat.canWrite { return recordedFormat }
        guard let format = TagFormat(rawValue: defaultRawValue), format.canWrite else {
            return .openSpool
        }
        return format
    }

    /// The line under the ELEGOO form's Canvas filament picker: what the
    /// printer will read, or — with nothing picked, and Write disabled — why.
    static func elegooFilamentCaption(entry: ElegooCanvasCatalog.Entry?, material: String) -> String {
        if let entry {
            return "The Canvas reads this as ELEGOO \(entry.name). ELEGOO tags hold no brand or name — SpoolKid still links the tag to your spool."
        }
        let material = material.trimmingCharacters(in: .whitespaces)
        return material.isEmpty
            ? "Pick a Canvas filament."
            : "Pick a Canvas filament — \u{201C}\(material)\u{201D} has no Canvas equivalent."
    }

    static func visibleFields(
        format: TagFormat,
        visibilityStore: NFCFieldVisibilityStore = .init()
    ) -> [NFCFieldDefinition] {
        let visibleFieldIDs = visibilityStore.visibleFieldIDs(for: format)
        return NFCFieldCatalog.fields(for: format).filter { visibleFieldIDs.contains($0.id) }
    }

    static func shouldShowNameField(
        visibleFieldIDs: Set<String>
    ) -> Bool {
        visibleFieldIDs.contains("name")
    }

    /// What an ACE tag's SKU field starts as.
    ///
    /// `SM<id>` wherever the spool's ID is one a SpoolLink client can resolve,
    /// because on ACE hardware the SKU is the only thing that identifies a
    /// spool — the reader reports no UID (issue #5). It is a default, not an
    /// option: the form still lets the user type a name over it, but they have
    /// to choose the name rather than remember to choose the ID.
    ///
    /// The filament name otherwise.
    ///
    /// Owner, 2026-10-09: the ACE unit shows the printer only the tag's
    /// contents, never its UID, so the SKU carries `SM<id>` in every identity
    /// mode — unlike OpenSpool's `spool_id`, which only Spool ID mode writes.
    static func defaultACESKU(
        name: String,
        spoolID: Int?,
        spoolIDsResolveViaSpoolLink: Bool
    ) -> String {
        guard spoolIDsResolveViaSpoolLink, let spoolID else { return name }
        return SpoolLinkSKU.sku(forSpoolID: spoolID)
    }

    /// Why a pre-filled spool ID no longer names the spool its data was
    /// written for. Recent Tags and a re-written scanned tag carry the ID from
    /// when they were made; deleting that spool frees the ID, FilaMan hands it
    /// to the next spool created, and writing it unchecked linked the new tag
    /// to that stranger (device report, 2026-10-03).
    nonisolated enum StaleSpoolID: Equatable, Sendable {
        /// No spool has this ID — deleted, or the data came from another backend.
        case notFound(id: Int)
        /// The ID belongs to a spool of a different filament now.
        case changed(id: Int, nowHolds: String)

        /// The Recent Tags row's badge.
        var badge: String {
            switch self {
            case .notFound: "spool not found"
            case .changed: "spool changed"
            }
        }

        /// The Write Tag form's explanation, once the ID has been cleared.
        var note: String {
            switch self {
            case .notFound(let id):
                "Spool #\(id) wasn't found. The Spool ID was cleared, so this tag won't be linked to a spool."
            case .changed(let id, let nowHolds):
                "Spool #\(id) now holds a different filament (\(nowHolds)). The Spool ID was cleared, "
                    + "so this tag won't be linked to a spool."
            }
        }
    }

    /// `nil` when the data carries no spool ID, when the ID still names a spool
    /// of the same filament — the hub's "tag differs" rule, so material, colour
    /// and brand, never the name — or when the list is empty: before the first
    /// fetch lands, "no spool has this ID" is not yet known.
    static func staleSpoolID(in data: FilamentTagData, spools: [Spool]) -> StaleSpoolID? {
        guard let id = data.spoolmanId, !spools.isEmpty else { return nil }
        guard let spool = spools.first(where: { $0.id == id }) else { return .notFound(id: id) }
        guard HubActionPlan.tagDiffers(tagData: data, filament: spool.filament) else { return nil }
        return .changed(id: id, nowHolds: spool.filament.listTitle)
    }

    /// What a format's spool-ID field gets: OpenSpool's `spool_id`, in Spool ID
    /// mode only. ACE carries the ID in the SKU instead (`defaultACESKU`), and
    /// the other formats — TigerTag among them — have no ID field: the spool
    /// link is `card_uids`' job.
    static func spoolIDToWrite(format: TagFormat, spoolID: Int?, writeSpoolID: Bool) -> Int? {
        format == .openSpool && writeSpoolID ? spoolID : nil
    }

    /// The form's rows for `data`: what a spool, filament, scanned tag or
    /// Recent Tag already says. A tag's numbers are untrusted, so a weight no
    /// `Int` can hold reads as not stated rather than trapping.
    static func prefill(from data: FilamentTagData) -> WriteTagPrefill {
        func wholeGrams(_ value: Double?) -> Int {
            guard let stated = FilamentTagData.statedMeasurement(value),
                  let whole = Int(exactly: stated.rounded()) else { return 0 }
            return whole
        }
        func decimalText(_ value: Double?) -> String {
            guard let stated = FilamentTagData.statedMeasurement(value), stated.isFinite else { return "" }
            return String(format: "%g", stated)
        }
        // A tag that states only an actual weight still has a full weight, so
        // rewriting it keeps its consumption.
        let fullWeight = FilamentTagData.statedMeasurement(data.nominalNetWeight)
            ?? FilamentTagData.statedMeasurement(data.actualNetWeight)
        return WriteTagPrefill(
            nominalWeight: wholeGrams(fullWeight),
            emptyWeight: wholeGrams(data.emptyContainerWeight),
            remaining: data.remainingOnTag.flatMap { Int(exactly: $0.rounded()) },
            density: decimalText(data.density),
            diameter: decimalText(data.diameter),
            preheat: data.preheatTemp ?? 0,
            dryingTemp: data.dryingTemp ?? 0,
            dryingTime: data.dryingTime ?? 0,
            gtin: data.gtin ?? "",
            country: data.countryOfOrigin ?? "",
            manufactured: data.manufacturedDateUnix.flatMap { date(fromUnixSeconds: $0) },
            url: data.tagURL ?? ""
        )
    }

    /// A decimal the user typed into the form: a comma counts as the decimal
    /// separator. Nil unless it is a finite number above zero, which is what
    /// "stated" means everywhere a tag's measurements are concerned.
    nonisolated static func statedDecimal(_ text: String) -> Double? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")),
              value.isFinite, value > 0 else { return nil }
        return value
    }

    /// The rows that stop a Prusa printer counting this tag down, in form
    /// order: each of Net Weight, Density and Diameter that is hidden or not a
    /// stated number above zero. The printer needs all three to turn grams
    /// into filament length, and SpoolKid never substitutes a default for
    /// any of them. Density and diameter are parsed as the write path parses
    /// them, so a comma counts as the decimal separator.
    static func countdownBlockers(
        visibleFieldIDs: Set<String>, nominalWeight: Int, density: String, diameter: String
    ) -> [String] {
        var blockers: [String] = []
        if !visibleFieldIDs.contains("nominal_weight") || nominalWeight <= 0 { blockers.append("Net Weight") }
        if !visibleFieldIDs.contains("density") || statedDecimal(density) == nil { blockers.append("Density") }
        if !visibleFieldIDs.contains("diameter") || statedDecimal(diameter) == nil { blockers.append("Diameter") }
        return blockers
    }

    /// The data a spool's own write puts on a tag outside the write screen
    /// (the spool form's Write Tag) — the same rules `buildTagData` applies.
    static func spoolWriteData(
        for spool: Spool, format: TagFormat, writesSpoolID: Bool, spoolIDsResolveViaSpoolLink: Bool,
        writesOpacity: Bool = false
    ) -> FilamentTagData {
        var data = FilamentTagData.from(spool: spool)
        if format == .anycubicACE {
            data.name = defaultACESKU(
                name: data.name ?? "", spoolID: spool.id, spoolIDsResolveViaSpoolLink: spoolIDsResolveViaSpoolLink
            )
        }
        // ELEGOO writes a Canvas filament, never the spool's free text: the
        // one Write Tag would suggest (issue #14). With none, the encoder
        // refuses and `NFCManager.writeRefusal` says so before the session.
        if format == .elegoo {
            if let entry = ElegooCanvasCatalog.suggestedEntry(material: data.material, subtype: data.subtype) {
                let fields = ElegooCanvasCatalog.tagFields(for: entry)
                data.material = fields.material
                data.subtype = fields.subtype
            }
            data.name = nil
            data.brand = "ELEGOO"
        }
        data.spoolmanId = spoolIDToWrite(format: format, spoolID: spool.id, writeSpoolID: writesSpoolID)
        // Only OpenPrintTag has a consumed-weight field (as in `buildTagData`).
        if format != .openPrintTag { data.consumedWeight = nil }
        data.colorAlpha = FilamentOpacity.alphaToWrite(
            td: data.transmissionDistance, carried: nil, format: format, enabled: writesOpacity
        )
        return data
    }

    static func buildTagData(
        format: TagFormat,
        name: String,
        /// The ACE SKU as the form shows it. The name field IS the SKU on an
        /// ACE tag, so this replaces `name` there and is ignored elsewhere.
        sku: String? = nil,
        material: String,
        subtype: String,
        brand: String,
        colorHex: String,
        /// The colors after the first, for a multi-color tag.
        additionalColorHexes: [String]? = nil,
        minNozzleTemp: Int,
        maxNozzleTemp: Int,
        minBedTemp: Int,
        maxBedTemp: Int,
        spoolmanId: Int?,
        writeSpoolID: Bool,
        preheatTemp: Int? = nil,
        nominalNetWeight: Double? = nil,
        emptyContainerWeight: Double? = nil,
        density: Double? = nil,
        diameter: Double? = nil,
        dryingTemp: Int? = nil,
        dryingTime: Int? = nil,
        gtin: String? = nil,
        countryOfOrigin: String? = nil,
        manufacturedDateUnix: Int? = nil,
        tagURL: String? = nil,
        /// Grams left on the spool, in OpenPrintTag's Remaining row. Nil is a
        /// full spool; the printer counts down from the difference.
        remainingWeight: Int? = nil,
        /// The filament's TD. The form has no row for it: it comes with the
        /// data the form opened on.
        transmissionDistance: Double? = nil,
        /// The alpha that data carried, for a tag rewritten with no TD.
        carriedAlpha: Int? = nil,
        writesOpacity: Bool = false
    ) -> FilamentTagData {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSKU = (sku ?? name).trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSubtype = subtype.trimmingCharacters(in: .whitespacesAndNewlines)

        let nameToWrite: String? = switch format {
        case .anycubicACE:
            normalizedSKU.isEmpty ? nil : normalizedSKU
        case .openSpool, .openPrintTag, .openTag3D, .tigerTag:
            normalizedName.isEmpty ? nil : normalizedName
        case .elegoo:
            // The block has no name field.
            nil
        }

        let subtypeToWrite: String? = switch format {
        case .openSpool, .openTag3D, .tigerTag, .elegoo:
            // ELEGOO's is the Canvas subtype, page 19 of the tag.
            normalizedSubtype.isEmpty ? nil : normalizedSubtype
        case .openPrintTag, .anycubicACE:
            nil
        }

        // Nor a brand field: every ELEGOO tag reads back as ELEGOO, so the
        // record of what was written says so too.
        let brandToWrite = format == .elegoo ? "ELEGOO" : brand

        let spoolIdToWrite = spoolIDToWrite(format: format, spoolID: spoolmanId, writeSpoolID: writeSpoolID)

        return FilamentTagData(
            name: nameToWrite,
            material: material,
            subtype: subtypeToWrite,
            brand: brandToWrite,
            colorHex: colorHex,
            additionalColorHexes: additionalColorHexes,
            minNozzleTemp: minNozzleTemp,
            maxNozzleTemp: maxNozzleTemp,
            minBedTemp: minBedTemp,
            maxBedTemp: maxBedTemp,
            spoolmanId: spoolIdToWrite,
            density: density,
            diameter: diameter,
            transmissionDistance: transmissionDistance,
            gtin: gtin,
            manufacturedDateUnix: manufacturedDateUnix,
            countryOfOrigin: countryOfOrigin,
            preheatTemp: preheatTemp,
            dryingTemp: dryingTemp,
            dryingTime: dryingTime,
            nominalNetWeight: nominalNetWeight,
            actualNetWeight: nil,
            emptyContainerWeight: emptyContainerWeight,
            tagURL: tagURL,
            consumedWeight: format == .openPrintTag
                ? FilamentTagData.consumption(fullWeight: nominalNetWeight, remaining: remainingWeight.map(Double.init))
                : nil,
            colorAlpha: FilamentOpacity.alphaToWrite(
                td: transmissionDistance, carried: carriedAlpha, format: format, enabled: writesOpacity
            )
        )
    }

    static func unixSeconds(from date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded())
    }

    static func date(fromUnixSeconds unix: Int) -> Date? {
        guard unix >= 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(unix))
    }
}
