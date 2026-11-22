//
//  ScanHubFilamentIdentityTests.swift
//  SpoolKidTests
//
//  Purpose: Covers the scan hub's filament identity seam —
//  `ScanResolutionService.findExistingFilament` / `findOrCreateFilament`
//  (vendor + material + colour, name ignored), the resolution-source tagging
//  of the mapping tiers, and the hub's provenance caption builders.
//

import Foundation
import SwiftData
import Testing
@testable import SpoolKid

// MARK: - Helpers

private func makeTag(
    material: String = "PLA",
    brand: String = "Elegoo",
    name: String? = "PLA Basic",
    subtype: String? = nil,
    colorHex: String = "FF0000",
    spoolmanId: Int? = nil
) -> FilamentTagData {
    FilamentTagData(
        name: name,
        material: material,
        subtype: subtype,
        brand: brand,
        colorHex: colorHex,
        minNozzleTemp: 190,
        maxNozzleTemp: 240,
        minBedTemp: 35,
        maxBedTemp: 65,
        spoolmanId: spoolmanId
    )
}

private func makeFilament(
    id: Int = 10,
    name: String? = "PLA Basic",
    material: String = "PLA",
    vendor: Vendor? = Vendor(id: 1, name: "Elegoo"),
    colorHex: String? = "FF0000"
) -> Filament {
    Filament(id: id, name: name, material: material, vendor: vendor, colorHex: colorHex)
}

@MainActor
private func makeLocalRepository() throws -> LocalRepository {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self,
        configurations: config
    )
    return LocalRepository(context: ModelContext(container))
}

@MainActor
private func makeResolutionService(
    repository: any SpoolDataRepository,
    ledger: TagAssociationStore = makeIsolatedLedger()
) -> ScanResolutionService {
    ScanResolutionService(
        repository: repository,
        spoolmanDBService: SpoolmanDBService.shared,
        webParserService: WebSpoolParserService.shared,
        identity: TagIdentityPolicy(mode: .spoolID, linkTargets: []),
        ledger: ledger
    )
}

// MARK: - Find existing filament (identity: vendor + material + colour)

@Suite("Scan hub filament identity find")
struct ScanHubFilamentFindTests {

    @Test("Same vendor, material and colour matches regardless of case")
    func matchesCaseInsensitively() {
        let filament = makeFilament(name: "Totally Different Name")
        let found = ScanResolutionService.findExistingFilament(
            tagData: makeTag(), filaments: [filament]
        )
        #expect(found?.id == filament.id)
    }

    @Test("Colour compares normalized: # prefix and lowercase match")
    func matchesNormalizedColor() {
        let filament = makeFilament(colorHex: "#ff0000")
        let found = ScanResolutionService.findExistingFilament(
            tagData: makeTag(colorHex: "FF0000"), filaments: [filament]
        )
        #expect(found?.id == filament.id)
    }

    @Test("Different colour does not match")
    func rejectsDifferentColor() {
        let filament = makeFilament(colorHex: "00FF00")
        let found = ScanResolutionService.findExistingFilament(
            tagData: makeTag(colorHex: "FF0000"), filaments: [filament]
        )
        #expect(found == nil)
    }

    @Test("Different vendor does not match")
    func rejectsDifferentVendor() {
        let filament = makeFilament(vendor: Vendor(id: 2, name: "Bambu Lab"))
        let found = ScanResolutionService.findExistingFilament(
            tagData: makeTag(brand: "Elegoo"), filaments: [filament]
        )
        #expect(found == nil)
    }

    @Test("Vendorless filament does not match")
    func rejectsVendorlessFilament() {
        let filament = makeFilament(vendor: nil)
        let found = ScanResolutionService.findExistingFilament(
            tagData: makeTag(brand: "Elegoo"), filaments: [filament]
        )
        #expect(found == nil)
    }

