//
//  PrinterTabTests.swift
//  SpoolKidTests
//
//  Printer tab rules. The status fixtures follow what a U1 on 2.0.0-paxx12-24
//  returned on 2026-11-07, including the 0 in CARD_UID when no tag is read.
//

import Testing
import Foundation
@testable import SpoolKid

@MainActor
private final class FakeTransport: PrinterTransport {
    var onNotification: ((String, [Any]) -> Void)?
    var onClosed: (() -> Void)?
    var replies: [String: Any] = [:]
    var failures: [String: Error] = [:]
    var scripts: [String] = []
    /// Successive answers to a query, before `replies` takes over.
    var queryReplies: [[String: Any]] = []

    func call(_ method: String, params: [String: Any]) async throws -> MoonrakerValue {
        if let failure = failures[method] { throw failure }
        if method == "printer.objects.query", !queryReplies.isEmpty {
            return MoonrakerValue(value: queryReplies.removeFirst())
        }
        if method == "printer.gcode.script" { scripts.append(params["script"] as? String ?? "") }
        return MoonrakerValue(value: replies[method] ?? [String: Any]())
    }

    func close() {}
}

private func config(types: [String] = ["NONE", "NONE", "NONE", "PETG"], spoolIDs: [Int] = [0, 0, 0, 4], official: [Bool] = [false, false, false, true]) -> [String: Any] {
    [
        "filament_type": types,
        "filament_vendor": types.map { $0 == "NONE" ? "NONE" : "AzureFilm" },
        "filament_sub_type": types.map { $0 == "NONE" ? "NONE" : "" },
        "filament_color_rgba": ["FFFFFFFF", "FFFFFFFF", "FFFFFFFF", "E1E1E1FF"],
        "filament_color_multi": (0..<4).map { index -> [String: Any] in
            ["nums": 1, "alpha": 255, "mode": 0, "colors": [index == 3 ? "E1E1E1" : "FFFFFF"]]
        },
        "filament_official": official,
        "filament_exist": [false, false, false, true],
        "filament_spool_id": spoolIDs
    ]
}

private func spool(id: Int = 9, td: String? = nil, vendor: String = "Pol\"ar;") -> Spool {
    let filament = Filament(
        id: 3, name: "Clear", material: "PETG", vendor: Vendor(id: 1, name: vendor), colorHex: "1A2B3C",
        extra: td.map { ["td": $0] }
    )
    return Spool(
        id: id, filament: filament, remainingWeight: 500, initialWeight: 1000,
        spoolWeight: 200, statusId: nil, externalId: nil, purchaseDate: nil
    )
}

struct PrinterStackTests {
    @Test func theFirmwareVersionNamesTheExtendedFirmware() {
        #expect(PrinterStack.detect(softwareVersion: "2.0.0-paxx12-24", objects: []) == .extendedFirmware)
    }

    @Test func afcObjectsAloneAreNotBespok3D() {
        #expect(PrinterStack.detect(softwareVersion: "2.0.0", objects: ["AFC", "AFC_lane E0"]) == .stock)
    }

    @Test func bespok3DHasItsOwnObject() {
        #expect(PrinterStack.detect(softwareVersion: "2.0.0", objects: ["bespok3d_rfid"]) == .bespok3d)
    }

    @Test func bespok3DIsNamedByItsMoonrakerConfigFiles() {
        let files = ["moonraker.conf", "bespok3d/moonraker/main.cfg"]
        #expect(PrinterStack.detect(softwareVersion: "2.0.0.205_20260914173503", objects: ["AFC"], configFiles: files) == .bespok3d)
        #expect(PrinterStack.detect(softwareVersion: "2.0.0", objects: [], configFiles: ["moonraker.conf"]) == .stock)
        #expect(PrinterStack.bespok3d.label == "Stock + Bespok3d")
    }

    @Test func theExtendedFirmwareWinsOverLeftoverBespok3DFiles() {
        let files = ["bespok3d/moonraker/main.cfg"]
        #expect(PrinterStack.detect(softwareVersion: "2.0.0-paxx12-24", objects: [], configFiles: files) == .extendedFirmware)
    }

    @Test(arguments: [
        ("[components]\nrfid: snapmaker\nupgrade: testing", PrinterReaderMode.builtIn),
        ("[components]\nrfid: openrfid", .openRFID),
        ("[components]\nrfid: openrfid-generic", .openRFID),
        ("[components]\nrfid: external", .external),
        ("[components]\nrfid: something-new", .unknown),
        ("[other]\nrfid: openrfid", .builtIn),
        ("[components]\n# rfid: openrfid\n", .builtIn),
        ("", .builtIn)
    ])
    func readerModeComesFromTheConfig(text: String, mode: PrinterReaderMode) {
        #expect(PrinterReaderMode.parse(extendedConfig: text) == mode)
    }

    @Test func theBuiltInReaderReadsOnlyOpenSpool() {
        let capabilities = PrinterCapabilities.of(.extendedFirmware, readerMode: .builtIn, hasSpoolman: true)
        #expect(capabilities.tagFormatsRead == [.openSpool])
        #expect(capabilities.assignsSpoolID)
    }

    @Test func theU1LaysCardsOutAsItsSpoolsAreLoaded() {
        let heads = (0..<4).map { ToolheadState(index: $0, colorHexes: [], alpha: 255, isLoaded: false, isOfficial: false) }
        #expect(PrinterProfile.snapmakerU1.arranged(heads).map(\.name) == ["T1", "T3", "T2", "T4"])
    }

    @Test func theU1OffersTheMaterialsItHasSettingsFor() {
        #expect(PrinterProfile.snapmakerU1.materials == [
            "PLA", "PLA-CF", "PETG", "PETG-CF", "ABS", "ASA", "PC", "PC-ABS", "PA", "PA-CF", "PA-GF",
            "PA6-CF", "PA6-GF", "PAHT-CF", "TPU", "PEBA", "PVA"
        ])
    }

    @Test func onlyTheU1sMaterialsAreKept() {
        let u1 = PrinterProfile.snapmakerU1
        #expect(u1.material(matching: "petg") == "PETG")
        #expect(u1.material(matching: "PLA+") == "")
        #expect(u1.material(matching: "NONE") == "")
        #expect(u1.material(matching: nil) == "")
    }

    @Test func everyManufacturerGetsAllTheU1sSubtypes() {
        let u1 = PrinterProfile.snapmakerU1
        #expect(u1.subtypes(for: "PETG") == ["HF", "PolyLite", "Translucent"])
        #expect(u1.subtypes(for: "TPU") == ["90A", "95A HF"])
        #expect(u1.subtypes(for: "ASA") == [])
        #expect(u1.subtypes(for: "PLA").contains("Full Spectrum"))
        #expect(u1.subtypes(for: "PLA").contains("PolyTerra"))
    }

    @Test func onlyTheU1sSubtypesAreKept() {
        let u1 = PrinterProfile.snapmakerU1
        #expect(u1.subtype(matching: "matte", material: "PLA") == "Matte")
        #expect(u1.subtype(matching: "Matte", material: "PETG") == "")
        #expect(u1.subtype(matching: "NONE", material: "TPU") == "")
    }

    @Test func noSpoolmanNoSpoolID() {
        #expect(!PrinterCapabilities.of(.extendedFirmware, readerMode: .builtIn, hasSpoolman: false).assignsSpoolID)
    }
}

