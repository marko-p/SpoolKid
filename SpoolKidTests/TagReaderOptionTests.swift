//
//  TagReaderOptionTests.swift
//  SpoolKidTests
//
//  Purpose: The tag reader picker's rules.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Testing
@testable import SpoolKid

@Suite struct TagReaderOptionTests {
    private static func head(_ index: Int, uid: String? = nil, official: Bool = false,
                      material: String? = nil) -> ToolheadState {
        ToolheadState(index: index, material: material, colorHexes: [], alpha: 255,
                      isLoaded: uid != nil, isOfficial: official, tagUID: uid)
    }

    private func options(
        plugin: PrinterTagPlugin = .ready(version: "1"), connected: Bool = true, busy: Bool = false,
        heads: [ToolheadState], names: [Int: String] = [:], purpose: TagReaderPurpose = .read
    ) -> [TagReaderOption] {
        TagReaderOption.options(plugin: plugin, isConnected: connected, isPrinterBusy: busy,
                                toolheads: heads, spoolName: { names[$0.index] }, purpose: purpose)
    }

    @Test func noOptionsWithoutThePlugin() {
        #expect(options(plugin: .notInstalled, heads: [Self.head(0, uid: "04AABBCCDDEEFF")]).isEmpty)
        #expect(options(plugin: .notReady(reason: "x"), heads: [Self.head(0)]).isEmpty)
    }

    @Test func noOptionsWhenDisconnected() {
        #expect(options(connected: false, heads: [Self.head(0)]).isEmpty)
    }

    @Test func iPhoneFirstThenReadersOneToFour() {
        let result = options(heads: [Self.head(2), Self.head(0), Self.head(1)])
        #expect(result.map(\.reader) == [.iPhone, .toolhead(0), .toolhead(1), .toolhead(2)])
        #expect(result.map(\.title) == ["iPhone", "RFID reader 1", "RFID reader 2", "RFID reader 3"])
    }

    /// The printer reads a tag when filament is loaded, not when a tag is swapped or
    /// stuck on a loaded spool, so no report is not "no tag".
    @Test func aReaderWithNoReportedTagStaysSelectable() {
        for purpose in [TagReaderPurpose.read, .write(format: .openSpool)] {
            let result = options(heads: [Self.head(0)], purpose: purpose)
            #expect(result[1].detail == "No tag read yet")
            #expect(result[1].disabledReason == nil)
        }
        #expect(options(busy: true, heads: [Self.head(0)])[1].disabledReason == TagReaderOption.busyNote)
    }

    @Test func blankOrUnknownTagIsSelectable() {
        let blank = Self.head(0, uid: "04AABBCCDDEEFF")
        for purpose in [TagReaderPurpose.read, .write(format: .openSpool)] {
            let result = options(heads: [blank], purpose: purpose)
            #expect(result[1].detail == "Blank or unknown tag")
            #expect(result[1].disabledReason == nil)
        }
    }