    @Test("Different material does not match")
    func rejectsDifferentMaterial() {
        let filament = makeFilament(material: "PETG")
        let found = ScanResolutionService.findExistingFilament(
            tagData: makeTag(material: "PLA"), filaments: [filament]
        )
        #expect(found == nil)
    }

    @Test("Re-scanning a multi-color tag finds the multi-color filament")
    func rescanningSameMultiTagFindsFirstFilament() {
        let filament = Filament(
            id: 11, name: "PLA Basic", material: "PLA", vendor: Vendor(id: 1, name: "Elegoo"),
            colorHex: nil, multiColorHexes: "2D39C9,A51A52", multiColorDirection: "coaxial"
        )
        var tag = makeTag(colorHex: "2D39C9")
        tag.additionalColorHexes = ["A51A52"]

        let found = ScanResolutionService.findExistingFilament(tagData: tag, filaments: [filament])

        #expect(found?.id == filament.id)
    }

    @Test("A multi-color tag does not match a single-color filament")
    func multiTagDoesNotMatchSingleColorFilament() {
        let filament = makeFilament(colorHex: "2D39C9")
        var tag = makeTag(colorHex: "2D39C9")
        tag.additionalColorHexes = ["A51A52"]

        let found = ScanResolutionService.findExistingFilament(tagData: tag, filaments: [filament])

        #expect(found == nil)
    }

    private func multi(_ id: Int, _ hexes: String) -> Filament {
        Filament(
            id: id, name: "PLA Basic", material: "PLA", vendor: Vendor(id: 1, name: "Elegoo"),
            colorHex: nil, multiColorHexes: hexes, multiColorDirection: "coaxial"
        )
    }

    private func tag(_ hexes: [String]) -> FilamentTagData {
        var tag = makeTag(colorHex: hexes[0])
        tag.additionalColorHexes = Array(hexes.dropFirst())
        return tag
    }

    @Test("An ACE tag (capacity 1) finds the 2-color filament with the same first color")
    func aceTagFindsTruncatedMultiFilament() {
        let filament = multi(11, "2D39C9,A51A52")
        let found = ScanResolutionService.findExistingFilament(
            tagData: tag(["2D39C9"]), filaments: [filament], format: .anycubicACE
        )
        #expect(found?.id == filament.id)
    }

    @Test("A TigerTag 3-color tag finds the 4-color filament with the same leading 3")
    func tigerTagFindsTruncatedFourColorFilament() {
        let filament = multi(11, "111111,222222,333333,444444")
        let found = ScanResolutionService.findExistingFilament(
            tagData: tag(["111111", "222222", "333333"]), filaments: [filament], format: .tigerTag
        )
        #expect(found?.id == filament.id)
    }

    @Test("An OpenSpool 2-color tag (not at capacity) does not find a 3-color filament")
    func untruncatedTagDoesNotPrefixMatch() {
        let filament = multi(11, "111111,222222,333333")
        let found = ScanResolutionService.findExistingFilament(
            tagData: tag(["111111", "222222"]), filaments: [filament], format: .openSpool
        )
        #expect(found == nil)
    }

    @Test("Without a known format a tag at capacity stays exact-only")
    func noFormatIsExactOnly() {
        let filament = multi(11, "2D39C9,A51A52")
        let found = ScanResolutionService.findExistingFilament(
            tagData: tag(["2D39C9"]), filaments: [filament]
        )
        #expect(found == nil)
    }

    @Test("An exact match is preferred over a prefix match")
    func exactBeatsPrefix() {
        let prefix = multi(11, "2D39C9,A51A52")
        let exact = makeFilament(id: 12, colorHex: "2D39C9")
        let found = ScanResolutionService.findExistingFilament(
            tagData: tag(["2D39C9"]), filaments: [prefix, exact], format: .anycubicACE
        )
        #expect(found?.id == exact.id)
    }

