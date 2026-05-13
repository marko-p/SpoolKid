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

    @Test func openSpoolNameFieldRemainsVisibleWhenU1CompatEnabledIfVisibilityAllowsIt() {
        let shouldShow = WriteTagFormAssembler.shouldShowNameField(
            format: .openSpool,
            visibleFieldIDs: ["name"],
            isU1CompatActive: true
        )

        #expect(shouldShow)
    }

    @Test func nameFieldHidesWhenNotVisibleInFormatVisibility() {
        let shouldShow = WriteTagFormAssembler.shouldShowNameField(
            format: .openSpool,
            visibleFieldIDs: [],
            isU1CompatActive: false
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
}
