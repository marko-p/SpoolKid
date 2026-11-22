//
//  FilaManMappingTests.swift
//  SpoolKidTests
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct FilaManMappingTests {
    /// `grossInitial` is FilaMan's `initial_total_weight_g` — filament PLUS the
    /// empty spool (F31). The default pair (1250 gross on a 250 g core) is a
    /// 1 kg NET spool, so every expectation below reads in net grams.
    private func makeFilaManSpool(
        statusId: Int = 1,
        locationId: Int? = nil,
        customFields: [String: FilaManJSONValue]? = nil,
        rfidUid: String? = nil,
        grossInitial: Double? = 1250,
        emptySpool: Double? = 250,
        remaining: Double? = 400
    ) -> FilaManSpool {
        FilaManSpool(
            id: 40, filamentId: 177, statusId: statusId, lotNumber: "LOT-1",
            rfidUid: rfidUid, externalId: nil, locationId: locationId,
            purchaseDate: nil, purchasePrice: 19.99, stockedInAt: nil, lastUsedAt: nil,
            initialTotalWeightG: grossInitial, emptySpoolWeightG: emptySpool,
            remainingWeightG: remaining, createdAt: nil, customFields: customFields
        )
    }

    private let filament = Filament(
        id: 177, name: "White", material: "PLA", vendor: nil, price: 19.99,
        colorHex: "3f3f3f", density: 1.24, diameter: 1.75, weight: 1000,
        spoolWeight: 250, articleNumber: nil, comment: nil,
        settingsExtruderTemp: nil, settingsBedTemp: nil,
        multiColorHexes: nil, multiColorDirection: nil, externalId: nil, extra: nil
    )

    // MARK: - F31: initial_total_weight_g is GROSS, Spool.initialWeight is NET
    //
    // Owner-corrected 2026-08-21 and proven live. `remaining_weight_g` is net
    // on both sides; only `initial` needed converting. These fixtures are the
    // only guard against a regression — every spool on the owner's own
    // instance carries an empty spool weight of 0 or null, which makes the
    // whole conversion invisible there.

    @Test func mapsInitialTotalWeightAsGrossMinusTheEmptySpool() {
        let spool = FilaManRepository.mapSpool(makeFilaManSpool(), filament: filament, locationsById: [:])

        #expect(spool.initialWeight == 1000)
        #expect(spool.remainingWeight == 400)
        #expect(spool.spoolWeight == 250)
    }

    @Test func mapSpoolCarriesTheWritableFlag() {
        let writable = FilaManRepository.mapSpool(
            makeFilaManSpool(rfidUid: "045d7774ce2a81"), filament: filament, locationsById: [:], rfidWritable: true
        )
        let readOnly = FilaManRepository.mapSpool(
            makeFilaManSpool(rfidUid: "045d7774ce2a81"), filament: filament, locationsById: [:]
        )
        #expect(writable.rfidUIDWritable)
        #expect(!readOnly.rfidUIDWritable)
    }

    @Test func mapSpoolsCarriesTheWritableFlag() {
        let spools = FilaManRepository.mapSpools(
            [makeFilaManSpool(rfidUid: "045d7774ce2a81")], filaments: [filament], locationsById: [:], rfidWritable: true
        )
        #expect(spools.first?.rfidUIDWritable == true)
    }

    @Test func derivesUsedWeightFromTheNetInitialNotTheGrossOne() {
        let spool = FilaManRepository.mapSpool(makeFilaManSpool(), filament: filament, locationsById: [:])

        #expect(spool.usedWeight == 600)
    }

    /// The case that was wrong before F31: a spool nobody has printed from
    /// reported its own core as filament already consumed.
    @Test func anUntouchedSpoolOnANonZeroCoreReportsNothingUsed() {
        let spool = FilaManRepository.mapSpool(
            makeFilaManSpool(grossInitial: 1250, emptySpool: 250, remaining: 1000),
            filament: filament, locationsById: [:]
        )

        #expect(spool.initialWeight == 1000)
        #expect(spool.usedWeight == 0)
        #expect(DashboardStatsService.fillFraction(for: spool) == 1.0)
        #expect(DashboardStatsService.bucket(for: spool) == .full)
    }

    /// `empty_spool_weight_g` is nullable: a null means FilaMan tracks no core
    /// weight, not that the net initial is unknowable.
    @Test func aMissingEmptySpoolWeightTreatsTheGrossFigureAsNet() {
        let spool = FilaManRepository.mapSpool(
            makeFilaManSpool(grossInitial: 1000, emptySpool: nil, remaining: 1000),
            filament: filament, locationsById: [:]
        )

        #expect(spool.initialWeight == 1000)
        #expect(spool.usedWeight == 0)
    }

    @Test func netInitialWeightIsNilOnlyWhenThereIsNoGrossFigure() {
        #expect(FilaManRepository.netInitialWeight(gross: nil, emptySpool: 250) == nil)
        #expect(FilaManRepository.netInitialWeight(gross: 1250, emptySpool: 250) == 1000)
        #expect(FilaManRepository.netInitialWeight(gross: 1250, emptySpool: nil) == 1250)
    }

    @Test func usedWeightIsNilWhenEitherWeightIsMissing() {
        let spool = FilaManRepository.mapSpool(
            makeFilaManSpool(grossInitial: nil), filament: filament, locationsById: [:]
        )

        #expect(spool.usedWeight == nil)
    }

    @Test func fillFractionMatchesDashboardExpectation() {
        let spool = FilaManRepository.mapSpool(makeFilaManSpool(), filament: filament, locationsById: [:])

        // DashboardStatsService divides remaining by the NET initial;
        // 400/1000 = Low. On the pre-F31 gross basis this was 400/1250 = 0.32,
        // which is a whole bucket lower (Critical).
        #expect(DashboardStatsService.fillFraction(for: spool) == 0.4)
    }

    /// Read then write: what FilaMan reported must be what SpoolKid sends back.
    @Test func grossToNetToGrossRoundTripsWithoutDrift() {
        let mapped = FilaManRepository.mapSpool(makeFilaManSpool(), filament: filament, locationsById: [:])

        var draft = SpoolDraft()
        // A read-back round trip: the mapped values are `Double?`, and the
        // write side is a patch, so state them.
        draft.initialWeight = mapped.initialWeight.map { .set($0) } ?? .ignore
        draft.spoolWeight = mapped.spoolWeight.map { .set($0) } ?? .ignore
        let payload = FilaManPayloadBuilder.spoolPayload(from: draft, location: .ignore)

        #expect(payload["initial_total_weight_g"] as? Double == 1250)
        #expect(payload["empty_spool_weight_g"] as? Double == 250)
    }

    @Test func archivedStatusMapsToArchivedFlag() {
        let archived = FilaManRepository.mapSpool(
            makeFilaManSpool(statusId: FilaManSpoolStatus.archived),
            filament: filament, locationsById: [:]
        )
        let active = FilaManRepository.mapSpool(
            makeFilaManSpool(statusId: FilaManSpoolStatus.active),
            filament: filament, locationsById: [:]
        )

        #expect(archived.archived == true)
        #expect(active.archived == false)
    }

    @Test func resolvesLocationIdToName() {
        let spool = FilaManRepository.mapSpool(
            makeFilaManSpool(locationId: 3), filament: filament, locationsById: [3: "Shelf A"]
        )

        #expect(spool.location == "Shelf A")
    }

    @Test func unknownLocationIdMapsToNilRatherThanAPlaceholder() {
        let spool = FilaManRepository.mapSpool(
            makeFilaManSpool(locationId: 99), filament: filament, locationsById: [3: "Shelf A"]
        )

        #expect(spool.location == nil)
    }

    @Test func commentComesFromCustomFields() {
        let spool = FilaManRepository.mapSpool(
            makeFilaManSpool(customFields: ["comment": "top shelf"]),
            filament: filament, locationsById: [:]
        )

        #expect(spool.comment == "top shelf")
    }

    @Test func cardUIDsSurviveIntoExtraForTheCodec() {
        let spool = FilaManRepository.mapSpool(
            makeFilaManSpool(customFields: ["card_uids": "AABBCCDD,11223344"]),
            filament: filament, locationsById: [:]
        )

        #expect(spool.cardUIDs == ["AABBCCDD", "11223344"])
    }

    @Test func rfidUidJoinsMappedCardUIDsWithoutDuplicating() {
        let spool = FilaManRepository.mapSpool(
            makeFilaManSpool(customFields: ["card_uids": "AABBCCDD"], rfidUid: "04A1B2C3D4E5F6"),
            filament: filament, locationsById: [:]
        )

        #expect(spool.mappedCardUIDs == ["AABBCCDD", "04A1B2C3D4E5F6"])
    }

    @Test func rfidUidAlreadyInCardUIDsIsNotDuplicated() {
        let spool = FilaManRepository.mapSpool(
            makeFilaManSpool(customFields: ["card_uids": "AABBCCDD"], rfidUid: "aabbccdd"),
            filament: filament, locationsById: [:]
        )

        #expect(spool.mappedCardUIDs == ["AABBCCDD"])
    }

    // MARK: - Remaining Spool table rows (id, filament, price, lotNr, extra, rfidUID, dates)

    private func makeFilaManSpoolWithDates(
        createdAt: String? = nil,
        stockedInAt: String? = nil,
        lastUsedAt: String? = nil
    ) -> FilaManSpool {
        FilaManSpool(
            id: 41, filamentId: 177, statusId: FilaManSpoolStatus.active, lotNumber: "LOT-2",
            rfidUid: nil, externalId: nil, locationId: nil,
            purchaseDate: nil, purchasePrice: 24.5, stockedInAt: stockedInAt, lastUsedAt: lastUsedAt,
            initialTotalWeightG: 1000, emptySpoolWeightG: 250,
            remainingWeightG: 800, createdAt: createdAt, customFields: nil
        )
    }

    @Test func mapsIdAndFilamentPassthrough() {
        let spool = FilaManRepository.mapSpool(makeFilaManSpool(), filament: filament, locationsById: [:])

        #expect(spool.id == 40)
        #expect(spool.filament.id == filament.id)
    }

    @Test func mapsPriceFromPurchasePrice() {
        let spool = FilaManRepository.mapSpool(makeFilaManSpool(), filament: filament, locationsById: [:])

        #expect(spool.price == 19.99)
    }

    @Test func mapsLotNrFromLotNumber() {
        let spool = FilaManRepository.mapSpool(makeFilaManSpool(), filament: filament, locationsById: [:])

        #expect(spool.lotNr == "LOT-1")
    }

    @Test func extraCarriesCustomFieldsThrough() {
        let fields: [String: FilaManJSONValue] = ["comment": "top shelf", "card_uids": "AABBCCDD"]
        let spool = FilaManRepository.mapSpool(
            makeFilaManSpool(customFields: fields), filament: filament, locationsById: [:]
        )

        #expect(spool.extra == ["comment": "top shelf", "card_uids": "AABBCCDD"])
    }

    /// `custom_fields` is free-form: every record migrated from Spoolman
    /// carries `spoolman_id` as an **Int**, which the app's `[String: String]`
    /// `extra` map still has to render rather than drop.
    @Test func extraRendersNonStringCustomFieldValues() {
        let spool = FilaManRepository.mapSpool(
            makeFilaManSpool(customFields: ["spoolman_id": 43, "comment": "top shelf"]),
            filament: filament, locationsById: [:]
        )

        #expect(spool.extra == ["spoolman_id": "43", "comment": "top shelf"])
    }

    /// …but a non-string value under a key SpoolKid reads as text is not text.
    /// Coercing it would invent a comment the user never wrote.
    @Test func commentIsReadOnlyWhenItActuallyIsAString() {
        let spool = FilaManRepository.mapSpool(
            makeFilaManSpool(customFields: ["comment": 7]), filament: filament, locationsById: [:]
        )

        #expect(spool.comment == nil)
    }

    @Test func mapsRfidUidOntoSpool() {
        let spool = FilaManRepository.mapSpool(
            makeFilaManSpool(rfidUid: "04A1B2C3D4E5F6"), filament: filament, locationsById: [:]
        )

        #expect(spool.rfidUID == "04A1B2C3D4E5F6")
    }

    // MARK: - Date conversion (F18) — registered/firstUsed/lastUsed

    @Test func parsesTimestampWithTimezone() {
        // Live-server format, verified 2026-08-19.
        let spool = FilaManRepository.mapSpool(
            makeFilaManSpoolWithDates(createdAt: "2026-05-28T12:37:57Z"),
            filament: filament, locationsById: [:]
        )

        var expectedComponents = DateComponents()
        expectedComponents.year = 2026
        expectedComponents.month = 5
        expectedComponents.day = 28
        expectedComponents.hour = 12
        expectedComponents.minute = 37
        expectedComponents.second = 57
        expectedComponents.timeZone = TimeZone(identifier: "UTC")
        let expectedDate = Calendar(identifier: .iso8601).date(from: expectedComponents)

        #expect(spool.registered == expectedDate)
    }

    @Test func parsesTimestampWithoutTimezone() {
        // Task 12's fixture format — `.withInternetDateTime` alone rejects this.
        let spool = FilaManRepository.mapSpool(
            makeFilaManSpoolWithDates(stockedInAt: "2026-08-18T00:14:00"),
            filament: filament, locationsById: [:]
        )

        var expectedComponents = DateComponents()
        expectedComponents.year = 2026
        expectedComponents.month = 8
        expectedComponents.day = 18
        expectedComponents.hour = 0
        expectedComponents.minute = 14
        expectedComponents.second = 0
        expectedComponents.timeZone = TimeZone(identifier: "UTC")
        let expectedDate = Calendar(identifier: .iso8601).date(from: expectedComponents)

        #expect(spool.firstUsed == expectedDate)
    }

    @Test func parsesTimestampWithFractionalSecondsAndTimezone() {
        let spool = FilaManRepository.mapSpool(
            makeFilaManSpoolWithDates(lastUsedAt: "2026-05-28T12:37:57.250Z"),
            filament: filament, locationsById: [:]
        )

        #expect(spool.lastUsed != nil)
    }

    @Test func parsesTimestampWithFractionalSecondsAndNoTimezone() {
        let spool = FilaManRepository.mapSpool(
            makeFilaManSpoolWithDates(lastUsedAt: "2026-08-18T00:14:00.500"),
            filament: filament, locationsById: [:]
        )

        #expect(spool.lastUsed != nil)
    }

    @Test func nilDateStringMapsToNilDate() {
        let spool = FilaManRepository.mapSpool(makeFilaManSpoolWithDates(), filament: filament, locationsById: [:])

        #expect(spool.registered == nil)
        #expect(spool.firstUsed == nil)
        #expect(spool.lastUsed == nil)
    }

    @Test func garbageDateStringMapsToNilRatherThanThrowing() {
        let spool = FilaManRepository.mapSpool(
            makeFilaManSpoolWithDates(createdAt: "not-a-date"),
            filament: filament, locationsById: [:]
        )

        #expect(spool.registered == nil)
    }

    // MARK: - Filament table

    private func makeFilaManFilament(
        materialSubgroup: String? = "Silk",
        diameterMm: Double? = 1.75,
        rawMaterialWeightG: Double? = 1000,
        defaultSpoolWeightG: Double? = 250,
        price: Double? = 24.99,
        densityGCm3: Double? = 1.24,
        multiColorStyle: String? = "linear",
        customFields: [String: FilaManJSONValue]? = nil,
        colors: [FilaManColorSlot]? = nil
    ) -> FilaManFilament {
        FilaManFilament(
            id: 177, manufacturerId: 9, designation: "Galaxy Purple", materialType: "PLA",
            materialSubgroup: materialSubgroup, diameterMm: diameterMm,
            rawMaterialWeightG: rawMaterialWeightG, defaultSpoolWeightG: defaultSpoolWeightG,
            price: price, densityG_cm3: densityGCm3, colorMode: nil,
            multiColorStyle: multiColorStyle, customFields: customFields, colors: colors
        )
    }

    @Test func mapsFilamentScalarFields() {
        let mapped = FilaManRepository.mapFilament(makeFilaManFilament(), vendor: nil)

        #expect(mapped.id == 177)
        #expect(mapped.name == "Galaxy Purple")
        #expect(mapped.material == "PLA")
        #expect(mapped.density == 1.24)
        #expect(mapped.diameter == 1.75)
        #expect(mapped.weight == 1000)
        #expect(mapped.spoolWeight == 250)
        #expect(mapped.price == 24.99)
    }

    @Test func mapsMaterialSubgroupIntoVariant() {
        // `Filament.variant` is computed from `extra["variant"]` — there is no
        // stored `variant` property on the app's Filament.
        let mapped = FilaManRepository.mapFilament(makeFilaManFilament(materialSubgroup: "Silk"), vendor: nil)

        #expect(mapped.variant == "Silk")
    }

    @Test func mapFilamentReadsTD() {
        let mapped = FilaManRepository.mapFilament(makeFilaManFilament(customFields: ["td": .double(2.8)]), vendor: nil)
        #expect(mapped.transmissionDistance == 2.8)
        #expect(mapped.variant == "Silk")
    }

    @Test func mapsVendorPassthrough() {
        let vendor = Vendor(id: 9, name: "Acme Filaments")
        let mapped = FilaManRepository.mapFilament(makeFilaManFilament(), vendor: vendor)

        #expect(mapped.vendor?.id == 9)
        #expect(mapped.vendor?.name == "Acme Filaments")
    }

    @Test func mapsColorHexFromPositionOneStrippingHash() {
        let colors = [
            FilaManColorSlot(position: 2, color: FilaManColor(id: 2, name: "Blue", hexCode: "#0000FF")),
            FilaManColorSlot(position: 1, color: FilaManColor(id: 1, name: "Red", hexCode: "#FF0000"))
        ]
        let mapped = FilaManRepository.mapFilament(makeFilaManFilament(colors: colors), vendor: nil)

        #expect(mapped.colorHex == "FF0000")
    }

    @Test func mapsMultiColorHexesOrderedByPosition() {
        let colors = [
            FilaManColorSlot(position: 2, color: FilaManColor(id: 2, name: "Blue", hexCode: "#0000FF")),
            FilaManColorSlot(position: 1, color: FilaManColor(id: 1, name: "Red", hexCode: "#FF0000"))
        ]
        let mapped = FilaManRepository.mapFilament(makeFilaManFilament(colors: colors), vendor: nil)

        #expect(mapped.multiColorHexes == "FF0000,0000FF")
    }

    /// FilaMan's `striped` reads back as Spoolman's `coaxial`, so the Library
    /// shows the same layout whichever backend stores it (owner decision 2026-10-28).
    @Test func readsStripedAsCoaxial() {
        let colors = [
            FilaManColorSlot(position: 1, color: FilaManColor(id: 1, name: "Red", hexCode: "#FF0000")),
            FilaManColorSlot(position: 2, color: FilaManColor(id: 2, name: "Blue", hexCode: "#0000FF"))
        ]
        let mapped = FilaManRepository.mapFilament(
            makeFilaManFilament(multiColorStyle: "striped", colors: colors), vendor: nil
        )

        #expect(mapped.multiColorDirection == "coaxial")
    }

    @Test func readsGradientAsLongitudinal() {
        let colors = [
            FilaManColorSlot(position: 1, color: FilaManColor(id: 1, name: "Red", hexCode: "#FF0000")),
            FilaManColorSlot(position: 2, color: FilaManColor(id: 2, name: "Blue", hexCode: "#0000FF"))
        ]
        let mapped = FilaManRepository.mapFilament(
            makeFilaManFilament(multiColorStyle: "gradient", colors: colors), vendor: nil
        )

        #expect(mapped.multiColorDirection == "longitudinal")
    }

    /// A direction means nothing on a single colour, so none is reported.
    @Test func singleColorHasNoDirection() {
        let colors = [FilaManColorSlot(position: 1, color: FilaManColor(id: 1, name: "Red", hexCode: "#FF0000"))]
        let mapped = FilaManRepository.mapFilament(
            makeFilaManFilament(multiColorStyle: "striped", colors: colors), vendor: nil
        )

        #expect(mapped.multiColorDirection == nil)
    }

    @Test func mapsArticleNumberAndSettingsTempsFromCustomFields() {
        let mapped = FilaManRepository.mapFilament(
            makeFilaManFilament(customFields: [
                "article_number": "ABC-123",
                "settings_extruder_temp": "210",
                "settings_bed_temp": "60"
            ]),
            vendor: nil
        )

        #expect(mapped.articleNumber == "ABC-123")
        #expect(mapped.settingsExtruderTemp == 210)
        #expect(mapped.settingsBedTemp == 60)
    }

    @Test func missingCustomFieldsMapArticleNumberAndSettingsTempsToNil() {
        let mapped = FilaManRepository.mapFilament(makeFilaManFilament(customFields: nil), vendor: nil)

        #expect(mapped.articleNumber == nil)
        #expect(mapped.settingsExtruderTemp == nil)
        #expect(mapped.settingsBedTemp == nil)
    }

    // MARK: - Task 17: colour-write decision (F27/R18)
    //
    // `PUT /filaments/{id}/colors` is a full REPLACE and an empty `colors: []`
    // wipes every colour a filament has, so "no colour in the draft" must mean
    // SKIP THE REQUEST, never "send an empty one".

    @Test func colourWritesAreSkippedWhenTheDraftHasNoColour() {
        #expect(FilaManRepository.writableHexes([]).isEmpty)
        #expect(FilaManRepository.writableHexes(["#3f3f3f"]) == ["3f3f3f"])
    }

    @Test func blankHexesDoNotCountAsAColour() {
        #expect(FilaManRepository.writableHexes(["", "  ", "#"]).isEmpty)
    }

    /// M3: the check and the iteration now read the same list, so a blank
    /// alongside a real colour can no longer survive into a
    /// `{"name":"#","hex_code":"#"}` create.
    @Test func aBlankAlongsideARealColourIsDroppedRatherThanWritten() {
        #expect(FilaManRepository.writableHexes(["#FF0000", "", "#00FF00"]) == ["ff0000", "00ff00"])
    }

    @Test func colourHexesComeFromTheSingleHexWhenThereIsNoMultiList() {
        var draft = FilamentDraft()
        draft.colorHex = "3F3F3F"

        #expect(FilaManRepository.colorHexes(from: draft) == ["3f3f3f"])
    }

    @Test func colourHexesComeFromTheMultiListWhenPresent() {
        // `mapFilament` builds `multiColorHexes` as the COMPLETE ordered list
        // (position 1 included), so it wins over the single `colorHex`.
        var draft = FilamentDraft()
        draft.colorHex = "FF0000"
        draft.multiColorHexes = .set("FF0000,0000FF")

        #expect(FilaManRepository.colorHexes(from: draft) == ["ff0000", "0000ff"])
    }

    @Test func colourHexesDropBlankEntriesFromAMultiList() {
        var draft = FilamentDraft()
        draft.multiColorHexes = .set("#ff0000, ,#0000ff")

        #expect(FilaManRepository.colorHexes(from: draft) == ["ff0000", "0000ff"])
    }

    @Test func colourHexesAreEmptyWhenTheDraftCarriesNoColourAtAll() {
        #expect(FilaManRepository.colorHexes(from: FilamentDraft()).isEmpty)
    }

    // MARK: - Task 17: hex → color_id matching (F27)

    @Test func colourIdLookupMatchesIgnoringCaseAndHash() {
        let rows = [
            FilaManColor(id: 4, name: "#FF0000", hexCode: "#ff0000"),
            FilaManColor(id: 9, name: "#0000FF", hexCode: "0000FF")
        ]
        let map = FilaManRepository.colorIdByHex(rows)

        #expect(map["ff0000"] == 4)
        #expect(map["0000ff"] == 9)
    }

    @Test func colourIdLookupSkipsRowsWithoutAUsableHex() {
        let map = FilaManRepository.colorIdByHex([
            FilaManColor(id: 4, name: "Nameless", hexCode: nil),
            FilaManColor(id: 5, name: "Blank", hexCode: "  ")
        ])

        #expect(map.isEmpty)
    }

    @Test func colourIdLookupKeepsTheLowestIdForADuplicatedHex() {
        // Repeated writes must keep landing on the same row rather than
        // alternating between two rows that mean the same colour.
        let map = FilaManRepository.colorIdByHex([
            FilaManColor(id: 12, name: "#FF0000", hexCode: "#ff0000"),
            FilaManColor(id: 4, name: "#FF0000", hexCode: "#FF0000")
        ])

        #expect(map["ff0000"] == 4)
    }

    @Test func aKnownHexResolvesToItsExistingColourId() {
        let plan = FilaManRepository.plannedColorSlot(hex: "#FF0000", colorIdByHex: ["ff0000": 4])

        #expect(plan == .existing(4))
    }

    /// The F27 shape: an unknown hex must surface as "create this", never as
    /// "there is nothing to do" — `GET /colors` has no hex filter and an
    /// exact-pair duplicate `POST /colors` returns 500, so resolve-before-create
    /// is mandatory and its miss case has to be actionable.
    @Test func anUnknownHexPlansACreateCarryingTheNormalizedHex() {
        let plan = FilaManRepository.plannedColorSlot(hex: " #3F3F3F ", colorIdByHex: [:])

        #expect(plan == .create("3f3f3f"))
    }

    // MARK: - Task 17: location resolve-or-create (F25/R15)
    //
    // The whole point of `FilaManLocationPlan` is that `.create` is a case of
    // its own. The previous `resolvedLocationPatch` collapsed an unresolvable
    // name into `.ignore`, so `updateSpool` could not tell "the user asked for
    // a location I don't have" from "the user didn't touch the location" and
    // reported success for a write it never made.

    @Test func locationPlanIsIgnoreWhenTheDraftDoesNotTouchTheLocation() {
        #expect(FilaManRepository.plannedLocationResolution(
            for: .ignore, locationIdByName: ["shelf b": 3]
        ) == .ignore)
    }

    @Test func locationPlanIsClearForAnExplicitClear() {
        #expect(FilaManRepository.plannedLocationResolution(
            for: .setNil, locationIdByName: ["shelf b": 3]
        ) == .clear)
    }

    @Test func locationPlanMatchesAnExistingNameCaseInsensitively() {
        #expect(FilaManRepository.plannedLocationResolution(
            for: .set("Shelf B"), locationIdByName: ["shelf b": 3]
        ) == .existing(3))
    }

    @Test func anUnknownLocationNamePlansACreateRatherThanCollapsingToIgnore() {
        #expect(FilaManRepository.plannedLocationResolution(
            for: .set("  Brand New Shelf  "), locationIdByName: [:]
        ) == .create("Brand New Shelf"))
    }

    @Test func aWhitespaceOnlyLocationNameAsksForNothing() {
        // Nothing was named, so there is nothing that could fail — this is a
        // genuine `.ignore`, not a swallowed failure.
        #expect(FilaManRepository.plannedLocationResolution(
            for: .set("   "), locationIdByName: ["shelf b": 3]
        ) == .ignore)
    }

    // MARK: - Task 17: relative weight adjustment (F28/R17)

    @Test func weightAdjustmentIsTheSignedDifferenceFromTheCurrentRemaining() {
        #expect(FilaManRepository.weightAdjustment(target: 400, current: 512.5) == .delta(-112.5))
        #expect(FilaManRepository.weightAdjustment(target: 600, current: 512.5) == .delta(87.5))
    }

    @Test func weightAdjustmentPostsNothingWhenTheSpoolIsAlreadyAtTheTarget() {
        // A zero-delta adjustment would still create an event and flip
        // status_id 1 "new" → 2 "opened" — a real change to the user's data
        // for a write that changes nothing.
        #expect(FilaManRepository.weightAdjustment(target: 400, current: 400) == .alreadyThere)
    }

    /// A relative adjustment is meaningless without a current remaining weight,
    /// and this must be sayable as its own outcome — collapsing it into a
    /// `.delta` (treating nil as 0) would set the spool to `grams` above
    /// whatever it actually holds and report success.
    @Test func weightAdjustmentReportsAnUnknownCurrentRatherThanGuessing() {
        #expect(FilaManRepository.weightAdjustment(target: 400, current: nil) == .currentUnknown)
    }

    // MARK: - Task 17b (I2): what a draft asks the remaining weight to become
    //
    // `SpoolFormView` feeds the weight field into `remainingWeight` or
    // `usedWeight` depending on the mode the user picked, and FilaMan's spool
    // payload carried neither: the PATCH returned 200, the message was
    // cleared, `true` was returned, and the weight was never written.

    @Test func anExplicitRemainingWeightIsTheTarget() {
        var draft = SpoolDraft()
        draft.remainingWeight = .set(512.5)

        #expect(FilaManRepository.remainingWeightTarget(for: draft, netInitial: 1000) == .grams(512.5))
    }

    /// FilaMan stores what is LEFT; SpoolKid's "used" mode asks in the other
    /// direction. Converting needs the net initial as the basis.
    @Test func aUsedWeightIsConvertedAgainstTheNetInitial() {
        var draft = SpoolDraft()
        draft.usedWeight = .set(250)

        #expect(FilaManRepository.remainingWeightTarget(for: draft, netInitial: 1000) == .grams(750))
    }

    /// The case that must not collapse into `.unchanged`: the user asked for
    /// something, and it cannot be honoured. Saying "nothing was requested"
    /// here is the F24/F25/F29/I2 defect exactly.
    @Test func aUsedWeightWithNoBasisIsUnsupportedNotUnchanged() {
        var draft = SpoolDraft()
        draft.usedWeight = .set(250)

        guard case .unsupported = FilaManRepository.remainingWeightTarget(for: draft, netInitial: nil) else {
            Issue.record("A used weight with no initial weight must report that it could not be applied.")
            return
        }
    }

    @Test func anExplicitRemainingWeightWinsOverAUsedWeight() {
        var draft = SpoolDraft()
        draft.remainingWeight = .set(400)
        draft.usedWeight = .set(250)

        #expect(FilaManRepository.remainingWeightTarget(for: draft, netInitial: 1000) == .grams(400))
    }

    @Test func aDraftThatNamesNoWeightAsksForNothing() {
        #expect(FilaManRepository.remainingWeightTarget(for: SpoolDraft(), netInitial: 1000) == .unchanged)
    }

    /// M3: `netInitial - used` goes negative once more filament has been used
    /// than the spool ever held. Update clamps at 0 server-side and create is
    /// unprobed, so a negative is either silently altered or a 422 — neither
    /// of which is a number the user meant.
    @Test func aUsedWeightAboveTheInitialWeightIsUnsupportedNotNegative() {
        var draft = SpoolDraft()
        draft.usedWeight = .set(1200)

        guard case .unsupported = FilaManRepository.remainingWeightTarget(for: draft, netInitial: 1000) else {
            Issue.record("A used weight above the initial weight must be refused, not sent as a negative.")
            return
        }
    }

    /// The boundary is inclusive: an entirely spent spool is a real state.
    @Test func aUsedWeightEqualToTheInitialWeightEmptiesTheSpool() {
        var draft = SpoolDraft()
        draft.usedWeight = .set(1000)

        #expect(FilaManRepository.remainingWeightTarget(for: draft, netInitial: 1000) == .grams(0))
    }

    // MARK: - Task 17b fix round (R20/F32): `.unchanged` means "ensure it did not change"
    //
    // A patch that CHANGES `empty_spool_weight_g` makes FilaMan re-base the
    // remaining weight by the same delta, opposite in sign, holding the gross
    // figure constant. A draft that names no weight
    // is asking for the weight to END UP unchanged — which, once the basis has
    // moved, takes a compensating adjustment rather than doing nothing.

    /// The defect: correct a core weight from 250 g to 400 g with the weight
    /// field left blank, and the spool silently loses 150 g on a clean save.
    /// The goal must be the value the spool reported BEFORE the patch.
    @Test func aSpoolWeightOnlyEditHoldsTheReportedRemainingWeightWhereItWas() {
        // Blank weight field: the draft names neither a remaining nor a used
        // weight. Only the basis is being edited.
        let draft = SpoolDraft()

        let goal = FilaManRepository.remainingWeightGoal(
            draft: draft, netInitial: 850, before: .reported(800)
        )

        #expect(goal == .grams(800))
        // …and the adjustment that lands it there is measured from the
        // POST-patch figure, which the basis change has already moved down by
        // the 150 g the core gained.
        #expect(FilaManRepository.weightAdjustment(target: 800, current: 650) == .delta(150))
    }

    /// The compensation must not fire when there was nothing to compensate:
    /// a patch whose basis matches what the spool already had leaves the
    /// reported weight alone, and posting a zero delta would still write an
    /// event and flip status_id 1 "new" → 2 "opened".
    @Test func aBasisThatDidNotActuallyMoveWritesNoAdjustment() {
        let goal = FilaManRepository.remainingWeightGoal(
            draft: SpoolDraft(), netInitial: 1000, before: .reported(800)
        )

        #expect(goal == .grams(800))
        #expect(FilaManRepository.weightAdjustment(target: 800, current: 800) == .alreadyThere)
    }

    /// No `empty_spool_weight_g` in the payload means nothing can have shifted,
    /// so this stays a genuine no-op — no read, no event, no status flip.
    @Test func aPatchThatCannotMoveTheBasisStillDoesNothing() {
        #expect(FilaManRepository.remainingWeightGoal(
            draft: SpoolDraft(), netInitial: 1000, before: .cannotMove
        ) == .unchanged)
    }

    /// `remaining = gross − basis` is nil only when the stored gross is, and no
    /// basis change can conjure one — so there is genuinely nothing to hold.
    @Test func aSpoolWithNoReportedWeightHasNothingToHold() {
        #expect(FilaManRepository.remainingWeightGoal(
            draft: SpoolDraft(), netInitial: 1000, before: .unreported
        ) == .unchanged)
    }

    /// A pre-patch read that failed leaves it unknowable whether the basis
    /// change moved anything. That is a caveat, not a silent pass — the exact
    /// collapse ("could not check" → "nothing was requested") this round exists
    /// to stop repeating.
    @Test func anUnreadablePreviousWeightIsReportedRatherThanAssumedFine() {
        #expect(FilaManRepository.remainingWeightGoal(
            draft: SpoolDraft(), netInitial: 1000, before: .unreadable("the server was unreachable")
        ) == .unsupported("the server was unreachable"))
    }

    /// A draft that DID name a weight is unaffected by the hold: the user's
    /// own target wins, and it is already absolute rather than relative to the
    /// pre-patch value.
    @Test func aNamedWeightTargetIgnoresThePrePatchValue() {
        var draft = SpoolDraft()
        draft.remainingWeight = .set(512.5)

        #expect(FilaManRepository.remainingWeightGoal(
            draft: draft, netInitial: 1000, before: .reported(800)
        ) == .grams(512.5))
    }

    /// …and an unsupportable one still reports itself rather than being
    /// quietly replaced by the hold value.
    @Test func anUnsupportedWeightSurvivesTheHold() {
        var draft = SpoolDraft()
        draft.usedWeight = .set(250)

        guard case .unsupported = FilaManRepository.remainingWeightGoal(
            draft: draft, netInitial: nil, before: .reported(800)
        ) else {
            Issue.record("A used weight that cannot be converted must still be reported.")
            return
        }
    }

    // MARK: - Task 17b: two caveats from one write must both survive

    @Test func combinedNoteJoinsEveryStatedCaveat() {
        #expect(SaveOutcome.combinedNote(["first", "second"]) == "first\nsecond")
    }

    @Test func combinedNoteIsNilWhenThereIsNothingToSay() {
        #expect(SaveOutcome.combinedNote([nil, nil]) == nil)
        #expect(SaveOutcome.combinedNote([]) == nil)
        #expect(SaveOutcome.combinedNote([nil, "  "]) == nil)
    }

    @Test func combinedNoteKeepsASingleCaveatVerbatim() {
        #expect(SaveOutcome.combinedNote([nil, "only this"]) == "only this")
    }

    // MARK: - Vendor table

    @Test func mapsVendorFields() {
        let manufacturer = FilaManManufacturer(
            id: 9, name: "Acme Filaments", url: nil, emptySpoolWeightG: 210,
            customFields: ["comment": "reliable supplier", "region": "EU"]
        )

        let vendor = FilaManRepository.mapVendor(manufacturer)

        #expect(vendor.id == 9)
        #expect(vendor.name == "Acme Filaments")
        #expect(vendor.emptySpoolWeight == 210)
        #expect(vendor.comment == "reliable supplier")
        #expect(vendor.extra == ["comment": "reliable supplier", "region": "EU"])
    }

    // MARK: - C1/R19: a dropped colour direction is reported, not swallowed

    @Test func droppedStyleNoteNamesTheValueFilaManCannotStore() {
        let note = FilaManRepository.droppedStyleNote(requested: "diagonal", colorCount: 2)
        #expect(note?.contains("diagonal") == true)
        #expect(note?.contains("striped or gradient") == true)
    }

    @Test func nothingIsReportedWhenTheDirectionIsOneFilaManSupports() {
        #expect(FilaManRepository.droppedStyleNote(requested: "Gradient", colorCount: 2) == nil)
        #expect(FilaManRepository.droppedStyleNote(requested: "coaxial", colorCount: 2) == nil)
    }

    @Test func nothingIsReportedForASingleColourBecauseTheKeyIsNeverSent() {
        // colorsPayload omits multi_color_style unless multi, so a single
        // colour drops nothing and must not claim it did.
        #expect(FilaManRepository.droppedStyleNote(requested: "diagonal", colorCount: 1) == nil)
    }

    @Test func nothingIsReportedWhenNoDirectionWasAskedFor() {
        #expect(FilaManRepository.droppedStyleNote(requested: nil, colorCount: 2) == nil)
        #expect(FilaManRepository.droppedStyleNote(requested: "  ", colorCount: 2) == nil)
    }
}