    @Test("Name is ignored: same identity with a different name matches")
    func nameIsIgnored() {
        let filament = makeFilament(name: "Elegoo PLA Silver Something")
        let found = ScanResolutionService.findExistingFilament(
            tagData: makeTag(name: "PLA Basic"), filaments: [filament]
        )
        #expect(found?.id == filament.id)
    }
}

// MARK: - Find-or-create against a real repository

@Suite("Scan hub find-or-create filament")
@MainActor
struct ScanHubFindOrCreateTests {

    @Test("Empty repository creates vendor and filament from tag data")
    func createsParentsFromTagData() async throws {
        let repository = try makeLocalRepository()
        let service = makeResolutionService(repository: repository)

        let created = await service.findOrCreateFilament(for: makeTag(subtype: "Matte"))

        let filament = try #require(created)
        #expect(filament.material == "PLA")
        #expect(filament.colorHex == "FF0000")
        let vendor = try #require(filament.vendor)
        #expect(vendor.name == "Elegoo")
        #expect(repository.filaments.count == 1)
        #expect(repository.vendors.count == 1)
    }

    @Test("A new filament from a tag takes the tag's TD; a matched one is not written")
    func newFilamentFromTagSeedsTD() async throws {
        let repository = try makeLocalRepository()
        let service = makeResolutionService(repository: repository)
        var tag = makeTag()
        tag.transmissionDistance = 2.3

        let created = try #require(await service.findOrCreateFilament(for: tag))
        #expect(created.transmissionDistance == 2.3)

        tag.transmissionDistance = 5.0
        let matched = try #require(await service.findOrCreateFilament(for: tag))
        #expect(matched.id == created.id)
        #expect(repository.filaments.first { $0.id == created.id }?.transmissionDistance == 2.3)
    }

    /// Final review #1: a create that succeeds with a caveat ("TD was not
    /// saved: …") must hand the caveat to the hub, which posts it.
    @Test("A filament created with a caveat reports it; a clean create reports none")
    func createdFilamentCaveatIsReported() async throws {
        let writer = MockMigrationWriter()
        writer.filamentCreateNote = "TD was not saved: this Spoolman's td field is integer, not a number."
        let service = makeResolutionService(repository: writer)

        _ = try #require(await service.findOrCreateFilament(for: makeTag()))
        #expect(service.lastCreateCaveat == writer.filamentCreateNote)

        // The mock's filaments carry no color, so this creates again — now
        // cleanly: the previous caveat must not linger.
        writer.filamentCreateNote = nil
        _ = try #require(await service.findOrCreateFilament(for: makeTag()))
        #expect(service.lastCreateCaveat == nil)
    }

    @Test("Second call with the same tag data returns the existing filament")
    func isIdempotent() async throws {
        let repository = try makeLocalRepository()
        let service = makeResolutionService(repository: repository)

        let first = try #require(await service.findOrCreateFilament(for: makeTag()))
        let second = try #require(await service.findOrCreateFilament(for: makeTag()))

        #expect(first.id == second.id)
        #expect(repository.filaments.count == 1)
        #expect(repository.vendors.count == 1)
    }

    @Test("Reuses an existing vendor instead of creating a duplicate")
    func reusesExistingVendor() async throws {
        let repository = try makeLocalRepository()
        _ = await repository.addVendor(name: "elegoo")
        let service = makeResolutionService(repository: repository)

        _ = try #require(await service.findOrCreateFilament(for: makeTag()))

        #expect(repository.vendors.count == 1)
        #expect(repository.filaments.count == 1)
    }

    @Test("A manufacturer that could not be created stops the create")
    func failedVendorCreateCreatesNoFilament() async throws {
        let context = try SaveFailureInjection.makeContext(for: [
            LocalVendor.self, LocalFilament.self, LocalSpool.self, LocalIdSequence.self
        ])
        let repository = LocalRepository(context: context)
        let service = makeResolutionService(repository: repository)
        try SaveFailureInjection.arm(context)

        #expect(await service.findOrCreateFilament(for: makeTag()) == nil)
        #expect(repository.filaments.isEmpty)
    }

