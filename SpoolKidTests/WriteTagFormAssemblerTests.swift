import Foundation
import Testing
@testable import SpoolKid

struct WriteTagFormAssemblerTests {
    @Test func localOverrideFallsBackToOpenSpoolForInvalidRawValue() {
        let selected = WriteTagFormAssembler.initialOverride(defaultRawValue: "not-a-format")
        #expect(selected == .openSpool)
    }

    @Test func openspoolWritesCustomSubtypeAndSpoolID() {
        let data = WriteTagFormAssembler.buildTagData(
            format: .openSpool,
            name: "My PLA",
            material: "PLA",
            subtype: "Custom Pearl",
            brand: "Generic",
            colorHex: "AABBCC",
            minNozzleTemp: 190,
            maxNozzleTemp: 220,
            minBedTemp: 50,
            maxBedTemp: 70,
            spoolmanId: 42,
            writeSpoolID: true
        )

        #expect(data.subtype == "Custom Pearl")
        #expect(data.spoolmanId == 42)
    }

    @Test func extraColorsSurviveBuildTagData() {
        let data = WriteTagFormAssembler.buildTagData(
            format: .openSpool,
            name: "Dual",
            material: "PLA",
            subtype: "",
            brand: "Brand",
            colorHex: "2D39C9",
            additionalColorHexes: ["A51A52"],
            minNozzleTemp: 190,
            maxNozzleTemp: 220,
            minBedTemp: 50,
            maxBedTemp: 70,
            spoolmanId: nil,
            writeSpoolID: false
        )

        #expect(data.colorHex == "2D39C9")
        #expect(data.additionalColorHexes == ["A51A52"])
    }

    @Test func openTag3DWritesNameAndSubtypeButNeverSpoolID() {
        let data = WriteTagFormAssembler.buildTagData(
            format: .openTag3D,
            name: "Cloud White",
            material: "PLA",
            subtype: "Matte",
            brand: "OpenTag3D",
            colorHex: "FFFFFF",
            minNozzleTemp: 190,
            maxNozzleTemp: 220,
            minBedTemp: 50,
            maxBedTemp: 65,
            spoolmanId: 7,
            writeSpoolID: true
        )

        #expect(data.name == "Cloud White")
        #expect(data.subtype == "Matte")
        #expect(data.spoolmanId == nil)
    }

    @Test func anycubicACEWritesNameOmitsSubtypeAndNeverSpoolID() {
        let data = WriteTagFormAssembler.buildTagData(
            format: .anycubicACE,
            name: "ACE-SKU-01",
            material: "PLA",
            subtype: "Ignored",
            brand: "Anycubic",
            colorHex: "000000",
            minNozzleTemp: 200,
            maxNozzleTemp: 230,
            minBedTemp: 55,
            maxBedTemp: 70,
            spoolmanId: 55,
            writeSpoolID: true
        )

        #expect(data.name == "ACE-SKU-01")
        #expect(data.subtype == nil)
        #expect(data.spoolmanId == nil)
    }

    @Test func trimsWhitespaceFromNameAndSubtypeForOpenTag3D() {
        let data = WriteTagFormAssembler.buildTagData(
            format: .openTag3D,
            name: "  Deep Blue  ",
            material: "PLA",
            subtype: "  Matte  ",
            brand: "Test",
            colorHex: "123456",
            minNozzleTemp: 190,
            maxNozzleTemp: 220,
            minBedTemp: 50,
            maxBedTemp: 60,
            spoolmanId: nil,
            writeSpoolID: false
        )

        #expect(data.name == "Deep Blue")
        #expect(data.subtype == "Matte")
    }

    @Test func normalizesEmptyNameAndSubtypeToNilAfterTrimming() {
        let data = WriteTagFormAssembler.buildTagData(
            format: .openSpool,
            name: "   \n",
            material: "PLA",
            subtype: "   ",
            brand: "Test",
            colorHex: "ABCDEF",
            minNozzleTemp: 190,
            maxNozzleTemp: 220,
            minBedTemp: 50,
            maxBedTemp: 60,
            spoolmanId: nil,
            writeSpoolID: false
        )

        #expect(data.name == nil)
        #expect(data.subtype == nil)
    }

    @Test func subtypeServiceIncludesKnownPresetAndCustomPassthrough() {
        let options = SubtypeOptionService.presetOptions
        #expect(options.contains("Basic"))
        #expect(options.contains("Silk"))

        let resolved = SubtypeOptionService.resolve(userInput: "MySpecialBlend")
        #expect(resolved == "MySpecialBlend")
    }