    @Test func snapmakerTagIsSelectableForReadAndDisabledForWrite() {
        let snapmaker = Self.head(0, uid: "AABBCCDD", official: true, material: "PLA")
        let read = options(heads: [snapmaker])
        #expect(read[1].detail == "Snapmaker tag")
        #expect(read[1].disabledReason == nil)
        let write = options(heads: [snapmaker], purpose: .write(format: .openSpool))
        #expect(write[1].disabledReason == "Snapmaker tags can't be rewritten.")
        let other = Self.head(0, uid: "AABBCCDD")
        #expect(options(heads: [other], purpose: .write(format: nil))[1].disabledReason
                == "This tag type can't be written by the printer.")
        // A 7-byte UID is writable even when the printer flags it official.
        let ntag = Self.head(0, uid: "04AABBCCDDEEFF", official: true)
        #expect(options(heads: [ntag], purpose: .write(format: .openSpool))[1].disabledReason == nil)
    }

    @Test func everyToolheadDisabledWhilePrinting() {
        let result = options(busy: true, heads: [Self.head(0, uid: "04AABBCCDDEEFF"), Self.head(1, uid: "04AABBCCDDEE11")])
        #expect(result[0].disabledReason == nil)
        #expect(result[1].disabledReason == TagReaderOption.busyNote)
        #expect(result[2].disabledReason == TagReaderOption.busyNote)
    }

    @Test func formatNeedingISO15693DisablesToolheads() {
        let result = options(heads: [Self.head(0, uid: "04AABBCCDDEEFF")], purpose: .write(format: .openPrintTag))
        #expect(result[0].disabledReason == nil)
        #expect(result[1].disabledReason == "This format needs a tag the printer can't write. Use the iPhone.")
        #expect(options(heads: [Self.head(0, uid: "04AABBCCDDEEFF")], purpose: .read)[1].disabledReason == nil)
    }

    @Test func fallbackToIPhoneWhenTheChosenReaderStopsBeingSelectable() {
        let emptied = options(busy: true, heads: [Self.head(0)])
        let fallback = TagReaderOption.fallback(for: .toolhead(0), in: emptied, isSettled: true)
        #expect(fallback?.reader == .iPhone)
        #expect(fallback?.reason == TagReaderOption.busyNote)
        #expect(TagReaderOption.fallback(for: .toolhead(0), in: options(heads: [Self.head(0)]), isSettled: true) == nil)
        let gone = TagReaderOption.fallback(for: .toolhead(0), in: [], isSettled: true)
        #expect(gone?.reader == .iPhone)
        #expect(gone?.reason == "The RFID reader is no longer available.")
        let fine = options(heads: [Self.head(0, uid: "04AABBCCDDEEFF")])
        #expect(TagReaderOption.fallback(for: .toolhead(0), in: fine, isSettled: true) == nil)
        #expect(TagReaderOption.fallback(for: .iPhone, in: emptied, isSettled: true) == nil)
    }

    @Test func fallbackWhenEveryOptionIsGone() {
        let disconnected = options(connected: false, heads: [Self.head(0, uid: "04AABBCCDDEEFF")])
        let fallback = TagReaderOption.fallback(for: .toolhead(0), in: disconnected, isSettled: true)
        #expect(fallback?.reader == .iPhone)
        #expect(fallback?.reason == "The RFID reader is no longer available.")
    }

    @Test func fallbackOnAppearForAToolheadHandedInMissingOrBusy() {
        let missing = TagReaderOption.fallback(for: .toolhead(1), in: options(heads: [Self.head(0)]), isSettled: true)
        #expect(missing?.reader == .iPhone)
        let busy = options(busy: true, heads: [Self.head(0, uid: "04AABBCCDDEEFF")])
        #expect(TagReaderOption.fallback(for: .toolhead(0), in: busy, isSettled: true)?.reason == TagReaderOption.busyNote)
    }

    @Test func toolheadDetailNamesSpoolThenTagContentThenLibraryGap() {
        func detail(_ toolhead: ToolheadState, name: String? = nil) -> String? {
            options(heads: [toolhead], names: name.map { [toolhead.index: $0] } ?? [:])[1].detail
        }
        var described = Self.head(0, uid: "04AABBCCDDEEFF", material: "PLA")
        described.vendor = "Polymaker"
        #expect(detail(described) == "Polymaker PLA")
        #expect(detail(described, name: "My spool") == "My spool")
        #expect(detail(Self.head(0, uid: "04AABBCCDDEEFF", material: "PETG")) == "PETG")
        var tagOnly = Self.head(0, uid: "04AABBCCDDEEFF")
        tagOnly.tag = ToolheadTagData(vendor: nil, material: "ABS", subtype: nil, colorHexes: [], alpha: 255)
        #expect(detail(tagOnly) == "ABS")
    }

    @Test func pluginNeedingAnAppUpdateGivesNoOptions() {
        #expect(options(plugin: .needsAppUpdate(version: "9"), heads: [Self.head(0)]).isEmpty)
    }

    @Test func readersAreListedOneToFourWhateverOrderTheyArrive() {
        // The spool-holder layout (1, 3, 2, 4) belongs to the Printer tab alone.
        let arranged = [Self.head(0), Self.head(2), Self.head(1), Self.head(3)]
        #expect(options(heads: arranged).dropFirst().map(\.reader)
                == [.toolhead(0), .toolhead(1), .toolhead(2), .toolhead(3)])
    }

    private let usable = Self.head(0, uid: "04AABBCCDDEEFF")

    private let waiting = PrinterTagPlugin.notReady(reason: PrinterTagPlugin.waitingReason)

    private func settled(_ connection: PrinterConnection, _ plugin: PrinterTagPlugin,
                         _ heads: [ToolheadState]) -> Bool {
        TagReaderOption.isSettled(connection: connection, plugin: plugin, toolheads: heads)
    }

    @Test func connectingIsNeverSettled() {
        #expect(!settled(.connecting, .ready(version: "1"), [usable]))
        #expect(!settled(.connecting, .notInstalled, []))
        let kept = TagReaderOption.fallback(
            for: .toolhead(0), in: options(heads: [usable]),
            isSettled: settled(.connecting, .ready(version: "1"), [usable]))
        #expect(kept == nil)
    }

    @Test func otherNotConnectedStatesAreSettled() {
        for connection in [PrinterConnection.offline("x"), .needsSignIn, .notConfigured] {
            #expect(settled(connection, .notInstalled, []))
            let drop = TagReaderOption.fallback(
                for: .toolhead(0), in: options(connected: false, heads: [usable]),
                isSettled: settled(connection, .ready(version: "1"), [usable]))
            #expect(drop?.reader == .iPhone)
        }
    }

    @Test func onlineWithAKnownAbsentOrUnusablePluginIsSettledWithoutToolheads() {
        #expect(settled(.online, .notInstalled, []))
        #expect(settled(.online, .needsAppUpdate(version: "9"), []))
        let drop = TagReaderOption.fallback(
            for: .toolhead(0), in: options(plugin: .notInstalled, heads: []),
            isSettled: settled(.online, .notInstalled, []))
        #expect(drop?.reader == .iPhone)
    }

    @Test func onlineWithTheWaitingPluginIsNotSettled() {
        #expect(!settled(.online, waiting, [usable]))
        #expect(!settled(.online, waiting, []))
    }

    @Test func onlineWithAReadyOrOtherwiseNotReadyPluginSettlesOnceToolheadsArrive() {
        for plugin in [PrinterTagPlugin.ready(version: "1"), .notReady(reason: "no tag reader")] {
            #expect(!settled(.online, plugin, []))
            #expect(settled(.online, plugin, [usable]))
        }
        let withoutIt = options(heads: [Self.head(1, uid: "04AABBCCDDEEFF")])
        let drop = TagReaderOption.fallback(
            for: .toolhead(0), in: withoutIt, isSettled: settled(.online, .ready(version: "1"), [Self.head(1)]))
        #expect(drop?.reader == .iPhone)
    }

    @Test func readerRoutesToTheIPhoneUnlessTheToolheadIsSelectable() {
        #expect(TagReaderOption.reader(for: .toolhead(0), in: options(heads: [usable])) == .toolhead(0))
        #expect(TagReaderOption.reader(for: .toolhead(0), in: options(busy: true, heads: [usable])) == .iPhone)
        #expect(TagReaderOption.reader(for: .toolhead(0), in: options(connected: false, heads: [usable])) == .iPhone)
        #expect(TagReaderOption.reader(for: .toolhead(0), in: options(heads: [])) == .iPhone)
    }

    @Test func fallbackNoteGoesStaleWhenTheDroppedReaderIsSelectableAgain() {
        let busy = options(busy: true, heads: [usable])
        #expect(!TagReaderOption.noteIsStale(droppedReader: .toolhead(0), in: busy))
        #expect(!TagReaderOption.noteIsStale(droppedReader: .toolhead(0), in: []))
        #expect(TagReaderOption.noteIsStale(droppedReader: .toolhead(0), in: options(heads: [usable])))
        #expect(TagReaderOption.noteIsStale(droppedReader: nil, in: busy))
    }

    @Test func detailDropsBlankFieldsAndKeepsEachCase() {
        func detail(_ toolhead: ToolheadState) -> String? { options(heads: [toolhead])[1].detail }
        var blankVendor = Self.head(0, uid: "04AABBCCDDEEFF", material: "PLA")
        blankVendor.vendor = "   "
        #expect(detail(blankVendor) == "PLA")
        var blankMaterial = Self.head(0, uid: "04AABBCCDDEEFF", material: " ")
        blankMaterial.vendor = "Polymaker"
        #expect(detail(blankMaterial) == "Polymaker")
        var neither = Self.head(0, uid: "04AABBCCDDEEFF", material: " ")
        neither.vendor = ""
        #expect(detail(neither) == "Tag not in Library")
        #expect(detail(Self.head(0, uid: "04AABBCCDDEEFF")) == "Blank or unknown tag")
        #expect(detail(Self.head(0)) == "No tag read yet")
        #expect(detail(Self.head(0, uid: "AABBCCDD", official: true, material: "PLA")) == "Snapmaker tag")
    }
}