    @Test("Filament without a name falls back to material + subtype")
    func nameFallback() async throws {
        let repository = try makeLocalRepository()
        let service = makeResolutionService(repository: repository)

        let created = try #require(await service.findOrCreateFilament(
            for: makeTag(name: nil, subtype: "Matte")
        ))

        #expect(created.name == "PLA Matte")
    }

    @Test("Created filament carries the default diameter (FilaMan refuses creates without one)")
    func createdFilamentHasDiameter() async throws {
        let repository = try makeLocalRepository()
        let service = makeResolutionService(repository: repository)

        let created = try #require(await service.findOrCreateFilament(for: makeTag()))

        #expect(created.diameter == AppConfig.Defaults.diameter)
    }

    @Test("Created filament keeps the tag's empty spool weight, nominal net weight and diameter")
    func createdFilamentKeepsTagWeights() async throws {
        let repository = try makeLocalRepository()
        let service = makeResolutionService(repository: repository)
        // A Prusament OpenPrintTag: keys 18, 16, 17 and 30.
        var tag = makeTag()
        tag.emptyContainerWeight = 277
        tag.nominalNetWeight = 1000
        tag.actualNetWeight = 1018
        tag.diameter = 2.85

        let created = try #require(await service.findOrCreateFilament(for: tag))

        #expect(created.spoolWeight == 277)
        #expect(created.weight == 1000)
        #expect(created.diameter == 2.85)
    }

    @Test("A tag stating no weights leaves the created filament's weights unset")
    func createdFilamentWithoutTagWeights() async throws {
        let repository = try makeLocalRepository()
        let service = makeResolutionService(repository: repository)
        var tag = makeTag()
        tag.emptyContainerWeight = 0
        tag.nominalNetWeight = 0

        let created = try #require(await service.findOrCreateFilament(for: tag))

        #expect(created.spoolWeight == nil)
        #expect(created.weight == nil)
    }

    @Test("A tag stating no temperatures leaves the created filament's temperatures unset")
    func createdFilamentWithoutTagTemperatures() async throws {
        let repository = try makeLocalRepository()
        let service = makeResolutionService(repository: repository)
        var tag = makeTag()
        tag.nozzleTempsStated = false
        tag.bedTempsStated = false

        let created = try #require(await service.findOrCreateFilament(for: tag))

        #expect(created.settingsExtruderTemp == nil)
        #expect(created.settingsBedTemp == nil)
    }

    @Test("A tag stating only nozzle temperatures sets only the extruder temperature")
    func createdFilamentWithOnlyNozzleTemperatures() async throws {
        let repository = try makeLocalRepository()
        let service = makeResolutionService(repository: repository)
        var tag = makeTag()
        tag.bedTempsStated = false

        let created = try #require(await service.findOrCreateFilament(for: tag))

        #expect(created.settingsExtruderTemp == 215)
        #expect(created.settingsBedTemp == nil)
    }

    @Test("An existing filament the tag matches keeps its own weights")
    func existingFilamentIsNotRewritten() async throws {
        let repository = try makeLocalRepository()
        let service = makeResolutionService(repository: repository)
        let first = try #require(await service.findOrCreateFilament(for: makeTag()))
        var tag = makeTag()
        tag.emptyContainerWeight = 277

        let second = try #require(await service.findOrCreateFilament(for: tag))

        #expect(second.id == first.id)
        #expect(second.spoolWeight == nil)
    }

    @Test("Tag without a density gets its material's (Spoolman refuses creates without one)")
    func createdFilamentHasMaterialDensity() async throws {
        let repository = try makeLocalRepository()
        let service = makeResolutionService(repository: repository)

        // ACE, ELEGOO and OpenSpool tags carry no density.
        let created = try #require(await service.findOrCreateFilament(for: makeTag(material: "PETG")))

        #expect(created.density == 1.27)
    }

    @Test("Unrecognized material without a density falls back to the default")
    func createdFilamentHasDefaultDensity() async throws {
        let repository = try makeLocalRepository()
        let service = makeResolutionService(repository: repository)

        let created = try #require(await service.findOrCreateFilament(
            for: makeTag(material: "Mike's Exotic Blend")
        ))

        #expect(created.density == AppConfig.Defaults.density)
    }

    @Test("Tag's own density wins over the default")
    func createdFilamentKeepsTagDensity() async throws {
        let repository = try makeLocalRepository()
        let service = makeResolutionService(repository: repository)
        var tag = makeTag()
        tag.density = 1.27

        let created = try #require(await service.findOrCreateFilament(for: tag))

        #expect(created.density == 1.27)
    }

    @Test("A junk extra color does not cost the tag's primary color")
    func junkExtraKeepsPrimaryColor() async throws {
        let repository = try makeLocalRepository()
        let service = makeResolutionService(repository: repository)
        var tag = makeTag(colorHex: "2D39C9")
        tag.additionalColorHexes = ["ZZZ"]

        let created = try #require(await service.findOrCreateFilament(for: tag))

        #expect(created.colorHex == "2D39C9")
        #expect(created.multiColorHexes == nil)
    }

    @Test("Two-color tag creates a Coextruded multi-color filament")
    func multiColorTagCreatesCoextrudedFilament() async throws {
        let repository = try makeLocalRepository()
        let service = makeResolutionService(repository: repository)
        var tag = makeTag(colorHex: "2D39C9")
        tag.additionalColorHexes = ["A51A52"]

        let created = try #require(await service.findOrCreateFilament(for: tag))

        #expect(created.multiColorHexes == "2D39C9,A51A52")
        #expect(created.multiColorDirection == "coaxial")
        #expect(created.colorHex == nil)
    }

    @Test("Single-color tag creates a single-color filament")
    func singleColorTagCreatesSingleColorFilament() async throws {
        let repository = try makeLocalRepository()
        let service = makeResolutionService(repository: repository)

        let created = try #require(await service.findOrCreateFilament(for: makeTag(colorHex: "2D39C9")))

        #expect(created.colorHex == "2D39C9")
        #expect(created.multiColorHexes == nil)
        #expect(created.multiColorDirection == nil)
    }

    @Test("Missing filament in a populated repository is created, not guessed")
    func createsWhenIdentityMisses() async throws {
        let repository = try makeLocalRepository()
        _ = await repository.addVendor(name: "Elegoo")
        _ = await repository.addFilament(draft: FilamentDraft(
            name: "PLA Basic", vendorId: .set(1), material: "PLA",
            colorHex: "00FF00"
        ))
        #expect(repository.filaments.count == 1)
        let service = makeResolutionService(repository: repository)

        // Same vendor + material, DIFFERENT colour → not the same filament.
        let created = try #require(await service.findOrCreateFilament(
            for: makeTag(colorHex: "FF0000")
        ))

        #expect(repository.filaments.count == 2)
        #expect(created.colorHex == "FF0000")
        #expect(created.vendor?.name == "Elegoo")
    }
}