struct ToolheadStateTests {
    private func state(_ index: Int, detect: [[String: Any]]? = nil) -> ToolheadState? {
        var status: [String: [String: Any]] = ["print_task_config": config()]
        if let detect { status["filament_detect"] = ["info": detect] }
        return ToolheadState.parse(index: index, status: status)
    }

    @Test func anEmptyToolheadHasNoData() throws {
        let toolhead = try #require(state(0))
        #expect(!toolhead.hasData)
        #expect(toolhead.source == .empty)
        #expect(toolhead.colorHexes.isEmpty)
        #expect(toolhead.name == "T1")
    }

    @Test func aSpoolmanToolheadParses() throws {
        let toolhead = try #require(state(3))
        #expect(toolhead.material == "PETG")
        #expect(toolhead.vendor == "AzureFilm")
        #expect(toolhead.subtype == nil)
        #expect(toolhead.colorHexes == ["E1E1E1"])
        #expect(toolhead.spoolID == 4)
        #expect(toolhead.isLoaded)
        #expect(toolhead.source == .spoolman)
    }

    @Test func noSuchToolheadIsNil() {
        #expect(state(4) == nil)
    }

    @Test func cardUIDIsZeroWithoutATag() {
        #expect(ToolheadState.uid(from: 0) == nil)
        #expect(ToolheadState.uid(from: [Int]()) == nil)
    }

    @Test func cardUIDBytesBecomeNormalisedHex() {
        #expect(ToolheadState.uid(from: [0x04, 0xE8, 0x15, 0x56, 0xC9, 0x2A, 0x81]) == "04E81556C92A81")
    }

    @Test func aPrintBlocksWrites() {
        #expect(PrinterActivity.parse(status: ["print_stats": ["state": "printing"], "virtual_sdcard": ["progress": 0.42]]) == .printing(percent: 42))
        #expect(PrinterActivity.parse(status: ["print_stats": ["state": "paused"]]).blocksWrites)
        #expect(!PrinterActivity.parse(status: ["print_stats": ["state": "standby"]]).blocksWrites)
    }
}

@MainActor
struct PrinterCommandsTests {
    @Test func aSpoolBecomesOneCommand() {
        let assignment = ToolheadAssignment(spool: spool(td: "5"), sendsSpoolID: true)
        #expect(PrinterCommands.assign(assignment, toolhead: 2, force: false)
            == #"SET_PRINT_FILAMENT_CONFIG CONFIG_EXTRUDER=2 VENDOR="Polar" FILAMENT_TYPE="PETG" FILAMENT_SUBTYPE="Transparent" COLOR_NUMS=1 COLORS=1A2B3C MULTI_MODE=0 ALPHA=94 FILAMENT_SPOOL_ID=9"#)
    }

    @Test func noSpoolIDWhenTheServersDiffer() {
        let text = PrinterCommands.assign(ToolheadAssignment(spool: spool(), sendsSpoolID: false), toolhead: 0, force: true)
        #expect(!text.contains("FILAMENT_SPOOL_ID"))
        #expect(text.hasSuffix("ALPHA=255 FORCE=1"))
    }

    @Test func textThatWouldEndTheCommandIsDropped() {
        #expect(PrinterCommands.sanitized("A\"B;C#D*E\\F\nG") == "ABCDEFG")
    }

    @Test func aMatchingToolheadConfirms() {
        let assignment = ToolheadAssignment(spool: spool(vendor: "Polar"), sendsSpoolID: true)
        var state = ToolheadState(index: 0, material: "petg", vendor: "POLAR", subtype: nil, colorHexes: ["1A2B3C"], alpha: 255, isLoaded: false, isOfficial: false, spoolID: 9)
        #expect(PrinterCommands.confirms(assignment, state: state))
        state.spoolID = nil
        #expect(!PrinterCommands.confirms(assignment, state: state))
        state.spoolID = 9
        state.colorHexes = ["FFFFFF"]
        #expect(!PrinterCommands.confirms(assignment, state: state))
    }
}

@MainActor
struct ToolheadMismatchTests {
    private let tag = ToolheadTagData(vendor: "Polar", material: "PETG", subtype: "Silk", colorHexes: ["1A2B3C"], alpha: 255)

    private func head(material: String = "PETG", colors: [String] = ["1A2B3C"], tag: ToolheadTagData?) -> ToolheadState {
        ToolheadState(index: 0, material: material, colorHexes: colors, alpha: 255, isLoaded: true, isOfficial: true, tag: tag)
    }

    @Test func noTagNoMismatch() {
        #expect(ToolheadMismatch.of(head(tag: nil), spool: spool()) == nil)
    }

    @Test func aMatchingToolheadIsQuiet() {
        #expect(ToolheadMismatch.of(head(tag: tag), spool: spool()) == nil)
    }

    @Test func aBlankedSubtypeIsNotAMismatch() {
        var state = head(tag: tag)
        state.subtype = nil
        #expect(ToolheadMismatch.of(state, spool: nil) == nil)
    }

    private let other = ToolheadTagData(vendor: "Polar", material: "PETG", subtype: nil, colorHexes: ["FF0000"], alpha: 255)

    @Test func noLibrarySpoolOnlyComparesThePrinter() {
        let mismatch = ToolheadMismatch.of(head(colors: ["FFFFFF"], tag: tag), spool: nil)
        #expect(mismatch == ToolheadMismatch(printerMatchesTag: false, printerMatchesLibrary: nil, libraryMatchesTag: nil))
        #expect(mismatch?.title == "Printer Doesn't Match the Tag")
    }

    /// The reported case: SpoolLink gave the printer the Library's data.
    @Test func thePrinterFollowingTheLibraryIsNamed() {
        let mismatch = ToolheadMismatch.of(head(tag: other), spool: spool())
        #expect(mismatch == ToolheadMismatch(printerMatchesTag: false, printerMatchesLibrary: true, libraryMatchesTag: false))
        #expect(mismatch?.message == "The printer is using the Library spool. The tag says otherwise.")
        #expect(mismatch?.title == "Tag and Library Don't Match")
        #expect(mismatch?.printerUsesNeither == false)
    }