@Suite struct TagReaderProgressTests {
    @Test func aToolheadNamesItsOperation() {
        #expect(TagReaderOption.progressText(for: .toolhead(1), writing: false) == "Reading from RFID reader 2…")
        #expect(TagReaderOption.progressText(for: .toolhead(1), writing: true) == "Writing with RFID reader 2…")
    }

    @Test func theIPhoneHasNoProgressText() {
        #expect(TagReaderOption.progressText(for: .iPhone, writing: false) == nil)
    }

    @Test func theOtherSideIsOfferedOnlyAfterAToolheadWrite() {
        #expect(TagReaderOption.offersOtherSide(afterWritingWith: .toolhead(0)))
        #expect(!TagReaderOption.offersOtherSide(afterWritingWith: .iPhone))
        #expect(!TagReaderOption.offersOtherSide(afterWritingWith: nil))
    }
}

@Suite struct TagReaderRunScreenTests {
    @Test func aToolheadOperationHoldsTheScreenOnlyWhileItRuns() {
        let toolhead = TagReaderRun(reader: .toolhead(1), isWriting: true)
        #expect(toolhead.holdsScreen(isScanning: true))
        #expect(!toolhead.holdsScreen(isScanning: false))
    }

    @Test func theIPhoneNeverHoldsTheScreen() {
        #expect(!TagReaderRun.iPhone.holdsScreen(isScanning: true))
    }

    @Test func aToolheadFailureReachesTheScreenButTheIPhonesDoesNot() {
        let toolhead = TagReaderRun(reader: .toolhead(0))
        #expect(toolhead.toolheadFailure(alertMessage: "No tag answered at RFID reader 1.") == "No tag answered at RFID reader 1.")
        #expect(toolhead.toolheadFailure(alertMessage: "") == nil)
        #expect(TagReaderRun.iPhone.toolheadFailure(alertMessage: "Something") == nil)
    }
}
