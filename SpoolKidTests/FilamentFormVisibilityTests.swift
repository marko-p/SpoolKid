import Foundation
import Testing
@testable import SpoolKid

struct FilamentFormVisibilityTests {
    /// The form helper routes through the support∩preference intersection and
    /// returns this entity's fields. It asserts the DEFAULT only: the helper
    /// takes capabilities, not a `UserDefaults`, so a toggle cannot be injected
    /// here. Toggle behaviour is covered directly, against an injected suite,
    /// in `FieldVisibilityStoreTests`.
    @Test func filamentFormHidesCommentByDefault() {
        let ids = FilamentFormView.visibleFieldIDs(for: BackendCapabilities.spoolman)

        #expect(!ids.contains("comment"))
    }

    /// Pins the Spoolman side of the Temperatures section gate (fix round 1,
    /// F31 review): the section renders when either ID is in this set, so
    /// both must stay in it on Spoolman even though FilaMan drops them.
    @Test func filamentFormShowsBothTemperaturesOnSpoolman() {
        let ids = FilamentFormView.visibleFieldIDs(for: BackendCapabilities.spoolman)

        #expect(ids.contains("settings_extruder_temp"))
        #expect(ids.contains("settings_bed_temp"))
    }

    /// …and FilaMan shows neither, since the support table no longer declares
    /// them (`BackendFieldSupportTests.filaManDoesNotDeclareFieldsItLacks`
    /// pins the table; this pins the same fact through the form's own gate).
    @Test func filamentFormHidesBothTemperaturesOnFilaMan() {
        let ids = FilamentFormView.visibleFieldIDs(for: BackendCapabilities.filaman)

        #expect(!ids.contains("settings_extruder_temp"))
        #expect(!ids.contains("settings_bed_temp"))
    }

    @Test func filamentPayloadIncludesArticleAndWeight() {
        let draft = FilamentFormView.filamentPayload(
            name: "PLA Black",
            vendorId: 1,
            material: "PLA",
            colors: FilamentColors(hexes: ["111111"]),
            density: "1.24",
            diameter: "1.75",
            extruderTemp: "210",
            bedTemp: "60",
            price: "19.99",
            weight: "1000",
            spoolWeight: "140",
            articleNumber: "PM70820",
            comment: "fast profile",
            externalId: "poly_pla_black"
        )

        #expect(draft.articleNumber == .set("PM70820"))
        #expect(draft.weight == .set(1000))
        // Not editing, so the boxes left empty say nothing rather than
        // clearing — there is no record yet to clear anything on.
        #expect(draft.multiColorHexes == .ignore)
    }

    // `filamentUpdateClearFieldKeysIncludeEmptyOptionalInputs` lived here. Same
    // idea, said in the type instead of in a set of Spoolman key names (R21
    // stage 4): an empty box on an EDIT clears the field.
    @Test func anEmptiedBoxClearsTheField() {
        let draft = emptyOptionalsDraft(loaded: "was-here", loadedVendorId: 3)

        #expect(draft.vendorId == .setNil)
        #expect(draft.comment == .setNil)
        #expect(draft.price == .setNil)
        #expect(draft.externalId == .setNil)
    }

    /// A box still holding what was loaded says NOTHING. Before this the form
    /// re-asserted every field on every save, so two people editing one
    /// filament meant the second silently reverted the first — the lost update
    /// R21 closed for spools and left standing here.
    @Test func anUntouchedBoxSaysNothing() {
        let draft = FilamentFormView.filamentPayload(
            name: "PLA", vendorId: 3, material: "PLA",
            colors: FilamentColors(hexes: ["FF0000", "00FF00"], pattern: .coextruded),
            density: "1.24", diameter: "1.75", extruderTemp: "210", bedTemp: "60",
            price: "19.99", weight: "1000", spoolWeight: "140",
            articleNumber: "ART-1", comment: "note",
            externalId: "ext-1",
            loadedVendorId: 3, loadedPrice: "19.99", loadedWeight: "1000",
            loadedSpoolWeight: "140", loadedArticleNumber: "ART-1", loadedComment: "note",
            loadedExtruderTemp: "210", loadedBedTemp: "60",
            loadedExternalId: "ext-1",
            loadedColors: FilamentColors(hexes: ["FF0000", "00FF00"], pattern: .coextruded)
        )

        #expect(draft.vendorId == .ignore)
        #expect(draft.price == .ignore)
        #expect(draft.weight == .ignore)
        #expect(draft.comment == .ignore)
        #expect(draft.extruderTemp == .ignore)
        #expect(draft.multiColorHexes == .ignore)
    }