    @Test func openTag3DKeepsSubtypeButAceDropsIt() {
        let ot3d = WriteTagFormAssembler.buildTagData(
            format: .openTag3D,
            name: "Color Name",
            material: "PLA",
            subtype: "Silk",
            brand: "Generic",
            colorHex: "112233",
            minNozzleTemp: 200,
            maxNozzleTemp: 220,
            minBedTemp: 50,
            maxBedTemp: 60,
            spoolmanId: 5,
            writeSpoolID: true
        )

        let ace = WriteTagFormAssembler.buildTagData(
            format: .anycubicACE,
            name: "Material Name",
            material: "PLA",
            subtype: "Silk",
            brand: "Generic",
            colorHex: "112233",
            minNozzleTemp: 200,
            maxNozzleTemp: 220,
            minBedTemp: 50,
            maxBedTemp: 60,
            spoolmanId: 5,
            writeSpoolID: true
        )

        #expect(ot3d.subtype == "Silk")
        #expect(ace.subtype == nil)
    }

    @Test func visibleFieldsAreGatedByFormatVisibilityStore() {
        let defaults = UserDefaults(suiteName: "WriteTagFormAssemblerTests.visibleFields")!
        defaults.removePersistentDomain(forName: "WriteTagFormAssemblerTests.visibleFields")
        defaults.set(false, forKey: AppConfig.visibilityNFCOpenSpoolSubtypeKey)

        let visibilityStore = NFCFieldVisibilityStore(userDefaults: defaults)
        let openSpoolFieldIDs = Set(WriteTagFormAssembler.visibleFields(format: .openSpool, visibilityStore: visibilityStore).map(\.id))

        #expect(!openSpoolFieldIDs.contains("subtype"))
    }

    /// Page 30 and 31 of an ACE tag carry diameter and net weight, so the form
    /// has to be able to state them rather than always writing a default.
    @Test func aceOffersDiameterAndNetWeightByDefault() {
        let suite = "WriteTagFormAssemblerTests.aceDefaults"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let visibilityStore = NFCFieldVisibilityStore(userDefaults: defaults)
        let fieldIDs = Set(WriteTagFormAssembler.visibleFields(format: .anycubicACE, visibilityStore: visibilityStore).map(\.id))

        #expect(fieldIDs.contains("diameter"))
        #expect(fieldIDs.contains("nominal_weight"))
    }

    @Test func aceDiameterAndNetWeightCanBeHidden() {
        let suite = "WriteTagFormAssemblerTests.aceHidden"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(false, forKey: AppConfig.visibilityNFCAnycubicDiameterKey)
        defaults.set(false, forKey: AppConfig.visibilityNFCAnycubicNominalWeightKey)

        let visibilityStore = NFCFieldVisibilityStore(userDefaults: defaults)
        let fieldIDs = Set(WriteTagFormAssembler.visibleFields(format: .anycubicACE, visibilityStore: visibilityStore).map(\.id))

        #expect(!fieldIDs.contains("diameter"))
        #expect(!fieldIDs.contains("nominal_weight"))
    }

    @Test func nameFieldShowsWhenVisibleInFormatVisibility() {
        let shouldShow = WriteTagFormAssembler.shouldShowNameField(
            visibleFieldIDs: ["name"]
        )

        #expect(shouldShow)
    }

    @Test func nameFieldHidesWhenNotVisibleInFormatVisibility() {
        let shouldShow = WriteTagFormAssembler.shouldShowNameField(
            visibleFieldIDs: []
        )

        #expect(!shouldShow)
    }

    @Test func dateUnixRoundTripPreservesDayPrecision() {
        let calendar = Calendar(identifier: .gregorian)
        let components = DateComponents(year: 2026, month: 5, day: 8, hour: 12, minute: 0, second: 0)
        guard let sourceDate = calendar.date(from: components) else {
            Issue.record("Failed to create source date")
            return
        }

        let unix = WriteTagFormAssembler.unixSeconds(from: sourceDate)
        guard let roundTrip = WriteTagFormAssembler.date(fromUnixSeconds: unix) else {
            Issue.record("Failed to decode unix seconds")
            return
        }

        let roundTripComponents = calendar.dateComponents([.year, .month, .day], from: roundTrip)
        #expect(roundTripComponents.year == 2026)
        #expect(roundTripComponents.month == 5)
        #expect(roundTripComponents.day == 8)
    }

