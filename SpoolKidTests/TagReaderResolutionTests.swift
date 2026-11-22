//
//  TagReaderResolutionTests.swift
//  SpoolKidTests
//
//  Purpose: An operation reaches a toolhead only while that toolhead is on
//  offer and selectable; otherwise it goes to the iPhone.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import SwiftData
import Testing
@testable import SpoolKid

@MainActor
private final class StubTransport: PrinterTransport {
    var onNotification: ((String, [Any]) -> Void)?
    var onClosed: (() -> Void)?
    var replies: [String: Any] = [:]

    func call(_ method: String, params: [String: Any]) async throws -> MoonrakerValue {
        MoonrakerValue(value: replies[method] ?? [String: Any]())
    }

    func close() {}
}

@MainActor
@Suite struct TagReaderResolutionTests {
    private func store() throws -> SpoolDataStore {
        let container = try ModelContainer(
            for: LocalVendor.self, LocalFilament.self, LocalSpool.self,
                 LocalIdSequence.self, LocationRegistryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return SpoolDataStore(repository: LocalRepository(context: ModelContext(container)))
    }

    /// An online printer with the plugin object listed and a 7-byte tag on toolhead 1.
    private func printer(pluginReady: Bool, printing: Bool = false, uid: [Int] = [4, 1, 2, 3, 4, 5, 6]) async -> PrinterService {
        let transport = StubTransport()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("http://10.0.0.5", forKey: AppConfig.printerAddressKey)
        transport.replies["printer.info"] = ["software_version": "2.0.0-paxx12-24"]
        transport.replies["printer.objects.list"] = ["objects": ["print_task_config", "spoolkid_rfid"]]
        let config: [String: Any] = [
            "filament_type": ["PLA", "NONE", "NONE", "NONE"], "filament_vendor": ["Acme", "NONE", "NONE", "NONE"],
            "filament_sub_type": ["", "NONE", "NONE", "NONE"],
            "filament_color_rgba": ["FFFFFFFF", "FFFFFFFF", "FFFFFFFF", "FFFFFFFF"],
            "filament_color_multi": (0..<4).map { _ in ["nums": 1, "alpha": 255, "mode": 0, "colors": ["FFFFFF"]] as [String: Any] },
            "filament_official": [false, false, false, false], "filament_exist": [true, false, false, false],
            "filament_spool_id": [0, 0, 0, 0]
        ]
        let detect: [String: Any] = ["info": [["CARD_UID": uid], 0, 0, 0] as [Any]]
        transport.replies["printer.objects.subscribe"] = ["status": ["print_task_config": config, "filament_detect": detect]]
        transport.replies["printer.objects.query"] = ["status": ["print_task_config": config, "filament_detect": detect]]
        let printer = PrinterService(defaults: defaults, makeTransport: { _ in transport },
                                     fetchText: { _, _ in nil }, readCredentials: { nil },
                                     writeCredentials: { _ in true }, pause: {})
        await printer.connect()
        var status: [String: Any] = ["spoolkid_rfid": ["api_version": 1, "plugin_version": "1", "ready": pluginReady,
                                   "not_ready_reason": pluginReady ? "" : "Reader is starting.", "busy": false]]
        if printing { status["print_stats"] = ["state": "printing"] }
        transport.onNotification?("notify_status_update", [status, 1.0])
        return printer
    }

    @Test func theIPhoneStaysTheIPhone() async throws {
        let printer = await printer(pluginReady: true)
        #expect(TagReaderOption.reader(for: .iPhone, purpose: .read, printer: printer, store: try store()) == .iPhone)
    }

    @Test func aSelectableToolheadIsKept() async throws {
        let printer = await printer(pluginReady: true)
        let reader = TagReaderOption.reader(for: .toolhead(0), purpose: .read, printer: printer, store: try store())
        #expect(reader == .toolhead(0))
    }

    @Test func aReaderWithNoReportedTagIsUsed() async throws {
        let printer = await printer(pluginReady: true)
        let reader = TagReaderOption.reader(for: .toolhead(2), purpose: .read, printer: printer, store: try store())
        #expect(reader == .toolhead(2))
    }

    @Test func aFormatThePrinterCannotWriteFallsBackToTheIPhone() async throws {
        let printer = await printer(pluginReady: true)
        let reader = TagReaderOption.reader(for: .toolhead(0), purpose: .write(format: .openPrintTag),
                                            printer: printer, store: try store())
        #expect(reader == .iPhone)
    }

    @Test func aPluginThatIsNotReadyFallsBackToTheIPhone() async throws {
        let printer = await printer(pluginReady: false)
        let reader = TagReaderOption.reader(for: .toolhead(0), purpose: .read, printer: printer, store: try store())
        #expect(reader == .iPhone)
    }

    @Test func aPrintingPrinterFallsBackToTheIPhone() async throws {
        let printer = await printer(pluginReady: true, printing: true)
        let reader = TagReaderOption.reader(for: .toolhead(0), purpose: .read, printer: printer, store: try store())
        #expect(reader == .iPhone)
    }

    @Test func aFourByteTagFallsBackToTheIPhoneForWritingButNotForReading() async throws {
        let printer = await printer(pluginReady: true, uid: [0xA1, 0xB2, 0xC3, 0xD4])
        let store = try store()
        #expect(TagReaderOption.reader(for: .toolhead(0), purpose: .write(format: .openSpool),
                                       printer: printer, store: store) == .iPhone)
        #expect(TagReaderOption.reader(for: .toolhead(0), purpose: .write(format: nil),
                                       printer: printer, store: store) == .iPhone)
        #expect(TagReaderOption.reader(for: .toolhead(0), purpose: .read, printer: printer, store: store) == .toolhead(0))
    }

    @Test func aWriteWithNoFormatStillUsesASelectableToolhead() async throws {
        let printer = await printer(pluginReady: true)
        let reader = TagReaderOption.reader(for: .toolhead(0), purpose: .write(format: nil),
                                            printer: printer, store: try store())
        #expect(reader == .toolhead(0))
    }

    @Test func aRunFollowsTheResolvedReaderNotTheSelection() async throws {
        let printer = await printer(pluginReady: true)
        let store = try store()
        let toolhead = TagReaderRun.start(.toolhead(0), purpose: .write(format: .openSpool), printer: printer, store: store)
        #expect(toolhead.progressText == "Writing with RFID reader 1…")
        #expect(toolhead.offersOtherSide)
        let dropped = TagReaderRun.start(.toolhead(0), purpose: .write(format: .openPrintTag), printer: printer, store: store)
        #expect(dropped.reader == .iPhone)
        #expect(dropped.progressText == nil)
        #expect(TagReaderRun.iPhone.progressText == nil)
        let read = TagReaderRun.start(.toolhead(0), purpose: .read, printer: printer, store: store)
        #expect(read.progressText == "Reading from RFID reader 1…")
        #expect(!read.offersOtherSide)
    }
}