    @Test func thePrinterFollowingTheTagIsNamed() {
        let mismatch = ToolheadMismatch.of(head(colors: ["FF0000"], tag: other), spool: spool())
        #expect(mismatch == ToolheadMismatch(printerMatchesTag: true, printerMatchesLibrary: false, libraryMatchesTag: false))
        #expect(mismatch?.message == "The printer is using the tag. The Library spool says otherwise.")
    }

    @Test func thePrinterUsingNeither() {
        let agreeing = ToolheadMismatch.of(head(material: "PLA", tag: tag), spool: spool())
        #expect(agreeing == ToolheadMismatch(printerMatchesTag: false, printerMatchesLibrary: false, libraryMatchesTag: true))
        #expect(agreeing?.printerUsesNeither == true)
        #expect(agreeing?.title == "Printer Doesn't Match the Tag")
        let allDiffer = ToolheadMismatch.of(head(colors: ["FFFFFF"], tag: other), spool: spool())
        #expect(allDiffer?.message == "The tag, the Library and the printer all differ.")
    }

    /// The U1 can't write tags (paxx12-24 has read, clear and query only), so
    /// the iPhone does, and only a tag it can write: the U1 reports "NTAG".
    @Test func onlyAnNTAGIsWrittenWithTheIPhone() {
        #expect(ToolheadMismatch.phoneWritesTag(tagType: "NTAG"))
        #expect(ToolheadMismatch.phoneWritesTag(tagType: "ntag"))
        for other in [nil, "", "M1", "MIFARE", "Mifare Classic"] as [String?] {
            #expect(!ToolheadMismatch.phoneWritesTag(tagType: other))
        }
    }
}

@MainActor
struct FilamentCorrectionTests {
    private let tag = ToolheadTagData(vendor: "Snapmaker", material: "PLA", subtype: nil, colorHexes: ["F4C032"], alpha: 255)

    @Test func takesTheTagsMaterialAndColors() {
        let correction = FilamentCorrection.from(tag: tag, spool: spool(), spools: [spool()])
        #expect(correction.material == "PLA")
        #expect(correction.colorHexes == ["F4C032"])
        #expect(correction.note == nil)
    }

    @Test func countsOtherSpoolsOfTheFilament() {
        let spools = [spool(id: 9), spool(id: 10), spool(id: 11)]
        #expect(FilamentCorrection.from(tag: tag, spool: spool(id: 9), spools: spools).note
            == "Also changes 2 other spools of this filament.")
        #expect(FilamentCorrection.from(tag: tag, spool: spool(id: 9), spools: Array(spools.prefix(2))).note
            == "Also changes 1 other spool of this filament.")
    }
}

@MainActor
struct ToolheadManualEntryTests {
    private let empty = ToolheadState(index: 0, colorHexes: [], alpha: 255, isLoaded: false, isOfficial: false)
    private let tracked = ToolheadState(index: 0, material: "PLA", colorHexes: ["FFFFFF"], alpha: 255, isLoaded: true, isOfficial: false, spoolID: 4)

    private func entry(material: String = "PLA", colors: [String] = ["FF0000"], opacity: Double = 100, on head: ToolheadState) -> ToolheadAssignment? {
        ToolheadAssignment.byHand(material: material, vendor: "", subtype: "", colorHexes: colors, opacityPercent: opacity, replacing: head)
    }

    @Test func aMaterialAndAColorAreRequired() {
        #expect(entry(material: "  ", on: empty) == nil)
        #expect(entry(colors: ["nope"], on: empty) == nil)
    }

    @Test func aBlankVendorIsGeneric() {
        #expect(entry(on: empty)?.vendor == "Generic")
    }

    @Test func colorsAreCappedAtFive() {
        #expect(entry(colors: ["111111", "222222", "333333", "444444", "555555", "666666"], on: empty)?.colorHexes.count == 5)
    }

    @Test func noSpoolIDIsSentToAToolheadWithoutOne() {
        let assignment = entry(on: empty)
        #expect(assignment?.spoolID == nil)
    }

    @Test func aHandEntryDropsTheSpoolID() throws {
        let assignment = try #require(entry(on: tracked))
        #expect(PrinterCommands.assign(assignment, toolhead: 0, force: true).contains("FILAMENT_SPOOL_ID=0 FORCE=1"))
    }

    @Test func aDroppedSpoolIDConfirmsOnlyOnceGone() throws {
        let assignment = try #require(entry(on: tracked))
        var state = ToolheadState(index: 0, material: "PLA", vendor: "Generic", colorHexes: ["FF0000"], alpha: 255, isLoaded: true, isOfficial: false, spoolID: 4)
        #expect(!PrinterCommands.confirms(assignment, state: state))
        state.spoolID = nil
        #expect(PrinterCommands.confirms(assignment, state: state))
    }

    @Test(arguments: [(100.0, 255), (55.0, 140), (1.0, 3), (0.0, 3), (500.0, 255)])
    func opacityBecomesAlpha(percent: Double, alpha: Int) {
        #expect(ToolheadAssignment.alpha(opacityPercent: percent) == alpha)
    }

    @Test func aSpoolIDOrOfficialToolheadNeedsForce() {
        #expect(PrinterCommands.needsForce(tracked))
        #expect(!PrinterCommands.needsForce(empty))
    }

    @Test func useTagDataKeepsTheSpoolID() {
        let tag = ToolheadTagData(vendor: nil, material: "PLA", subtype: "Silk", colorHexes: ["CCBC55"], alpha: 255)
        let assignment = ToolheadAssignment(tag: tag, keepingSpoolID: 1)
        #expect(assignment.vendor == "Generic")
        #expect(assignment.subtype == "Silk")
        #expect(assignment.spoolID == 1)
    }
}

struct ToolheadTagDataTests {
    @Test func aDecodedTagParses() {
        let tag = ToolheadTagData.parse(["MAIN_TYPE": "PLA", "VENDOR": "AzureFilm", "SUB_TYPE": "Silk", "ALPHA": 255, "COLOR_NUMS": 2, "RGB_1": 13417557, "RGB_2": 255])
        #expect(tag == ToolheadTagData(vendor: "AzureFilm", material: "PLA", subtype: "Silk", colorHexes: ["CCBC55", "0000FF"], alpha: 255))
    }

    @Test func anEmptyReadIsNoTag() {
        #expect(ToolheadTagData.parse(["MAIN_TYPE": "NONE", "RGB_1": 16777215]) == nil)
        #expect(ToolheadTagData.parse(nil) == nil)
    }
}

struct ToolheadAssignmentWarningTests {
    private let builtIn = PrinterCapabilities.of(.extendedFirmware, readerMode: .builtIn, hasSpoolman: true)
    private let emptyHead = ToolheadState(index: 0, colorHexes: [], alpha: 255, isLoaded: false, isOfficial: false)