// MARK: - Resolution source tagging

@Suite("Scan hub resolution source tagging")
@MainActor
struct ScanHubResolutionSourceTests {

    /// Seeds vendor → filament → spool and returns the spool id.
    private func seedSpool(
        _ repository: LocalRepository,
        cardUIDs: [String]? = nil
    ) async -> Int? {
        guard let vendor = await repository.addVendor(name: "Elegoo"),
              let filament = await repository.addFilament(draft: FilamentDraft(
                  name: "PLA Basic", vendorId: .set(vendor.id), material: "PLA", colorHex: "FF0000"
              )),
              let spool = await repository.addSpool(draft: SpoolDraft(
                  filamentId: filament.id, cardUIDs: cardUIDs
              ))
        else { return nil }
        return spool.id
    }

    @Test("card_uids hit is tagged cardUIDs")
    func cardUIDsHitTagsSource() async throws {
        let repository = try makeLocalRepository()
        let service = makeResolutionService(repository: repository)
        _ = try #require(await seedSpool(repository, cardUIDs: ["bb"]))
        let scan = ScanResult(cardUID: "bb", tagData: makeTag(), format: .openSpool)

        let resolution = await service.resolve(scan, effectiveTagData: nil)

        guard case .cardUIDSpool(_, let source) = resolution else {
            Issue.record("Expected .cardUIDSpool, got \(resolution)")
            return
        }
        #expect(source == .cardUIDs)
    }

