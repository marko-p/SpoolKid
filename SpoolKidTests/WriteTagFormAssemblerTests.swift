import Foundation
import Testing
@testable import SpoolKid

struct WriteTagFormAssemblerTests {
    @Test func localOverrideUsesProvidedFormatWithoutMutatingDefault() {
        let selected = WriteTagFormAssembler.initialOverride(defaultRawValue: TagFormat.openPrintTag.rawValue)
        #expect(selected == .openPrintTag)
    }

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

    @Test func openPrintTagWritesNameOmitsSubtypeAndKeepsSpoolIDWhenEnabled() {
        let data = WriteTagFormAssembler.buildTagData(
            format: .openPrintTag,
            name: "Silk Green",
            material: "PLA",
            subtype: "Ignored",
            brand: "OpenPrint",
            colorHex: "11AA33",
            minNozzleTemp: 195,
            maxNozzleTemp: 220,
            minBedTemp: 45,
            maxBedTemp: 60,
            spoolmanId: 88,
            writeSpoolID: true
        )

        #expect(data.name == "Silk Green")
        #expect(data.subtype == nil)
        #expect(data.spoolmanId == 88)
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

    @Test func opentag3dKeepsSubtypeButOpenPrintTagDropsIt() {
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

        let opt = WriteTagFormAssembler.buildTagData(
            format: .openPrintTag,
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
        #expect(opt.subtype == nil)
    }

    @Test func visibleFieldsAreGatedByFormatVisibilityStore() {
        let defaults = UserDefaults(suiteName: "WriteTagFormAssemblerTests.visibleFields")!
        defaults.removePersistentDomain(forName: "WriteTagFormAssemblerTests.visibleFields")
        defaults.set(false, forKey: AppConfig.visibilityNFCOpenSpoolSubtypeKey)

        let visibilityStore = NFCFieldVisibilityStore(userDefaults: defaults)
        let openSpoolFieldIDs = Set(WriteTagFormAssembler.visibleFields(format: .openSpool, visibilityStore: visibilityStore).map(\.id))
        let openPrintTagFieldIDs = Set(WriteTagFormAssembler.visibleFields(format: .openPrintTag, visibilityStore: visibilityStore).map(\.id))

        #expect(!openSpoolFieldIDs.contains("subtype"))
        #expect(openPrintTagFieldIDs.contains("name"))
    }
}