    private func lines(_ head: ToolheadState, _ tag: ToolheadAssignmentWarning.SpoolTag) -> [String] {
        ToolheadAssignmentWarning.lines(toolhead: head, tag: tag, capabilities: builtIn).lines
    }

    @Test func noTagIsKept() {
        #expect(lines(emptyHead, .none) == ["Kept when you load this spool.", "Unloading clears the toolhead."])
    }

    @Test func aTagThisReaderCannotReadIsKept() {
        #expect(lines(emptyHead, .scanned(format: .tigerTag, differsAs: nil)).first == "Kept when you load this spool.")
    }

    @Test func aReadableMatchingTagSetsIt() {
        #expect(lines(emptyHead, .scanned(format: .openSpool, differsAs: nil)).first == "Its tag sets this toolhead when you load it.")
    }

    @Test func aReadableDifferingTagReplacesIt() {
        #expect(lines(emptyHead, .scanned(format: .openSpool, differsAs: "PLA FF0000")).first
            == "Its tag will replace this with PLA FF0000 when loaded. Rewrite the tag first?")
    }

    @Test func anUnknownReaderAssumesTheTagIsRead() {
        let unknown = PrinterCapabilities.of(.extendedFirmware, readerMode: .unknown, hasSpoolman: true)
        let result = ToolheadAssignmentWarning.lines(
            toolhead: emptyHead, tag: .scanned(format: .tigerTag, differsAs: nil), capabilities: unknown
        )
        #expect(result.lines.first == "Its tag sets this toolhead when you load it.")
    }

    @Test func aLoadedToolheadSaysSo() {
        let head = ToolheadState(index: 1, material: "PLA", vendor: "Polar", colorHexes: ["FF0000"], alpha: 255, isLoaded: true, isOfficial: false)
        #expect(lines(head, .none).first == "T2 holds Polar PLA. Unloading it will clear this.")
    }

    @Test func anOfficialToolheadNeedsForce() {
        let head = ToolheadState(index: 0, material: "PLA", vendor: "Snapmaker", colorHexes: ["FF0000"], alpha: 255, isLoaded: true, isOfficial: true)
        let result = ToolheadAssignmentWarning.lines(toolhead: head, tag: .none, capabilities: builtIn)
        #expect(result.needsForce)
        #expect(result.lines.first == "Replaces the Snapmaker spool's data.")
    }

    @Test func aTagSpoolLinkResolvesUsesSpoolmanData() {
        let readable = ToolheadAssignmentWarning.lines(
            toolhead: emptyHead, tag: .scanned(format: .openSpool, differsAs: "PLA FF0000"), capabilities: builtIn, spoolLinkResolves: true
        )
        #expect(readable.lines.first == "When you load it, the printer reads its tag and uses this spool's Spoolman data.")
        let picked = ToolheadAssignmentWarning.lines(toolhead: emptyHead, tag: .unknownFormat, capabilities: builtIn, spoolLinkResolves: true)
        #expect(picked.lines.first == "If the printer can read this spool's tag, it uses this spool's Spoolman data when you load it.")
    }

    @Test func aTagTheReaderCannotReadStaysKeptEvenWithSpoolLink() {
        let result = ToolheadAssignmentWarning.lines(
            toolhead: emptyHead, tag: .scanned(format: .tigerTag, differsAs: nil), capabilities: builtIn, spoolLinkResolves: true
        )
        #expect(result.lines.first == "Kept when you load this spool.")
    }

    @Test func anOpenSpoolTagIsNotCalledSnapmaker() {
        let head = ToolheadState(index: 0, material: "PLA", vendor: "AzureFilm", colorHexes: ["CCBC55"], alpha: 255, isLoaded: true, isOfficial: true, tagUID: "048D1356C92A81")
        let result = ToolheadAssignmentWarning.lines(toolhead: head, tag: .none, capabilities: builtIn)
        #expect(result.needsForce)
        #expect(result.lines.first == "Replaces what this toolhead's tag set.")
    }

    @Test func aSpoolLinkToolheadNamesItsSpool() {
        let head = ToolheadState(index: 3, material: "PETG", colorHexes: ["E1E1E1"], alpha: 255, isLoaded: true, isOfficial: true, spoolID: 4)
        #expect(lines(head, .none).first == "Replaces Spoolman spool #4 on T4.")
    }
}

@MainActor
struct PrinterServiceTests {
    private func service(_ fake: FakeTransport, address: String = "http://10.0.0.5") -> PrinterService {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(address, forKey: AppConfig.printerAddressKey)
        fake.replies["printer.info"] = ["software_version": "2.0.0-paxx12-24"]
        fake.replies["printer.objects.list"] = ["objects": ["print_task_config"]]
        fake.replies["server.config"] = ["config": ["spoolman": ["server": "http://192.168.20.33:7912"]]]
        fake.replies["printer.objects.subscribe"] = ["status": ["print_task_config": config()]]
        fake.replies["printer.objects.query"] = ["status": ["print_task_config": config()]]
        return PrinterService(
            defaults: defaults, makeTransport: { _ in fake },
            fetchText: { _, _ in "[components]\nrfid: snapmaker" }, readCredentials: { nil }, writeCredentials: { _ in true }, pause: {}
        )
    }

    @Test func connectingReadsTheStackAndToolheads() async {
        let fake = FakeTransport()
        let printer = service(fake)
        await printer.connect()
        #expect(printer.connection == .online)
        #expect(printer.capabilities?.stack == .extendedFirmware)
        #expect(printer.capabilities?.tagFormatsRead == [.openSpool])
        #expect(printer.spoolmanServer == "http://192.168.20.33:7912")
        #expect(printer.toolheads.count == 4)
    }

    @Test func aPartialUpdateKeepsTheOtherFields() async {
        let fake = FakeTransport()
        let printer = service(fake)
        await printer.connect()
        fake.onNotification?("notify_status_update", [["print_task_config": ["filament_exist": [true, false, false, true]]], 1.0])
        #expect(printer.toolheads[0].isLoaded)
        #expect(printer.toolheads[3].material == "PETG")
    }

    @Test func pluginStateFollowsThePrintersObjectStatus() async {
        let fake = FakeTransport()
        let printer = service(fake)
        fake.replies["printer.objects.list"] = ["objects": ["print_task_config", "spoolkid_rfid"]]
        await printer.connect()
        #expect(printer.tagPlugin == .notReady(reason: "Waiting for the plugin to report."))
        fake.onNotification?("notify_status_update", [[
            "spoolkid_rfid": ["api_version": 1, "plugin_version": "0.1.0", "ready": true, "not_ready_reason": "", "busy": false]
        ], 1.0])
        #expect(printer.tagPlugin == .ready(version: "0.1.0"))
    }

