//
//  BLETranscriptTests.swift
//  SpoolKidTests
//
//  The transcript is the whole output of a bench session with an unknown
//  scale — it is what leaves the phone and gets read somewhere else. If it
//  drops a packet, loses the byte order, or files a known weight in the wrong
//  place, the session has to be repeated with the hardware in hand. So it is
//  covered here, where no hardware is needed.
//

import Testing
import Foundation
@testable import SpoolKid

struct BLETranscriptTests {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func packet(_ bytes: [UInt8], at offset: TimeInterval, on uuid: String = "2C12") -> BLELogEntry {
        BLELogEntry(
            at: start.addingTimeInterval(offset),
            content: .packet(characteristic: uuid, data: Data(bytes))
        )
    }

    // MARK: - Byte rendering

    @Test func hexIsUppercaseAndSpaced() {
        #expect(BLETranscript.hex(Data([0x00, 0x0f, 0xa0, 0xff])) == "00 0F A0 FF")
    }

    /// A zero byte must still occupy a column. Collapsing it would shift every
    /// byte after it and silently change the offsets being reasoned about.
    @Test func hexPadsSingleDigitBytes() {
        #expect(BLETranscript.hex(Data([0x01, 0x02])) == "01 02")
    }

    @Test func hexOfNothingIsEmpty() {
        #expect(BLETranscript.hex(Data()) == "")
    }

    /// Some scales push text rather than a binary frame, and "1234 g" hiding
    /// in a byte dump is invisible until it is rendered.
    @Test func asciiRendersPrintableBytes() {
        #expect(BLETranscript.ascii(Data("160 g".utf8)) == "160 g")
    }

    @Test func asciiMasksControlAndHighBytes() {
        #expect(BLETranscript.ascii(Data([0x00, 0x41, 0x1F, 0x7F, 0xFF])) == ".A...")
    }

    // MARK: - Timing

    /// Packet spacing is half the protocol on a scale that streams: a reading
    /// every 200 ms and a reading on change look identical in wall-clock times.
    @Test func offsetsAreRelativeToTheFirstEntry() {
        #expect(BLETranscript.offset(start, from: start).trimmingCharacters(in: .whitespaces) == "+0.000")
        #expect(
            BLETranscript.offset(start.addingTimeInterval(1.25), from: start)
                .trimmingCharacters(in: .whitespaces) == "+1.250"
        )
    }

    // MARK: - The transcript

    @Test func everyPacketReachesTheTranscript() {
        let text = BLETranscript.text(
            title: "Scale",
            identifier: "ID",
            advertised: [],
            profile: [],
            entries: [packet([0xA0], at: 0), packet([0xA1], at: 0.2), packet([0xA2], at: 0.4)]
        )
        #expect(text.contains("A0"))
        #expect(text.contains("A1"))
        #expect(text.contains("A2"))
        #expect(text.contains("CAPTURE  (3 entries)"))
    }

    /// The reason the explorer exists rather than a generic sniffer. A known
    /// weight has to sit *between* the packets it explains, in order, or the
    /// pairing is lost and the bench session was wasted.
    @Test func aKnownWeightSitsInLineWithTheBytesAroundIt() {
        let text = BLETranscript.text(
            title: "Scale",
            identifier: "ID",
            advertised: [],
            profile: [],
            entries: [
                packet([0x00, 0x00], at: 0),
                BLELogEntry(at: start.addingTimeInterval(1), content: .mark(grams: 500, photo: "mark-01.jpg")),
                packet([0xF4, 0x01], at: 2)
            ]
        )
        let lines = text.split(separator: "\n").map(String.init)
        let zero = lines.firstIndex { $0.contains("00 00") }
        let mark = lines.firstIndex { $0.contains("500") && $0.contains("display reads") }
        let after = lines.firstIndex { $0.contains("F4 01") }
        #expect(zero != nil && mark != nil && after != nil)
        #expect(zero! < mark!)
        #expect(mark! < after!)
    }

    @Test func theServiceTreeIsCarried() {
        let profile = [
            BLEServiceProfile(uuid: "1910", characteristics: [
                BLECharacteristicProfile(
                    uuid: "2C12", properties: "notify", isNotifying: true, canNotify: true, canRead: false, canWrite: false
                )
            ])
        ]
        let text = BLETranscript.text(
            title: "Scale", identifier: "ID", advertised: ["1910"], profile: profile, entries: []
        )
        #expect(text.contains("1910"))
        #expect(text.contains("2C12"))
        #expect(text.contains("notify"))
        #expect(text.contains("[subscribed]"))
        #expect(text.contains("Advertised services: 1910"))
    }

    /// An empty capture is a real outcome — a scale that advertises and then
    /// says nothing is itself a finding, and the transcript has to say so
    /// rather than looking like a failed export.
    @Test func anEmptyCaptureStillProducesAReadableTranscript() {
        let text = BLETranscript.text(
            title: "Scale", identifier: "ID", advertised: [], profile: [], entries: []
        )
        #expect(text.contains("(nothing captured)"))
        #expect(text.contains("Advertised services: (none)"))
        #expect(text.contains("(not discovered)"))
    }
}