    /// The create case falls out of the same rule: nothing was loaded, so a
    /// blank box says nothing rather than clearing.
    @Test func anEmptyBoxOnACreateSaysNothing() {
        let draft = emptyOptionalsDraft(loaded: "", loadedVendorId: nil)

        #expect(draft.vendorId == .ignore)
        #expect(draft.comment == .ignore)
        #expect(draft.price == .ignore)
        #expect(draft.externalId == .ignore)
    }

    private func emptyOptionalsDraft(loaded: String, loadedVendorId: Int?) -> FilamentDraft {
        FilamentFormView.filamentPayload(
            name: "PLA",
            vendorId: nil,
            material: "PLA",
            colors: FilamentColors(hexes: ["111111"]),
            density: "",
            diameter: "",
            extruderTemp: "",
            bedTemp: "",
            price: "",
            weight: "",
            spoolWeight: "",
            articleNumber: "",
            comment: "",
            externalId: "",
            loadedVendorId: loadedVendorId,
            loadedPrice: loaded,
            loadedWeight: loaded,
            loadedSpoolWeight: loaded,
            loadedArticleNumber: loaded,
            loadedComment: loaded,
            loadedExtruderTemp: loaded,
            loadedBedTemp: loaded,
            loadedExternalId: loaded
        )
    }

    private func draft(colors: FilamentColors, loadedColors: FilamentColors?) -> FilamentDraft {
        FilamentFormView.filamentPayload(
            name: "PLA", vendorId: nil, material: "PLA", colors: colors,
            density: "", diameter: "", extruderTemp: "", bedTemp: "",
            price: "", weight: "", spoolWeight: "", articleNumber: "", comment: "",
            externalId: "", loadedColors: loadedColors
        )
    }

    @Test func formSavesNewMultiFilament() {
        let multi = FilamentColors(hexes: ["2D39C9", "A51A52"], pattern: .coextruded)
        let draft = draft(colors: multi, loadedColors: nil)

        #expect(draft.colorHex == nil)
        #expect(draft.multiColorHexes == .set("2D39C9,A51A52"))
        #expect(draft.multiColorDirection == .set("coaxial"))
    }

    @Test func formEditUnrelatedFieldLeavesColors() {
        let multi = FilamentColors(hexes: ["2D39C9", "A51A52"], pattern: .gradient)
        let draft = draft(colors: multi, loadedColors: multi)

        #expect(draft.multiColorHexes == .ignore)
        #expect(draft.multiColorDirection == .ignore)
    }

    @Test func formSwitchToSingle() {
        var colors = FilamentColors(hexes: ["2D39C9", "A51A52"], pattern: .coextruded)
        let loaded = colors
        colors.switchToSingle()
        let draft = draft(colors: colors, loadedColors: loaded)

        #expect(draft.colorHex == "2D39C9")
        #expect(draft.multiColorHexes == .setNil)
        #expect(draft.multiColorDirection == .setNil)
    }

    @Test func filamentCatalogHasNoRawMultiColorFields() {
        let ids = FieldCatalog.fields(for: .filament).map(\.id)
        #expect(!ids.contains("multi_color_hexes"))
        #expect(!ids.contains("multi_color_direction"))
    }

    // `filamentExtraJSONValidationRejectsInvalidJSON` lived here. The Extra
    // JSON box it tested is gone as of 2026-08-28 (task 4, backend-aware
    // fields).
}