    @Test func noPluginObjectMeansNotInstalled() async {
        let fake = FakeTransport()
        let printer = service(fake)
        await printer.connect()
        #expect(printer.tagPlugin == .notInstalled)
    }

    @Test func aNoAnswerGoesOfflineAndKeepsLastState() async {
        let fake = FakeTransport()
        let printer = service(fake)
        await printer.connect()
        fake.onClosed?()
        #expect(printer.connection == .offline("Lost the connection to the printer."))
        #expect(printer.toolheads.count == 4)
    }

    @Test func anUnreachablePrinterIsOffline() async {
        let fake = FakeTransport()
        fake.failures["server.connection.identify"] = MoonrakerError.timedOut
        let printer = service(fake)
        await printer.connect()
        #expect(printer.connection == .offline("Can't reach the printer at http://10.0.0.5."))
    }

    @Test func aWriteThePrinterDoesNotShowIsNotSuccess() async {
        let fake = FakeTransport()
        let printer = service(fake)
        await printer.connect()
        let outcome = await printer.assign(ToolheadAssignment(spool: spool(vendor: "Polar"), sendsSpoolID: false), toolhead: 0, force: false)
        #expect(outcome == .notConfirmed)
        #expect(fake.scripts.count == 1)
    }

    @Test func aClearThatLandsLateIsStillConfirmed() async {
        let fake = FakeTransport()
        let printer = service(fake)
        await printer.connect()
        fake.queryReplies = [
            ["status": ["print_task_config": config()]],
            ["status": ["print_task_config": config(types: ["NONE", "NONE", "NONE", "NONE"])]]
        ]
        let outcome = await printer.clear(toolhead: 3)
        #expect(outcome == .confirmed)
    }

    @Test func aClearThatNeverLandsIsNotConfirmed() async {
        let fake = FakeTransport()
        let printer = service(fake)
        await printer.connect()
        let outcome = await printer.clear(toolhead: 3)
        #expect(outcome == .notConfirmed)
    }

    @Test func aRejectedCommandReportsWhy() async {
        let fake = FakeTransport()
        let printer = service(fake)
        await printer.connect()
        fake.failures["printer.gcode.script"] = MoonrakerError.rejected("Official filament")
        let outcome = await printer.assign(ToolheadAssignment(spool: spool(), sendsSpoolID: false), toolhead: 0, force: false)
        #expect(outcome == .failed("Official filament"))
    }

    @Test func nothingIsSentDuringAPrint() async {
        let fake = FakeTransport()
        let printer = service(fake)
        await printer.connect()
        fake.onNotification?("notify_status_update", [["print_stats": ["state": "printing"]], 1.0])
        let outcome = await printer.clear(toolhead: 0)
        #expect(outcome == .failed("The printer is busy with a print."))
        #expect(fake.scripts.isEmpty)
    }

    private func tagged() -> [String: Any] {
        ["info": [["CARD_UID": [4, 141]], ["CARD_UID": 0], ["CARD_UID": [4, 142]], ["CARD_UID": 0]]]
    }

    @Test func refreshReReadsOnlyToolheadsWithATag() async {
        let fake = FakeTransport()
        let printer = service(fake)
        await printer.connect()
        fake.onNotification?("notify_status_update", [["filament_detect": tagged()], 1.0])
        #expect(await printer.refresh() == nil)
        #expect(fake.scripts == ["FILAMENT_DT_UPDATE CHANNEL=0", "FILAMENT_DT_UPDATE CHANNEL=2"])
    }

    @Test func refreshNeverClears() async {
        let fake = FakeTransport()
        let printer = service(fake)
        await printer.connect()
        fake.onNotification?("notify_status_update", [["filament_detect": tagged()], 1.0])
        _ = await printer.refresh()
        #expect(!fake.scripts.contains { $0.contains("CLEAR") })
    }

    @Test func refreshSendsNothingDuringAPrint() async {
        let fake = FakeTransport()
        let printer = service(fake)
        await printer.connect()
        fake.onNotification?("notify_status_update", [["filament_detect": tagged(), "print_stats": ["state": "printing"]], 1.0])
        #expect(await printer.refresh() == nil)
        #expect(fake.scripts.isEmpty)
    }

    @Test func aRefusedReadIsReported() async {
        let fake = FakeTransport()
        let printer = service(fake)
        await printer.connect()
        fake.onNotification?("notify_status_update", [["filament_detect": tagged()], 1.0])
        fake.failures["printer.gcode.script"] = MoonrakerError.rejected("Busy")
        #expect(await printer.refresh() == "Busy")
    }

    @Test func refreshWhileOfflineReconnects() async {
        let fake = FakeTransport()
        let printer = service(fake)
        await printer.connect()
        fake.onClosed?()
        _ = await printer.refresh()
        #expect(printer.connection == .online)
    }

    @Test func bothPortsAreTriedOnlyWithoutOne() {
        #expect(PrinterService.candidateBases(for: "192.168.20.70") == ["http://192.168.20.70", "http://192.168.20.70:7125"])
        #expect(PrinterService.candidateBases(for: "http://192.168.20.70:8080") == ["http://192.168.20.70:8080"])
        #expect(PrinterService.candidateBases(for: "").isEmpty)
    }

    @Test func theSocketLivesAtWebsocket() {
        #expect(PrinterService.socketURL(base: "http://192.168.20.70:7125")?.absoluteString == "ws://192.168.20.70:7125/websocket")
    }

    @Test func spoolIDsNeedTheSameServer() {
        let target = "spoolman|\(ServerAddress.identity(of: "http://192.168.20.33:7912"))"
        #expect(PrinterService.sharesSpoolman(printerServer: "http://192.168.20.33:7912/", connectionTarget: target))
        #expect(!PrinterService.sharesSpoolman(printerServer: "http://192.168.20.31:7912", connectionTarget: target))
        #expect(!PrinterService.sharesSpoolman(printerServer: nil, connectionTarget: target))
        #expect(!PrinterService.sharesSpoolman(printerServer: "http://192.168.20.33:7912", connectionTarget: "local"))
    }
}

@MainActor
struct ToolheadAssignmentWatchTests {
    private let sent = ToolheadAssignment(spool: spool(vendor: "Polar"), sendsSpoolID: false)

    private func state(material: String? = "PETG", colors: [String] = ["1A2B3C"], loaded: Bool = true, uid: String? = nil) -> ToolheadState {
        ToolheadState(index: 0, material: material, vendor: material == nil ? nil : "Polar", colorHexes: colors, alpha: 255, isLoaded: loaded, isOfficial: false, tagUID: uid)
    }

    @Test func unchangedHasNoNote() {
        #expect(ToolheadAssignmentWatch.note(for: sent, state: state()) == nil)
    }