@MainActor
struct BLEScaleServiceLogTests {

    /// A capture left running while the user fetches the next spool must not
    /// grow without bound, and what it drops must be the OLDEST — a protocol
    /// reveals itself in the most recent exchange.
    @Test func theLogKeepsTheMostRecentEntries() {
        let service = BLEScaleService()
        for i in 1...(BLEScaleService.logCapacity + 10) {
            service.mark(grams: Double(i))
        }
        #expect(service.log.count == BLEScaleService.logCapacity)
        guard case .mark(let first, _) = service.log.first?.content else {
            Issue.record("expected a mark"); return
        }
        guard case .mark(let last, _) = service.log.last?.content else {
            Issue.record("expected a mark"); return
        }
        #expect(first == 11)
        #expect(last == Double(BLEScaleService.logCapacity + 10))
    }

    @Test func clearingEmptiesTheCapture() {
        let service = BLEScaleService()
        service.mark(grams: 100)
        service.clearLog()
        #expect(service.log.isEmpty)
    }

    /// Each state names a different remedy, and only some of them are the
    /// user's to perform. A single "Bluetooth unavailable" would send someone
    /// to Control Centre for a permission they have to grant in Settings.
    @Test func eachUnavailableStateExplainsItself() {
        #expect(BLEScaleService.Availability.ready.message == nil)
        #expect(BLEScaleService.Availability.unknown.message == nil)
        #expect(BLEScaleService.Availability.poweredOff.message?.contains("switched off") == true)
        #expect(BLEScaleService.Availability.unauthorized.message?.contains("Settings") == true)
        #expect(BLEScaleService.Availability.unsupported.message?.contains("no Bluetooth") == true)
    }
}

struct BLEMarkEvidenceTests {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    /// A photographed mark and a typed one must not read alike in the
    /// transcript. Whoever decodes it later is trusting these numbers, and a
    /// typed one is a claim while a photographed one is evidence.
    @Test func aTypedMarkIsLabelledUnverified() {
        let text = BLETranscript.text(
            title: "S", identifier: "I", advertised: [], profile: [],
            entries: [BLELogEntry(at: start, content: .mark(grams: 160, photo: nil))]
        )
        #expect(text.contains("UNVERIFIED"))
        #expect(!text.contains("photo:"))
    }

    @Test func aPhotographedMarkNamesItsFile() {
        let text = BLETranscript.text(
            title: "S", identifier: "I", advertised: [], profile: [],
            entries: [BLELogEntry(at: start, content: .mark(grams: 160, photo: "mark-03.jpg"))]
        )
        #expect(text.contains("photo: mark-03.jpg"))
        #expect(!text.contains("UNVERIFIED"))
    }

    // MARK: - What the screen tells the tester

    @Test func allPhotographedSaysSo() {
        #expect(BLEScaleExplorerView.markSummary(verified: 4, unverified: 0, unmatchable: 0) == "4 marks, all photographed.")
    }