    @Test func appConfigSubtypesIsSingleSourceForPresetOptions() {
        let presetOptions = SubtypeOptionService.presetOptions
        #expect(presetOptions == AppConfig.subtypes)
        #expect(Set(presetOptions).isSuperset(of: ["Basic", "Silk", "HF", "Matte"]))
    }

    // MARK: - OpenPrintTag rich build (Task 4)

    @Test func buildsOpenPrintTagRichFields() {
        let data = WriteTagFormAssembler.buildTagData(
            format: .openPrintTag,
            name: "PLA Galaxy", material: "PLA", subtype: "", brand: "Prusament",
            colorHex: "3D3E3D", minNozzleTemp: 205, maxNozzleTemp: 225,
            minBedTemp: 40, maxBedTemp: 60, spoolmanId: nil, writeSpoolID: false,
            preheatTemp: 170, nominalNetWeight: 1000, emptyContainerWeight: 280,
            density: 1.24, dryingTemp: 55, dryingTime: 480,
            gtin: "8594173675001", countryOfOrigin: "CZ",
            manufacturedDateUnix: 1758709719, tagURL: "https://3dtag.org/s/abc"
        )
        #expect(data.name == "PLA Galaxy")
        #expect(data.subtype == nil)
        #expect(data.preheatTemp == 170)
        #expect(data.nominalNetWeight == 1000)
        #expect(data.emptyContainerWeight == 280)
        #expect(data.density == 1.24)
        #expect(data.dryingTemp == 55)
        #expect(data.dryingTime == 480)
        #expect(data.gtin == "8594173675001")
        #expect(data.countryOfOrigin == "CZ")
        #expect(data.manufacturedDateUnix == 1758709719)
        #expect(data.tagURL == "https://3dtag.org/s/abc")
    }

    @Test func openSpoolUnaffectedByRichDefaults() {
        let data = WriteTagFormAssembler.buildTagData(
            format: .openSpool, name: "x", material: "PLA", subtype: "", brand: "B",
            colorHex: "000000", minNozzleTemp: 200, maxNozzleTemp: 210,
            minBedTemp: 50, maxBedTemp: 60, spoolmanId: nil, writeSpoolID: false
        )
        #expect(data.density == nil)
        #expect(data.tagURL == nil)
    }

    // MARK: - Writable formats

    /// Every format writes since ELEGOO gained an encoder (2026-10-05, issue
    /// #14). Until then ELEGOO decoded only — the decoder guessed between
    /// three layouts, so there was nothing authoritative to write back — and
    /// these tests pinned it out of the picker. `canWrite` stays so a future
    /// read-only format cannot reach the picker unnoticed.
    @Test func everyFormatCanBeWritten() {
        for format in TagFormat.allCases {
            #expect(format.canWrite, "\(format.displayName) should be writable")
        }
        #expect(TagFormat.writable == TagFormat.allCases)
    }

    /// The Settings.bundle format picker governs reads too, so `elegoo` is a
    /// legitimate stored default — and now one the form opens on.
    @Test func aStoredELEGOODefaultOpensOnELEGOO() {
        #expect(WriteTagFormAssembler.initialOverride(defaultRawValue: "elegoo") == .elegoo)
    }

    // MARK: - ELEGOO

    /// Page 19 names the Canvas subtype, so it is written, not dropped.
    @Test func elegooKeepsTheCanvasSubtype() {
        #expect(elegooData(name: "", subtype: "PLA Silk").subtype == "PLA Silk")
    }

    /// The block has no brand field: every ELEGOO tag reads back as ELEGOO,
    /// so that is what the write records — not the spool's brand.
    @Test func anELEGOOTagStatesELEGOOAsItsBrand() {
        #expect(elegooData(name: "", subtype: "").brand == "ELEGOO")
    }

    /// Nor a name field.
    @Test func anELEGOOTagCarriesNoName() {
        #expect(elegooData(name: "Bench spool", subtype: "").name == nil)
    }