    @Test("Ledger hit is tagged onDeviceLedger")
    func ledgerHitTagsSource() async throws {
        let repository = try makeLocalRepository()
        let spoolId = try #require(await seedSpool(repository))
        let ledger = makeIsolatedLedger()
        ledger.record(uid: "ee", spoolId: spoolId)
        let service = makeResolutionService(repository: repository, ledger: ledger)
        let scan = ScanResult(cardUID: "ee", tagData: makeTag(), format: .openSpool)

        let resolution = await service.resolve(scan, effectiveTagData: nil)

        guard case .cardUIDSpool(_, let source) = resolution else {
            Issue.record("Expected .cardUIDSpool, got \(resolution)")
            return
        }
        #expect(source == .onDeviceLedger)
    }
}

// MARK: - FilamentTagData from a backend filament

@Suite("FilamentTagData from backend filament")
struct FilamentTagDataFromFilamentTests {

    @Test("Maps vendor, material, colour, name, density and temps from settings")
    func mapsFields() {
        let filament = Filament(
            id: 3,
            name: "PLA Basic",
            material: "PLA",
            vendor: Vendor(id: 1, name: "Elegoo"),
            colorHex: "FF0000",
            density: 1.24,
            diameter: 1.75,
            settingsExtruderTemp: 220,
            settingsBedTemp: 60
        )

        let tagData = FilamentTagData.from(filament: filament)

        #expect(tagData.name == "PLA Basic")
        #expect(tagData.brand == "Elegoo")
        #expect(tagData.material == "PLA")
        #expect(tagData.colorHex == "FF0000")
        #expect(tagData.density == 1.24)
        #expect(tagData.minNozzleTemp == 220)
        #expect(tagData.maxNozzleTemp == 220 + AppConfig.Defaults.nozzleTempOffset)
        #expect(tagData.minBedTemp == 60)
        #expect(tagData.maxBedTemp == 60 + AppConfig.Defaults.bedTempOffset)
        #expect(tagData.spoolmanId == nil)
    }

    @Test("Nil backend fields fall back to the same defaults as from(spool:)")
    func fallsBackToDefaults() {
        let filament = Filament(id: 4, name: nil, material: nil, vendor: nil, colorHex: nil)

        let tagData = FilamentTagData.from(filament: filament)

        #expect(tagData.brand == AppConfig.Defaults.brand)
        #expect(tagData.material == AppConfig.Defaults.material)
        #expect(tagData.colorHex == AppConfig.Defaults.colorHex)
        #expect(tagData.minNozzleTemp == AppConfig.Defaults.minNozzleTemp)
        #expect(tagData.minBedTemp == AppConfig.Defaults.minBedTemp)
    }
}

// MARK: - Adopted filament (hub seam)

@Suite("Scan hub adopted filament seam")
@MainActor
struct ScanHubAdoptionSeamTests {

    private let matched = Filament(
        id: 20, name: "Heuristic Match", material: "PLA",
        vendor: Vendor(id: 2, name: "Bambu Lab"), colorHex: "00FF00"
    )

    private let adopted = Filament(
        id: 30, name: "Saved By User", material: "PLA",
        vendor: Vendor(id: 3, name: "ANYCUBIC"), colorHex: "FF0000"
    )

