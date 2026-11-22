//
//  FilaManPayloadBuilderTests.swift
//  SpoolKidTests
//

import Foundation
import Testing
@testable import SpoolKid

struct FilaManPayloadBuilderTests {
    @Test func vendorPayloadUsesFilaManFieldNames() {
        let payload = FilaManPayloadBuilder.vendorPayload(from: VendorDraft(name: "Prusament"))

        #expect(payload["name"] as? String == "Prusament")
    }

    // `status`, not `status_id`: verified live 2026-08-20 against a 1.2.19
    // instance's /openapi.json — `POST /spools/{id}/status`'s
    // `StatusChangeRequest.status` field is a string ("active"/"archived"/…),
    // not the numeric id GET responses use.
    @Test func statusPayloadMapsArchivedToStatusKey() {
        #expect(FilaManPayloadBuilder.statusPayload(archived: true)["status"] as? String == "archived")
    }

    @Test func statusPayloadMapsUnarchivedToActiveKey() {
        #expect(FilaManPayloadBuilder.statusPayload(archived: false)["status"] as? String == "active")
    }

    @Test func statusPayloadDelegatesToTheSingleStatusMapping() {
        // A4: one implementation per concept. The archived⇄status mapping lives
        // on FilaManSpoolStatus; the payload builder must not restate it.
        for archived in [true, false] {
            #expect(FilaManPayloadBuilder.statusPayload(archived: archived)["status"] as? String
                    == FilaManSpoolStatus.key(archived: archived))
        }
    }

    // MARK: - F28: adjustments
    //
    // `AdjustmentRequest` requires `adjustment_type`; the previous builder sent
    // a bare `remaining_weight_g`, which is not a field of that schema at all.
    // Only `relative` is ever produced — see the builder's doc comment for why
    // `absolute`/`measured_weight_g` (GROSS weight) would under-report every
    // spool by its own empty-spool weight.

    @Test func adjustmentPayloadIsAlwaysRelative() {
        let payload = FilaManPayloadBuilder.adjustmentPayload(deltaGrams: -87.5)

        #expect(payload["adjustment_type"] as? String == "relative")
    }

    @Test func adjustmentPayloadCarriesTheDelta() {
        let payload = FilaManPayloadBuilder.adjustmentPayload(deltaGrams: -87.5)

        #expect(payload["delta_weight_g"] as? Double == -87.5)
    }

    @Test func adjustmentPayloadNeverSendsAGrossMeasuredWeight() {
        // `measured_weight_g` is spool + filament. SpoolKid's remainingWeight is
        // net filament, so this key must never appear.
        let payload = FilaManPayloadBuilder.adjustmentPayload(deltaGrams: 100)

        #expect(payload["measured_weight_g"] == nil)
        #expect(payload["remaining_weight_g"] == nil)
    }

    // MARK: - F27: colours are entities, referenced by integer FK
    //
    // `FilamentColorEntry` has no `hex_code` field — an entry is `color_id` +
    // `position`. `FilamentColorsReplace` additionally requires `color_mode`.
    // The previous builder sent positional `hex_code` entries and no
    // `color_mode`, so every colour write would have 422'd.

    @Test func coloursPayloadReferencesColorIdsPositionallyFromOne() {
        let payload = FilaManPayloadBuilder.colorsPayload(colorIds: [12, 34], multiColorStyle: nil)
        let colors = payload["colors"] as? [[String: Any]]

        #expect(colors?.count == 2)
        #expect(colors?[0]["color_id"] as? Int == 12)
        #expect(colors?[0]["position"] as? Int == 1)
        #expect(colors?[1]["color_id"] as? Int == 34)
        #expect(colors?[1]["position"] as? Int == 2)
    }

    @Test func coloursPayloadNeverSendsHexCodeInAnEntry() {
        let colors = FilaManPayloadBuilder.colorsPayload(colorIds: [12], multiColorStyle: nil)["colors"]
            as? [[String: Any]]

        #expect(colors?[0]["hex_code"] == nil)
    }

    @Test func coloursPayloadModeIsSingleForOneColour() {
        let payload = FilaManPayloadBuilder.colorsPayload(colorIds: [12], multiColorStyle: nil)

        #expect(payload["color_mode"] as? String == "single")
    }

    @Test func coloursPayloadModeIsMultiForSeveralColours() {
        let payload = FilaManPayloadBuilder.colorsPayload(colorIds: [12, 34, 56], multiColorStyle: nil)

        #expect(payload["color_mode"] as? String == "multi")
    }

    @Test func coloursPayloadCarriesMultiColorStyleOnlyWhenMulti() {
        let multi = FilaManPayloadBuilder.colorsPayload(colorIds: [12, 34], multiColorStyle: "gradient")
        let single = FilaManPayloadBuilder.colorsPayload(colorIds: [12], multiColorStyle: "gradient")

        #expect(multi["multi_color_style"] as? String == "gradient")
        #expect(single["multi_color_style"] == nil)
    }

    // MARK: - C1/R19: multi_color_style must satisfy ^(striped|gradient)$
    //
    // `multi_color_direction` is a free-text field in SpoolKid and carries
    // Spoolman's vocabulary after a migration. Forwarding one of those verbatim
    // fails FilaMan's pattern — and since this payload is merged INLINE into
    // POST /filaments, that 422 destroys the whole create, not just the colour.
    // An earlier version of the test above pinned "linear" as a valid emission,
    // certifying a payload the server rejects.

    @Test func multiColorStyleAcceptsOnlyFilaMansTwoValues() {
        #expect(FilaManPayloadBuilder.supportedMultiColorStyle("striped") == "striped")
        #expect(FilaManPayloadBuilder.supportedMultiColorStyle("gradient") == "gradient")
    }

    @Test func multiColorStyleNormalizesCaseAndWhitespace() {
        #expect(FilaManPayloadBuilder.supportedMultiColorStyle("  Gradient ") == "gradient")
        #expect(FilaManPayloadBuilder.supportedMultiColorStyle("STRIPED") == "striped")
    }

    /// Owner decision 2026-10-28: Spoolman's Coextruded (`coaxial`) is FilaMan's
    /// `striped`, and Gradient (`longitudinal`) is `gradient`. Anything else
    /// stays unmapped, so a made-up direction is never silently restyled.
    @Test func mapsSpoolmanDirections() {
        #expect(FilaManPayloadBuilder.supportedMultiColorStyle("coaxial") == "striped")
        #expect(FilaManPayloadBuilder.supportedMultiColorStyle("longitudinal") == "gradient")
        #expect(FilaManPayloadBuilder.supportedMultiColorStyle("Gradient ") == "gradient")
        #expect(FilaManPayloadBuilder.supportedMultiColorStyle("diagonal") == nil)
        #expect(FilaManPayloadBuilder.supportedMultiColorStyle("linear") == nil)
    }

    @Test func multiColorStyleRejectsBlankAndMissing() {
        #expect(FilaManPayloadBuilder.supportedMultiColorStyle(nil) == nil)
        #expect(FilaManPayloadBuilder.supportedMultiColorStyle("   ") == nil)
    }

    @Test func coloursPayloadOmitsAnUnsupportedStyleRatherThanForwardingIt() {
        let payload = FilaManPayloadBuilder.colorsPayload(colorIds: [12, 34], multiColorStyle: "linear")

        // Omitted, not forwarded: forwarding 422s the create and loses the filament.
        #expect(payload["multi_color_style"] == nil)
        // The rest of the payload still stands — the filament is still created.
        #expect(payload["color_mode"] as? String == "multi")
        #expect((payload["colors"] as? [[String: Any]])?.count == 2)
    }

    @Test func coloursPayloadOmitsMultiColorStyleWhenBlank() {
        let payload = FilaManPayloadBuilder.colorsPayload(colorIds: [12, 34], multiColorStyle: "   ")

        #expect(payload["multi_color_style"] == nil)
    }

    // MARK: - POST /api/v1/colors

    @Test func colorPayloadUsesUppercaseNameAndLowercaseHexCode() {
        let payload = FilaManPayloadBuilder.colorPayload(hex: "3F3f3F")

        #expect(payload["name"] as? String == "#3F3F3F")
        #expect(payload["hex_code"] as? String == "#3f3f3f")
    }

    @Test func colorPayloadAcceptsAHexThatAlreadyCarriesAHash() {
        let payload = FilaManPayloadBuilder.colorPayload(hex: "#ffffff")

        #expect(payload["name"] as? String == "#FFFFFF")
        #expect(payload["hex_code"] as? String == "#ffffff")
    }

    @Test func normalizedHexStripsHashTrimsAndLowercases() {
        #expect(FilaManPayloadBuilder.normalizedHex("  #3F3F3F ") == "3f3f3f")
        #expect(FilaManPayloadBuilder.normalizedHex("3f3f3f") == "3f3f3f")
    }

    @Test func vendorPayloadOmitsNameWhenNil() {
        let payload = FilaManPayloadBuilder.vendorPayload(from: VendorDraft())

        #expect(payload["name"] == nil)
    }

    @Test func vendorPayloadOmitsCustomFieldsWhenNothingIsSet() {
        #expect(FilaManPayloadBuilder.vendorPayload(from: VendorDraft(name: "X"))["custom_fields"] == nil)
        #expect(FilaManPayloadBuilder.vendorPayload(from: VendorDraft(name: "X", comment: ""))["custom_fields"] == nil)
    }

    /// `comment` used to be emulated in `custom_fields`; since 2026-08-28 a
    /// SET comment does not travel at all — `FilaManRepository.addVendor`
    /// reports the drop instead (`unwritableCommentNoteOnCreate`).
    @Test func aSetVendorCommentDoesNotTravel() {
        var draft = VendorDraft(name: "X")
        draft.comment = "Great vendor"
        draft.extra = ["source": "catalog"]

        let custom = FilaManPayloadBuilder.vendorPayload(from: draft)["custom_fields"] as? [String: String]

        #expect(custom?["comment"] == nil)
        #expect(custom?["source"] == "catalog")
    }

    @Test func filamentPayloadUsesFilaManFieldNames() {
        let draft = FilamentDraft(
            name: "PLA Basic",
            material: "PLA",
            price: .set(19.99),
            density: 1.24,
            diameter: 1.75,
            weight: .set(1000),
            spoolWeight: .set(140)
        )
        let payload = FilaManPayloadBuilder.filamentPayload(from: draft, manufacturerId: 7)

        #expect(payload["manufacturer_id"] as? Int == 7)
        #expect(payload["designation"] as? String == "PLA Basic")
        #expect(payload["material_type"] as? String == "PLA")
        #expect(payload["diameter_mm"] as? Double == 1.75)
        #expect(payload["density_g_cm3"] as? Double == 1.24)
        #expect(payload["raw_material_weight_g"] as? Double == 1000)
        #expect(payload["default_spool_weight_g"] as? Double == 140)
        #expect(payload["price"] as? Double == 19.99)
    }

    @Test func filamentPayloadOmitsOptionalFieldsWhenNil() {
        let draft = FilamentDraft()
        let payload = FilaManPayloadBuilder.filamentPayload(from: draft, manufacturerId: 3)

        #expect(payload["manufacturer_id"] as? Int == 3)
        #expect(payload["designation"] == nil)
        #expect(payload["material_type"] == nil)
        #expect(payload["diameter_mm"] == nil)
        #expect(payload["custom_fields"] == nil)
    }

    /// The catalogue write-back (Task 4) on FilaMan. `manufacturer_id` is not a
    /// change: FilaMan's PATCH always restates the filament's current
    /// manufacturer (`FilaManRepository.updateFilament` fills it from the
    /// cached filament), as every filament edit does. Nothing else travels, so
    /// the designation, material, diameter, density, weights, price and custom
    /// fields stay as they are.
    @Test func spoolWeightOnlyUpdate() {
        let payload = FilaManPayloadBuilder.filamentPayload(
            from: FilamentDraft(spoolWeight: .set(193)), manufacturerId: 79
        )

        #expect(Set(payload.keys) == ["manufacturer_id", "default_spool_weight_g"])
        #expect(payload["manufacturer_id"] as? Int == 79)
        #expect(payload["default_spool_weight_g"] as? Double == 193)
    }

    @Test func spoolPayloadUsesFilaManFieldNames() {
        var draft = SpoolDraft()
        draft.filamentId = 42
        draft.price = 25.0
        draft.initialWeight = .set(1000)
        draft.spoolWeight = .set(140)
        draft.lotNr = .set("LOT-1")

        let payload = FilaManPayloadBuilder.spoolPayload(from: draft, location: .set(9))

        #expect(payload["filament_id"] as? Int == 42)
        #expect(payload["location_id"] as? Int == 9)
        #expect(payload["purchase_price"] as? Double == 25.0)
        // GROSS: the draft's 1000 g of filament sitting on its 140 g core.
        #expect(payload["initial_total_weight_g"] as? Double == 1140)
        #expect(payload["empty_spool_weight_g"] as? Double == 140)
        #expect(payload["lot_number"] as? String == "LOT-1")
    }

    // MARK: - F31: initial_total_weight_g is GROSS and its basis travels with it

    @Test func spoolPayloadConvertsTheNetInitialWeightToGross() {
        var draft = SpoolDraft()
        draft.initialWeight = .set(1000)
        draft.spoolWeight = .set(250)

        let payload = FilaManPayloadBuilder.spoolPayload(from: draft, location: .ignore)

        #expect(payload["initial_total_weight_g"] as? Double == 1250)
        #expect(payload["empty_spool_weight_g"] as? Double == 250)
    }

    /// Verified live 2026-08-21: a gross figure sent without its basis makes
    /// FilaMan inherit the FILAMENT's `default_spool_weight_g` instead, so the
    /// number that comes back is not the number that was sent. Zero is a basis
    /// and must be stated, never left to be inferred.
    // `spoolPayloadSendsAZeroBasisRatherThanOmittingIt` lived here. It set an
    // initial weight, left the basis unset, and asserted a basis of 0 went
    // out — which was right when "unset" could only mean "the draft names no
    // spool weight". Under R21 that setup is `.set` + `.ignore`, the one
    // combination the builder refuses, so the test now describes a case it
    // does not mean. Both halves of its intent are covered more precisely by
    // `aZeroBasisIsStillStated` (a stated zero travels) and
    // `aGrossFigureWithAnUnstatedBasisSendsNothing` (an unstated basis is not
    // invented). Removed rather than rewritten, per T2.

    @Test func spoolPayloadOmitsBothWeightKeysWhenTheDraftCarriesNoWeight() {
        let payload = FilaManPayloadBuilder.spoolPayload(from: SpoolDraft(), location: .ignore)

        #expect(payload.keys.contains("initial_total_weight_g") == false)
        #expect(payload.keys.contains("empty_spool_weight_g") == false)
    }

    /// An empty-spool-weight-only edit still has to reach the server: there is
    /// no gross figure to anchor it to, but the user did change the core.
    @Test func spoolPayloadSendsTheBasisAloneWhenNoInitialWeightIsGiven() {
        var draft = SpoolDraft()
        draft.spoolWeight = .set(140)

        let payload = FilaManPayloadBuilder.spoolPayload(from: draft, location: .ignore)

        #expect(payload["empty_spool_weight_g"] as? Double == 140)
        #expect(payload.keys.contains("initial_total_weight_g") == false)
    }

    /// The invariant, now stated over ALL NINE combinations rather than three.
    ///
    /// It survives R21 unchanged — a gross figure never travels without its
    /// basis. What changed is HOW the unstated-basis case satisfies it. With
    /// bare optionals, `spoolWeight: nil` meant "the draft names no spool
    /// weight", and inventing a basis of 0 was right: nothing else could have
    /// been meant. `.ignore` means "leave the stored basis alone", so
    /// inventing 0 would now be wrong whenever the server holds a basis the
    /// user simply did not edit — it would silently re-base the spool. The
    /// builder therefore sends NEITHER key.
    ///
    /// That combination does not arise from the app: `SpoolFormView`'s
    /// `weightPairPatch` and `MigrationService` both state the basis whenever
    /// they state a gross figure. It is handled here anyway, because a builder
    /// that quietly invents a basis is exactly how F31 happened.
    @Test func aGrossFigureNeverTravelsWithoutItsBasis() {
        let values: [SpoolmanPatchValue<Double>] = [.ignore, .set(1000), .setNil]

        for net in values {
            for basis in values {
                let keys = FilaManPayloadBuilder.spoolWeightKeys(netInitial: net, spoolWeight: basis)
                if keys["initial_total_weight_g"] is Double {
                    #expect(
                        keys["empty_spool_weight_g"] != nil,
                        "a gross figure went out with no basis for (\(net), \(basis))"
                    )
                }
            }
        }
    }

    @Test func statingBothWeightsConvertsNetToGross() {
        let keys = FilaManPayloadBuilder.spoolWeightKeys(netInitial: .set(1000), spoolWeight: .set(250))

        #expect(keys["initial_total_weight_g"] as? Double == 1250)
        #expect(keys["empty_spool_weight_g"] as? Double == 250)
    }

    /// The basis travels even at zero — see `spoolWeightKeys`.
    @Test func aZeroBasisIsStillStated() {
        let keys = FilaManPayloadBuilder.spoolWeightKeys(netInitial: .set(1000), spoolWeight: .set(0))

        #expect(keys["initial_total_weight_g"] as? Double == 1000)
        #expect(keys["empty_spool_weight_g"] as? Double == 0)
    }

    @Test func aBasisAloneTravelsAlone() {
        let keys = FilaManPayloadBuilder.spoolWeightKeys(netInitial: .ignore, spoolWeight: .set(250))

        #expect(keys["empty_spool_weight_g"] as? Double == 250)
        #expect(keys["initial_total_weight_g"] == nil)
    }

    @Test func sayingNothingSendsNothing() {
        #expect(FilaManPayloadBuilder.spoolWeightKeys(netInitial: .ignore, spoolWeight: .ignore).isEmpty)
    }

    /// The case R21 made representable: a gross figure whose basis the draft
    /// declines to state cannot be converted, so neither key goes out. Sending
    /// the gross figure alone would let FilaMan pick the basis from the
    /// filament's default and rewrite the number (F31).
    @Test func aGrossFigureWithAnUnstatedBasisSendsNothing() {
        #expect(FilaManPayloadBuilder.spoolWeightKeys(netInitial: .set(1000), spoolWeight: .ignore).isEmpty)
    }

    /// …and the form guarantees that combination never reaches the builder.
    @Test func theFormAlwaysStatesTheBasisWhenItStatesAGrossFigure() {
        // Initial weight edited, spool weight untouched at its loaded value.
        let pair = SpoolFormView.weightPairPatch(
            initialWeight: "900", loadedInitialWeight: "1000",
            spoolWeight: "250", loadedSpoolWeight: "250"
        )

        #expect(pair.initial == .set(900))
        #expect(pair.basis == .set(250), "the basis must be stated alongside a changed gross figure")
    }

    // MARK: - F32: the basis key can re-base the remaining weight

    /// Every payload that emits a basis has to be recognised as one that may
    /// shift the spool's reported remaining weight, including the case that
    /// looks most innocent: a lone `empty_spool_weight_g` with no gross figure
    /// beside it, which names no weight at all and moves it anyway. Answering
    /// on the key rather than on a change of value over-reports on purpose —
    /// see `movesWeightBasis`.
    @Test func anyPayloadCarryingTheBasisIsKnownToMoveTheRemainingWeight() {
        var draft = SpoolDraft()
        draft.spoolWeight = .set(250)
        #expect(FilaManPayloadBuilder.movesWeightBasis(
            FilaManPayloadBuilder.spoolPayload(from: draft, location: .ignore)
        ))

        draft.initialWeight = .set(1000)
        #expect(FilaManPayloadBuilder.movesWeightBasis(
            FilaManPayloadBuilder.spoolPayload(from: draft, location: .ignore)
        ))
    }

    /// …and one that carries no basis does not, so an edit that cannot disturb
    /// the weight does not pay for a pre-patch read.
    @Test func aPayloadWithNoWeightKeysLeavesTheRemainingWeightAlone() {
        var draft = SpoolDraft()
        draft.comment = .set("metadata only")

        #expect(FilaManPayloadBuilder.movesWeightBasis(
            FilaManPayloadBuilder.spoolPayload(from: draft, location: .ignore)
        ) == false)
    }

    @Test func spoolPayloadOmitsLocationIdWhenNil() {
        let payload = FilaManPayloadBuilder.spoolPayload(from: SpoolDraft(), location: .ignore)

        #expect(payload["location_id"] == nil)
        #expect(payload["filament_id"] == nil)
    }

    // MARK: - F24: .ignore / .set / .setNil must stay three distinct wire
    // outcomes for location_id — `.setNil` collapsing to the same "omit the
    // key" behavior as `.ignore` was the bug: a spool's location would look
    // cleared to the caller (returns true, no error) while the server never
    // saw anything telling it to clear it. Verified live 2026-08-20:
    // `PATCH /spools/{id}` with `{"location_id": null}` returns 200 and a
    // re-GET confirms the field is actually cleared.

    @Test func spoolPayloadOmitsLocationIdKeyEntirelyForIgnore() {
        let payload = FilaManPayloadBuilder.spoolPayload(from: SpoolDraft(), location: .ignore)

        #expect(payload.keys.contains("location_id") == false)
    }

    @Test func spoolPayloadSendsExplicitNullForSetNil() {
        let payload = FilaManPayloadBuilder.spoolPayload(from: SpoolDraft(), location: .setNil)

        #expect(payload.keys.contains("location_id"))
        #expect(payload["location_id"] is NSNull)
    }

    @Test func spoolPayloadSendsTheResolvedIdForSet() {
        let payload = FilaManPayloadBuilder.spoolPayload(from: SpoolDraft(), location: .set(9))

        #expect(payload["location_id"] as? Int == 9)
    }

    // MARK: - I2: SpoolCreate carries remaining_weight_g, SpoolUpdate does not

    @Test func spoolCreatePayloadCarriesTheRemainingWeight() {
        let payload = FilaManPayloadBuilder.spoolCreatePayload(
            from: SpoolDraft(), location: .ignore, remainingWeight: 512.5
        )

        #expect(payload["remaining_weight_g"] as? Double == 512.5)
    }

    @Test func spoolCreatePayloadOmitsRemainingWeightWhenTheDraftAsksForNone() {
        let payload = FilaManPayloadBuilder.spoolCreatePayload(
            from: SpoolDraft(), location: .ignore, remainingWeight: nil
        )

        #expect(payload.keys.contains("remaining_weight_g") == false)
    }

    @Test func spoolCreatePayloadKeepsEveryScalarTheSharedBuilderProduces() {
        var draft = SpoolDraft()
        draft.filamentId = 42
        draft.initialWeight = .set(1000)
        draft.spoolWeight = .set(250)

        let payload = FilaManPayloadBuilder.spoolCreatePayload(
            from: draft, location: .set(9), remainingWeight: 400
        )

        #expect(payload["filament_id"] as? Int == 42)
        #expect(payload["location_id"] as? Int == 9)
        #expect(payload["initial_total_weight_g"] as? Double == 1250)
        #expect(payload["remaining_weight_g"] as? Double == 400)
    }

    /// `SpoolUpdate` has no remaining-weight field at all (verified live
    /// 2026-08-21), so the shared body must never carry one: a PATCH with a
    /// key the endpoint ignores returns 200 and writes nothing, which is how
    /// every remaining-weight edit on FilaMan was silently lost.
    @Test func theSharedSpoolPayloadNeverCarriesARemainingWeight() {
        var draft = SpoolDraft()
        draft.remainingWeight = .set(400)
        draft.usedWeight = .set(250)

        let payload = FilaManPayloadBuilder.spoolPayload(from: draft, location: .ignore)

        #expect(payload.keys.contains("remaining_weight_g") == false)
        #expect(payload.keys.contains("used_weight") == false)
    }

    @Test func customFieldsPayloadWrapsFieldsVerbatim() {
        let payload = FilaManPayloadBuilder.customFieldsPayload(["card_uids": "AABBCC"])

        #expect((payload["custom_fields"] as? [String: String])?["card_uids"] == "AABBCC")
    }

    // MARK: - Tag payload (rfid_uid)

    @Test func tagPayloadClearIsNull() {
        let payload = FilaManPayloadBuilder.spoolTagPayload(customFields: nil, rfid: .clear)

        #expect(payload["rfid_uid"] is NSNull)
        #expect(Set(payload.keys) == ["rfid_uid"])
    }

    @Test func tagPayloadSetIsLowercase() {
        let payload = FilaManPayloadBuilder.spoolTagPayload(customFields: nil, rfid: .set("04A1B2"))

        #expect(payload["rfid_uid"] as? String == "04a1b2")
    }

    @Test func tagPayloadKeepOmitsKey() {
        let payload = FilaManPayloadBuilder.spoolTagPayload(customFields: ["card_uids": .string("AA")], rfid: .keep)

        #expect(Set(payload.keys) == ["custom_fields"])
    }

    // MARK: - Dates: `stocked_in_at` is create-only, `last_used_at` is FilaMan's
    //
    // Probed live 2026-08-25 against the owner's instance. `PATCH /spools/{id}`
    // accepts BOTH keys with a 200 and stores NEITHER; a create stores
    // `stocked_in_at` and still ignores `last_used_at`. Corroborated by the
    // data: both are null on all 38 spools, while `created_at` is populated on
    // all 38.
    //
    // These four tests replace four that asserted the opposite. They were not
    // wrong about the mapping — `stocked_in_at` IS where `firstUsed` goes —
    // only about which endpoint would keep it.

    /// A create keeps it, so a create sends it.
    @Test func spoolCreatePayloadMapsFirstUsedToStockedInAt() {
        var draft = SpoolDraft()
        draft.firstUsed = .set("2026-01-01T00:00:00Z")

        let payload = FilaManPayloadBuilder.spoolCreatePayload(
            from: draft, location: .ignore, remainingWeight: nil
        )

        #expect(payload["stocked_in_at"] as? String == "2026-01-01T00:00:00Z")
    }

    @Test func spoolCreatePayloadOmitsStockedInAtWhenFirstUsedIsNil() {
        let payload = FilaManPayloadBuilder.spoolCreatePayload(
            from: SpoolDraft(), location: .ignore, remainingWeight: nil
        )

        #expect(payload["stocked_in_at"] == nil)
    }

    /// An update DROPS it, so an update must not send it. A key the endpoint
    /// takes with a 200 and discards is indistinguishable from a key that
    /// worked — which is the whole defect.
    @Test func spoolUpdatePayloadNeverSendsStockedInAt() {
        var draft = SpoolDraft()
        draft.firstUsed = .set("2026-01-01T00:00:00Z")

        let payload = FilaManPayloadBuilder.spoolPayload(from: draft, location: .ignore)

        #expect(payload["stocked_in_at"] == nil)
    }

    /// FilaMan derives this from its own usage history — no endpoint accepts
    /// it, create included.
    @Test func neitherPayloadEverSendsLastUsedAt() {
        var draft = SpoolDraft()
        draft.lastUsed = .set("2026-02-02T00:00:00Z")

        #expect(FilaManPayloadBuilder.spoolPayload(from: draft, location: .ignore)["last_used_at"] == nil)
        #expect(
            FilaManPayloadBuilder.spoolCreatePayload(
                from: draft, location: .ignore, remainingWeight: nil
            )["last_used_at"] == nil
        )
    }

    @Test func spoolPayloadMergesExtraIntoCustomFields() {
        var draft = SpoolDraft()
        draft.extra = .set(["card_uids": "AABBCCDD"])

        let custom = FilaManPayloadBuilder.spoolPayload(from: draft, location: .ignore)["custom_fields"] as? [String: String]

        #expect(custom?["card_uids"] == "AABBCCDD")
    }

    @Test func spoolPayloadOmitsCustomFieldsWhenExtraIsNilAndNothingElseSet() {
        let payload = FilaManPayloadBuilder.spoolPayload(from: SpoolDraft(), location: .ignore)

        #expect(payload["custom_fields"] == nil)
    }

    // MARK: - R21: a cleared lot number actually clears
    //
    // Before this, `clearFieldKeys` carried SPOOLMAN's key names and nothing in
    // the FilaMan path read them, so emptying the box returned `true` and
    // changed nothing on the server.

    @Test func anUntouchedLotNumberIsNotSent() {
        let payload = FilaManPayloadBuilder.spoolPayload(from: SpoolDraft(), location: .ignore)

        #expect(payload.keys.contains("lot_number") == false)
    }

    @Test func aClearedLotNumberTravelsAsAnExplicitNull() {
        var draft = SpoolDraft()
        draft.lotNr = .setNil

        let payload = FilaManPayloadBuilder.spoolPayload(from: draft, location: .ignore)

        #expect(payload["lot_number"] is NSNull)
    }

    /// `comment` used to be emulated in `custom_fields`; since 2026-08-28 a
    /// SET comment does not travel at all — `FilaManRepository.addSpool`
    /// reports the drop instead (`unwritableCommentNoteOnCreate`).
    @Test func aSetSpoolCommentDoesNotTravel() {
        var draft = SpoolDraft()
        draft.comment = .set("Bench spool")
        draft.extra = .set(["spool_core_diameter": "genuine"])

        let custom = FilaManPayloadBuilder.spoolPayload(from: draft, location: .ignore)["custom_fields"] as? [String: String]

        #expect(custom?["comment"] == nil)
        #expect(custom?["spool_core_diameter"] == "genuine")
    }

    /// FilaMan's `extra` IS `custom_fields`, and that is where `card_uids`
    /// lives — so emptying it is refused rather than honoured.
    @Test func anEmptiedExtraContributesNothingRatherThanWipingCustomFields() {
        var draft = SpoolDraft()
        draft.extra = .setNil
        draft.cardUIDs = ["AABBCCDD"]

        let custom = FilaManPayloadBuilder.spoolPayload(from: draft, location: .ignore)["custom_fields"] as? [String: String]

        #expect(custom == ["card_uids": "AABBCCDD"])
    }

    /// F38: the typed UID list is the one channel that knows FilaMan's
    /// encoding, so a stale pre-encoded `extra["card_uids"]` must never win —
    /// that value is Spoolman's wrapped form and double-wraps through the
    /// compat layer.
    @Test func spoolPayloadTypedCardUIDsOverwriteACollidingExtraKey() {
        var draft = SpoolDraft()
        draft.extra = .set(["card_uids": CardUIDsCodec.encode(["AABBCCDD"])])
        draft.cardUIDs = ["AABBCCDD"]

        let custom = FilaManPayloadBuilder.spoolPayload(from: draft, location: .ignore)["custom_fields"] as? [String: String]

        #expect(custom?["card_uids"] == "AABBCCDD")
    }

    // MARK: - R21 stage 4: clearing a filament field on FilaMan

    /// Probed live 2026-08-25: all three take an explicit null and a re-GET
    /// confirms the clear.
    @Test func theThreeClearableFilamentScalarsTravelAsExplicitNulls() {
        var draft = FilamentDraft()
        draft.price = .setNil
        draft.weight = .setNil
        draft.spoolWeight = .setNil

        let payload = FilaManPayloadBuilder.filamentPayload(from: draft, manufacturerId: 7)

        #expect(payload["price"] is NSNull)
        #expect(payload["raw_material_weight_g"] is NSNull)
        #expect(payload["default_spool_weight_g"] is NSNull)
    }

    @Test func anUntouchedFilamentScalarIsNotSentAtAll() {
        let payload = FilaManPayloadBuilder.filamentPayload(from: FilamentDraft(), manufacturerId: 7)

        #expect(payload["price"] == nil)
        #expect(payload["raw_material_weight_g"] == nil)
        #expect(payload["default_spool_weight_g"] == nil)
    }

    @Test func filamentPayloadMergesExtraIntoCustomFields() {
        var draft = FilamentDraft()
        draft.extra = .set(["spool_core_diameter": "genuine"])

        let custom = FilaManPayloadBuilder.filamentPayload(from: draft, manufacturerId: 1)["custom_fields"] as? [String: String]

        #expect(custom?["spool_core_diameter"] == "genuine")
    }

    @Test func filamentPayloadOmitsCustomFieldsWhenExtraIsNilAndNothingElseSet() {
        let payload = FilaManPayloadBuilder.filamentPayload(from: FilamentDraft(), manufacturerId: 1)

        #expect(payload["custom_fields"] == nil)
    }

    @Test func vendorPayloadMergesExtraIntoCustomFields() {
        var draft = VendorDraft(name: "X")
        draft.extra = ["source": "catalog"]

        let custom = FilaManPayloadBuilder.vendorPayload(from: draft)["custom_fields"] as? [String: String]

        #expect(custom?["source"] == "catalog")
    }

    @Test func vendorPayloadMapsEmptySpoolWeightToEmptySpoolWeightG() {
        var draft = VendorDraft(name: "X")
        draft.emptySpoolWeight = 201.0

        let payload = FilaManPayloadBuilder.vendorPayload(from: draft)

        #expect(payload["empty_spool_weight_g"] as? Double == 201.0)
    }

    @Test func vendorPayloadOmitsEmptySpoolWeightGWhenNil() {
        let payload = FilaManPayloadBuilder.vendorPayload(from: VendorDraft(name: "X"))

        #expect(payload["empty_spool_weight_g"] == nil)
    }

    // MARK: - Locations

    @Test func locationPayloadCarriesNameVerbatim() {
        #expect(FilaManPayloadBuilder.locationPayload(name: "Shelf B")["name"] as? String == "Shelf B")
    }

    // MARK: - The emulation is gone, the data is not (2026-08-28)

    /// SpoolKid no longer contributes the four emulated keys. There is no
    /// separate `customFields(from:)` — `filamentPayload` is the builder that
    /// used to write them inline, so its `custom_fields` output is what this
    /// asserts against.
    @Test func aFilamentPayloadNoLongerWritesTheEmulatedKeys() {
        var draft = FilamentDraft()
        draft.name = "PLA Silk GOLD"
        draft.material = "PLA"
        draft.comment = .set("should not travel")
        draft.articleNumber = .set("should not travel")
        draft.extruderTemp = .set(220)
        draft.bedTemp = .set(60)
        // Forces `custom_fields` to actually exist, so a builder that dropped
        // the key entirely could not pass this by accident — the four
        // `#expect`s below have to be reading a real dictionary.
        draft.extra = .set(["spool_core_diameter": "genuine"])

        let fields = FilaManPayloadBuilder.filamentPayload(from: draft, manufacturerId: 1)["custom_fields"] as? [String: String]

        #expect(fields?["spool_core_diameter"] == "genuine")
        #expect(fields?["comment"] == nil)
        #expect(fields?["article_number"] == nil)
        #expect(fields?["settings_extruder_temp"] == nil)
        #expect(fields?["settings_bed_temp"] == nil)
    }

    /// …and a save over a record that HAS them leaves them exactly where they
    /// are. 46 of 50 filaments on the owner's server depend on this.
    @Test func aSaveDoesNotRemoveEmulatedKeysAlreadyOnTheServer() {
        let existing: [String: FilaManJSONValue] = [
            "comment": .string("Closed enclosure, speed < 200 mm/s"),
            "article_number": .string("FAP171-9005"),
            "spoolman_id": .string("177")
        ]

        let merged = FilaManService.mergedCustomFields(existing: existing, new: ["card_uids": "04A1"])

        #expect(merged["comment"]?.displayString == "Closed enclosure, speed < 200 mm/s")
        #expect(merged["article_number"]?.displayString == "FAP171-9005")
        #expect(merged["spoolman_id"]?.displayString == "177")
        #expect(merged["card_uids"]?.displayString == "04A1")
    }

    // MARK: - Status picker (2026-08-28)

    /// Shape measured from the owner's live FilaMan, 2026-08-28.
    @Test func statusOptionsDecodeFromTheLiveShape() throws {
        let json = """
        [{"id":1,"key":"new","label":"New","description":"New spool","sort_order":1},
         {"id":6,"key":"archived","label":"Archived","description":"Archived","sort_order":6}]
        """.data(using: .utf8)!

        let options = try JSONDecoder().decode([FilaManSpoolStatus.Option].self, from: json)

        #expect(options.map(\.key) == ["new", "archived"])
        #expect(options.first?.label == "New")
        #expect(options.last?.id == 6)
    }

    /// The endpoint takes a key string, never the numeric id (422 otherwise) —
    /// so the generalised builder must carry the key straight through.
    @Test func aStatusPayloadCarriesTheKeyNotTheId() {
        #expect(FilaManPayloadBuilder.statusPayload(key: "drying")["status"] as? String == "drying")
    }

    /// The archived overload must keep producing exactly what it always did,
    /// or every existing archive path changes meaning underneath this task.
    @Test func theArchivedOverloadStillAgreesWithTheKeyOne() {
        for archived in [true, false] {
            let viaFlag = FilaManPayloadBuilder.statusPayload(archived: archived)["status"] as? String
            let viaKey = FilaManPayloadBuilder
                .statusPayload(key: FilaManSpoolStatus.key(archived: archived))["status"] as? String
            #expect(viaFlag == viaKey)
        }
    }

    // MARK: - Location identifier (FilaMan's own NFC tag field)

    /// FilaMan stores `locations.identifier` as colon-separated lowercase hex,
    /// two characters per segment. It ships a migration whose only job is
    /// padding leading zeros back onto identifiers an older scale firmware
    /// stripped, so the padding is load-bearing on their side — SpoolKid's
    /// normalization (uppercase, unseparated) has to be converted, not sent.
    @Test func aLocationIdentifierIsColonSeparatedLowercaseHex() {
        #expect(FilaManPayloadBuilder.locationIdentifier(fromUID: "04A1B2C3") == "04:a1:b2:c3")
    }

    /// A leading zero byte is exactly the case FilaMan's migration exists for.
    @Test func aLeadingZeroByteKeepsItsPadding() {
        #expect(FilaManPayloadBuilder.locationIdentifier(fromUID: "04F5023A") == "04:f5:02:3a")
    }

    /// SpoolKid's own separators and casing are stripped first, so the same tag
    /// converts identically however the UID reached us.
    @Test func theInputIsNormalizedBeforeItIsFormatted() {
        let spaced = FilaManPayloadBuilder.locationIdentifier(fromUID: "04:a1:b2:c3")
        #expect(spaced == "04:a1:b2:c3")
        #expect(FilaManPayloadBuilder.locationIdentifier(fromUID: "04-A1-B2-C3") == spaced)
    }

    /// FilaMan puts no constraint on the column, so a malformed value would be
    /// stored happily and read back as a binding matching nothing. Refusing is
    /// the honest answer.
    @Test func aMalformedUIDIsRefusedRatherThanStored() {
        #expect(FilaManPayloadBuilder.locationIdentifier(fromUID: "") == nil)
        #expect(FilaManPayloadBuilder.locationIdentifier(fromUID: "ZZZZ") == nil)
        #expect(FilaManPayloadBuilder.locationIdentifier(fromUID: "04A") == nil)
    }

    /// `LocationUpdate` is `exclude_unset`, so a body carrying only this key
    /// leaves `name` and `custom_fields` alone. A body carrying `name` too
    /// would rewrite the name on every tag write.
    @Test func theIdentifierPayloadCarriesNothingElse() {
        let payload = FilaManPayloadBuilder.locationIdentifierPayload("04:a1:b2:c3")

        #expect(payload.count == 1)
        #expect(payload["identifier"] as? String == "04:a1:b2:c3")
    }

    /// Clearing has to travel as an explicit null: an omitted key is
    /// `exclude_unset`'s "leave it alone", which is the opposite instruction.
    @Test func clearingTheIdentifierSendsAnExplicitNull() {
        #expect(FilaManPayloadBuilder.locationIdentifierPayload(nil)["identifier"] is NSNull)
    }

    // MARK: - TD (`custom_fields["td"]`)

    @Test func tdIsWrittenAsNumber() {
        let result = FilaManPayloadBuilder.customFieldsApplyingTransmissionDistance(
            .set(3.5), to: ["spoolman_id": .int(4)]
        )
        #expect(result == ["spoolman_id": .int(4), "td": .double(3.5)])
    }

    /// FilaMan's PATCH replaces `custom_fields` whole, so omitting the key is
    /// a real clear.
    @Test func tdClearRemovesKey() {
        let result = FilaManPayloadBuilder.customFieldsApplyingTransmissionDistance(
            .setNil, to: ["spoolman_id": .int(4), "td": .double(3.5)]
        )
        #expect(result == ["spoolman_id": .int(4)])
    }

    @Test func registryPayloadForTD() {
        let payload = FilaManPayloadBuilder.systemExtraFieldPayload(
            targetType: "filament", key: TransmissionDistance.fieldKey, label: TransmissionDistance.fieldName,
            fieldType: "number", config: ["unit": "mm", "decimal_places": 1]
        )
        #expect(payload["target_type"] as? String == "filament")
        #expect(payload["key"] as? String == "td")
        #expect(payload["label"] as? String == "Transmission Distance (TD)")
        #expect(payload["field_type"] as? String == "number")
        let config = payload["config"] as? [String: Any]
        #expect(config?["unit"] as? String == "mm")
        #expect(config?["decimal_places"] as? Int == 1)
    }

    @Test func cardUIDsRegistryPayloadIsUnchanged() {
        let payload = FilaManPayloadBuilder.systemExtraFieldPayload(targetType: "spool", key: "card_uids", label: "Card UIDs")
        #expect(payload["field_type"] as? String == "text")
        #expect(payload["config"] == nil)
    }

    @Test func registryRefusalIsCaveat() {
        let note = FilaManRepository.transmissionDistanceRegistryNote(error: "Forbidden.")
        #expect(note.contains("TD saved"))
        #expect(note.contains("field list"))
        #expect(note.contains("Forbidden."))
    }
}
