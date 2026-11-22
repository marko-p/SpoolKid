//
//  TagReaderTests.swift
//  SpoolKidTests
//
//  Spec 3: SpoolKid as a Spoolman 0.27 tag reader — who it says it is, what
//  a report carries, and which scans are reported.
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct TagReaderTests {
    private func isolatedDefaults(_ values: [String: Any] = [:]) -> UserDefaults {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        for (key, value) in values { defaults.set(value, forKey: key) }
        return defaults
    }

    // MARK: - Identity

    @Test func theReaderIDIsGeneratedOnceAndKept() {
        let defaults = isolatedDefaults()
        let first = TagReaderIdentity.readerID(defaults: defaults)
        #expect(first.wholeMatch(of: /spoolkid-[0-9a-f]{8}/) != nil)
        #expect(TagReaderIdentity.readerID(defaults: defaults) == first)
        #expect(defaults.string(forKey: AppConfig.tagReaderIdKey) == first)
    }

    @Test func theNameIsTheUsersTrimmedElseTheDefault() {
        #expect(TagReaderIdentity.defaultName(model: "iPhone") == "SpoolKid on iPhone")
        #expect(TagReaderIdentity.name(stored: nil, model: "iPhone") == "SpoolKid on iPhone")
        #expect(TagReaderIdentity.name(stored: "   ", model: "iPad") == "SpoolKid on iPad")
        #expect(TagReaderIdentity.name(stored: "  Bench phone ", model: "iPhone") == "Bench phone")
    }

    /// Spoolman refuses a name over 64 characters.
    @Test func theNameIsCutTo64Characters() {
        let long = String(repeating: "x", count: 80)
        #expect(TagReaderIdentity.name(stored: long, model: "iPhone").count == 64)
    }

    /// Spoolman counts code points: a family emoji is one Swift character
    /// but seven scalars.
    @Test func theNameLimitCountsUnicodeScalars() {
        let family = "👨‍👩‍👧‍👦"
        let name = TagReaderIdentity.name(stored: String(repeating: family, count: 10), model: "iPhone")
        #expect(name.unicodeScalars.count == 64)
        #expect(TagReaderIdentity.limited(String(repeating: "x", count: 80)) == String(repeating: "x", count: 64))
        #expect(TagReaderIdentity.limited("Bench") == "Bench")
    }

    @Test func reportingIsOnUnlessSwitchedOff() {
        #expect(TagReaderIdentity.isEnabled(defaults: isolatedDefaults()))
        #expect(!TagReaderIdentity.isEnabled(defaults: isolatedDefaults([AppConfig.tagReaderEnabledKey: false])))
    }

    // MARK: - The request body

    @Test func theBodyUsesSpoolmansKeysAndOmitsWhatIsMissing() {
        let bare = TagScanReport(uid: "04AABBCC", readerId: "spoolkid-0a1b2c3d", name: "SpoolKid on iPhone")
        #expect(bare.body == ["uid": "04AABBCC", "reader_id": "spoolkid-0a1b2c3d", "name": "SpoolKid on iPhone"])

        let full = TagScanReport(
            uid: "04AABBCC", readerId: "spoolkid-0a1b2c3d", name: "SpoolKid on iPhone",
            format: "openspool", payloadBase64: "AQI="
        )
        #expect(full.body["format"] == "openspool")
        #expect(full.body["payload_b64"] == "AQI=")
    }

    // MARK: - Which scans are reported

    @Test func anNFCScanIsReportedWithItsFormatAndUppercaseUID() throws {
        let defaults = isolatedDefaults([AppConfig.tagReaderNameKey: "Bench"])
        let scan = ScanResult(cardUID: "04aabbcc", tagData: nil, format: .openSpool)
        let report = try #require(TagScanReporter.report(for: scan, defaults: defaults, model: "iPhone"))
        #expect(report.uid == "04AABBCC")
        #expect(report.name == "Bench")
        #expect(report.format == "openspool")
        #expect(report.readerId == TagReaderIdentity.readerID(defaults: defaults))
    }

    @Test func nothingIsReportedWhenSwitchedOffOrWithoutAUID() {
        let off = isolatedDefaults([AppConfig.tagReaderEnabledKey: false])
        #expect(TagScanReporter.report(for: ScanResult(cardUID: "04aa", tagData: nil, format: .openSpool), defaults: off, model: "iPhone") == nil)
        #expect(TagScanReporter.report(for: ScanResult(cardUID: nil, tagData: nil, format: .openSpool), defaults: isolatedDefaults(), model: "iPhone") == nil)
    }

    /// A camera scan (QR/web, OCR) carries no UID, so it is not a tag read.
    @Test func cameraScansAreNotReported() {
        let defaults = isolatedDefaults()
        #expect(TagScanReporter.report(for: ScanResult(cardUID: nil, tagData: nil, format: .webUrl), defaults: defaults, model: "iPhone") == nil)
        #expect(TagScanReporter.report(for: ScanResult(cardUID: nil, tagData: nil, format: .ocr), defaults: defaults, model: "iPhone") == nil)
    }

    /// An NFC tag that carries a URL record is still a tag read.
    @Test func anNFCTagWithAURLIsReported() throws {
        let scan = ScanResult(cardUID: "04aa", tagData: nil, format: .webUrl)
        let report = try #require(TagScanReporter.report(for: scan, defaults: isolatedDefaults(), model: "iPhone"))
        #expect(report.uid == "04AA")
        #expect(report.format == nil)
    }

    @Test func theFormatSlugs() {
        #expect(TagScanReporter.formatSlug(.openSpool) == "openspool")
        #expect(TagScanReporter.formatSlug(.openPrintTag) == "openprinttag")
        #expect(TagScanReporter.formatSlug(.openTag3D) == "opentag3d")
        #expect(TagScanReporter.formatSlug(.anycubicACE) == "anycubic")
        #expect(TagScanReporter.formatSlug(.elegoo) == "elegoo")
        #expect(TagScanReporter.formatSlug(.tigerTag) == "tigertag")
        #expect(TagScanReporter.formatSlug(.webUrl) == nil)
        #expect(TagScanReporter.formatSlug(nil) == nil)
    }

    @Test func thePayloadIsTheNDEFMessageOrTheRawPages() {
        let ndef = TagSnapshot.ndef([
            NDEFRecordSnapshot(typeNameFormat: 0x01, type: Data([0x54]), identifier: Data(), payload: Data([0x00]))
        ])
        #expect(TagScanReporter.payloadBase64(ndef) == Data([0xD1, 0x01, 0x01, 0x54, 0x00]).base64EncodedString())
        #expect(TagScanReporter.payloadBase64(.rawPages(firstPage: 4, bytes: [1, 2, 3, 4])) == Data([1, 2, 3, 4]).base64EncodedString())
        #expect(TagScanReporter.payloadBase64(nil) == nil)
    }

    /// Spoolman refuses `payload_b64` over 8192 characters; the report goes
    /// without it rather than not at all.
    @Test func anOversizedPayloadIsLeftOut() {
        let big = TagSnapshot.rawPages(firstPage: 4, bytes: [UInt8](repeating: 7, count: 7000))
        #expect(TagScanReporter.payloadBase64(big) == nil)
    }

    @Test func pairingSendsThePlaceholderUIDAndNothingElse() {
        let defaults = isolatedDefaults()
        let report = TagScanReporter.pairingReport(defaults: defaults, model: "iPhone")
        #expect(report.uid == "00000000")
        #expect(report.name == "SpoolKid on iPhone")
        #expect(report.format == nil)
        #expect(report.payloadBase64 == nil)
    }

    // MARK: - Copy

    @Test func pairingResultsSayWhatToDoNext() {
        #expect(TagReaderText.pairingResult(.reported, name: "Bench")
            == "In Spoolman, open Settings → Tag Scanning and choose Use this next to Bench.")
        #expect(TagReaderText.pairingResult(.unsupported, name: "Bench")
            == "This server can't pair with a tag reader. Spoolman 0.27 or later can.")
        #expect(TagReaderText.pairingResult(.failed("Timed out"), name: "Bench")
            == "SpoolKid could not report to Spoolman: Timed out")
    }

    @Test func theFooterNamesTheReaderID() {
        #expect(TagReaderText.footer(readerID: "spoolkid-0a1b2c3d")
            == "Each tag you scan is reported to Spoolman, so a browser paired with SpoolKid opens its spool. Spoolman finds only tags linked in Spoolman Tags. Reader id: spoolkid-0a1b2c3d.")
    }
}