    /// Singular matters here: "1 marked weights" in a tester-facing string is
    /// the kind of thing that makes people trust the rest of the screen less.
    @Test func oneIsSingular() {
        #expect(BLEScaleExplorerView.markSummary(verified: 1, unverified: 0, unmatchable: 0) == "1 mark, all photographed.")
        #expect(BLEScaleExplorerView.markSummary(verified: 0, unverified: 1, unmatchable: 0).hasPrefix("1 mark,"))
    }

    /// Said while the scale is still on the bench, where another mark costs
    /// nothing — not discovered afterwards by whoever reads the capture.
    @Test func noPhotosAtAllWarns() {
        let summary = BLEScaleExplorerView.markSummary(verified: 0, unverified: 3, unmatchable: 0)
        #expect(summary.contains("none photographed"))
        #expect(summary.contains("nobody else can check"))
    }

    @Test func aMixReportsBoth() {
        #expect(BLEScaleExplorerView.markSummary(verified: 2, unverified: 1, unmatchable: 0) == "2 photographed, 1 typed only.")
    }
}

struct DiagnosticsPreferenceTests {

    private func scratch(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "test.diagnostics.\(name)")!
        defaults.removePersistentDomain(forName: "test.diagnostics.\(name)")
        return defaults
    }

    /// The switch this replaced was shipped and opted into. Dropping those
    /// users back to off is a contribution that silently stops arriving and
    /// that nobody reports.
    @Test func aTesterWhoOptedIntoOCRArchivesIsCarriedOver() {
        let defaults = scratch("carry")
        defaults.set(true, forKey: AppConfig.saveOCRArchivesKey)
        DiagnosticsPreference.migrateLegacyOCRArchiveSwitch(in: defaults)
        #expect(defaults.bool(forKey: AppConfig.diagnosticsEnabledKey))
        #expect(defaults.object(forKey: AppConfig.saveOCRArchivesKey) == nil)
    }

    @Test func someoneWhoNeverTurnedItOnStaysOff() {
        let defaults = scratch("off")
        defaults.set(false, forKey: AppConfig.saveOCRArchivesKey)
        DiagnosticsPreference.migrateLegacyOCRArchiveSwitch(in: defaults)
        #expect(!defaults.bool(forKey: AppConfig.diagnosticsEnabledKey))
        #expect(defaults.object(forKey: AppConfig.saveOCRArchivesKey) == nil)
    }

    @Test func aFreshInstallHasNothingToMigrate() {
        let defaults = scratch("fresh")
        DiagnosticsPreference.migrateLegacyOCRArchiveSwitch(in: defaults)
        #expect(!defaults.bool(forKey: AppConfig.diagnosticsEnabledKey))
    }

    /// The migration runs at every launch. Turning diagnostics off must stick.
    @Test func itNeverSwitchesDiagnosticsBackOn() {
        let defaults = scratch("idempotent")
        defaults.set(true, forKey: AppConfig.saveOCRArchivesKey)
        DiagnosticsPreference.migrateLegacyOCRArchiveSwitch(in: defaults)
        defaults.set(false, forKey: AppConfig.diagnosticsEnabledKey)
        DiagnosticsPreference.migrateLegacyOCRArchiveSwitch(in: defaults)
        #expect(!defaults.bool(forKey: AppConfig.diagnosticsEnabledKey))
    }

    /// Diagnostics already on and the legacy key present must not end with the
    /// legacy key surviving to be read again by something that should not.
    @Test func theLegacyKeyIsAlwaysRemoved() {
        let defaults = scratch("removed")
        defaults.set(true, forKey: AppConfig.diagnosticsEnabledKey)
        defaults.set(true, forKey: AppConfig.saveOCRArchivesKey)
        DiagnosticsPreference.migrateLegacyOCRArchiveSwitch(in: defaults)
        #expect(defaults.object(forKey: AppConfig.saveOCRArchivesKey) == nil)
        #expect(defaults.bool(forKey: AppConfig.diagnosticsEnabledKey))
    }
}