    @Test func theCaptionSaysWhatTheCanvasWillRead() throws {
        let silk = try #require(ElegooCanvasCatalog.entry(typeIndex: 0, subtypeID: 3))
        #expect(WriteTagFormAssembler.elegooFilamentCaption(entry: silk, material: "PLA")
                == "The Canvas reads this as ELEGOO PLA Silk. ELEGOO tags hold no brand or name — SpoolKid still links the tag to your spool.")
    }

    @Test func theCaptionAsksForAPickWhenTheMaterialHasNoCanvasEquivalent() {
        #expect(WriteTagFormAssembler.elegooFilamentCaption(entry: nil, material: "Nylon")
                == "Pick a Canvas filament — \u{201C}Nylon\u{201D} has no Canvas equivalent.")
        #expect(WriteTagFormAssembler.elegooFilamentCaption(entry: nil, material: " ")
                == "Pick a Canvas filament.")
    }

    private func elegooData(name: String, subtype: String) -> FilamentTagData {
        WriteTagFormAssembler.buildTagData(
            format: .elegoo,
            name: name,
            material: "PLA",
            subtype: subtype,
            brand: "Sunlu",
            colorHex: "29D464",
            minNozzleTemp: 190,
            maxNozzleTemp: 230,
            minBedTemp: 50,
            maxBedTemp: 60,
            spoolmanId: 12,
            writeSpoolID: true
        )
    }

    /// The pre-existing fallback still holds, and a writable default is still
    /// honoured — this must not have become "always OpenSpool".
    @Test func aWritableStoredDefaultIsStillHonoured() {
        #expect(WriteTagFormAssembler.initialOverride(defaultRawValue: "opentag3d") == .openTag3D)
        #expect(WriteTagFormAssembler.initialOverride(defaultRawValue: "anycubic_ace") == .anycubicACE)
        #expect(WriteTagFormAssembler.initialOverride(defaultRawValue: "nonsense") == .openSpool)
    }

    // MARK: - Spool data reaches the tag model (printer parity, Task 3)

    private func build(
        _ format: TagFormat, nominalNetWeight: Double? = nil, remainingWeight: Int? = nil
    ) -> FilamentTagData {
        WriteTagFormAssembler.buildTagData(
            format: format, name: "PLA Galaxy", material: "PLA", subtype: "", brand: "Prusament",
            colorHex: "3D3E3D", minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 40, maxBedTemp: 60,
            spoolmanId: nil, writeSpoolID: false, nominalNetWeight: nominalNetWeight,
            remainingWeight: remainingWeight
        )
    }

    @Test func prefillCoversEveryRichField() {
        let data = FilamentTagData(
            name: "PLA Galaxy", material: "PLA", brand: "Prusament", colorHex: "3D3E3D",
            minNozzleTemp: 205, maxNozzleTemp: 225, minBedTemp: 40, maxBedTemp: 60,
            density: 1.24, diameter: 1.75, gtin: "8594173675001", manufacturedDateUnix: 1_758_709_719,
            countryOfOrigin: "CZ", preheatTemp: 170, dryingTemp: 55, dryingTime: 480,
            nominalNetWeight: 1000, emptyContainerWeight: 196, tagURL: "https://3dtag.org/s/abc",
            consumedWeight: 388
        )

        #expect(WriteTagFormAssembler.prefill(from: data) == WriteTagPrefill(
            nominalWeight: 1000, emptyWeight: 196, remaining: 612,
            density: "1.24", diameter: "1.75",
            preheat: 170, dryingTemp: 55, dryingTime: 480,
            gtin: "8594173675001", country: "CZ",
            manufactured: Date(timeIntervalSince1970: 1_758_709_719), url: "https://3dtag.org/s/abc"
        ))
    }

    @Test func prefillOfBareDataIsEmpty() {
        let data = FilamentTagData(
            material: "PLA", brand: "B", colorHex: "000000",
            minNozzleTemp: 200, maxNozzleTemp: 210, minBedTemp: 50, maxBedTemp: 60
        )

        #expect(WriteTagFormAssembler.prefill(from: data) == WriteTagPrefill(
            nominalWeight: 0, emptyWeight: 0, remaining: nil, density: "", diameter: "",
            preheat: 0, dryingTemp: 0, dryingTime: 0, gtin: "", country: "", manufactured: nil, url: ""
        ))
    }

    /// Remaining is on the printer's basis (actual full weight, else nominal)
    /// and rounds to the form's whole grams; a stated zero is not a density.
    @Test func prefillRemainingFollowsThePrintersBasis() {
        var data = FilamentTagData(
            material: "PLA", brand: "B", colorHex: "000000",
            minNozzleTemp: 200, maxNozzleTemp: 210, minBedTemp: 50, maxBedTemp: 60,
            density: 0, diameter: 0,
            nominalNetWeight: 1000, actualNetWeight: 1012, consumedWeight: 400.4
        )
        let prefill = WriteTagFormAssembler.prefill(from: data)
        #expect(prefill.remaining == 612)
        #expect(prefill.nominalWeight == 1000)
        #expect(prefill.density == "")
        #expect(prefill.diameter == "")

        data.consumedWeight = 5000
        #expect(WriteTagFormAssembler.prefill(from: data).remaining == 0)
    }

    /// A tag's floats are untrusted: a corrupt weight must not trap the form.
    @Test func prefillSurvivesWeightsNoIntCanHold() {
        let data = FilamentTagData(
            material: "PLA", brand: "B", colorHex: "000000",
            minNozzleTemp: 200, maxNozzleTemp: 210, minBedTemp: 50, maxBedTemp: 60,
            density: .infinity, nominalNetWeight: 1e300, emptyContainerWeight: .infinity
        )
        let prefill = WriteTagFormAssembler.prefill(from: data)
        #expect(prefill.nominalWeight == 0)
        #expect(prefill.emptyWeight == 0)
        #expect(prefill.density == "")
    }

    @Test func buildTagDataWritesConsumptionOnlyForOpenPrintTag() {
        #expect(build(.openPrintTag, nominalNetWeight: 1000, remainingWeight: 612).consumedWeight == 388)
        #expect(build(.openTag3D, nominalNetWeight: 1000, remainingWeight: 612).consumedWeight == nil)
        #expect(build(.anycubicACE, nominalNetWeight: 1000, remainingWeight: 612).consumedWeight == nil)
    }

    /// A blank Remaining is a full spool and 0 is an empty one. Nothing is
    /// recorded without a stated net weight to count down from.
    @Test func buildTagDataStatesNoConsumptionWithoutBothWeights() {
        #expect(build(.openPrintTag, nominalNetWeight: 1000, remainingWeight: nil).consumedWeight == nil)
        #expect(build(.openPrintTag, nominalNetWeight: 1000, remainingWeight: 0).consumedWeight == 1000)
        #expect(build(.openPrintTag, nominalNetWeight: 1000, remainingWeight: 1000).consumedWeight == nil)
        #expect(build(.openPrintTag, nominalNetWeight: nil, remainingWeight: 612).consumedWeight == nil)
        #expect(build(.openPrintTag, nominalNetWeight: 0, remainingWeight: 612).consumedWeight == nil)
    }

    private static let everyRow: Set<String> = ["nominal_weight", "density", "diameter"]

    @Test func countdownBlockersListWhatIsMissing() {
        #expect(WriteTagFormAssembler.countdownBlockers(
            visibleFieldIDs: Self.everyRow, nominalWeight: 1000, density: "1.24", diameter: "1,75"
        ) == [])
        #expect(WriteTagFormAssembler.countdownBlockers(
            visibleFieldIDs: Self.everyRow, nominalWeight: 0, density: "", diameter: "1.75"
        ) == ["Net Weight", "Density"])
        #expect(WriteTagFormAssembler.countdownBlockers(
            visibleFieldIDs: ["nominal_weight", "density"], nominalWeight: 1000, density: "1.24", diameter: "1.75"
        ) == ["Diameter"])
    }

    @Test func countdownBlockersCountEveryRowThatIsHiddenOrNotANumberAboveZero() {
        #expect(WriteTagFormAssembler.countdownBlockers(
            visibleFieldIDs: [], nominalWeight: 1000, density: "1.24", diameter: "1.75"
        ) == ["Net Weight", "Density", "Diameter"])
        #expect(WriteTagFormAssembler.countdownBlockers(
            visibleFieldIDs: Self.everyRow, nominalWeight: 1000, density: "0", diameter: "abc"
        ) == ["Density", "Diameter"])
        #expect(WriteTagFormAssembler.countdownBlockers(
            visibleFieldIDs: Self.everyRow, nominalWeight: -5, density: "-1.2", diameter: "1.75"
        ) == ["Net Weight", "Density"])
    }

    /// Call 11 / decision 5: the spool form's Write Tag carries the spool's weights and
    /// diameter into every format, ACE included.
    @Test func spoolWriteDataCarriesTheSpoolsWeights() {
        let spool = FilamentTagDataExtensionsTests.weighedSpool()
        let data = WriteTagFormAssembler.spoolWriteData(
            for: spool, format: .anycubicACE, writesSpoolID: false, spoolIDsResolveViaSpoolLink: true
        )

        #expect(data.nominalNetWeight == 1000)
        #expect(data.diameter == 1.75)
        #expect(data.emptyContainerWeight == 196)
        #expect(data.consumedWeight == nil)
    }

    /// Only OpenPrintTag has a consumed-weight field, so only its write
    /// carries the spool's consumption, as `buildTagData` does.
    @Test func spoolWriteDataCarriesConsumptionOnlyForOpenPrintTag() {
        let spool = FilamentTagDataExtensionsTests.weighedSpool()

        #expect(WriteTagFormAssembler.spoolWriteData(
            for: spool, format: .openPrintTag, writesSpoolID: false, spoolIDsResolveViaSpoolLink: true
        ).consumedWeight == 388)
        #expect(WriteTagFormAssembler.spoolWriteData(
            for: spool, format: .openTag3D, writesSpoolID: false, spoolIDsResolveViaSpoolLink: true
        ).consumedWeight == nil)
    }

    /// Issue #14: the spool form's Write Tag wrote the spool's own material and
    /// subtype, which name no Canvas filament ("PLA" + "Matte"), so every ELEGOO
    /// write from the spool form failed at the tag. It now writes the Canvas
    /// filament Write Tag would suggest.
    @Test func spoolWriteDataForELEGOOIsTheSuggestedCanvasFilament() {
        let spool = Self.spool(named: "PLA Matte Black", material: "PLA")
        let data = WriteTagFormAssembler.spoolWriteData(
            for: spool, format: .elegoo, writesSpoolID: false, spoolIDsResolveViaSpoolLink: true
        )

        #expect(data.material == "PLA")
        #expect(data.subtype == "PLA Matte")
        #expect(data.brand == "ELEGOO")
        #expect(data.name == nil)
        #expect(NFCManager.rawFilamentWritePages(for: data, format: .elegoo)?.isEmpty == false)
    }

    /// "Basic" is SpoolKid's fallback subtype, so it means the plain entry.
    @Test func spoolWriteDataForELEGOOWritesPlainPLAForABasicSpool() {
        let data = WriteTagFormAssembler.spoolWriteData(
            for: FilamentTagDataExtensionsTests.weighedSpool(), format: .elegoo,
            writesSpoolID: false, spoolIDsResolveViaSpoolLink: true
        )

        #expect(data.material == "PLA")
        #expect(data.subtype == nil)
        #expect(NFCManager.rawFilamentWritePages(for: data, format: .elegoo)?.isEmpty == false)
    }

    /// Other formats keep the spool's own fields.
    @Test func spoolWriteDataOutsideELEGOOKeepsTheSpoolsFields() {
        let data = WriteTagFormAssembler.spoolWriteData(
            for: Self.spool(named: "PLA Matte Black", material: "PLA"), format: .openSpool,
            writesSpoolID: false, spoolIDsResolveViaSpoolLink: true
        )

        #expect(data.subtype == "Matte")
        #expect(data.brand == "Prusament")
        #expect(data.name == "PLA Matte Black")
    }

    private static func spool(named name: String, material: String) -> Spool {
        let filament = Filament(
            id: 3, name: name, material: material, vendor: Vendor(id: 11, name: "Prusament"),
            colorHex: "3D3E3D", density: 1.24, diameter: 1.75, weight: 750, spoolWeight: 250
        )
        return Spool(id: 9, filament: filament, statusId: nil, externalId: nil, purchaseDate: nil)
    }

    /// A tag that states only an actual net weight still has a full weight to
    /// count down from, so rewriting it keeps its consumption.
    @Test func prefillTakesTheActualWeightWhenNoNominalIsStated() {
        let data = FilamentTagData(
            material: "PLA", brand: "B", colorHex: "000000",
            minNozzleTemp: 200, maxNozzleTemp: 210, minBedTemp: 50, maxBedTemp: 60,
            actualNetWeight: 818, consumedWeight: 200
        )
        let prefill = WriteTagFormAssembler.prefill(from: data)
        #expect(prefill.nominalWeight == 818)
        #expect(prefill.remaining == 618)
    }

    /// The one rule for a decimal the user typed: a comma is a decimal
    /// separator, and anything that is not a number above zero is not stated.
    @Test func statedDecimalParsesWhatTheWritePathParses() {
        #expect(WriteTagFormAssembler.statedDecimal("1,75") == 1.75)
        #expect(WriteTagFormAssembler.statedDecimal("1.24") == 1.24)
        #expect(WriteTagFormAssembler.statedDecimal("") == nil)
        #expect(WriteTagFormAssembler.statedDecimal("0") == nil)
        #expect(WriteTagFormAssembler.statedDecimal("-1.2") == nil)
        #expect(WriteTagFormAssembler.statedDecimal("abc") == nil)
        #expect(WriteTagFormAssembler.statedDecimal("inf") == nil)
    }
}