    @Test func unloadingClears() {
        #expect(ToolheadAssignmentWatch.note(for: sent, state: state(material: nil, loaded: false)) == .clearedWhenUnloaded)
    }

    @Test func aClearWithFilamentStillThereIsNotAnUnload() {
        #expect(ToolheadAssignmentWatch.note(for: sent, state: state(material: nil, loaded: true)) == .clearedOnPrinter)
    }

    @Test func aTagReadReplaces() {
        #expect(ToolheadAssignmentWatch.note(for: sent, state: state(colors: ["FF0000"], uid: "04AA")) == .replacedByTag)
    }

    @Test func aChangeWithoutATagIsJustAChange() {
        #expect(ToolheadAssignmentWatch.note(for: sent, state: state(colors: ["FF0000"])) == .changedOnPrinter)
    }

    @Test func anotherPrintersWatchIsNotLoaded() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        ToolheadAssignmentWatch(address: "http://a", assignments: [0: sent]).save(to: defaults)
        #expect(ToolheadAssignmentWatch.load(address: "http://a", defaults: defaults).assignments[0] == sent)
        #expect(ToolheadAssignmentWatch.load(address: "http://b", defaults: defaults).assignments.isEmpty)
    }

    private func connected(_ fake: FakeTransport, defaults: UserDefaults) async -> PrinterService {
        defaults.set("http://10.0.0.5", forKey: AppConfig.printerAddressKey)
        fake.replies["printer.info"] = ["software_version": "2.0.0-paxx12-24"]
        fake.replies["printer.objects.subscribe"] = ["status": ["print_task_config": config()]]
        let printer = PrinterService(defaults: defaults, makeTransport: { _ in fake }, fetchText: { _, _ in nil }, readCredentials: { nil }, writeCredentials: { _ in true }, pause: {})
        await printer.connect()
        return printer
    }

    private func held() -> [String: Any] {
        var held = config(types: ["PETG", "NONE", "NONE", "NONE"], spoolIDs: [0, 0, 0, 0], official: [false, false, false, false])
        held["filament_vendor"] = ["Polar", "NONE", "NONE", "NONE"]
        held["filament_color_multi"] = [["nums": 1, "alpha": 255, "mode": 0, "colors": ["1A2B3C"]]]
            + (1..<4).map { _ in ["nums": 1, "alpha": 255, "mode": 0, "colors": ["FFFFFF"]] as [String: Any] }
        return held
    }

    @Test func anUnloadAfterAConfirmedAssignShowsANote() async {
        let fake = FakeTransport()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let printer = await connected(fake, defaults: defaults)
        fake.replies["printer.objects.query"] = ["status": ["print_task_config": held()]]
        #expect(await printer.assign(sent, toolhead: 0, force: false) == .confirmed)
        #expect(printer.notes.isEmpty)
        fake.onNotification?("notify_status_update", [["print_task_config": config(types: ["NONE", "NONE", "NONE", "NONE"])], 1.0])
        #expect(printer.notes[0] == .clearedWhenUnloaded)
        printer.acknowledgeNote(toolhead: 0)
        #expect(printer.notes.isEmpty)
    }

    @Test func aNoteSurvivesARestart() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        ToolheadAssignmentWatch(address: "http://10.0.0.5", assignments: [0: sent]).save(to: defaults)
        let printer = await connected(FakeTransport(), defaults: defaults)
        #expect(printer.notes[0] == .clearedWhenUnloaded)
    }

    @Test func theUsersOwnClearLeavesNoNote() async {
        let fake = FakeTransport()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        ToolheadAssignmentWatch(address: "http://10.0.0.5", assignments: [3: sent]).save(to: defaults)
        let printer = await connected(fake, defaults: defaults)
        fake.replies["printer.objects.query"] = ["status": ["print_task_config": config(types: ["NONE", "NONE", "NONE", "NONE"])]]
        #expect(await printer.clear(toolhead: 3) == .confirmed)
        #expect(printer.notes.isEmpty)
    }
}

/// A printer that wants a sign-in, per Moonraker's source: identify answers 401
/// without a valid token, and login and refresh work on the same socket.
@MainActor
private final class AuthFake: PrinterTransport {
    var onNotification: ((String, [Any]) -> Void)?
    var onClosed: (() -> Void)?
    var validToken = "good"
    var validKey = "key"
    var calls: [(String, [String: Any])] = []

    func call(_ method: String, params: [String: Any]) async throws -> MoonrakerValue {
        calls.append((method, params))
        switch method {
        case "server.connection.identify":
            guard params["access_token"] as? String == validToken || params["api_key"] as? String == validKey else {
                throw MoonrakerError.unauthorized("Unauthorized")
            }
            return MoonrakerValue(value: [String: Any]())
        case "access.login":
            guard params["password"] as? String == "secret" else { throw MoonrakerError.unauthorized("Invalid Password") }
            return MoonrakerValue(value: ["token": validToken, "refresh_token": "refresh"])
        case "access.refresh_jwt":
            guard params["refresh_token"] as? String == "refresh" else { throw MoonrakerError.unauthorized("Invalid Refresh Token") }
            return MoonrakerValue(value: ["token": validToken])
        case "printer.objects.subscribe":
            return MoonrakerValue(value: ["status": ["print_task_config": config()]])
        default:
            return MoonrakerValue(value: [String: Any]())
        }
    }

    func close() {}
}

@MainActor
private final class CredentialBox {
    var json: String?
    init(_ credentials: PrinterCredentials? = nil) { json = credentials?.encoded }
}

@MainActor
struct PrinterSignInTests {
    private let address = "http://10.0.0.5"

    private func service(_ fake: AuthFake, _ box: CredentialBox) -> PrinterService {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(address, forKey: AppConfig.printerAddressKey)
        return PrinterService(
            defaults: defaults, makeTransport: { _ in fake }, fetchText: { _, _ in nil },
            readCredentials: { box.json }, writeCredentials: { box.json = $0; return true }, pause: {}
        )
    }

    @Test func aPrinterThatRefusesAsksForASignIn() async {
        let printer = service(AuthFake(), CredentialBox())
        await printer.connect()
        #expect(printer.connection == .needsSignIn)
    }

    @Test func signingInStoresTokensAndNeverThePassword() async {
        let box = CredentialBox()
        let printer = service(AuthFake(), box)
        await printer.connect()
        #expect(await printer.signIn(username: "marko", password: "secret") == nil)
        #expect(printer.connection == .online)
        #expect(box.json?.contains("good") == true)
        #expect(box.json?.contains("secret") == false)
    }

    @Test func aWrongPasswordSaysWhyAndStoresNothing() async {
        let box = CredentialBox()
        let printer = service(AuthFake(), box)
        await printer.connect()
        #expect(await printer.signIn(username: "marko", password: "nope") == "Invalid Password")
        #expect(box.json == nil)
    }