    @Test("Actions work on the adopted filament when one exists")
    func adoptedWins() {
        #expect(ScanResultHubView.workingFilament(adopted: adopted, matched: matched)?.id == 30)
    }

    @Test("Without adoption the heuristic match is the working filament")
    func matchedFallsBack() {
        #expect(ScanResultHubView.workingFilament(adopted: nil, matched: matched)?.id == 20)
        #expect(ScanResultHubView.workingFilament(adopted: nil, matched: nil) == nil)
    }

    @Test("Card displays the adopted filament's values over the tag payload")
    func displayPrefersAdopted() {
        let tagData = FilamentTagData(
            name: "Tag Name", material: "PLA", subtype: nil, brand: "AC",
            colorHex: "0000FF", minNozzleTemp: 190, maxNozzleTemp: 240,
            minBedTemp: 35, maxBedTemp: 65
        )

        let displayed = ScanResultHubView.displayedFilamentData(adopted: adopted, tagData: tagData)
        #expect(displayed.brand == "ANYCUBIC")
        #expect(displayed.name == "Saved By User")

        let untouched = ScanResultHubView.displayedFilamentData(adopted: nil, tagData: tagData)
        #expect(untouched.brand == "AC")
    }

    @Test("Create failure message appends the backend's reason when there is one")
    func failureMessage() {
        #expect(
            ScanResultHubView.createSpoolFailureMessage(backendName: "FilaMan", detail: "A filament needs a diameter on FilaMan.")
                == "Could not create the filament in FilaMan: A filament needs a diameter on FilaMan."
        )
        #expect(
            ScanResultHubView.createSpoolFailureMessage(backendName: "FilaMan", detail: nil)
                == "Could not create the filament in FilaMan."
        )
        #expect(
            ScanResultHubView.createSpoolFailureMessage(backendName: "FilaMan", detail: "  ")
                == "Could not create the filament in FilaMan."
        )
    }
}

// MARK: - Provenance captions

@Suite("Scan hub provenance captions")
struct ScanHubCaptionTests {

    @Test("Footer names how the hub found its answer, briefly")
    func footerResolutionParts() {
        #expect(HubActionPlan.footerResolutionPart(.spoolLinkMapping, backendName: "Spoolman") == "found by its tag link")
        #expect(HubActionPlan.footerResolutionPart(.embeddedSpoolID, backendName: "Spoolman") == "found by the spool ID on the tag")
        #expect(HubActionPlan.footerResolutionPart(.onDeviceLedger, backendName: "Spoolman") == "found only by this iPhone's record of this tag, not linked on Spoolman")
        #expect(HubActionPlan.footerResolutionPart(.manualChoice, backendName: "Spoolman") == "spool chosen by you")
        // The percentage lives in the filament row (state 3).
        #expect(HubActionPlan.footerResolutionPart(.heuristicMatch(topConfidence: 87), backendName: "Spoolman") == nil)
        #expect(HubActionPlan.footerResolutionPart(nil, backendName: "Spoolman") == nil)
    }

    @Test("Data-source caption covers every NFC format, OCR, and web")
    func dataSourceCaptions() {
        #expect(
            ScanResultHubView.provenanceCaption(format: .openSpool, hasParsedWebData: false, webHost: nil)
                == "Read from tag · OpenSpool"
        )
        #expect(
            ScanResultHubView.provenanceCaption(format: .anycubicACE, hasParsedWebData: false, webHost: nil)
                == "Read from tag · Anycubic ACE"
        )
        #expect(
            ScanResultHubView.provenanceCaption(format: .ocr, hasParsedWebData: false, webHost: nil)
                == "Read from label · OCR Scan"
        )
        #expect(
            ScanResultHubView.provenanceCaption(format: .webUrl, hasParsedWebData: true, webHost: "example.com")
                == "Parsed from web · example.com"
        )
        #expect(
            ScanResultHubView.provenanceCaption(format: .webUrl, hasParsedWebData: false, webHost: nil) == nil
        )
    }
}