    @Test func anExpiredTokenIsRefreshedOnce() async {
        let fake = AuthFake()
        let box = CredentialBox(PrinterCredentials(address: address, token: "expired", refreshToken: "refresh"))
        let printer = service(fake, box)
        await printer.connect()
        #expect(printer.connection == .online)
        #expect(fake.calls.filter { $0.0 == "access.refresh_jwt" }.count == 1)
        #expect(box.json?.contains("good") == true)
    }

    @Test func aRefusedRefreshAsksForASignIn() async {
        let box = CredentialBox(PrinterCredentials(address: address, token: "expired", refreshToken: "stale"))
        let printer = service(AuthFake(), box)
        await printer.connect()
        #expect(printer.connection == .needsSignIn)
    }

    @Test func anAPIKeySignsIn() async {
        let box = CredentialBox()
        let printer = service(AuthFake(), box)
        await printer.connect()
        #expect(await printer.signIn(apiKey: " key ") == nil)
        #expect(printer.connection == .online)
    }

    @Test func aRefusedKeyIsNotKept() async {
        let box = CredentialBox()
        let printer = service(AuthFake(), box)
        await printer.connect()
        #expect(await printer.signIn(apiKey: "wrong") == "The printer refused this key.")
        #expect(box.json == nil)
    }

    @Test func anotherPrintersTokenIsNeverSent() async {
        let fake = AuthFake()
        let box = CredentialBox(PrinterCredentials(address: "http://10.0.0.9", token: "good"))
        let printer = service(fake, box)
        await printer.connect()
        #expect(printer.connection == .needsSignIn)
        #expect(fake.calls.allSatisfy { $0.1["access_token"] == nil })
    }

    @Test func signingOutForgetsTheCredentials() async {
        let box = CredentialBox(PrinterCredentials(address: address, token: "good"))
        let printer = service(AuthFake(), box)
        await printer.connect()
        await printer.signOut()
        #expect(box.json == nil)
        #expect(printer.connection == .needsSignIn)
    }

    @Test func aTokenBeatsAKeyAndHeadersFollow() {
        let both = PrinterCredentials(address: address, token: "t", apiKey: "k")
        #expect(both.identifyFields == ["access_token": "t"])
        #expect(both.httpHeaders == ["Authorization": "Bearer t"])
        #expect(PrinterCredentials(address: address, apiKey: "k").httpHeaders == ["X-Api-Key": "k"])
    }
}

struct AppTabRestoreTests {
    @Test func theLastTabReopens() {
        #expect(ContentView.startTab(uiStartOnSpoolman: false, restored: nil, saved: .printer, printerConfigured: true) == .printer)
    }

    @Test func aRebuildBeatsTheSavedTab() {
        #expect(ContentView.startTab(uiStartOnSpoolman: false, restored: .home, saved: .printer, printerConfigured: true) == .home)
    }

    @Test func theUITestArgumentStillWins() {
        #expect(ContentView.startTab(uiStartOnSpoolman: true, restored: nil, saved: .printer, printerConfigured: true) == .spoolman)
    }

    /// The Printer tab is hidden until a printer is set up, so it can't open on it.
    @Test func aHiddenPrinterTabOpensHome() {
        #expect(ContentView.startTab(uiStartOnSpoolman: false, restored: nil, saved: .printer, printerConfigured: false) == .home)
        #expect(ContentView.startTab(uiStartOnSpoolman: false, restored: .printer, saved: nil, printerConfigured: false) == .home)
        #expect(ContentView.startTab(uiStartOnSpoolman: false, restored: nil, saved: .tags, printerConfigured: false) == .tags)
    }

    @Test func aPrinterIsConfiguredOnceItHasAUsableAddress() {
        #expect(!PrinterService.isConfigured(address: ""))
        #expect(!PrinterService.isConfigured(address: "   "))
        #expect(PrinterService.isConfigured(address: "192.168.20.70"))
        #expect(PrinterService.isConfigured(address: "http://u1.local:7125"))
    }
}

/// Bespok3D's bridge writes `card_uids` as a JSON array (spec, "Tag links
/// written by Bespok3D").
struct CardUIDsBespok3DTests {
    @Test func theBridgesArrayFormParses() {
        #expect(CardUIDsCodec.parse("\"[\\\"04a1b2c3d4e5f6\\\"]\"") == ["04A1B2C3D4E5F6"])
    }

    @Test func aHexPrefixIsDropped() {
        #expect(CardUIDsCodec.parse("\"0x04a1b2c3d4e5f6\"") == ["04A1B2C3D4E5F6"])
    }
}

/// FilaMan's Moonraker component, from its README only (GPLv3, clean-room).
@MainActor
struct FilaManComponentTests {
    @Test func extruderNames() {
        #expect(PrinterCommands.extruderName(toolhead: 0) == "extruder")
        #expect(PrinterCommands.extruderName(toolhead: 3) == "extruder3")
    }

    @Test func theFilaManPath() {
        #expect(PrinterCommands.filamanSpoolPath(toolhead: 1, spoolID: 42) == "/server/filaman/spool_id?extruder=extruder1&spool_id=42")
    }

    private func service(status: Int?, posted: @escaping (URL) -> Void = { _ in }) -> PrinterService {
        let fake = FakeTransport()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("http://10.0.0.5", forKey: AppConfig.printerAddressKey)
        fake.replies["printer.info"] = ["software_version": "2.0.0-paxx12-24"]
        fake.replies["printer.objects.list"] = ["objects": ["print_task_config"]]
        fake.replies["server.config"] = ["config": ["filaman": ["server": "http://192.168.20.40:8000", "api_key": "secret"]]]
        fake.replies["printer.objects.subscribe"] = ["status": ["print_task_config": config()]]
        return PrinterService(
            defaults: defaults, makeTransport: { _ in fake }, fetchText: { _, _ in nil },
            post: { url, _ in posted(url); return status },
            readCredentials: { nil }, writeCredentials: { _ in true }, pause: {}
        )
    }

    @Test func onlyTheComponentsServerIsRead() async {
        let printer = service(status: 200)
        await printer.connect()
        #expect(printer.filamanServer == "http://192.168.20.40:8000")
        #expect(printer.spoolmanServer == nil)
    }

    @Test func anAcceptedFilaManWriteIsConfirmed() async {
        var sent: URL?
        let printer = service(status: 200) { sent = $0 }
        await printer.connect()
        #expect(await printer.assignFilaManSpool(42, toolhead: 1) == .confirmed)
        #expect(sent?.absoluteString == "http://10.0.0.5/server/filaman/spool_id?extruder=extruder1&spool_id=42")
    }

    @Test func aRefusedFilaManWriteFails() async {
        let printer = service(status: 404)
        await printer.connect()
        guard case .failed = await printer.assignFilaManSpool(42, toolhead: 1) else {
            Issue.record("a 404 must not count as assigned")
            return
        }
    }

    @Test func noAnswerFails() async {
        let printer = service(status: nil)
        await printer.connect()
        guard case .failed = await printer.assignFilaManSpool(42, toolhead: 0) else {
            Issue.record("no reply must not count as assigned")
            return
        }
    }

    @Test func notConnectedFails() async {
        let printer = service(status: 200)
        guard case .failed = await printer.assignFilaManSpool(42, toolhead: 0) else {
            Issue.record("a write before connecting must fail")
            return
        }
    }
}

@Suite struct ToolheadTagActionsTests {
    private func toolhead(uid: String?, official: Bool = false) -> ToolheadState {
        ToolheadState(index: 1, colorHexes: [], alpha: 255, isLoaded: true, isOfficial: official, tagUID: uid)
    }
    private let ntag = "04A1B2C3D4E5F6"
    private let ready = PrinterTagPlugin.ready(version: "0.1.0")

    @Test func nothingWithoutAUsablePlugin() {
        for plugin in [PrinterTagPlugin.notInstalled, .notReady(reason: "x"), .needsAppUpdate(version: "2")] {
            let actions = ToolheadTagActions.available(
                connection: .online, plugin: plugin, toolhead: toolhead(uid: ntag), hasLibrarySpool: true, isPrinterBusy: false)
            #expect(actions.read == false)
            #expect(actions.write == .hidden)
        }
    }

    @Test func nothingUnlessThePrinterIsOnline() {
        for connection in [PrinterConnection.notConfigured, .connecting, .needsSignIn, .offline("x")] {
            let actions = ToolheadTagActions.available(
                connection: connection, plugin: ready, toolhead: toolhead(uid: ntag), hasLibrarySpool: true, isPrinterBusy: false)
            #expect(actions.read == false)
            #expect(actions.write == .hidden)
        }
    }

    @Test func nothingWithoutAReportedTag() {
        for uid in [nil, ""] as [String?] {
            let actions = ToolheadTagActions.available(
                connection: .online, plugin: ready, toolhead: toolhead(uid: uid), hasLibrarySpool: true, isPrinterBusy: false)
            #expect(actions.read == false)
            #expect(actions.write == .hidden)
        }
    }

    @Test func readIsOfferedForAnyReportedTag() {
        for (uid, official) in [(ntag, false), ("0A1B2C3D", true), ("0A1B2C3D", false)] {
            let actions = ToolheadTagActions.available(
                connection: .online, plugin: ready, toolhead: toolhead(uid: uid, official: official), hasLibrarySpool: false, isPrinterBusy: false)
            #expect(actions.read)
        }
    }

    @Test func writeIsHiddenWithoutALibrarySpool() {
        let actions = ToolheadTagActions.available(
            connection: .online, plugin: ready, toolhead: toolhead(uid: ntag), hasLibrarySpool: false, isPrinterBusy: false)
        #expect(actions.write == .hidden)
    }

    @Test func writeIsEnabledForAWritableTagWithASpool() {
        let actions = ToolheadTagActions.available(
            connection: .online, plugin: ready, toolhead: toolhead(uid: ntag), hasLibrarySpool: true, isPrinterBusy: false)
        #expect(actions.write == .enabled)
    }

    @Test func aSevenByteTagFlaggedOfficialIsStillWritable() {
        let actions = ToolheadTagActions.available(
            connection: .online, plugin: ready, toolhead: toolhead(uid: ntag, official: true), hasLibrarySpool: true, isPrinterBusy: false)
        #expect(actions.write == .enabled)
    }

    @Test func aSnapmakerTagIsDisabledWithItsReason() {
        let actions = ToolheadTagActions.available(
            connection: .online, plugin: ready, toolhead: toolhead(uid: "0A1B2C3D", official: true), hasLibrarySpool: true, isPrinterBusy: false)
        #expect(actions.write == .disabled(reason: TagReaderOption.snapmakerReason))
    }

    @Test func anotherFourByteTagIsDisabledWithTheOtherReason() {
        let actions = ToolheadTagActions.available(
            connection: .online, plugin: ready, toolhead: toolhead(uid: "0A1B2C3D"), hasLibrarySpool: true, isPrinterBusy: false)
        #expect(actions.write == .disabled(reason: TagReaderOption.unwritableReason))
    }

    @Test func aBusyPrinterDisablesWriteWithTheBusyNote() {
        let actions = ToolheadTagActions.available(
            connection: .online, plugin: ready, toolhead: toolhead(uid: ntag), hasLibrarySpool: true, isPrinterBusy: true)
        #expect(actions.write == .disabled(reason: TagReaderOption.busyNote))
        #expect(actions.read)
    }
}

@Suite struct PrinterTagPluginSettingsRowTests {
    @Test func showsTheStateOnlyWhileOnline() {
        #expect(PrinterTagPlugin.notInstalled.settingsRow(connection: .online) == "SpoolKid RFID Writer: not installed")
        #expect(PrinterTagPlugin.ready(version: "0.1.0").settingsRow(connection: .online) == "SpoolKid RFID Writer: ready (0.1.0)")
    }

    @Test func saysNothingWhenNotOnline() {
        for connection in [PrinterConnection.notConfigured, .connecting, .needsSignIn, .offline("x")] {
            #expect(PrinterTagPlugin.notInstalled.settingsRow(connection: connection) == nil)
            #expect(PrinterTagPlugin.ready(version: "0.1.0").settingsRow(connection: connection) == nil)
        }
    }
}

@Suite struct ToolheadTagActionsPrecedenceTests {
    private let ready = PrinterTagPlugin.ready(version: "0.1.0")

    @Test func busyWithNoMatchedSpoolStaysHidden() {
        let toolhead = ToolheadState(index: 0, colorHexes: [], alpha: 255, isLoaded: true, isOfficial: false, tagUID: "04A1B2C3D4E5F6")
        let actions = ToolheadTagActions.available(connection: .online, plugin: ready, toolhead: toolhead, hasLibrarySpool: false, isPrinterBusy: true)
        #expect(actions.write == .hidden)
    }

    @Test func busyWithASnapmakerTagReportsTheBusySentence() {
        let toolhead = ToolheadState(index: 0, colorHexes: [], alpha: 255, isLoaded: true, isOfficial: true, tagUID: "0A1B2C3D")
        let actions = ToolheadTagActions.available(connection: .online, plugin: ready, toolhead: toolhead, hasLibrarySpool: true, isPrinterBusy: true)
        #expect(actions.write == .disabled(reason: TagReaderOption.busyNote))
    }
}
